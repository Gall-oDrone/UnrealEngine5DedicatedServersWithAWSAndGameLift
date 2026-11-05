# Unreal Engine 5 Terraform Infrastructure

This Terraform layout deploys AWS infrastructure for Unreal Engine 5 workflows using an environment + modules structure.

## Layout

```text
infrastructure/terraform/
├── environments/
│   └── dev/
│       ├── main.tf
│       ├── backend.tf              # S3 remote state (partial config)
│       ├── backend.hcl             # bucket/key/region for `terraform init`
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
└── modules/
    ├── networking/
    ├── security/
    ├── compute/                    # EC2 + EBS (restores the UE 5.6 snapshot)
    └── monitoring/
```

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

# 3. WORK ...

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
- `root_volume_snapshot_id` defaults to the AMI's own snapshot and creates an
  *extra* 100 GB copy of the OS disk on `/dev/sdg` (~$8/month while deployed).
  Set it to `""` if you don't need it.
