#!/bin/bash
#
# manage_snapshot.sh - Manage the archived Unreal Engine 5.6 EBS snapshot.
#
# The UE 5.6 build environment (VS2022, UE 5.6 compiled from GitHub source,
# NVIDIA drivers, installers; ~450 GB of data on a 500 GB volume) is kept as
# an EBS snapshot in the ARCHIVE tier (~$0.0125/GB-month ≈ $5-6/month).
#
# An archived snapshot cannot be used to create a volume. Before running
# `terraform apply` it must be restored to the standard tier, which takes
# 24-72 hours and costs a one-time ~$0.03/GB (~$13 for this snapshot).
#
#   temporary restore : standard-tier copy for N days, then auto re-archives.
#                       You pay standard rate (~$0.05/GB-month, pro-rated) on
#                       top of the archive rate while restored.
#   permanent restore : snapshot moves back to standard tier (~$21/month)
#                       until you archive it again.
#
# NOTE: archive has a 90-day minimum. This snapshot was archived on
# 2026-11-04, so re-archiving / deleting before 2027-02-02 still bills 90 days.
#
# Usage:
#   manage_snapshot.sh status                    # tier, restore expiry, size
#   manage_snapshot.sh restore [--days N|--permanent] [--wait]
#   manage_snapshot.sh wait                      # block until restore completes
#   manage_snapshot.sh extend --days N           # change temporary restore period
#   manage_snapshot.sh archive                   # move back to archive tier
#   manage_snapshot.sh list                      # all snapshots owned by this account
#
# Options:
#   -s, --snapshot-id ID   (default: value in terraform variables / env SNAPSHOT_ID)
#   -r, --region REGION    (default: us-east-1)
#   -y, --yes              skip confirmation prompts
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TF_VARS_FILE="$INFRA_ROOT/terraform/environments/dev/variables.tf"
[[ -f "$TF_VARS_FILE" ]] || TF_VARS_FILE="$INFRA_ROOT/environments/dev/variables.tf"

# Canonical UE 5.6 snapshot. Falls back to the Terraform default so the two
# never drift silently.
DEFAULT_SNAPSHOT_ID="snap-0777feef308067690"
if [[ -f "$TF_VARS_FILE" ]]; then
    tf_default=$(awk '/variable "data_volume_snapshot_id"/,/^}/' "$TF_VARS_FILE" \
        | grep -E '^\s*default\s*=' | sed -E 's/.*"([^"]*)".*/\1/' || true)
    [[ -n "${tf_default:-}" ]] && DEFAULT_SNAPSHOT_ID="$tf_default"
fi

SNAPSHOT_ID="${SNAPSHOT_ID:-$DEFAULT_SNAPSHOT_ID}"
AWS_REGION="${AWS_REGION:-us-east-1}"
RESTORE_DAYS=7
PERMANENT=false
WAIT=false
ASSUME_YES=false
POLL_SECONDS=300
COMMAND=""

usage() { sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; }

