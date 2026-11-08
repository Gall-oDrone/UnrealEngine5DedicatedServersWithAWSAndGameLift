# Build scripts

Headless build of the FrontendUI **Linux dedicated server** on the EC2 box that Terraform
creates from the UE 5.6 source-build snapshot. No RDP, no DCV: everything goes through
SSM Run Command, and the result lands in S3.

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

## Notes

- The script finds the engine by scanning each fixed volume one directory deep for
  `Engine\Build\BatchFiles\RunUAT.bat` and picks the first 5.6 one not on `C:`.
- `LINUX_MULTIARCH_ROOT` is set machine-wide to `C:\UnrealToolchains\v25_clang-18.1.0-rockylinux8`
  (UE 5.6's toolchain). Installing it is the only download besides the repo (~1.5 GB).
- Run Command caps stdout at 24 KB, so the script prints status lines only; full UAT
  output is in `C:\ue5-build\uat-<platform>-<stamp>.log` and copied to `builds/logs/`.
- `executionTimeout` is 4 h. If the cook needs longer, pass a bigger value in `run-build.sh`.
