# Unreal Engine 5 Terraform Infrastructure

This Terraform layout deploys AWS infrastructure for Unreal Engine 5 workflows using an environment + modules structure.

## Layout

```text
infrastructure/terraform/
├── environments/
│   ├── dev/                        # UE 5.6 build box - create, build, DESTROY (billable)
│   │   ├── main.tf
│   │   ├── backend.tf              # S3 remote state (partial config)
│   │   ├── backend.hcl             # bucket/key/region for `terraform init`
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars.example
│   │   └── ci.tfvars               # the (non-secret) values the GitHub workflow applies with
│   ├── gamelift-proxy/             # API Gateway + Lambda for Shipping clients - long-lived (~$0 idle)
│   │   ├── main.tf
│   │   └── backend.hcl             # same bucket, separate state key
│   ├── gamelift-observability/     # CloudWatch dashboard + alarms + SNS e-mail - long-lived (~$0)
│   │   ├── main.tf                 # reads the proxy stack's remote state for the API/Lambda ids
│   │   └── backend.hcl
│   └── github-oidc/                # GitHub Actions OIDC provider + CI role - long-lived (free)
│       ├── main.tf                 # see scripts/build/README.md "CI"
│       └── backend.hcl
└── modules/
    ├── networking/
    ├── security/
    ├── compute/                    # EC2 + EBS (restores the UE 5.6 snapshot)
    ├── monitoring/
    ├── gamelift-proxy/             # HTTP API + Python Lambda (lambda/proxy.py, no dependencies)
    └── gamelift-observability/     # dashboard keyed on the GameLift metric group, 4 alarms
```

## Observability (`environments/gamelift-observability`)

```bash
cd infrastructure/terraform/environments/gamelift-observability
terraform init -backend-config=backend.hcl
terraform apply -var alert_email=you@example.com     # confirm the SNS mail once
terraform output -raw dashboard_url
```

Dashboard `frontendui-gamelift`: game/player sessions, server processes and capacity,
`PercentAvailableGameSessions` (the auto-scaling signal) with crash counts, proxy requests by
status / p95 latency / Lambda errors, EC2 On-Demand vCPUs in use, and the last 4xx/5xx proxy
requests. GameLift metrics are read through the fleet **metric group** `default`, so new fleets
(Anywhere or container) show up without editing anything. Alarms (all to the SNS topic):
proxy Lambda errors, proxy 5xx, `ServerProcessAbnormalTerminations` (server crashes), and
**EC2 vCPUs in use for 6 h straight** - the "forgot to destroy the build box / fleet" guard.

## Container fleet lifecycle (`scripts/gamelift/container-fleet.sh`)

The Docs/GameLift.md §5 recipe as one command, with target-tracking auto-scaling and alias switch:

```bash
S=infrastructure/scripts/gamelift/container-fleet.sh
$S create --image-tag <sha> --instance-type c6i.large --min 1 --max 2 --target 50 --alias alias-...
$S status --alias alias-...
$S delete --fleet-id containerfleet-... --alias alias-... --restore-fleet fleet-...   # same day!
```

`create` reuses the CGD version when the image tag is unchanged, waits for ACTIVE (and prints the
CloudWatch log group if the activation test fails), sets min/max capacity and a
`PercentAvailableGameSessions` target policy (50 % = keep one spare session's worth of capacity:
with one session per instance that means a second instance starts as soon as the first is in
use), and points the alias at the new fleet so clients and the proxy follow without changes.

Verified 2026-11-10: `create` took 7 min to ACTIVE; a game-session-queue placement fulfilled in
< 15 s; with the single container busy, target tracking brought a second instance to ACTIVE in
**409 s (~7 min)** and the next placement fulfilled in < 5 s. Size accordingly (min 2, or more
sessions per instance) - target tracking is a slow lever for a 1-session fleet.

Verified 2026-11-11 with the same CGD on **`c6i.xlarge`** (now the script default): GameLift
computes **3 sessions per instance** (vs 1 on `c6i.large`, for ~1.9x the price). Two placements
issued back to back both fulfilled in **1.9 s** on the same instance; with 1 of 3 slots left
(33 % < 50 % target) the second instance was ACTIVE between +392 s and +519 s - the same scale-out
time, but now in the background while a slot stays open. Note that the target-tracking change is
not reflected in `InstanceCounts.DESIRED` (stayed 1 while `ACTIVE` was 2) and logs no
`FLEET_SCALING_EVENT`; `status` shows it through the instance and container counts.
`create` → 8 min to ACTIVE including the policy; `delete` → 3 min.

