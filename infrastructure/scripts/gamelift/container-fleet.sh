#!/usr/bin/env bash
# Lifecycle of the FrontendUI Amazon GameLift Managed Container Fleet, as verified by hand in
# Docs/GameLift.md §5, with target-tracking auto-scaling and alias switching added.
#
#   container-fleet.sh create  [--image-tag <sha>] [--instance-type c6i.xlarge] [--min 1] [--max 2]
#                              [--target 50] [--alias <alias-id>] [--cidr 0.0.0.0/0]
#   container-fleet.sh cgd     --image-tag <sha> [--fleet-id <containerfleet-id>]   # new CGD version only (CI)
#   container-fleet.sh status  [--fleet-id <containerfleet-id>]      # default: the fleet the alias points at
#   container-fleet.sh delete  --fleet-id <containerfleet-id> [--alias <alias-id> --restore-fleet <fleet-id>]
#
# create:  CGD version for the image (new version only if the tag changed) -> fleet -> wait ACTIVE
#          -> capacity min/max -> target-tracking policy on PercentAvailableGameSessions
#          -> optional alias switch -> prints a client-free smoke test.
# cgd:     CGD version for the image, nothing billable; with --fleet-id also starts the rolling
#          deployment of that version onto the running fleet (~10 min) and waits for it.
# delete:  optional alias restore -> delete fleet -> wait until gone. The CGD and ECR image stay.
#
# Billing: >= min instances x instance price from create until delete. Default c6i.xlarge
# (~$0.17/h) runs 3 game sessions per instance with the 1 vCPU / 2 GiB CGD; c6i.large (~$0.09/h)
# runs 1, which makes target tracking useless (nothing is "available" while the only slot is busy).
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
CGD_NAME="${CGD_NAME:-frontendui-server}"
ECR_REPO="${ECR_REPO:-frontendui-server}"
ROLE_NAME="${FLEET_ROLE_NAME:-FrontendUI-GameLiftContainerFleetRole}"
PORT_FROM=7777
PORT_TO=7877

cmd="${1:-}"; shift || true
IMAGE_TAG="latest"; INSTANCE_TYPE="c6i.xlarge"; MIN=1; MAX=2; TARGET=50; ALIAS=""; CIDR="0.0.0.0/0"
FLEET_ID=""; RESTORE_FLEET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image-tag) IMAGE_TAG="$2"; shift 2 ;;
    --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
    --min) MIN="$2"; shift 2 ;;
    --max) MAX="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --alias) ALIAS="$2"; shift 2 ;;
    --cidr) CIDR="$2"; shift 2 ;;
    --fleet-id) FLEET_ID="$2"; shift 2 ;;
    --restore-fleet) RESTORE_FLEET="$2"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

gl() { aws gamelift --region "$REGION" "$@"; }
log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

fleet_status() { gl describe-container-fleet --fleet-id "$1" --query 'ContainerFleet.Status' --output text 2>/dev/null || echo "GONE"; }
deployment_status() { gl describe-fleet-deployment --fleet-id "$1" --query 'FleetDeployment.DeploymentStatus' --output text 2>/dev/null || echo "-"; }

wait_fleet_active() {
  local f="$1" s d
  for _ in $(seq 1 90); do
    s=$(fleet_status "$f"); d=$(deployment_status "$f")
    log "fleet=$s deployment=$d"
    case "$s:$d" in
      ACTIVE:COMPLETE|ACTIVE:-) return 0 ;;
      *:IMPAIRED|ERROR:*|DELETING:*|GONE:*)
        echo "fleet did not activate. Container stdout: CloudWatch log group gamelift-$f-$REGION" >&2
        gl describe-fleet-events --fleet-id "$f" --query 'Events[-5:].[EventTime,EventCode]' --output text >&2
        return 1 ;;
    esac
    sleep 30
  done
  echo "timed out waiting for the fleet" >&2; return 1
}

