#!/bin/bash
# Deploy and monitor Unreal Engine 5 IDE CloudFormation stacks (IAM -> Base -> CloudFront)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFN_DIR="$(dirname "$SCRIPT_DIR")"

TEMPLATE_FILE="${CFN_DIR}/unreal-engine-5-ide-cfn.yaml"
IAM_TEMPLATE_FILE="${CFN_DIR}/unreal-engine-5-ide-iam-cfn.yaml"
CLOUDFRONT_TEMPLATE_FILE="${CFN_DIR}/unreal-engine-5-ide-cloudfront-cfn.yaml"

STACK_NAME="${STACK_NAME:-unreal-engine-5-ide}"
IAM_STACK_NAME="${IAM_STACK_NAME:-${STACK_NAME}-iam}"
CLOUDFRONT_STACK_NAME="${CLOUDFRONT_STACK_NAME:-${STACK_NAME}-cloudfront}"
CLOUDFRONT_PRICE_CLASS="${CLOUDFRONT_PRICE_CLASS:-PriceClass_All}"
AWS_REGION="${AWS_REGION:-us-east-1}"
TIMEOUT_SECONDS=$(( ${TIMEOUT_MINUTES:-30} * 60 ))
POLL_INTERVAL=30
LOG_FILE="${SCRIPT_DIR}/deploy-stack.log"

REPOSITORY_OWNER="${REPOSITORY_OWNER:-Gall-oDrone}"
REPOSITORY_NAME="${REPOSITORY_NAME:-UnrealEngine5DedicatedServersWithAWSAndGameLift}"
REPOSITORY_REF="${REPOSITORY_REF:-main}"
INSTANCE_VOLUME_SIZE="${INSTANCE_VOLUME_SIZE:-30}"
ENVIRONMENT="${ENVIRONMENT:-}"
EKS_CLUSTER_ID="${EKS_CLUSTER_ID:-$STACK_NAME}"

log() {
  local level=$1; shift
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] [$level] $*" | tee -a "$LOG_FILE"
}
log_info(){ echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; log INFO "$1"; }
log_success(){ echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; log SUCCESS "$1"; }
log_warning(){ echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; log WARNING "$1"; }
log_error(){ echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; log ERROR "$1"; }
log_debug(){ echo -e "${CYAN}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"; log DEBUG "$1"; }

error_exit() {
  log_error "Script failed at line $1"
  exit 1
}
trap 'error_exit $LINENO' ERR

check_prerequisites() {
  command -v aws >/dev/null 2>&1 || { log_error "AWS CLI is required"; exit 1; }
  aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1 || { log_error "AWS credentials are invalid"; exit 1; }
  for file in "$TEMPLATE_FILE" "$IAM_TEMPLATE_FILE" "$CLOUDFRONT_TEMPLATE_FILE"; do
    [[ -f "$file" ]] || { log_error "Missing template file: $file"; exit 1; }
  done
  log_success "Prerequisites check passed"
}

stack_exists() {
  aws cloudformation describe-stacks --stack-name "$1" --region "$AWS_REGION" >/dev/null 2>&1
}

get_stack_status() {
  aws cloudformation describe-stacks --stack-name "$1" --region "$AWS_REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NONE"
}

wait_for_stack() {
  local stack_name=$1
  local operation=$2
  local start elapsed status
  start=$(date +%s)

  while true; do
    status=$(get_stack_status "$stack_name")
    case "$status" in
      CREATE_COMPLETE|UPDATE_COMPLETE)
        log_success "Stack '$stack_name' ${operation} completed"
        return 0
        ;;
      *_FAILED|*_ROLLBACK_*)
        log_error "Stack '$stack_name' failed with status: $status"
        aws cloudformation describe-stack-events --stack-name "$stack_name" --region "$AWS_REGION" --query 'StackEvents[0:10]' --output table | tee -a "$LOG_FILE" || true
        exit 1
        ;;
      NONE)
        log_error "Stack '$stack_name' was not found"
        exit 1
        ;;
      *)
        elapsed=$(( $(date +%s) - start ))
        if (( elapsed > TIMEOUT_SECONDS )); then
          log_error "Timed out waiting for '$stack_name' after ${TIMEOUT_SECONDS}s"
          exit 1
        fi
        if (( elapsed % 120 == 0 )); then
          log_info "${stack_name}: ${status} (${elapsed}s elapsed)"
        fi
        sleep "$POLL_INTERVAL"
        ;;
    esac
  done
}