confirm() {
    [[ "$ASSUME_YES" == true ]] && return 0
    read -r -p "$1 [y/N]: " ans
    [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

need_tools() {
    for t in aws jq; do
        command -v "$t" >/dev/null 2>&1 || { err "'$t' is required"; exit 1; }
    done
    aws sts get-caller-identity >/dev/null 2>&1 || { err "AWS credentials not configured"; exit 1; }
}

snapshot_json() {
    aws ec2 describe-snapshots --region "$AWS_REGION" --snapshot-ids "$SNAPSHOT_ID" \
        --query 'Snapshots[0]' --output json 2>/dev/null || echo "null"
}

tier_json() {
    aws ec2 describe-snapshot-tier-status --region "$AWS_REGION" \
        --filters "Name=snapshot-id,Values=$SNAPSHOT_ID" \
        --query 'SnapshotTierStatuses[0]' --output json 2>/dev/null || echo "null"
}

cmd_status() {
    local snap tier
    snap=$(snapshot_json)
    if [[ "$snap" == "null" ]]; then
        err "Snapshot $SNAPSHOT_ID not found in $AWS_REGION"
        exit 2
    fi
    tier=$(tier_json)

    local state size full desc storage_tier op op_detail progress expiry archived
    state=$(jq -r '.State' <<<"$snap")
    size=$(jq -r '.VolumeSize' <<<"$snap")
    full=$(jq -r '.FullSnapshotSizeInBytes // 0' <<<"$snap")
    desc=$(jq -r '.Description // ""' <<<"$snap")
    storage_tier=$(jq -r '.StorageTier // "standard"' <<<"$snap")
    op=$(jq -r '.LastTieringOperationStatus // "n/a"' <<<"$tier")
    op_detail=$(jq -r '.LastTieringOperationStatusDetail // ""' <<<"$tier")
    progress=$(jq -r '.LastTieringProgress // 0' <<<"$tier")
    expiry=$(jq -r '.RestoreExpiryTime // "-"' <<<"$tier")
    archived=$(jq -r '.ArchivalCompleteTime // "-"' <<<"$tier")

    echo "────────────────────────────────────────────────────────────"
    echo " Snapshot      : $SNAPSHOT_ID ($AWS_REGION)"
    echo " Description   : $desc"
    echo " State         : $state"
    echo " Volume size   : ${size} GB   (actual data: $(awk "BEGIN{printf \"%.1f\", $full/1024/1024/1024}") GiB)"
    echo " Storage tier  : $storage_tier"
    echo " Last tier op  : $op ${op_detail:+($op_detail)} ${progress}%"
    echo " Archived at   : $archived"
    echo " Restore expiry: $expiry   (temporary restores only; '-' = permanent/standard)"
    echo "────────────────────────────────────────────────────────────"

    case "$storage_tier:$op" in
        standard:*)
            ok "Snapshot is in the STANDARD tier - Terraform can create volumes from it."
            [[ "$expiry" != "-" && "$expiry" != "null" ]] && warn "Temporary restore expires $expiry - it will re-archive automatically afterwards."
            return 0 ;;
        archive:temporary-restore-in-progress|archive:permanent-restore-in-progress)
            warn "Restore in progress (${progress}%). Run '$0 wait' to block until done."
            return 3 ;;
        archive:*)
            warn "Snapshot is ARCHIVED. Run '$0 restore [--days N|--permanent] [--wait]' before terraform apply."
            return 3 ;;
    esac
}

cmd_restore() {
    local snap storage_tier
    snap=$(snapshot_json)
    [[ "$snap" == "null" ]] && { err "Snapshot $SNAPSHOT_ID not found"; exit 2; }
    storage_tier=$(jq -r '.StorageTier // "standard"' <<<"$snap")
    if [[ "$storage_tier" == "standard" ]]; then
        ok "Snapshot already in standard tier - nothing to restore."
        cmd_status || true
        return 0
    fi

    local size cost
    size=$(jq -r '.VolumeSize' <<<"$snap")
    cost=$(awk "BEGIN{printf \"%.2f\", $size*0.03}")
    if [[ "$PERMANENT" == true ]]; then
        warn "PERMANENT restore: one-time retrieval ≈ \$$cost, then ~\$$(awk "BEGIN{printf \"%.0f\", $size*0.05}")/month until re-archived."
    else
        warn "TEMPORARY restore for $RESTORE_DAYS day(s): one-time retrieval ≈ \$$cost + pro-rated standard storage."
    fi
    warn "Restores take 24-72 hours to complete."
    confirm "Start restore of $SNAPSHOT_ID now?" || { info "Aborted."; return 1; }

    if [[ "$PERMANENT" == true ]]; then
        aws ec2 restore-snapshot-tier --region "$AWS_REGION" --snapshot-id "$SNAPSHOT_ID" --permanent-restore --output json
    else
        aws ec2 restore-snapshot-tier --region "$AWS_REGION" --snapshot-id "$SNAPSHOT_ID" --temporary-restore-days "$RESTORE_DAYS" --output json
    fi
    ok "Restore requested."
    [[ "$WAIT" == true ]] && cmd_wait
    return 0
}