## Game session queue + proxy placement support

`aws gamelift create-game-session-queue --name frontendui-dev --timeout-in-seconds 480 --destinations DestinationArn=<alias ARN>`
and `terraform apply ... -var queue_name=frontendui-dev` on the proxy: the Lambda allows
`StartGameSessionPlacement` / `DescribeGameSessionPlacement` / `StopGameSessionPlacement`, pins the
queue name and, in `auth_mode=eos`, the `DesiredPlayerSessions[].PlayerId`. The game picks the queue
path when `GameSessionQueueName` is set, and sends the Stop when it abandons a placement that is
still `PENDING` so GameLift does not fulfil it later for a host who left (Docs/GameLift.md §6).

## GameLift client proxy (`environments/gamelift-proxy`)

Shipping builds of the game refuse raw AWS credentials, so the client posts its three
GameLift calls (`CreateGameSession`, `DescribeGameSessions`, `CreatePlayerSession`) to this
endpoint with the same JSON and `X-Amz-Target` header it would send to GameLift. The Lambda
signs the request with its own role, pins the fleet from `-var fleet_id=` (a shipped client
cannot retarget it), and returns GameLift's status and body **verbatim** - the client's
`FleetCapacityExceededException` retry loop depends on the `__type` field surviving.

```bash
cd infrastructure/terraform/environments/gamelift-proxy
terraform init -backend-config=backend.hcl
terraform apply -var alias_id=alias-xxxxxxxx-...     # preferred: swap fleets with `aws gamelift update-alias`
#   or: terraform apply -var fleet_id=fleet-... / containerfleet-...
terraform output -raw api_endpoint_url    # -> ApiEndpointUrl / -GameLiftEndpoint= / GAMELIFT_ENDPOINT_URL

# Smoke test without any AWS credentials on the caller:
U=$(terraform output -raw api_endpoint_url)
curl -s -X POST $U -H 'X-Amz-Target: GameLift.DescribeGameSessions' -d '{"StatusFilter":"ACTIVE"}'
#   {"GameSessions":[]}
curl -s -X POST $U -H 'X-Amz-Target: GameLift.CreateGameSession' -d '{"Name":"Probe","MaximumPlayerSessionCount":4}'
#   {"__type":"FleetCapacityExceededException",...}   <- passthrough when no server process is free
```

With `alias_id` the Lambda resolves the alias to its current fleet (`DescribeAlias`, cached 5 min) so
session-addressed calls (`DescribeGameSessions` by `GameSessionId`, `CreatePlayerSession`) are still
checked against the pinned fleet - it never adds `FleetId` to those (GameLift accepts exactly one of
`GameSessionId` / `FleetId` / `AliasId`). Unit tests: `docker run --rm -v $PWD/infrastructure/terraform/modules/gamelift-proxy/lambda:/w:ro -w /w python:3.12-slim sh -c 'pip install -q pytest; python -m pytest -q -p no:cacheprovider /w'`.

**Player auth**: `-var auth_mode=eos -var eos_client_id=<EOS Client ID>` requires every call to carry
`Authorization: Bearer <Epic access token>`; the Lambda introspects it with Epic's `tokenInfo`
(no client secret needed; `eos_client_secret_ssm_parameter` is optional), checks `active` and
`client_id`, and overwrites `PlayerId` / `CreatorId` with the verified `account_id`. The game
side is `UFrontendSessionBackend_GameLiftEOS` (`GAMELIFT_AUTH=EOS` in LaunchInstances.bat).

The stage is throttled (20 rps / 50 burst by default) and only `POST /` is routed; everything
else is 404. Logs: `/aws/lambda/frontendui-gamelift-proxy` and `/aws/apigateway/frontendui-gamelift-proxy`.

### Changing a deployed proxy: `proxy-deploy.sh`, not bare `terraform apply`

The stack keeps no tfvars (the EOS client id stays out of the repository), so its settings exist only
as the `-var` flags of whoever applied last. A bare `terraform apply` resets all of them to defaults:
`auth_mode` back to `none`, alias and queue pins dropped - the proxy would answer anyone. After the
first deployment use the wrapper, which reads the live Lambda environment, feeds it back as
`TF_VAR_*` and lets explicit `-var` flags override single values:

