#!/usr/bin/env bash
# terraform plan / apply for environments/gamelift-proxy that carries the DEPLOYED settings forward.
#
#   proxy-deploy.sh plan  [-var name=value ...]
#   proxy-deploy.sh apply [-var name=value ...]      # e.g. -var enable_leaderboard=true
#
# Why: the stack keeps no tfvars (the EOS client id stays out of the repository), so its settings
# only ever existed as -var flags on somebody's command line. A bare `terraform apply` therefore
# resets every variable to its default: auth_mode eos -> none, the alias and queue pins dropped -
# the proxy would quietly start answering anyone. This script reads the live Lambda environment,
# feeds it back as TF_VAR_* and lets explicit -var flags override single values.
#
# First deployment (no function yet): everything starts from the module defaults; pass -var flags.
# Needs: aws (lambda:GetFunctionConfiguration + whatever the plan touches), terraform >= 1.10, jq.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
FUNCTION="${PROXY_FUNCTION_NAME:-frontendui-gamelift-proxy}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../terraform/environments/gamelift-proxy" && pwd)"

cmd="${1:-}"; shift || true
case "$cmd" in
  plan|apply) ;;
  *) sed -n '2,14p' "$0"; exit 2 ;;
esac

live="$(aws lambda get-function-configuration --region "$REGION" --function-name "$FUNCTION" \
          --query 'Environment.Variables' --output json 2>/dev/null || echo '{}')"
[[ "$live" == "null" || -z "$live" ]] && live='{}'
get() { jq -r --arg k "$1" '.[$k] // ""' <<<"$live"; }
mask() { local v="$1"; [[ -z "$v" ]] && echo "-" || echo "${v:0:4}****"; }

export TF_VAR_fleet_id="$(get FLEET_ID)"
export TF_VAR_alias_id="$(get ALIAS_ID)"
export TF_VAR_queue_name="$(get QUEUE_NAME)"
export TF_VAR_auth_mode="$(get AUTH_MODE)"; [[ -n "$TF_VAR_auth_mode" ]] || TF_VAR_auth_mode="none"
export TF_VAR_eos_client_id="$(get EOS_CLIENT_ID)"
export TF_VAR_eos_client_secret_ssm_parameter="$(get EOS_CLIENT_SECRET_PARAM)"
if [[ -n "$(get LEADERBOARD_TABLE)" ]]; then export TF_VAR_enable_leaderboard=true; else export TF_VAR_enable_leaderboard=false; fi
export TF_VAR_leaderboard_server_key_ssm_parameter="$(get LEADERBOARD_SERVER_KEY_PARAM)"

echo "carrying forward from $FUNCTION: auth_mode=$TF_VAR_auth_mode fleet_id=${TF_VAR_fleet_id:--} alias_id=${TF_VAR_alias_id:--}" \
     "queue_name=${TF_VAR_queue_name:--} eos_client_id=$(mask "$TF_VAR_eos_client_id")" \
     "eos_client_secret_ssm_parameter=${TF_VAR_eos_client_secret_ssm_parameter:--} enable_leaderboard=$TF_VAR_enable_leaderboard" \
     "leaderboard_server_key_ssm_parameter=${TF_VAR_leaderboard_server_key_ssm_parameter:--}"
[[ $# -gt 0 ]] && echo "overrides: $*"

terraform -chdir="$DIR" init -input=false -backend-config=backend.hcl >/dev/null
if [[ "$cmd" == "plan" ]]; then
  terraform -chdir="$DIR" plan -input=false "$@"
else
  terraform -chdir="$DIR" apply -input=false "$@"
fi