cmd_wait() {
    info "Waiting for $SNAPSHOT_ID to reach the standard tier (polling every ${POLL_SECONDS}s, Ctrl-C to stop)..."
    local start now
    start=$(date +%s)
    while true; do
        local snap tier storage_tier op progress
        snap=$(snapshot_json); tier=$(tier_json)
        storage_tier=$(jq -r '.StorageTier // "standard"' <<<"$snap")
        op=$(jq -r '.LastTieringOperationStatus // ""' <<<"$tier")
        progress=$(jq -r '.LastTieringProgress // 0' <<<"$tier")
        if [[ "$storage_tier" == "standard" ]]; then
            ok "Restore complete - snapshot is in the standard tier."
            cmd_status || true
            return 0
        fi
        case "$op" in
            *failed*) err "Tiering operation failed: $(jq -r '.LastTieringOperationStatusDetail // ""' <<<"$tier")"; return 1 ;;
        esac
        now=$(date +%s)
        info "tier=$storage_tier op=${op:-n/a} progress=${progress}% elapsed=$(( (now-start)/60 ))m"
        sleep "$POLL_SECONDS"
    done
}

cmd_extend() {
    confirm "Change temporary restore period of $SNAPSHOT_ID to $RESTORE_DAYS day(s)?" || return 1
    aws ec2 modify-snapshot-tier --region "$AWS_REGION" --snapshot-id "$SNAPSHOT_ID" --storage-tier archive \
        --output json >/dev/null 2>&1 || true   # no-op if already archive; restore period is changed via restore-snapshot-tier
    aws ec2 restore-snapshot-tier --region "$AWS_REGION" --snapshot-id "$SNAPSHOT_ID" --temporary-restore-days "$RESTORE_DAYS" --output json
    ok "Restore period updated."
}

cmd_archive() {
    local snap storage_tier
    snap=$(snapshot_json)
    storage_tier=$(jq -r '.StorageTier // "standard"' <<<"$snap")
    if [[ "$storage_tier" == "archive" ]]; then
        local tier op
        tier=$(tier_json); op=$(jq -r '.LastTieringOperationStatus // ""' <<<"$tier")
        if [[ "$op" == "temporary-restore-completed" ]]; then
            confirm "Snapshot is temporarily restored. End the temporary restore now?" || return 1
            aws ec2 modify-snapshot-tier --region "$AWS_REGION" --snapshot-id "$SNAPSHOT_ID" --storage-tier archive --output json
            ok "Temporary restore ended; snapshot is archive-only again."
        else
            ok "Snapshot already archived."
        fi
        return 0
    fi
    warn "Archiving takes the snapshot out of reach of terraform apply (needs 24-72 h restore)."
    warn "Archive tier has a 90-day minimum charge."
    confirm "Move $SNAPSHOT_ID to the archive tier?" || return 1
    aws ec2 modify-snapshot-tier --region "$AWS_REGION" --snapshot-id "$SNAPSHOT_ID" --storage-tier archive --output json
    ok "Archival requested (completes in the background, typically < 2 h)."
}

cmd_list() {
    aws ec2 describe-snapshots --region "$AWS_REGION" --owner-ids self \
        --query 'Snapshots[].{Id:SnapshotId,SizeGB:VolumeSize,Tier:StorageTier,State:State,Started:StartTime,Name:Tags[?Key==`Name`]|[0].Value,Desc:Description}' \
        --output table
}

# ---- arg parsing -----------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        status|restore|wait|extend|archive|list) COMMAND="$1"; shift ;;
        -s|--snapshot-id) SNAPSHOT_ID="$2"; shift 2 ;;
        -r|--region) AWS_REGION="$2"; shift 2 ;;
        --days) RESTORE_DAYS="$2"; shift 2 ;;
        --permanent) PERMANENT=true; shift ;;
        --wait) WAIT=true; shift ;;
        --poll) POLL_SECONDS="$2"; shift 2 ;;
        -y|--yes) ASSUME_YES=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

[[ -z "$COMMAND" ]] && { usage; exit 1; }
need_tools
case "$COMMAND" in
    status)  cmd_status ;;
    restore) cmd_restore ;;
    wait)    cmd_wait ;;
    extend)  cmd_extend ;;
    archive) cmd_archive ;;
    list)    cmd_list ;;
esac