```bash
infrastructure/scripts/gamelift/proxy-deploy.sh plan                              # expect: no changes
infrastructure/scripts/gamelift/proxy-deploy.sh apply -var enable_leaderboard=true
```

### Leaderboard (`-var enable_leaderboard=true`)

Adds a DynamoDB table and one more operation on the same endpoint. Clients can only **read**;
scores are written by dedicated servers (*Score submission* below).

| | |
|---|---|
| Table | `frontendui-leaderboard`, on-demand, point-in-time recovery on. Key `Board` (S) + `PlayerId` (S); attributes `DisplayName` (S), `Score` (N), `UpdatedAt` (S) |
| Index | `ByScore`: `Board` + `Score` (N), projects `DisplayName` - the top-N read is one descending Query |
| Lambda role | `dynamodb:Query` / `GetItem` on the table and index, nothing else |
| Idle cost | ~$0 (pay per request) |

`X-Amz-Target: Leaderboard.GetTop`, body `{"Board":"Main","Limit":50}` (limit 1..100, clamped):

```json
{"Board":"Main",
 "Entries":[{"Rank":1,"DisplayName":"...","Score":23390}, {"Rank":2,"DisplayName":"...","Score":22780,"IsCaller":true}],
 "Caller":{"Rank":2,"DisplayName":"...","Score":22780,"IsCaller":true}}
```

- Ranks are competition ranks (1, 2, 2, 4). `Caller` is the asking player's own row, also when it is
  outside the returned page (`null` when they have no row); `RankIsLowerBound` appears if the board
  was too large to count in one request.
- In `auth_mode=eos` the caller is the verified token's account and a `PlayerId` in the body is
  ignored; with `auth_mode=none` the body's `PlayerId` is only a highlight hint.
- Player ids are never returned.
- Errors: `UnsupportedOperationException` (400) when the table is not enabled - the same answer an
  older proxy gives, so the game treats both as "no leaderboard here"; `InvalidRequestException`
  (unknown board); `LeaderboardUnavailableException` (502, the DynamoDB cause is in the Lambda log).

#### Score submission (`-var leaderboard_server_key_ssm_parameter=…`)

Clients still cannot write. Scores are added by **dedicated servers** with one more operation,
which only exists once a server key is configured:

```bash
infrastructure/scripts/gamelift/leaderboard.sh server-key create      # random key -> SSM SecureString, never printed
infrastructure/scripts/gamelift/proxy-deploy.sh apply -var leaderboard_server_key_ssm_parameter=/frontendui/leaderboard/server-key
```

`X-Amz-Target: Leaderboard.AddScore`, header `X-Server-Key: <key>`, body
`{"Board":"Main","PlayerSessionId":"psess-…","Points":100,"DisplayName":"…"}` →
`{"Board":"Main","Awarded":true,"Points":100}`.

| Rule | Why |
|---|---|
| The server key decides, not a player token (`403 AccessDeniedException` without it, also in `auth_mode=eos` with a valid bearer) | Players must never be able to call it |
| The caller names a **player session**, not a player. The Lambda asks GameLift (`DescribePlayerSessions`) and credits that record's `PlayerId` | In `auth_mode=eos` that id is the Epic account this proxy verified when the slot was created; nothing the server says can redirect the points |
| The player session must be on the pinned fleet and `ACTIVE` or `COMPLETED` | A slot that was reserved but never accepted by a server (`RESERVED`, `TIMEDOUT`) earns nothing |
| One reward per player session: a marker item (`Board` = `~award#<board>`, `PlayerId` = the player session id, expires after 90 days through the table TTL) is written in the same transaction as the score | A retried or replayed request answers `{"Awarded":false,"Reason":"AlreadyAwarded"}` and changes nothing; a leaked key can at most reward real slots once each |
| `Points` 1..1000 per award (`LEADERBOARD_MAX_POINTS_PER_AWARD`), added to the running total | |

The Lambda role gains `dynamodb:PutItem` / `UpdateItem` on the table, `ssm:GetParameter` on that
one parameter and `gamelift:DescribePlayerSessions` - only when the key is configured. The key is
re-read every 5 minutes; `leaderboard.sh server-key rotate` replaces it (restart the servers).
The game server reads it from `GAMELIFT_SERVER_KEY` (`LaunchDedicatedServer.bat` fetches it from
SSM); it must never be baked into a client build or an .ini.

Operator script, for looking at the table and for test data:

