# Remote state for the dev environment.
#
# WHY: state used to live only on the machine that ran `terraform apply`.
# After a re-clone (or on another machine) `terraform destroy` found nothing
# to destroy and the cleanup script reported "success" while a GPU instance
# kept running. Remote state makes destroy work from anywhere.
#
# The bucket/key/region live in backend.hcl (non-secret) so this block stays
# generic. Initialise with:
#
#   terraform init -backend-config=backend.hcl
#
# The deploy/cleanup scripts do this automatically.
terraform {
  backend "s3" {}
}