upload_template_to_s3() {
  local template_file=$1
  local stack_alias=$2
  local account bucket key
  account=$(aws sts get-caller-identity --query 'Account' --output text)
  bucket="cfn-templates-${account}-${AWS_REGION}"
  key="unreal-engine-5-ide/${stack_alias}-$(date +%Y%m%d-%H%M%S).yaml"

  if ! aws s3 ls "s3://${bucket}" >/dev/null 2>&1; then
    log_info "Creating S3 bucket: ${bucket}" >&2
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "$bucket" --region "$AWS_REGION" >/dev/null
    else
      aws s3api create-bucket --bucket "$bucket" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
    fi
  fi

  aws s3 cp "$template_file" "s3://${bucket}/${key}" --region "$AWS_REGION" >/dev/null
  echo "https://${bucket}.s3.${AWS_REGION}.amazonaws.com/${key}"
}

deploy_stack() {
  local stack_name=$1
  local template_file=$2
  shift 2
  local params=("$@")
  local template_url
  template_url=$(upload_template_to_s3 "$template_file" "$stack_name")

  if stack_exists "$stack_name"; then
    log_info "Updating stack: $stack_name"
    local output
    if output=$(aws cloudformation update-stack --stack-name "$stack_name" --template-url "$template_url" --capabilities CAPABILITY_NAMED_IAM --parameters "${params[@]}" --region "$AWS_REGION" 2>&1); then
      wait_for_stack "$stack_name" "update"
    else
      if echo "$output" | rg -q "No updates are to be performed"; then
        log_warning "No updates needed for $stack_name"
      else
        log_error "$output"
        exit 1
      fi
    fi
  else
    log_info "Creating stack: $stack_name"
    aws cloudformation create-stack --stack-name "$stack_name" --template-url "$template_url" --capabilities CAPABILITY_NAMED_IAM --parameters "${params[@]}" --region "$AWS_REGION" >/dev/null
    wait_for_stack "$stack_name" "create"
  fi
}

main() {
  log_info "Starting Unreal Engine 5 IDE stack deployment"
  log_info "Region: $AWS_REGION"
  log_info "Repository: $REPOSITORY_OWNER/$REPOSITORY_NAME@$REPOSITORY_REF"
  check_prerequisites

  deploy_stack "$IAM_STACK_NAME" "$IAM_TEMPLATE_FILE" \
    "ParameterKey=ParentStackName,ParameterValue=$STACK_NAME"

  local instance_profile
  instance_profile=$(aws cloudformation describe-stacks --stack-name "$IAM_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='InstanceProfileName'].OutputValue" --output text)
  [[ -n "$instance_profile" && "$instance_profile" != "None" ]] || { log_error "InstanceProfileName output missing from IAM stack"; exit 1; }

  deploy_stack "$STACK_NAME" "$TEMPLATE_FILE" \
    "ParameterKey=RepositoryOwner,ParameterValue=$REPOSITORY_OWNER" \
    "ParameterKey=RepositoryName,ParameterValue=$REPOSITORY_NAME" \
    "ParameterKey=RepositoryRef,ParameterValue=$REPOSITORY_REF" \
    "ParameterKey=InstanceVolumeSize,ParameterValue=$INSTANCE_VOLUME_SIZE" \
    "ParameterKey=Environment,ParameterValue=$ENVIRONMENT" \
    "ParameterKey=EksClusterId,ParameterValue=$EKS_CLUSTER_ID" \
    "ParameterKey=InstanceProfileName,ParameterValue=$instance_profile"

  local instance_dns
  instance_dns=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='InstancePublicDnsName'].OutputValue" --output text)
  [[ -n "$instance_dns" && "$instance_dns" != "None" ]] || { log_error "InstancePublicDnsName output missing from base stack"; exit 1; }

  deploy_stack "$CLOUDFRONT_STACK_NAME" "$CLOUDFRONT_TEMPLATE_FILE" \
    "ParameterKey=ParentStackName,ParameterValue=$STACK_NAME" \
    "ParameterKey=InstancePublicDnsName,ParameterValue=$instance_dns" \
    "ParameterKey=PriceClass,ParameterValue=$CLOUDFRONT_PRICE_CLASS"

  local ide_url secret_name
  ide_url=$(aws cloudformation describe-stacks --stack-name "$CLOUDFRONT_STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='IdeUrl'].OutputValue" --output text || true)
  secret_name=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs[?OutputKey=='IdePasswordSecretName'].OutputValue" --output text || true)

  log_success "Deployment completed"
  [[ -n "$ide_url" && "$ide_url" != "None" ]] && log_success "IDE URL: $ide_url"
  [[ -n "$secret_name" && "$secret_name" != "None" ]] && log_info "Secret name: $secret_name"

  if [[ -n "$secret_name" && "$secret_name" != "None" ]]; then
    local secret_json password
    secret_json=$(aws secretsmanager get-secret-value --secret-id "$secret_name" --region "$AWS_REGION" --query 'SecretString' --output text 2>/dev/null || true)
    password=$(printf '%s' "$secret_json" | python3 -c 'import sys,json; s=sys.stdin.read().strip(); print(json.loads(s).get("password","")) if s else print("")' 2>/dev/null || true)
    [[ -n "$password" ]] && log_success "IDE Password: $password"
  fi
}

main "$@"
