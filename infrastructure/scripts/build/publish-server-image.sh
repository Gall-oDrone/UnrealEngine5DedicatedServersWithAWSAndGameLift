#!/usr/bin/env bash
# Turn a LinuxServer zip from the build box into the GameLift server image.
#
#   publish-server-image.sh --zip s3://<bucket>/builds/FrontendUI-LinuxServer-<sha>-<stamp>.zip \
#                           --game-dir <checkout of the game repo: Dockerfile, docker/, .dockerignore> \
#                           [--tag <sha>] [--repo frontendui-server] [--no-push]
#
# Unzips into <game-dir>/Saved/StagedBuilds/ (what the Dockerfile COPYs), builds
# <account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>, pushes it and prints image=<uri>.
# The tag defaults to the <sha> in the zip name. Used by .github/workflows/server-image.yml;
# works the same from a laptop. Needs: aws (ECR + S3 read), docker, unzip.
set -euo pipefail
REGION="${AWS_REGION:-us-east-1}"
ZIP=""; GAME_DIR=""; TAG=""; REPO="frontendui-server"; PUSH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip) ZIP="$2"; shift 2 ;;
    --game-dir) GAME_DIR="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --no-push) PUSH=0; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$ZIP" && -n "$GAME_DIR" ]] || { echo "--zip and --game-dir are required" >&2; exit 2; }
[[ -f "$GAME_DIR/Dockerfile" ]] || { echo "no Dockerfile in $GAME_DIR" >&2; exit 2; }
if [[ -z "$TAG" ]]; then
  TAG=$(basename "$ZIP" | sed -n -E 's/^FrontendUI-LinuxServer-([0-9a-f]+)-[0-9]{8}-[0-9]{6}\.zip$/\1/p')
  [[ -n "$TAG" ]] || { echo "cannot derive the tag from $(basename "$ZIP"); pass --tag" >&2; exit 2; }
fi
log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

STAGE="$GAME_DIR/Saved/StagedBuilds"
mkdir -p "$STAGE"
rm -rf "$STAGE/LinuxServer"
local_zip="$STAGE/$(basename "$ZIP")"
log "downloading $ZIP"
aws s3 cp "$ZIP" "$local_zip" --region "$REGION" --only-show-errors
log "unzipping into $STAGE"
unzip -q -o "$local_zip" -d "$STAGE"
rm -f "$local_zip"
[[ -f "$STAGE/LinuxServer/FrontendUIServer.sh" ]] || { echo "LinuxServer/FrontendUIServer.sh missing after unzip" >&2; exit 1; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
IMAGE="$ECR/$REPO:$TAG"
log "docker build $IMAGE"
docker build -t "$IMAGE" "$GAME_DIR" >/dev/null
docker image inspect "$IMAGE" --format 'size={{.Size}} bytes' | sed "s/^/[$(date -u +%H:%M:%S)] /"

if [[ "$PUSH" == "1" ]]; then
  log "pushing to ECR"
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR" >/dev/null
  docker push "$IMAGE" >/dev/null
  DIGEST=$(aws ecr describe-images --region "$REGION" --repository-name "$REPO" --image-ids imageTag="$TAG" --query 'imageDetails[0].imageDigest' --output text)
  log "pushed $IMAGE ($DIGEST)"
fi
echo "image=$IMAGE"
echo "tag=$TAG"
