#!/bin/bash
#
# cleanup.sh - Tear down the Unreal Engine 5 infrastructure and VERIFY that
#              nothing billable is left behind.
#
# Why this script is paranoid: in April 2026 a g5.24xlarge (~$8/h) survived a
# "successful" cleanup for ~6 days (~$1,160). Root causes were:
#   1. Terraform state was local and had been lost, so `terraform destroy`
#      had nothing to destroy and reported success.
#   2. The old script deleted the local state files even when destroy failed,
#      orphaning every remaining resource.
#   3. There was no independent, tag-based verification against the account.
#
# This version:
#   * uses the S3 remote backend (environments/<env>/backend.hcl),
#   * streams `terraform destroy` output and keeps state on failure,
#   * then sweeps the account by TAG (Project / Purpose) for every resource
#     type the modules create: EC2 instances, spot requests, EBS volumes,
#     fast-snapshot-restores, EIPs, NAT gateways, ENIs, security groups,
#     subnets, route tables, IGWs, VPCs, flow logs, IAM roles/profiles,
#     CloudWatch alarms/dashboards/log groups, SNS topics, KMS aliases,
#   * scans for ANY running GPU/accelerated instance in the region,
#   * NEVER deletes snapshots or AMIs unless --delete-snapshots is given,
#     and always protects the archived UE 5.6 snapshot + the custom AMI,
#   * ends with a verification pass and a non-zero exit code if anything
#     billable is still present.
#
# Usage: cleanup.sh [OPTIONS] [ENVIRONMENT]
#   -e, --environment ENV   dev (default) | staging | prod
#   -p, --project NAME      Project tag / name prefix (default: from tfvars or ue5-compilation-dev)
#   -r, --region REGION     AWS region (default: from tfvars or us-east-1)
#   -d, --dry-run           Show what would be destroyed; change nothing
#   -f, --force             Skip the typed confirmation
#   -y, --yes               Alias for --force
#   --skip-terraform        Skip terraform destroy, only run the AWS sweep
#   --terminate-gpu         Also terminate running GPU instances that are NOT
#                           tagged with this project (otherwise only reported)
#   --delete-snapshots      Delete snapshots tagged with this project
#                           (protected snapshots are never deleted)
#   --delete-state-bucket   Also empty+delete the S3 state bucket (last step)
#   -h, --help
#
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"          # .../infrastructure (setup layout) or repo root (main layout)
if [[ -d "$INFRA_ROOT/terraform/environments" ]]; then
    ENVIRONMENTS_DIR="$INFRA_ROOT/terraform/environments"
else
    ENVIRONMENTS_DIR="$INFRA_ROOT/environments"
fi
SNAPSHOT_SCRIPT="$INFRA_ROOT/scripts/snapshot/manage_snapshot.sh"
LOG_DIR="$SCRIPT_DIR/logs"; mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup_$(date +%Y%m%d_%H%M%S).log"

ENVIRONMENT="dev"
PROJECT_NAME=""
AWS_REGION=""
DRY_RUN=false
FORCE=false
SKIP_TERRAFORM=false
TERMINATE_GPU=false
DELETE_SNAPSHOTS=false
DELETE_STATE_BUCKET=false

# Snapshots / AMIs that must survive any cleanup. The first one is the
# archived UE 5.6 source build (~$5/month); the second is the AMI's backing
# snapshot (Windows + VS2022 + DCV).
PROTECTED_SNAPSHOTS=("snap-0777feef308067690" "snap-031ad7508b5e1486d")
PROTECTED_AMIS=("ami-0a382bd9aedeb7bc3")

# Instance families whose presence we always report (GPU / accelerated).
GPU_FAMILY_REGEX='^(g[3-6]|p[2-5]|inf|trn|dl|vt|f1)'

REMAINING=()      # billable leftovers found by verification
ACTIONS=()        # human-readable list of what was done

log()     { echo -e "$*" | tee -a "$LOG_FILE"; }
info()    { log "${BLUE}[INFO]${NC} $*"; }
ok()      { log "${GREEN}[OK]${NC} $*"; }
warn()    { log "${YELLOW}[WARN]${NC} $*"; }
err()     { log "${RED}[ERROR]${NC} $*"; }
step()    { log "\n${CYAN}══ $* ══${NC}"; }
did()     { if [[ "$DRY_RUN" == true ]]; then ACTIONS+=("(dry-run) would: $*"); warn "would: $*"; else ACTIONS+=("$*"); ok "$*"; fi; }

