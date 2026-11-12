# Build scripts

Headless build of the FrontendUI **Linux dedicated server** (and, optionally, the Windows
server and a **Shipping Windows client**) on the EC2 box that Terraform creates from the
UE 5.6 source-build snapshot. No RDP, no DCV: everything goes through SSM Run Command, and
the result lands in S3.

```
run-build.sh  (your machine)            build-linux-server.ps1  (EC2, via SSM)
  wait for SSM agent  ─────────────►    bring data volume online, find UE 5.6 root
  upload .ps1 to S3                     install Linux cross toolchain v25 if missing
  send AWS-RunPowerShellScript ──────►  git clone/checkout <ref>
  stream output until done              RunUAT BuildCookRun -platform=Linux -server ...
  list s3://.../builds/   ◄───────────  zip Saved/StagedBuilds/LinuxServer -> S3 (+ logs)
```

## One build session

```bash
cd infrastructure/terraform/environments/dev
terraform apply                                  # c6i.4xlarge + 500 GB volume from the snapshot

cd ../../../scripts/build
./run-build.sh --ref master                      # ~1-2 h first time (cold DDC), less afterwards
# ./run-build.sh --ref master --also-windows     # + Win64 server zip
# ./run-build.sh --skip-cook                     # compile check only
# ./run-build.sh --instance i-0123...            # when terraform output is not reachable from the cwd

cd ../../terraform/environments/dev
terraform destroy                                # stop paying; the snapshot keeps the engine
```

Artifacts: `s3://ue5-artifacts-326105557351-us-east-1/builds/FrontendUI-LinuxServer-<sha>-<stamp>.zip`
and `builds/logs/` (UAT log + script log). On your PC:

```bash
aws s3 cp s3://ue5-artifacts-326105557351-us-east-1/builds/FrontendUI-LinuxServer-<sha>-<stamp>.zip .
unzip -q FrontendUI-LinuxServer-*.zip -d <game repo>/Saved/StagedBuilds/   # creates LinuxServer/
cd <game repo> && docker compose up --build                                  # see Docs/GameLift.md
```

## The Shipping client (`--windows-client`)

A Shipping client refuses raw AWS credentials and reads no `-ini:` overrides, so the proxy
URL, alias, location and queue have to be **in the packaged config**. `--windows-client`
appends them to the working copy's `Config/DefaultGame.ini` (and the EOS block to
`DefaultEngine.ini`) right before the cook and `git checkout -- Config` afterwards, so nothing
is committed and the repo stays free of ids:

```bash
export GAMELIFT_ENDPOINT_URL=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/   # ApiEndpointUrl
export GAMELIFT_ALIAS_ID=alias-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx                   # AliasId
export GAMELIFT_LOCATION=custom-frontendui-dev                                         # Location
export GAMELIFT_QUEUE_NAME=frontendui-dev                                              # GameSessionQueueName

./run-build.sh --ref master --also-windows --windows-client     # servers + client in one run
./run-build.sh --ref master --windows-client --client-only      # client only (box already built the servers)
```

| Input | Where it comes from | What is appended |
|---|---|---|
| `GAMELIFT_ENDPOINT_URL`, `GAMELIFT_ALIAS_ID`, `GAMELIFT_LOCATION`, `GAMELIFT_QUEUE_NAME` | your shell | `[/Script/FrontendMultiplayer.FrontendGameLiftSettings]` `ApiEndpointUrl=` / `AliasId=` / `Location=` / `GameSessionQueueName=` |
| SSM `/frontendui/eos/artifacts` (SecureString) | read on the box with `--with-decryption` | `[OnlineSubsystem] DefaultPlatformService=EOS` and `[/Script/OnlineSubsystemEOS.EOSSettings] +Artifacts=(...)`; `SessionBackendClass` becomes `FrontendSessionBackend_GameLiftEOS`. Absent → Null subsystem + plain `FrontendSessionBackend_GameLift` |

Put the EOS line in SSM once (it is the same `+Artifacts=(ArtifactName="...",ClientId="...",ClientSecret="...",ProductId="...",SandboxId="...",DeploymentId="...",EncryptionKey="...")`
line a developer keeps in the git-ignored `Config/UserEngine.ini`, see the game repo's `Docs/EOSSetup.md`;
quote it as a single argument - `cmd.exe` strips the inner double quotes if the value is not wrapped):

```bash
aws ssm put-parameter --name /frontendui/eos/artifacts --type SecureString --overwrite \
  --value '+Artifacts=(ArtifactName="FrontendUI",ClientId="xyz...",ClientSecret="...",ProductId="...",SandboxId="...",DeploymentId="...",EncryptionKey="0000...")'
```

The UAT line is `BuildCookRun -platform=Win64 -clientconfig=Shipping -build -cook -stage -pak`;
the stage lands in `Saved\StagedBuilds\Windows` and is uploaded as
`builds/FrontendUI-WindowsClient-Shipping-<sha>-<stamp>.zip` (`Windows\FrontendUI.exe` is the
launcher, the binary is `FrontendUI\Binaries\Win64\FrontendUI-Win64-Shipping.exe`). The script
log shows what was baked:
`client config: backend=.../FrontendSessionBackend_GameLiftEOS endpoint=https://... alias=alias-... location=custom-... queue=... eos=True`.

Measured 2026-11-11 (`5a0dbd7`, fresh snapshot restore, `c6i.4xlarge`):

| Run | Time |
|---|---|
| `--also-windows`: editor modules + Linux server + Win64 server, both cooked, zipped, uploaded | 71 min |
| `--windows-client --client-only` on the same box (982 Shipping compile actions + cook/stage/pak) | 43 min + 1 min zip/upload |
| Whole session incl. `terraform apply` / `destroy` | 2 h 05 min, ≈ $1.6 |

## Notes

- The script finds the engine by scanning each fixed volume one directory deep for
  `Engine\Build\BatchFiles\RunUAT.bat` and picks the first 5.6 one not on `C:`.
- `LINUX_MULTIARCH_ROOT` is set machine-wide to `C:\UnrealToolchains\v25_clang-18.1.0-rockylinux8`
  (UE 5.6's toolchain). Installing it is the only download besides the repo (~1.5 GB).
- Run Command caps stdout at 24 KB, so the script prints status lines only; full UAT
  output is in `C:\ue5-build\uat-<platform>-<stamp>.log` and copied to `builds/logs/`.
- `executionTimeout` is 4 h. If the cook needs longer, pass a bigger value in `run-build.sh`.
- Zips are written to `C:\ue5-build` (the 100 GB OS volume, ~6 GB free after the toolchain
  install) and deleted once the S3 upload succeeds, so several runs fit on one box.
- Do not edit `run-build.sh` while it is running - bash reads the file incrementally and
  reports phantom syntax errors at the end. Copy it to `/tmp` first if you must.
