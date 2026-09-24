# Justfile for nf-proteindesign.
#
# Requires: gcloud (for GCP auth), just, and nextflow. GCP Batch runs need a
# provisioned instance of the nextflow-on-gcp-terraform project (service
# account, work-dir bucket, enabled APIs) - see conf/gcp_batch.config for the
# project/region/bucket/service-account values currently wired in, and set
# NF_GCP_TF_DIR below if that project isn't checked out as a sibling of this
# repo.
#
# Run `just` with no arguments to list available recipes.

tf_dir := env_var_or_default("NF_GCP_TF_DIR", "../nextflow-on-gcp-terraform")

default:
    @just --list

# --- GCP login -----------------------------------------------------------

# Log in to gcloud as yourself and set the active project (read from the
# nextflow-on-gcp-terraform project's outputs).
login:
    #!/usr/bin/env bash
    set -euo pipefail
    project_id=$(terraform -chdir={{tf_dir}} output -raw project_id)
    gcloud auth login
    gcloud config set project "${project_id}"
    gcloud auth application-default login

# Configure Application Default Credentials to impersonate the Nextflow
# service account created by the Terraform project, so `nextflow run` acts
# as it without needing a downloaded JSON key. Requires that your user was
# added to that project's var.impersonators before `terraform apply`.
login-sa:
    #!/usr/bin/env bash
    set -euo pipefail
    sa_email=$(terraform -chdir={{tf_dir}} output -raw service_account_email 2>/dev/null || true)
    if [ -z "${sa_email}" ]; then
        echo "No service_account_email output found in {{tf_dir}} - run 'terraform apply' there first." >&2
        exit 1
    fi
    gcloud auth application-default login --impersonate-service-account="${sa_email}"

# Show the Terraform project's outputs (project, region, bucket, service account).
tf-outputs:
    terraform -chdir={{tf_dir}} output

# --- Nextflow: local runs -------------------------------------------------

# Run the pipeline locally with Docker.
# Usage: just run-local --input samplesheet.csv --protein_design_tool boltzgen
run-local *args:
    nextflow run . -profile docker {{args}}

# Run one of the pipeline's built-in test profiles locally with Docker.
# Usage: just test-local test_design_protein
test-local profile *args:
    nextflow run . -profile {{profile}},docker {{args}}

# --- Nextflow: Google Cloud Batch runs ------------------------------------

# Run the pipeline on Google Cloud Batch.
# Usage: just run-gcp-batch --input samplesheet.csv --protein_design_tool boltzgen
run-gcp-batch *args:
    nextflow run . -profile gcp_batch,docker {{args}}

# Run one of the pipeline's built-in test profiles on Google Cloud Batch.
# Usage: just test-gcp-batch test_design_protein
test-gcp-batch profile *args:
    nextflow run . -profile gcp_batch,{{profile}},docker {{args}}

# Watch submitted Google Batch jobs.
watch-gcp-batch:
    gcloud batch jobs list