usage() { sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'; }

# Run (or just print) a mutating command.
run() {
    if [[ "$DRY_RUN" == true ]]; then
        log "    ${YELLOW}DRY-RUN${NC} $*"
        return 0
    fi
    log "    \$ $*"
    "$@" >>"$LOG_FILE" 2>&1
    local rc=$?
    [[ $rc -ne 0 ]] && warn "    command failed (rc=$rc) - see $LOG_FILE"
    return $rc
}

aws_q() { aws --region "$AWS_REGION" "$@" 2>>"$LOG_FILE"; }

# ---------------------------------------------------------------------------
check_prerequisites() {
    step "Prerequisites"
    for t in aws jq; do
        command -v "$t" >/dev/null 2>&1 || { err "'$t' is required"; exit 1; }
    done
    if [[ "$SKIP_TERRAFORM" != true ]] && ! command -v terraform >/dev/null 2>&1; then
        warn "terraform not found - continuing with --skip-terraform (AWS sweep only)"
        SKIP_TERRAFORM=true
    fi
    local ident
    ident=$(aws sts get-caller-identity --output json 2>>"$LOG_FILE") || { err "AWS credentials not configured"; exit 1; }
    ACCOUNT_ID=$(jq -r .Account <<<"$ident")
    info "Account : $ACCOUNT_ID ($(jq -r .Arn <<<"$ident"))"
    info "Region  : $AWS_REGION"
    info "Project : $PROJECT_NAME"
    info "Env     : $ENVIRONMENT"
    info "Log     : $LOG_FILE"
    [[ "$DRY_RUN" == true ]] && warn "DRY RUN - nothing will be modified"
}

# Pull project_name / aws_region from terraform.tfvars or variables.tf so the
# tag filters match what Terraform actually created.
resolve_config() {
    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    local src
    for src in "$env_dir/terraform.tfvars" "$env_dir/variables.tf"; do
        [[ -f "$src" ]] || continue
        if [[ -z "$PROJECT_NAME" ]]; then
            if [[ "$src" == *.tfvars ]]; then
                PROJECT_NAME=$(grep -E '^\s*project_name\s*=' "$src" | sed -E 's/.*"([^"]*)".*/\1/' | head -1)
            else
                PROJECT_NAME=$(awk '/variable "project_name"/,/^}/' "$src" | grep -E '^\s*default' | sed -E 's/.*"([^"]*)".*/\1/' | head -1)
            fi
        fi
        if [[ -z "$AWS_REGION" ]]; then
            if [[ "$src" == *.tfvars ]]; then
                AWS_REGION=$(grep -E '^\s*aws_region\s*=' "$src" | sed -E 's/.*"([^"]*)".*/\1/' | head -1)
            else
                AWS_REGION=$(awk '/variable "aws_region"/,/^}/' "$src" | grep -E '^\s*default' | sed -E 's/.*"([^"]*)".*/\1/' | head -1)
            fi
        fi
    done
    PROJECT_NAME="${PROJECT_NAME:-ue5-compilation-dev}"
    AWS_REGION="${AWS_REGION:-us-east-1}"
    export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"
}

confirm_destruction() {
    [[ "$FORCE" == true || "$DRY_RUN" == true ]] && return 0
    log ""
    warn "════════════════════════════════════════════════════════════"
    warn "  DESTRUCTIVE OPERATION - environment '$ENVIRONMENT', project '$PROJECT_NAME'"
    warn "  Region $AWS_REGION, account $ACCOUNT_ID"
    warn "  Everything tagged Project=$PROJECT_NAME will be destroyed."
    warn "  Snapshots/AMIs are KEPT (archived UE 5.6 snapshot is protected)."
    warn "════════════════════════════════════════════════════════════"
    read -r -p "Type 'destroy-$ENVIRONMENT' to confirm: " answer
    [[ "$answer" == "destroy-$ENVIRONMENT" ]] || { err "Confirmation failed - aborting."; exit 1; }
}

# ---------------------------------------------------------------------------
# 1. Pre-flight inventory: show what is running BEFORE we touch anything.
# ---------------------------------------------------------------------------
preflight_inventory() {
    step "Pre-flight inventory (tag Project=$PROJECT_NAME)"
    local inst
    inst=$(aws_q ec2 describe-instances \
        --filters "Name=tag:Project,Values=$PROJECT_NAME" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,LaunchTime]' --output text)
    if [[ -n "$inst" ]]; then
        warn "Project instances:"; log "$inst"
    else
        info "No project instances."
    fi
    local gpu
    gpu=$(aws_q ec2 describe-instances \
        --filters "Name=instance-state-name,Values=pending,running" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,LaunchTime,Tags[?Key==`Project`]|[0].Value]' --output text \
        | awk -v re="$GPU_FAMILY_REGEX" '$2 ~ re')
    if [[ -n "$gpu" ]]; then
        warn "RUNNING GPU/ACCELERATED INSTANCES IN $AWS_REGION (any project):"; log "$gpu"
    else
        ok "No GPU instances running in $AWS_REGION."
    fi
}

# ---------------------------------------------------------------------------
# 2. terraform destroy (state kept on failure)
# ---------------------------------------------------------------------------
terraform_destroy() {
    step "Terraform destroy ($ENVIRONMENT)"
    [[ "$SKIP_TERRAFORM" == true ]] && { warn "Skipped (--skip-terraform)"; return 0; }

    local env_dir="$ENVIRONMENTS_DIR/$ENVIRONMENT"
    [[ -d "$env_dir" ]] || { warn "Environment dir not found: $env_dir - skipping terraform"; return 0; }
    pushd "$env_dir" >/dev/null || return 1

    local init_args=(-input=false -reconfigure)
    [[ -f backend.hcl ]] && init_args+=(-backend-config=backend.hcl)
    if ! terraform init "${init_args[@]}" >>"$LOG_FILE" 2>&1; then
        err "terraform init failed - see $LOG_FILE. Continuing with AWS sweep."
        popd >/dev/null; return 1
    fi

    local resources
    resources=$(terraform state list 2>>"$LOG_FILE" | wc -l | tr -d ' ')
    if [[ "$resources" == "0" ]]; then
        warn "Terraform state is EMPTY - nothing for terraform to destroy."
        warn "If resources exist they were created elsewhere; the AWS sweep below will find them by tag."
        popd >/dev/null; return 0
    fi
    info "State contains $resources resources."

    if [[ "$DRY_RUN" == true ]]; then
        terraform plan -destroy -input=false -lock=false -no-color 2>&1 | grep -E '^Plan:|will be destroyed' | tee -a "$LOG_FILE"
        popd >/dev/null; return 0
    fi

    # Stream output to the terminal AND the log so failures are visible.
    terraform destroy -auto-approve -input=false -no-color 2>&1 | tee -a "$LOG_FILE"
    local rc=${PIPESTATUS[0]}
    if [[ $rc -ne 0 ]]; then
        err "terraform destroy FAILED (rc=$rc). State is preserved; retrying once..."
        sleep 20
        terraform destroy -auto-approve -input=false -no-color 2>&1 | tee -a "$LOG_FILE"
        rc=${PIPESTATUS[0]}
    fi
    local left
    left=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
    if [[ $rc -eq 0 && "$left" == "0" ]]; then
        did "terraform destroy completed, state is empty"
    else
        err "terraform destroy left $left resource(s) in state. State NOT deleted. Sweep will continue."
        terraform state list 2>/dev/null | tee -a "$LOG_FILE"
    fi
    popd >/dev/null
    return $rc
}

# ---------------------------------------------------------------------------
# 3. Tag-based AWS sweep. Each function is idempotent.
# ---------------------------------------------------------------------------
tag_filter() { echo "Name=tag:Project,Values=$PROJECT_NAME"; }

sweep_fast_snapshot_restores() {
    step "Fast Snapshot Restores (~\$540/month each while enabled)"
    local rows
    rows=$(aws_q ec2 describe-fast-snapshot-restores \
        --filters "Name=state,Values=enabling,optimizing,enabled" \
        --query 'FastSnapshotRestores[].[SnapshotId,AvailabilityZone]' --output text)
    [[ -z "$rows" ]] && { ok "none"; return; }
    while read -r snap az; do
        [[ -z "$snap" ]] && continue
        warn "FSR enabled: $snap in $az"
        run aws ec2 disable-fast-snapshot-restores --region "$AWS_REGION" --availability-zones "$az" --source-snapshot-ids "$snap" \
            && did "Disabled FSR $snap/$az"
    done <<<"$rows"
}

sweep_spot_requests() {
    step "Spot instance requests"
    local ids
    ids=$(aws_q ec2 describe-spot-instance-requests \
        --filters "$(tag_filter)" "Name=state,Values=open,active" \
        --query 'SpotInstanceRequests[].SpotInstanceRequestId' --output text)
    [[ -z "$ids" ]] && { ok "none"; return; }
    run aws ec2 cancel-spot-instance-requests --region "$AWS_REGION" --spot-instance-request-ids $ids && did "Cancelled spot requests: $ids"
}

terminate_instances() {
    local ids="$1" label="$2"
    [[ -z "$ids" ]] && return 0
    for id in $ids; do
        # Clear termination protection if set, then terminate.
        run aws ec2 modify-instance-attribute --region "$AWS_REGION" --instance-id "$id" --no-disable-api-termination
        run aws ec2 modify-instance-attribute --region "$AWS_REGION" --instance-id "$id" --no-disable-api-stop
    done
    run aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids $ids && did "Terminating $label instances: $ids"
    if [[ "$DRY_RUN" != true ]]; then
        info "Waiting for termination..."
        aws_q ec2 wait instance-terminated --instance-ids $ids && ok "Terminated: $ids"
    fi
}

sweep_instances() {
    step "EC2 instances"
    local ids
    ids=$(aws_q ec2 describe-instances \
        --filters "$(tag_filter)" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].InstanceId' --output text)
    if [[ -n "$ids" ]]; then
        warn "Project instances still present: $ids"
        terminate_instances "$ids" "project"
    else
        ok "no project instances"
    fi

    # Name-based fallback: instances created by this project but missing the
    # Project tag (e.g. created manually from the AMI).
    local by_name
    by_name=$(aws_q ec2 describe-instances \
        --filters "Name=tag:Name,Values=${PROJECT_NAME}*,ue5-*,*unreal*,*UE5*" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].InstanceId' --output text)
    by_name=$(comm -23 <(tr ' \t' '\n\n' <<<"$by_name" | sort -u) <(tr ' \t' '\n\n' <<<"$ids" | sort -u) | tr '\n' ' ')
    if [[ -n "${by_name// /}" ]]; then
        warn "Instances matching UE5 naming but not tagged: $by_name"
        terminate_instances "$by_name" "UE5-named"
    fi

    # AMI-builder leftovers (build-custom-ami.sh tags Purpose=AMI-Builder).
    local builders
    builders=$(aws_q ec2 describe-instances \
        --filters "Name=tag:Purpose,Values=AMI-Builder" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].InstanceId' --output text)
    [[ -n "$builders" ]] && { warn "AMI-builder instances: $builders"; terminate_instances "$builders" "AMI-builder"; }

    # Any GPU instance in the region, regardless of tags.
    local gpu
    gpu=$(aws_q ec2 describe-instances \
        --filters "Name=instance-state-name,Values=pending,running,stopped" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Project`]|[0].Value]' --output text \
        | awk -v re="$GPU_FAMILY_REGEX" '$2 ~ re')
    if [[ -n "$gpu" ]]; then
        warn "GPU/accelerated instances present in $AWS_REGION:"; log "$gpu"
        if [[ "$TERMINATE_GPU" == true ]]; then
            terminate_instances "$(awk '{print $1}' <<<"$gpu" | tr '\n' ' ')" "GPU"
        else
            warn "Not terminating untagged GPU instances (re-run with --terminate-gpu to do so)."
            while read -r id type state proj; do REMAINING+=("GPU instance $id ($type, $state, Project=${proj:-none})"); done <<<"$gpu"
        fi
    else
        ok "no GPU instances in region"
    fi
}

sweep_volumes() {
    step "EBS volumes"
    local ids
    ids=$(aws_q ec2 describe-volumes --filters "$(tag_filter)" \
        --query 'Volumes[].[VolumeId,Size,State,Attachments[0].InstanceId]' --output text)
    [[ -z "$ids" ]] && { ok "none"; return; }
    while read -r vol size state inst; do
        [[ -z "$vol" ]] && continue
        if [[ "$state" == "in-use" && -n "$inst" && "$inst" != "None" ]]; then
            run aws ec2 detach-volume --region "$AWS_REGION" --volume-id "$vol" --force
            [[ "$DRY_RUN" != true ]] && aws_q ec2 wait volume-available --volume-ids "$vol"
        fi
        run aws ec2 delete-volume --region "$AWS_REGION" --volume-id "$vol" && did "Deleted volume $vol (${size} GB)"
    done <<<"$ids"
}

sweep_snapshots() {
    step "EBS snapshots"
    local rows
    rows=$(aws_q ec2 describe-snapshots --owner-ids self --filters "$(tag_filter)" \
        --query 'Snapshots[].[SnapshotId,VolumeSize,StorageTier,Description]' --output text)
    if [[ -z "$rows" ]]; then ok "no project-tagged snapshots"; return; fi
    while read -r snap size tier desc; do
        [[ -z "$snap" ]] && continue
        if printf '%s\n' "${PROTECTED_SNAPSHOTS[@]}" | grep -qx "$snap"; then
            ok "PROTECTED (kept): $snap ${size}GB [$tier] $desc"
            continue
        fi
        if [[ "$DELETE_SNAPSHOTS" == true ]]; then
            run aws ec2 delete-snapshot --region "$AWS_REGION" --snapshot-id "$snap" && did "Deleted snapshot $snap"
        else
            info "kept (use --delete-snapshots to remove): $snap ${size}GB [$tier] $desc"
        fi
    done <<<"$rows"
}

sweep_addresses() {
    step "Elastic IPs"
    local rows
    rows=$(aws_q ec2 describe-addresses --filters "$(tag_filter)" \
        --query 'Addresses[].[AllocationId,AssociationId,PublicIp]' --output text)
    [[ -z "$rows" ]] && { ok "none"; return; }
    while read -r alloc assoc ip; do
        [[ -z "$alloc" ]] && continue
        [[ -n "$assoc" && "$assoc" != "None" ]] && run aws ec2 disassociate-address --region "$AWS_REGION" --association-id "$assoc"
        run aws ec2 release-address --region "$AWS_REGION" --allocation-id "$alloc" && did "Released EIP $ip"
    done <<<"$rows"
}

sweep_nat_gateways() {
    step "NAT gateways (~\$32/month each)"
    local ids
    ids=$(aws_q ec2 describe-nat-gateways --filter "$(tag_filter)" "Name=state,Values=pending,available" \
        --query 'NatGateways[].NatGatewayId' --output text)
    [[ -z "$ids" ]] && { ok "none"; return; }
    for id in $ids; do
        run aws ec2 delete-nat-gateway --region "$AWS_REGION" --nat-gateway-id "$id" && did "Deleting NAT gateway $id"
    done
    if [[ "$DRY_RUN" != true ]]; then
        info "Waiting for NAT gateway deletion..."
        aws_q ec2 wait nat-gateway-deleted --nat-gateway-ids $ids || true
    fi
}

project_vpcs() {
    aws_q ec2 describe-vpcs --filters "$(tag_filter)" --query 'Vpcs[].VpcId' --output text
}

sweep_vpcs() {
    step "VPCs and dependencies"
    local vpcs
    vpcs=$(project_vpcs)
    [[ -z "$vpcs" ]] && { ok "none"; return; }
    for vpc in $vpcs; do
        warn "Tearing down VPC $vpc"

        # Flow logs
        local fl
        fl=$(aws_q ec2 describe-flow-logs --filter "Name=resource-id,Values=$vpc" --query 'FlowLogs[].FlowLogId' --output text)
        [[ -n "$fl" ]] && run aws ec2 delete-flow-logs --region "$AWS_REGION" --flow-log-ids $fl && did "Deleted flow logs $fl"

        # ENIs (detach + delete anything still hanging)
        local enis
        enis=$(aws_q ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --query 'NetworkInterfaces[].[NetworkInterfaceId,Attachment.AttachmentId,InterfaceType]' --output text)
        while read -r eni att itype; do
            [[ -z "$eni" ]] && continue
            [[ "$itype" == "nat_gateway" ]] && continue
            [[ -n "$att" && "$att" != "None" ]] && run aws ec2 detach-network-interface --region "$AWS_REGION" --attachment-id "$att" --force
            run aws ec2 delete-network-interface --region "$AWS_REGION" --network-interface-id "$eni" && did "Deleted ENI $eni"
        done <<<"$enis"

        # Internet gateways
        local igws
        igws=$(aws_q ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query 'InternetGateways[].InternetGatewayId' --output text)
        for igw in $igws; do
            run aws ec2 detach-internet-gateway --region "$AWS_REGION" --internet-gateway-id "$igw" --vpc-id "$vpc"
            run aws ec2 delete-internet-gateway --region "$AWS_REGION" --internet-gateway-id "$igw" && did "Deleted IGW $igw"
        done

        # Subnets
        local subnets
        subnets=$(aws_q ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query 'Subnets[].SubnetId' --output text)
        for s in $subnets; do run aws ec2 delete-subnet --region "$AWS_REGION" --subnet-id "$s" && did "Deleted subnet $s"; done

        # Non-main route tables
        local rts
        rts=$(aws_q ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
        for rt in $rts; do
            local assocs
            assocs=$(aws_q ec2 describe-route-tables --route-table-ids "$rt" --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text)
            for a in $assocs; do run aws ec2 disassociate-route-table --region "$AWS_REGION" --association-id "$a"; done
            run aws ec2 delete-route-table --region "$AWS_REGION" --route-table-id "$rt" && did "Deleted route table $rt"
        done

        # Security groups (non-default); strip rules first to break cycles
        local sgs
        sgs=$(aws_q ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
        for sg in $sgs; do
            local ing egr
            ing=$(aws_q ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json)
            egr=$(aws_q ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissionsEgress' --output json)
            [[ "$ing" != "[]" ]] && run aws ec2 revoke-security-group-ingress --region "$AWS_REGION" --group-id "$sg" --ip-permissions "$ing"
            [[ "$egr" != "[]" ]] && run aws ec2 revoke-security-group-egress --region "$AWS_REGION" --group-id "$sg" --ip-permissions "$egr"
        done
        for sg in $sgs; do run aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$sg" && did "Deleted security group $sg"; done

        run aws ec2 delete-vpc --region "$AWS_REGION" --vpc-id "$vpc" && did "Deleted VPC $vpc"
    done
}

sweep_iam() {
    step "IAM roles / instance profiles"
    # Names created by modules/compute and modules/security.
    local roles
    roles=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '${PROJECT_NAME}-')].RoleName" --output text 2>>"$LOG_FILE")
    local profiles
    profiles=$(aws iam list-instance-profiles --query "InstanceProfiles[?starts_with(InstanceProfileName, '${PROJECT_NAME}-')].InstanceProfileName" --output text 2>>"$LOG_FILE")
    [[ -z "$roles$profiles" ]] && { ok "none"; return; }

    local handled_profiles=" "
    for p in $profiles; do
        local prs
        prs=$(aws iam get-instance-profile --instance-profile-name "$p" --query 'InstanceProfile.Roles[].RoleName' --output text 2>>"$LOG_FILE")
        for r in $prs; do run aws iam remove-role-from-instance-profile --instance-profile-name "$p" --role-name "$r"; done
        run aws iam delete-instance-profile --instance-profile-name "$p" && did "Deleted instance profile $p"
        handled_profiles+="$p "
    done
    for r in $roles; do
        # instance profiles attached to the role but with a different name
        local rp
        rp=$(aws iam list-instance-profiles-for-role --role-name "$r" --query 'InstanceProfiles[].InstanceProfileName' --output text 2>>"$LOG_FILE")
        for p in $rp; do
            [[ "$handled_profiles" == *" $p "* ]] && continue
            run aws iam remove-role-from-instance-profile --instance-profile-name "$p" --role-name "$r"
            run aws iam delete-instance-profile --instance-profile-name "$p" && did "Deleted instance profile $p"
        done
        local att inl
        att=$(aws iam list-attached-role-policies --role-name "$r" --query 'AttachedPolicies[].PolicyArn' --output text 2>>"$LOG_FILE")
        for a in $att; do run aws iam detach-role-policy --role-name "$r" --policy-arn "$a"; done
        inl=$(aws iam list-role-policies --role-name "$r" --query 'PolicyNames' --output text 2>>"$LOG_FILE")
        for i in $inl; do run aws iam delete-role-policy --role-name "$r" --policy-name "$i"; done
        run aws iam delete-role --role-name "$r" && did "Deleted IAM role $r"
    done
}

sweep_cloudwatch() {
    step "CloudWatch alarms / dashboards / log groups"
    local alarms
    alarms=$(aws_q cloudwatch describe-alarms --alarm-name-prefix "${PROJECT_NAME}-" --query 'MetricAlarms[].AlarmName' --output text)
    [[ -n "$alarms" ]] && run aws cloudwatch delete-alarms --region "$AWS_REGION" --alarm-names $alarms && did "Deleted alarms: $alarms"

    local dash
    dash=$(aws_q cloudwatch list-dashboards --dashboard-name-prefix "${PROJECT_NAME}" --query 'DashboardEntries[].DashboardName' --output text)
    [[ -n "$dash" ]] && run aws cloudwatch delete-dashboards --region "$AWS_REGION" --dashboard-names $dash && did "Deleted dashboards: $dash"

    local prefix groups
    for prefix in "/aws/ec2/${PROJECT_NAME}" "/aws/application/${PROJECT_NAME}" "/aws/security/${PROJECT_NAME}" "/aws/vpc/flowlogs/${PROJECT_NAME}"; do
        groups=$(aws_q logs describe-log-groups --log-group-name-prefix "$prefix" --query 'logGroups[].logGroupName' --output text)
        for g in $groups; do run aws logs delete-log-group --region "$AWS_REGION" --log-group-name "$g" && did "Deleted log group $g"; done
    done
    ok "done"
}

sweep_sns_kms() {
    step "SNS topics / KMS aliases"
    local topics
    topics=$(aws_q sns list-topics --query "Topics[?contains(TopicArn, ':${PROJECT_NAME}-')].TopicArn" --output text)
    for t in $topics; do run aws sns delete-topic --region "$AWS_REGION" --topic-arn "$t" && did "Deleted SNS topic $t"; done

    local alias="alias/${PROJECT_NAME}-key" key
    key=$(aws_q kms describe-key --key-id "$alias" --query 'KeyMetadata.[KeyId,KeyState]' --output text 2>/dev/null || true)
    if [[ -n "$key" ]]; then
        read -r kid kstate <<<"$key"
        if [[ "$kstate" == "Enabled" || "$kstate" == "Disabled" ]]; then
            run aws kms delete-alias --region "$AWS_REGION" --alias-name "$alias"
            run aws kms schedule-key-deletion --region "$AWS_REGION" --key-id "$kid" --pending-window-in-days 7 && did "Scheduled KMS key $kid for deletion (7 days)"
        fi
    fi
    ok "done"
}

sweep_cloudformation() {
    step "CloudFormation IDE stacks (unreal-engine-5-ide*)"
    local stacks
    stacks=$(aws_q cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE CREATE_FAILED UPDATE_ROLLBACK_COMPLETE DELETE_FAILED \
        --query 'StackSummaries[?starts_with(StackName, `unreal-engine-5-ide`)].StackName' --output text)
    [[ -z "$stacks" ]] && { ok "none"; return; }
    warn "IDE stacks found: $stacks"
    local ide_cleanup="$INFRA_ROOT/cloudformation/cleanup/cleanup-ide.sh"
    [[ -x "$ide_cleanup" ]] || ide_cleanup="$INFRA_ROOT/scripts/cleanup/cleanup-ide.sh"
    if [[ -x "$ide_cleanup" && "$DRY_RUN" != true ]]; then
        AWS_REGION="$AWS_REGION" bash "$ide_cleanup" -f 2>&1 | tee -a "$LOG_FILE" && did "Deleted IDE stacks via cleanup-ide.sh"
    else
        for s in $stacks; do REMAINING+=("CloudFormation stack $s (delete with cloudformation/cleanup/cleanup-ide.sh)"); done
    fi
}

# ---------------------------------------------------------------------------
# 4. Verification - independent of everything above.
# ---------------------------------------------------------------------------
verify() {
    step "VERIFICATION (what is still billable?)"
    local x

    x=$(aws_q ec2 describe-instances --filters "$(tag_filter)" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output text)
    [[ -n "$x" ]] && while read -r l; do REMAINING+=("EC2 instance: $l"); done <<<"$x"

    x=$(aws_q ec2 describe-instances --filters "Name=instance-state-name,Values=pending,running" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key==`Project`]|[0].Value]' --output text | awk -v re="$GPU_FAMILY_REGEX" '$2 ~ re')
    [[ -n "$x" ]] && while read -r l; do REMAINING+=("RUNNING GPU INSTANCE (any project): $l"); done <<<"$x"

    x=$(aws_q ec2 describe-volumes --filters "$(tag_filter)" --query 'Volumes[].[VolumeId,Size,State]' --output text)
    [[ -n "$x" ]] && while read -r l; do REMAINING+=("EBS volume: $l"); done <<<"$x"

    x=$(aws_q ec2 describe-fast-snapshot-restores --filters "Name=state,Values=enabling,optimizing,enabled" --query 'FastSnapshotRestores[].[SnapshotId,AvailabilityZone]' --output text)
    [[ -n "$x" ]] && while read -r l; do REMAINING+=("Fast snapshot restore: $l"); done <<<"$x"

    x=$(aws_q ec2 describe-nat-gateways --filter "$(tag_filter)" "Name=state,Values=pending,available" --query 'NatGateways[].NatGatewayId' --output text)
    [[ -n "$x" ]] && REMAINING+=("NAT gateway(s): $x")

    x=$(aws_q ec2 describe-addresses --filters "$(tag_filter)" --query 'Addresses[].PublicIp' --output text)
    [[ -n "$x" ]] && REMAINING+=("Elastic IP(s): $x")

    x=$(project_vpcs)
    [[ -n "$x" ]] && REMAINING+=("VPC(s): $x")

    x=$(aws_q ec2 describe-spot-instance-requests --filters "$(tag_filter)" "Name=state,Values=open,active" --query 'SpotInstanceRequests[].SpotInstanceRequestId' --output text)
    [[ -n "$x" ]] && REMAINING+=("Spot request(s): $x")

    x=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '${PROJECT_NAME}-')].RoleName" --output text 2>>"$LOG_FILE")
    [[ -n "$x" ]] && REMAINING+=("IAM role(s) (free, but untidy): $x")

    # Snapshot report (informational - these are intentionally kept)
    step "Snapshots kept (informational)"
    aws_q ec2 describe-snapshots --owner-ids self \
        --query 'Snapshots[].{Id:SnapshotId,SizeGB:VolumeSize,Tier:StorageTier,Desc:Description}' --output table | tee -a "$LOG_FILE"
    if [[ -x "$SNAPSHOT_SCRIPT" ]]; then
        AWS_REGION="$AWS_REGION" "$SNAPSHOT_SCRIPT" status >>"$LOG_FILE" 2>&1 || true
    fi
}

summary() {
    log ""
    log "════════════════════════════════════════════════════════════"
    log " CLEANUP SUMMARY  env=$ENVIRONMENT project=$PROJECT_NAME region=$AWS_REGION"
    log "════════════════════════════════════════════════════════════"
    if [[ ${#ACTIONS[@]} -gt 0 ]]; then
        log "Actions:"; for a in "${ACTIONS[@]}"; do log "  • $a"; done
    else
        log "Actions: none required"
    fi
    log ""
    if [[ ${#REMAINING[@]} -eq 0 ]]; then
        ok "VERIFIED: no billable project resources remain in $AWS_REGION."
        ok "Ongoing cost: archived UE 5.6 snapshot (~\$5/mo) + AMI snapshot (~\$5/mo) + S3 state (<\$0.01)."
        log "Log: $LOG_FILE"
        return 0
    fi
    err "ATTENTION - resources still present:"
    for r in "${REMAINING[@]}"; do log "  ${RED}✗${NC} $r"; done
    log ""
    if [[ "$DRY_RUN" == true ]]; then
        warn "Dry run: the above is what a real run would remove (except untagged GPU instances, which need --terminate-gpu)."
    else
        err "Cleanup is NOT complete. Fix the above (or re-run with --terminate-gpu / check the log) before walking away."
    fi
    log "Log: $LOG_FILE"
    return 2
}

delete_state_bucket() {
    [[ "$DELETE_STATE_BUCKET" != true ]] && return 0
    step "S3 state bucket"
    local b
    b=$(grep -E '^\s*bucket\s*=' "$ENVIRONMENTS_DIR/$ENVIRONMENT/backend.hcl" 2>/dev/null | sed -E 's/.*"([^"]*)".*/\1/')
    [[ -z "$b" ]] && { warn "no backend.hcl bucket"; return 0; }
    if [[ ${#REMAINING[@]} -gt 0 ]]; then
        err "Refusing to delete state bucket $b while resources remain."
        return 1
    fi
    warn "Deleting ALL versions in s3://$b and the bucket itself"
    if [[ "$DRY_RUN" != true ]]; then
        aws s3api list-object-versions --bucket "$b" --output json 2>/dev/null \
            | jq -r '[.Versions[]?, .DeleteMarkers[]?] | .[] | "\(.Key)\t\(.VersionId)"' \
            | while IFS=$'\t' read -r k v; do aws s3api delete-object --bucket "$b" --key "$k" --version-id "$v" >>"$LOG_FILE" 2>&1; done
        aws s3api delete-bucket --bucket "$b" >>"$LOG_FILE" 2>&1 && did "Deleted state bucket $b"
    fi
}

# ---------------------------------------------------------------------------
main() {
    resolve_config
    check_prerequisites
    preflight_inventory
    confirm_destruction

    terraform_destroy || true

    sweep_fast_snapshot_restores
    sweep_spot_requests
    sweep_instances
    sweep_volumes
    sweep_addresses
    sweep_nat_gateways
    sweep_vpcs
    sweep_iam
    sweep_cloudwatch
    sweep_sns_kms
    sweep_cloudformation
    sweep_snapshots

    verify
    delete_state_bucket
    summary
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--environment) ENVIRONMENT="$2"; shift 2 ;;
        -p|--project) PROJECT_NAME="$2"; shift 2 ;;
        -r|--region) AWS_REGION="$2"; shift 2 ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        -f|--force|-y|--yes) FORCE=true; shift ;;
        --skip-terraform) SKIP_TERRAFORM=true; shift ;;
        --terminate-gpu) TERMINATE_GPU=true; shift ;;
        --delete-snapshots) DELETE_SNAPSHOTS=true; shift ;;
        --delete-state-bucket) DELETE_STATE_BUCKET=true; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1"; usage; exit 1 ;;
        *) ENVIRONMENT="$1"; shift ;;
    esac
done

main