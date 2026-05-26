# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`staticbot` is the public infrastructure-as-code repository for Staticbot.dev. It contains the reusable Terraform/OpenTofu modules and scripts that deploy static websites and web apps into a user's own AWS account using S3, CloudFront, Route 53, and ACM. Users own this code — they can fork it, run it standalone, and continue operating their infrastructure with no Staticbot dependency.

## Repository Structure

```
infrastructure/
  cloud_aws/              # AWS Terraform modules (S3, CloudFront, ACM, Route 53)
  cloud_eu/, cloud_eu2/   # EU-region variants
  _templates/             # Site templates
  __manual_deployments/   # Pinned configurations for one-off deployments
scripts/
  supabase-sync.py        # Sync helper for Supabase-backed deployments
tests/
  infrastructure/         # Terraform tests
websites/
  staticbot.eu            # Site definition for staticbot.eu
  _placeholder            # Placeholder/default site
```

## Commands

This repo is Terraform-driven. Typical workflow per website:

```bash
cd infrastructure/cloud_aws
tofu init
tofu plan -var-file=<website>.tfvars
tofu apply -var-file=<website>.tfvars
```

See `infrastructure/cloud_aws/README.md` for the full deployment guide.

## Conventions

- **No vendor lock-in**: every change must keep the Terraform code runnable standalone (without the Staticbot control plane).
- **Per-account deployment**: state is per AWS account; never assume a shared backend.
- **EU variants** (`cloud_eu`, `cloud_eu2`) exist for data-residency requirements — keep them in sync with `cloud_aws` when changing shared module behavior.
- **OpenTofu preferred** over Terraform CLI, but the modules must remain compatible with both.

## How This Fits the Platform

The Staticbot control plane (`staticbot-app`) generates deployment configurations that target the modules in this repo. When the control plane runs a deployment, it checks out this repo, writes a `.tfvars` file, and invokes the tf-runner worker (in `staticbot-control-center`) to apply.
