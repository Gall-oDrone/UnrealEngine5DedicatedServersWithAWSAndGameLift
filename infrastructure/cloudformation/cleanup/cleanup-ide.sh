#!/bin/bash
# Delete Unreal Engine 5 IDE CloudFormation stacks in dependency order.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="${STACK_NAME:-unreal-engine-5-ide}"
IAM_STACK_NAME="${IAM_STACK_NAME:-${STACK_NAME}-iam}"
CLOUDFRONT_STACK_NAME="${CLOUDFRONT_STACK_NAME:-${STACK_NAME}-cloudfront}"
AWS_REGION="${AWS_REGION:-us-east-1}"
MAX_WAIT_TIME=3600
POLL_INTERVAL=30
LOG_FILE="${SCRIPT_DIR}/cleanup-ide.log"
FORCE_DELETE=0

log(){ local l=$1; shift; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$l] $*" | tee -a "$LOG_FILE"; }
log_info(){ echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; log INFO "$1"; }
log_success(){ echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; log SUCCESS "$1"; }
log_warning(){ echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; log WARNING "$1"; }
log_error(){ echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; log ERROR "$1"; }

usage(){
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  -r, --region <region>    AWS region (default: $AWS_REGION)
  -f, --force              Skip delete confirmation prompt
  -h, --help               Show this help
USAGE
}

parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--region) AWS_REGION="$2"; shift 2 ;;
      -f|--force) FORCE_DELETE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

check_prerequisites(){
  command -v aws >/dev/null 2>&1 || { log_error "AWS CLI is required"; exit 1; }
  aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1 || { log_error "AWS credentials are invalid"; exit 1; }
}

stack_exists(){ aws cloudformation describe-stacks --stack-name "$1" --region "$AWS_REGION" >/dev/null 2>&1; }

get_stack_status(){ aws cloudformation describe-stacks --stack-name "$1" --region "$AWS_REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NONE"; }

wait_for_delete(){
  local stack=$1
  local start=$(date +%s)
  while true; do
    local status
    status=$(get_stack_status "$stack")
    case "$status" in
      NONE|DELETE_COMPLETE) log_success "Stack '$stack' deleted"; return 0 ;;
      *FAILED) log_error "Deletion failed for '$stack' ($status)"; exit 1 ;;
      *)
        if (( $(date +%s) - start > MAX_WAIT_TIME )); then
          log_error "Timeout deleting '$stack'"
          exit 1
        fi
        log_info "Waiting on '$stack' (${status})"
        sleep "$POLL_INTERVAL"
        ;;
    esac
  done
}

delete_stack(){
  local stack=$1
  if ! stack_exists "$stack"; then
    log_warning "Stack '$stack' does not exist, skipping"
    return
  fi

  local status
  status=$(get_stack_status "$stack")
  if [[ "$status" == "DELETE_IN_PROGRESS" ]]; then
    wait_for_delete "$stack"
    return
  fi

  log_info "Deleting stack '$stack'"
  aws cloudformation delete-stack --stack-name "$stack" --region "$AWS_REGION"
  wait_for_delete "$stack"
}

confirm(){
  if [[ "$FORCE_DELETE" -eq 1 ]]; then return; fi
  cat <<EOF2
The following stacks will be deleted in region '$AWS_REGION':
  1) $CLOUDFRONT_STACK_NAME
  2) $STACK_NAME
  3) $IAM_STACK_NAME
EOF2
  read -r -p "Type 'delete' to proceed: " ans
  [[ "$ans" == "delete" ]] || { log_info "Cancelled"; exit 0; }
}

main(){
  parse_args "$@"
  check_prerequisites
  confirm

  delete_stack "$CLOUDFRONT_STACK_NAME"
  delete_stack "$STACK_NAME"
  delete_stack "$IAM_STACK_NAME"

  log_success "Cleanup completed"
}

main "$@"