ensure_cgd_version() {
  local account ecr uri current
  account=$(aws sts get-caller-identity --query Account --output text)
  ecr="$account.dkr.ecr.$REGION.amazonaws.com"
  uri="$ecr/$ECR_REPO:$IMAGE_TAG"
  aws ecr describe-images --region "$REGION" --repository-name "$ECR_REPO" --image-ids imageTag="$IMAGE_TAG" --query 'imageDetails[0].imageDigest' --output text >/dev/null \
    || { echo "image $uri not found in ECR" >&2; return 1; }
  current=$(gl describe-container-group-definition --name "$CGD_NAME" --query 'ContainerGroupDefinition.GameServerContainerDefinition.ImageUri' --output text 2>/dev/null || echo "")
  if [[ "$current" == "$uri" ]]; then
    log "CGD $CGD_NAME already at $uri"
  else
    log "CGD $CGD_NAME: new version for $uri"
    gl update-container-group-definition --name "$CGD_NAME" --version-description "$IMAGE_TAG" \
      --game-server-container-definition "{\"ContainerName\":\"frontendui\",\"ImageUri\":\"$uri\",\"ServerSdkVersion\":\"5.2.0\",\"PortConfiguration\":{\"ContainerPortRanges\":[{\"FromPort\":7777,\"ToPort\":7777,\"Protocol\":\"UDP\"}]}}" \
      --query 'ContainerGroupDefinition.VersionNumber' --output text >/dev/null
    for _ in $(seq 1 20); do
      s=$(gl describe-container-group-definition --name "$CGD_NAME" --query 'ContainerGroupDefinition.Status' --output text)
      [[ "$s" == "READY" ]] && break
      [[ "$s" == "FAILED" ]] && { echo "CGD version FAILED" >&2; return 1; }
      sleep 15
    done
  fi
  CGD_ARN=$(gl describe-container-group-definition --name "$CGD_NAME" --query 'ContainerGroupDefinition.ContainerGroupDefinitionArn' --output text)
}

case "$cmd" in
  create)
    ensure_cgd_version
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)
    log "creating fleet: $INSTANCE_TYPE, image tag $IMAGE_TAG, UDP $PORT_FROM-$PORT_TO from $CIDR"
    FLEET_ID=$(gl create-container-fleet --cli-input-json "$(cat <<EOF
{"FleetRoleArn":"$ROLE_ARN","Description":"FrontendUI container fleet ($IMAGE_TAG)",
 "GameServerContainerGroupDefinitionName":"$CGD_ARN",
 "InstanceConnectionPortRange":{"FromPort":$PORT_FROM,"ToPort":$PORT_TO},
 "InstanceInboundPermissions":[{"FromPort":$PORT_FROM,"ToPort":$PORT_TO,"IpRange":"$CIDR","Protocol":"UDP"}],
 "InstanceType":"$INSTANCE_TYPE","BillingType":"ON_DEMAND","Locations":[{"Location":"$REGION"}],
 "LogConfiguration":{"LogDestination":"CLOUDWATCH"},"NewGameSessionProtectionPolicy":"NoProtection",
 "Tags":[{"Key":"Project","Value":"FrontendUI"},{"Key":"Env","Value":"dev"}]}
EOF
)" --query 'ContainerFleet.FleetId' --output text)
    log "fleet $FLEET_ID"
    # Both settings are checked back: the CLI shorthand for the port range was silently dropped once.
    gl describe-container-fleet --fleet-id "$FLEET_ID" --query 'ContainerFleet.[InstanceConnectionPortRange,LogConfiguration]' --output json
    wait_fleet_active "$FLEET_ID"

    log "capacity min=$MIN max=$MAX, target $TARGET% available game sessions"
    gl update-fleet-capacity --fleet-id "$FLEET_ID" --location "$REGION" --min-size "$MIN" --desired-instances "$MIN" --max-size "$MAX" >/dev/null
    gl put-scaling-policy --fleet-id "$FLEET_ID" --name keep-available-sessions --policy-type TargetBased \
      --metric-name PercentAvailableGameSessions --target-configuration "TargetValue=$TARGET" >/dev/null
    if [[ -n "$ALIAS" ]]; then
      log "alias $ALIAS -> $FLEET_ID"
      gl update-alias --alias-id "$ALIAS" --routing-strategy "Type=SIMPLE,FleetId=$FLEET_ID" >/dev/null
    fi
    cat <<EOF

