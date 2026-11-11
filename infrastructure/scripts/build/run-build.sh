#!/usr/bin/env bash
# Runs build-linux-server.ps1 on the UE 5.6 build box through SSM Run Command and
# follows it to completion. No inbound ports, no RDP: the script is uploaded to the
# artifacts bucket, the instance downloads it with its instance role and runs it.
#
# Usage:
#   ./run-build.sh                         # instance from terraform output, master, Linux only
#   ./run-build.sh --ref v1.1-gamelift-anywhere
#   ./run-build.sh --also-windows          # + Win64 server for LaunchDedicatedServer.bat PACKAGED
#   ./run-build.sh --windows-client        # + Win64 *Shipping* client: ApiEndpointUrl / AliasId / Location /
#                                          #   GameSessionQueueName from GAMELIFT_ENDPOINT_URL / GAMELIFT_ALIAS_ID /
#                                          #   GAMELIFT_LOCATION / GAMELIFT_QUEUE_NAME, EOS artifact from SSM
#                                          #   /frontendui/eos/artifacts (SecureString, the +Artifacts=(...) line)
#   ./run-build.sh --windows-client --client-only   # client only, on a box that already built the servers
#   ./run-build.sh --skip-cook             # compile check only (~10 min)
#   ./run-build.sh --instance i-0123... --bucket my-bucket
#
# Requires: aws CLI with permissions for ssm:SendCommand / GetCommandInvocation and
# s3:PutObject on the bucket; terraform (only to read outputs when --instance is omitted).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../../terraform/environments/dev"
REGION="${AWS_REGION:-us-east-1}"
BUCKET="ue5-artifacts-326105557351-us-east-1"
INSTANCE=""
REF="master"
EXTRA_PS=""
TIMEOUT_S=14400   # 4 h: first cook of a project on a cold DDC can take a while

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance) INSTANCE="$2"; shift 2 ;;
    --bucket)   BUCKET="$2";   shift 2 ;;
    --ref)      REF="$2";      shift 2 ;;
    --region)   REGION="$2";   shift 2 ;;
    --also-windows) EXTRA_PS="$EXTRA_PS -AlsoWindows"; shift ;;
    --windows-client)
      EXTRA_PS="$EXTRA_PS -WindowsClient -GameLiftRegion '$REGION'"
      [[ -n "${GAMELIFT_ENDPOINT_URL:-}" ]] && EXTRA_PS="$EXTRA_PS -GameLiftEndpoint '$GAMELIFT_ENDPOINT_URL'"
      [[ -n "${GAMELIFT_ALIAS_ID:-}" ]]     && EXTRA_PS="$EXTRA_PS -GameLiftAlias '$GAMELIFT_ALIAS_ID'"
      [[ -n "${GAMELIFT_LOCATION:-}" ]]     && EXTRA_PS="$EXTRA_PS -GameLiftLocation '$GAMELIFT_LOCATION'"
      [[ -n "${GAMELIFT_QUEUE_NAME:-}" ]]   && EXTRA_PS="$EXTRA_PS -GameLiftQueue '$GAMELIFT_QUEUE_NAME'"
      shift ;;
    --client-only)  EXTRA_PS="$EXTRA_PS -Platforms None"; shift ;;   # with --windows-client: skip the servers
    --skip-cook)    EXTRA_PS="$EXTRA_PS -SkipCook"; TIMEOUT_S=3600; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$INSTANCE" ]]; then
  INSTANCE="$(terraform -chdir="$TF_DIR" output -raw instance_id 2>/dev/null || true)"
  [[ -n "$INSTANCE" ]] || { echo "No --instance given and no terraform output instance_id" >&2; exit 2; }
fi

echo "instance : $INSTANCE ($REGION)"
echo "ref      : $REF"
echo "bucket   : s3://$BUCKET"

# 1. Wait for the SSM agent (fresh Windows boots take 3-6 min).
echo -n "waiting for SSM agent"
for _ in $(seq 1 60); do
  st="$(aws ssm describe-instance-information --region "$REGION" \
        --filters "Key=InstanceIds,Values=$INSTANCE" \
        --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)"
  [[ "$st" == "Online" ]] && { echo " online"; break; }
  echo -n "."; sleep 10
done
[[ "$st" == "Online" ]] || { echo; echo "SSM agent not online after 10 min" >&2; exit 1; }

# 2. Ship the build script via S3 (SSM parameters cap at ~48 KB and quoting PowerShell inline is fragile).
aws s3 cp "$SCRIPT_DIR/build-linux-server.ps1" "s3://$BUCKET/scripts/build-linux-server.ps1" --region "$REGION" --only-show-errors

# 3. Run it.
read -r -d '' BOOT <<EOF || true
\$ErrorActionPreference = 'Stop'
\$aws = 'C:\\Program Files\\Amazon\\AWSCLIV2\\aws.exe'
for (\$i = 0; \$i -lt 60 -and -not (Test-Path \$aws); \$i++) { Start-Sleep 10 }   # user-data still installing the CLI
New-Item -ItemType Directory -Force -Path C:\\ue5-build | Out-Null
& \$aws s3 cp s3://$BUCKET/scripts/build-linux-server.ps1 C:\\ue5-build\\build-linux-server.ps1 --only-show-errors
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\ue5-build\\build-linux-server.ps1 -Ref '$REF' -S3Bucket '$BUCKET' $EXTRA_PS
exit \$LASTEXITCODE
EOF

CMD_ID="$(aws ssm send-command --region "$REGION" \
  --instance-ids "$INSTANCE" \
  --document-name "AWS-RunPowerShellScript" \
  --comment "FrontendUI LinuxServer build ($REF)" \
  --timeout-seconds 600 \
  --parameters "$(jq -cn --arg c "$BOOT" --arg t "$TIMEOUT_S" '{commands: ($c | split("\n")), executionTimeout: [$t]}')" \
  --query 'Command.CommandId' --output text)"
echo "command  : $CMD_ID"
echo "log      : aws ssm get-command-invocation --region $REGION --command-id $CMD_ID --instance-id $INSTANCE --query StandardOutputContent --output text"

# 4. Follow.
last=""
while true; do
  inv="$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE" 2>/dev/null || true)"
  status="$(jq -r '.Status // "Pending"' <<<"$inv")"
  out="$(jq -r '.StandardOutputContent // ""' <<<"$inv")"
  if [[ "$out" != "$last" ]]; then
    # print only the new tail
    printf '%s\n' "$out" | tail -n +"$(( $(printf '%s\n' "$last" | wc -l) + 1 ))"
    last="$out"
  fi
  case "$status" in
    Success) echo "== SUCCESS"; break ;;
    Failed|Cancelled|TimedOut|Cancelling) echo "== $status"; jq -r '.StandardErrorContent // ""' <<<"$inv" | tail -n 30; exit 1 ;;
  esac
  sleep 20
done

echo
echo "artifacts:"
aws s3 ls "s3://$BUCKET/builds/" --region "$REGION" --human-readable | tail -n 5
