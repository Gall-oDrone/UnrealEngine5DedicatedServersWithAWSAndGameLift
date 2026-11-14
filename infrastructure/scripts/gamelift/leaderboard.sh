#!/usr/bin/env bash
# Operator tool for the FrontendUI leaderboard table (DynamoDB, modules/gamelift-proxy).
# Game clients can only READ the board, through the proxy (Leaderboard.GetTop). Scores are added
# by dedicated servers (Leaderboard.AddScore, with the server key below); this tool is for the
# operator: look, seed test rows, put a row by hand, manage that key.
#
#   leaderboard.sh top   [--board Main] [--limit 10]     # the rows Leaderboard.GetTop reads, with ids
#   leaderboard.sh count [--board Main]
#   leaderboard.sh put   --player-id <id> --name <display name> --score <n> [--board Main]
#   leaderboard.sh seed  [--board Main] [--count 25]     # synthetic rows: ids seed-001.., names "... (seed)"
#   leaderboard.sh clear-seed [--board Main]             # deletes ONLY the seed-* rows of the board
#   leaderboard.sh server-key create | rotate            # the key dedicated servers present to submit scores
#   leaderboard.sh awards [--board Main] [--limit 10]    # latest "player session rewarded" markers
#
# --player-id is what the proxy knows the player as: the Epic account id in auth_mode=eos
# (GameLift shows it as PlayerId of the player sessions the proxy created).
# server-key writes a random 64-hex-char value to the SSM SecureString $LEADERBOARD_SERVER_KEY_PARAM
# (default /frontendui/leaderboard/server-key) and never prints it. `create` refuses to replace an
# existing key; `rotate` replaces it - servers must be restarted to pick the new one up, and the
# proxy keeps accepting the old one for up to 5 minutes (its cache). Wire it into the proxy once:
#   proxy-deploy.sh apply -var leaderboard_server_key_ssm_parameter=/frontendui/leaderboard/server-key
# Needs: aws (dynamodb:Query/PutItem/BatchWriteItem/DeleteItem on the table; ssm:PutParameter for server-key), jq.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
TABLE="${LEADERBOARD_TABLE:-frontendui-leaderboard}"
INDEX="ByScore"

cmd="${1:-}"; shift || true
KEY_PARAM="${LEADERBOARD_SERVER_KEY_PARAM:-/frontendui/leaderboard/server-key}"
SUB=""; if [[ "$cmd" == "server-key" ]]; then SUB="${1:-}"; shift || true; fi
BOARD="Main"; LIMIT=10; COUNT=25; PLAYER_ID=""; NAME=""; SCORE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --board) BOARD="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --count) COUNT="$2"; shift 2 ;;
    --player-id) PLAYER_ID="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --score) SCORE="$2"; shift 2 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