fleet ready: $FLEET_ID
smoke test (then terminate it - a player-less session pins a process):
  aws gamelift create-game-session --region $REGION --fleet-id $FLEET_ID --maximum-player-session-count 2 --name Probe --query 'GameSession.[GameSessionId,IpAddress,Port,Status]' --output text
  aws gamelift terminate-game-session --region $REGION --game-session-id <arn> --termination-mode TRIGGER_ON_PROCESS_TERMINATE
clients: GAMELIFT_ALIAS_ID=$ALIAS (or GAMELIFT_SDK_FLEET_ID=$FLEET_ID) and GAMELIFT_LOCATION=$REGION
tear down: $0 delete --fleet-id $FLEET_ID${ALIAS:+ --alias $ALIAS --restore-fleet <previous-fleet-id>}
EOF
    ;;

  cgd)
    [[ "$IMAGE_TAG" != "latest" ]] || { echo "--image-tag <sha> required" >&2; exit 2; }
    ensure_cgd_version
    CGD_VERSION=$(gl describe-container-group-definition --name "$CGD_NAME" --query 'ContainerGroupDefinition.VersionNumber' --output text)
    log "CGD $CGD_NAME version $CGD_VERSION -> $CGD_ARN"
    if [[ -n "$FLEET_ID" ]]; then
      log "rolling version $CGD_VERSION onto $FLEET_ID"
      gl update-container-fleet --fleet-id "$FLEET_ID" --game-server-container-group-definition-name "$CGD_NAME" >/dev/null
      for _ in $(seq 1 60); do
        d=$(deployment_status "$FLEET_ID"); log "deployment=$d"
        [[ "$d" == "COMPLETE" ]] && break
        [[ "$d" == "ROLLBACK_COMPLETE" || "$d" == "CANCELLED" ]] && { echo "deployment ended with $d" >&2; exit 1; }
        sleep 20
      done
    fi
    echo "cgd_version=$CGD_VERSION"
    ;;

  status)
    if [[ -z "$FLEET_ID" && -n "$ALIAS" ]]; then FLEET_ID=$(gl describe-alias --alias-id "$ALIAS" --query 'Alias.RoutingStrategy.FleetId' --output text); fi
    [[ -n "$FLEET_ID" ]] || { echo "--fleet-id or --alias required" >&2; exit 2; }
    gl describe-container-fleet --fleet-id "$FLEET_ID" --query 'ContainerFleet.{Status:Status,Type:InstanceType,PerInstance:GameServerContainerGroupsPerInstance,Ports:InstanceConnectionPortRange}' --output json
    gl describe-fleet-location-capacity --fleet-id "$FLEET_ID" --location "$REGION" --query 'FleetCapacity.{Instances:InstanceCounts,Containers:GameServerContainerGroupCounts}' --output json
    gl describe-scaling-policies --fleet-id "$FLEET_ID" --query 'ScalingPolicies[].[Name,Status,MetricName,TargetConfiguration.TargetValue]' --output text
    gl describe-game-sessions --fleet-id "$FLEET_ID" --status-filter ACTIVE --query 'GameSessions[].[Name,CurrentPlayerSessionCount,IpAddress,Port]' --output text
    ;;

  delete)
    [[ -n "$FLEET_ID" ]] || { echo "--fleet-id required" >&2; exit 2; }
    if [[ -n "$ALIAS" && -n "$RESTORE_FLEET" ]]; then
      log "alias $ALIAS -> $RESTORE_FLEET"
      gl update-alias --alias-id "$ALIAS" --routing-strategy "Type=SIMPLE,FleetId=$RESTORE_FLEET" >/dev/null
    fi
    log "deleting $FLEET_ID"
    gl delete-container-fleet --fleet-id "$FLEET_ID"
    for _ in $(seq 1 30); do
      s=$(fleet_status "$FLEET_ID"); log "fleet=$s"
      [[ "$s" == "GONE" ]] && break
      sleep 20
    done
    log "remaining container fleets: $(gl list-container-fleets --query 'length(ContainerFleets)' --output text)"
    ;;

  *) sed -n '2,19p' "$0"; exit 2 ;;
esac