```bash
infrastructure/scripts/gamelift/leaderboard.sh seed --count 25      # synthetic rows: ids seed-NNN, names "... (seed)"
infrastructure/scripts/gamelift/leaderboard.sh top --limit 10       # what GetTop reads, with ids
infrastructure/scripts/gamelift/leaderboard.sh awards               # latest rewarded player sessions
infrastructure/scripts/gamelift/leaderboard.sh put --player-id <Epic account id> --name <name> --score 12345
infrastructure/scripts/gamelift/leaderboard.sh clear-seed           # deletes only the seed-* rows
```

Turning `enable_leaderboard` off again **deletes the table and its rows**; set
`leaderboard_deletion_protection = true` in the module call once the board holds real scores.

## The UE 5.6 build environment lives in an *archived* snapshot

| What | ID | Size | Tier | ~Cost |
|---|---|---|---|---|
| UE 5.6 data volume (VS2022, UE 5.6 compiled from source, NVIDIA drivers, installers) | `snap-0777feef308067690` | 500 GB (≈421 GiB used) | **archive** | ~$5/month |
| Windows + VS2022 + DCV AMI | `ami-0a382bd9aedeb7bc3` → `snap-031ad7508b5e1486d` | 100 GB | standard | ~$5/month |

The 500 GB gp3 volume and the previous snapshot were deleted on 2026-11-04 (they
cost ~$61/month while idle). Everything is recoverable from the archived snapshot,
but **an archived snapshot cannot be used until it is restored to the standard
tier, which takes 24–72 hours** and costs a one-time ≈$0.03/GB (~$13).

> Archive tier has a 90-day minimum: re-archiving or deleting before
> **2027-02-02** still bills the full 90 days.

### Day-to-day workflow

```bash
# 0. (once) copy and edit the tfvars
cd infrastructure/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars

# 1. Start the restore 1–3 days BEFORE you need the machine
../../../scripts/snapshot/manage_snapshot.sh status
../../../scripts/snapshot/manage_snapshot.sh restore --days 7        # temporary, cheapest
#   or: ... restore --permanent                                       # keeps standard tier (~$21/mo)
../../../scripts/snapshot/manage_snapshot.sh wait                    # optional: block until done

# 2. Deploy (deploy.sh checks the snapshot tier, shows the hourly price, inits the S3 backend)
../../../scripts/deployment/deploy.sh

# 3. Build (see scripts/build/README.md): servers, and optionally the Shipping client
../../../scripts/build/run-build.sh --ref master --also-windows [--windows-client]

# 4. Tear down and VERIFY (exit code != 0 if anything billable remains)
../../../scripts/cleanup/cleanup.sh
```

Terraform itself enforces the readiness check: `modules/compute` has
`precondition`s that fail the plan with a clear message if the snapshot is
still archived, so nothing billable is created half-way.

### Manual Terraform

```bash
cd infrastructure/terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
terraform destroy          # prefer scripts/cleanup/cleanup.sh - it verifies afterwards
```

## Cost guard-rails

* **Default instance type is `g6.2xlarge` (~$1/h).** Multi-GPU / very large
  types (`g5.24xlarge`, `g6.48xlarge`, `p4d`, …) are refused unless
  `allow_expensive_instance_types = true` is set in `terraform.tfvars`.
  A forgotten `g5.24xlarge` cost ≈$1,160 in April 2026.
* **Remote state in S3** (`ue5-tfstate-326105557351-us-east-1`, versioned).
  State used to be local; after a re-clone `terraform destroy` had nothing to
  destroy and reported success while the instance kept running.
* **`cleanup.sh` does not trust Terraform.** After `terraform destroy` it
  sweeps the account by tag for every resource type the modules create,
  scans the region for *any* running GPU instance, never deletes snapshots or
  AMIs unless told to, and exits non-zero if anything billable remains.
* **Fast Snapshot Restore is off by default** (`data_volume_snapshot_fsr`).
  It costs ≈$0.75 per AZ-hour (~$540/month) while enabled; `cleanup.sh`
  disables any FSR left behind.
* The account already has `EC2-G5-Billing-*` CloudWatch billing alarms and a
  `G5GuardrailLambda`; keep them.

## Notes

- `environments/dev` is the Terraform root module entrypoint.
- Shared building blocks are in `modules/*`.
- `root_volume_snapshot_id` is empty by default. Setting it to the AMI's own
  snapshot would create an *extra* 100 GB copy of the OS disk on `/dev/sdg`
  (~$8/month while deployed) - the AMI already boots from that snapshot.