ddb() { aws dynamodb --region "$REGION" "$@"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
item() { # board player-id name score
  jq -cn --arg b "$1" --arg p "$2" --arg n "$3" --arg s "$4" --arg t "$(now)" \
    '{Board:{S:$b}, PlayerId:{S:$p}, DisplayName:{S:$n}, Score:{N:$s}, UpdatedAt:{S:$t}}'
}
board_values() { jq -cn --arg b "$BOARD" '{":b":{S:$b}}'; }

case "$cmd" in
  top)
    ddb query --table-name "$TABLE" --index-name "$INDEX" --no-scan-index-forward --limit "$LIMIT" \
      --key-condition-expression '#b = :b' --expression-attribute-names '{"#b":"Board"}' \
      --expression-attribute-values "$(board_values)" --output json \
      | jq -r '.Items | to_entries[] | [(.key + 1), .value.Score.N, .value.DisplayName.S, .value.PlayerId.S] | @tsv'
    ;;

  count)
    ddb query --table-name "$TABLE" --select COUNT --key-condition-expression '#b = :b' \
      --expression-attribute-names '{"#b":"Board"}' --expression-attribute-values "$(board_values)" \
      --query Count --output text
    ;;

  put)
    [[ -n "$PLAYER_ID" && -n "$NAME" && "$SCORE" =~ ^-?[0-9]+$ ]] || { echo "put needs --player-id, --name and an integer --score" >&2; exit 2; }
    ddb put-item --table-name "$TABLE" --item "$(item "$BOARD" "$PLAYER_ID" "$NAME" "$SCORE")"
    echo "put $BOARD / ${PLAYER_ID:0:6}... '$NAME' = $SCORE"
    ;;

  seed)
    [[ "$COUNT" =~ ^[0-9]+$ && "$COUNT" -ge 1 && "$COUNT" -le 200 ]] || { echo "--count must be 1..200" >&2; exit 2; }
    names=(Valkyrie Ronin Cinder Specter Longshot Nomad Havoc Wraith Tempest Ember Raven Atlas Nightjar Falcon Mirage
           Blitz Onyx Saber Quill Drift Vortex Helix Gale Juno Kestrel Lynx Mako Nova Orion Pike Rook Sable Talon Umbra)
    batch=(); written=0
    flush() {
      [[ ${#batch[@]} -gt 0 ]] || return 0
      local out
      out=$(ddb batch-write-item --output json \
              --request-items "$(printf '%s\n' "${batch[@]}" | jq -cs --arg t "$TABLE" '{($t): map({PutRequest:{Item:.}})}')")
      # The CLI prints nothing at all when every item was written, so empty output is success.
      if [[ -n "$out" ]] && ! jq -e '(.UnprocessedItems // {}) | length == 0' >/dev/null <<<"$out"; then
        echo "DynamoDB left items unprocessed; run seed again (it is idempotent)" >&2; exit 1
      fi
      written=$((written + ${#batch[@]})); batch=()
    }
    for i in $(seq 1 "$COUNT"); do
      # Deterministic, descending, with one deliberate tie (rows 3 and 4) to show competition ranking.
      score=$((24000 - i * 610)); [[ "$i" -eq 4 ]] && score=$((24000 - 3 * 610))
      name="${names[$(((i - 1) % ${#names[@]}))]}"; [[ "$i" -gt ${#names[@]} ]] && name="$name$i"
      batch+=("$(item "$BOARD" "$(printf 'seed-%03d' "$i")" "$name (seed)" "$score")")
      [[ ${#batch[@]} -eq 25 ]] && flush
    done
    flush
    echo "seeded $written synthetic row(s) into $TABLE / $BOARD (remove them with: $0 clear-seed --board $BOARD)"
    ;;

  clear-seed)
    ids=$(ddb query --table-name "$TABLE" --key-condition-expression '#b = :b AND begins_with(#p, :seed)' \
            --expression-attribute-names '{"#b":"Board","#p":"PlayerId"}' \
            --expression-attribute-values "$(jq -cn --arg b "$BOARD" '{":b":{S:$b}, ":seed":{S:"seed-"}}')" \
            --projection-expression '#p' --query 'Items[].PlayerId.S' --output text)
    n=0
    for id in $ids; do
      [[ "$id" == seed-* ]] || continue   # belt and braces: never anything but seed rows
      ddb delete-item --table-name "$TABLE" --key "$(jq -cn --arg b "$BOARD" --arg p "$id" '{Board:{S:$b}, PlayerId:{S:$p}}')"
      n=$((n + 1))
    done
    echo "deleted $n seed row(s) from $TABLE / $BOARD"
    ;;

  server-key)
    [[ "$SUB" == "create" || "$SUB" == "rotate" ]] || { echo "server-key needs: create | rotate" >&2; exit 2; }
    exists=0; aws ssm get-parameter --region "$REGION" --name "$KEY_PARAM" --query 'Parameter.Version' --output text >/dev/null 2>&1 && exists=1
    if [[ "$SUB" == "create" && "$exists" -eq 1 ]]; then
      echo "$KEY_PARAM already exists; nothing changed (use: $0 server-key rotate)" >&2; exit 1
    fi
    # The value goes through a private temp file, not through argv, and is never echoed.
    umask 077; tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    jq -n --arg n "$KEY_PARAM" --arg v "$(openssl rand -hex 32)" \
      '{Name:$n, Value:$v, Type:"SecureString", Overwrite:true, Description:"FrontendUI dedicated servers: key for Leaderboard.AddScore on the proxy"}' > "$tmp"
    version=$(aws ssm put-parameter --region "$REGION" --cli-input-json "file://$tmp" --query Version --output text)
    echo "$KEY_PARAM: version $version written (64 hex chars, not shown)"
    ;;

  awards)
    ddb query --table-name "$TABLE" --no-scan-index-forward --limit "$LIMIT" \
      --key-condition-expression '#b = :b' --expression-attribute-names '{"#b":"Board"}' \
      --expression-attribute-values "$(jq -cn --arg b "~award#$BOARD" '{":b":{S:$b}}')" --output json \
      | jq -r '.Items[] | [.AwardedAt.S, .Points.N, .PlayerId.S, (.AwardedTo.S[0:6] + "...")] | @tsv' | sort -r
    ;;

  *) sed -n '2,23p' "$0"; exit 2 ;;
esac
