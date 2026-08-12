# OCI Terraform Lab

Hands-on Terraform labs against Oracle Cloud Infrastructure (OCI), built during the
4-week Ejada Cloud Build internship. Each `week*` folder is a self-contained
Terraform root module that provisions a progressively more realistic
environment — from a single public VM in Week 1 to a multi-tier VCN with a
load balancer, private compute, Bastion access, and shared file storage in
Week 2, with Weeks 3-4 building further on top.

## Table of Contents

- [Progress](#progress)
- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Usage](#usage)
- [Configuration Reference](#configuration-reference)
- [Documentation & Diagrams](#documentation--diagrams)
- [Security Notes](#security-notes)
- [Status](#status)

## Progress

`[██████████░░░░░░░░░░]` 2 / 4 weeks complete

- [x] **Week 1** — Core OCI building blocks (VCN, public VM, block + file storage)
- [x] **Week 2** — Intermediate Terraform + application tier architecture (load balancer, bastion, `for_each`/`dynamic` blocks)
- [ ] **Week 3** — In progress
- [ ] **Week 4** — Not started

## Overview

| | Week 1 | Week 2 | Week 3 | Week 4 |
|---|---|---|---|---|
| Status | Done | Done | In progress | Not started |
| Focus | Core OCI building blocks | Intermediate Terraform + application tier architecture | TBD | TBD |
| Network | Single public VCN/subnet | Public + private subnets, NAT gateway, tiered security lists | — | — |
| Compute | 1 public Linux VM | 1 private Linux VM behind a load balancer | — | — |
| Access | Direct SSH (public IP) | OCI Bastion (SSH), Load Balancer (HTTP) | — | — |
| Storage | Block Volume + File Storage (NFS) | Block Volume + File Storage (NFS), app files served from NFS | — | — |
| Terraform concepts | Providers, resources, data sources, variables, outputs | `for_each`, dynamic blocks, locals, lifecycle rules, `moved` blocks, `terraform import` | — | — |

Both modules target OCI region **Saudi Arabia West (Jeddah)** (`me-jeddah-1`) and
run against a single compartment.

## Repository Structure

```
oci-terraform-lab/
├── weekOne/                 # Week 1: single public VM, VCN, block + file storage
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── ejadaWeekOne.pdf      # Week 1 write-up
│
└── weekTwo/                 # Week 2: multi-tier VCN, load balancer, bastion
    ├── main.tf                # VCN, subnets (for_each), security lists (dynamic blocks)
    ├── loadbalancer.tf        # Flexible-shape LB, backend set, health check, listener
    ├── bastion.tf             # OCI Bastion service for private-instance SSH access
    ├── locals.tf               # Naming prefix, owner tag, common freeform tags
    ├── variables.tf
    ├── outputs.tf
    ├── provider.tf
    ├── moved.tf                # terraform state mv demo (moved block)
    ├── import_demo.tf          # terraform import demo target
    ├── templates/
    │   └── app_userdata.sh.tftpl  # cloud-init: mounts NFS, runs the app as a systemd service
    ├── docs/
    │   ├── Step1_Console_Walkthrough.md        # manual OCI Console build guide
    │   └── Week2_Network_Diagram_Ali_Yousef.drawio
    └── weekTwoDocumentation.pdf
```

Terraform state (`terraform.tfstate*`), provider caches (`.terraform/`), and
`terraform.tfvars` are intentionally **not** tracked in git — see
[Security Notes](#security-notes).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- An OCI account with API access enabled and an API signing key pair
- OCI CLI (optional, useful for verifying resources) — [install guide](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- An SSH key pair to inject into the compute instances

## Setup

1. Clone the repository and `cd` into the week you want to run:

   ```bash
   git clone https://github.com/alyyousef/ejada-cloud-intern-ali-yousef.git
   cd ejada-cloud-intern-ali-yousef/weekTwo   # or weekOne
   ```

2. Create a `terraform.tfvars` file in that folder (it is gitignored and must
   never be committed). At minimum, provide the OCI auth variables declared in
   `variables.tf`:

   ```hcl
   tenancy_ocid         = "ocid1.tenancy.oc1..xxxxx"
   user_ocid             = "ocid1.user.oc1..xxxxx"
   fingerprint           = "xx:xx:xx:...:xx"
   private_key_path      = "C:/Users/<you>/.oci/oci_api_key.pem"
   compartment_ocid       = "ocid1.compartment.oc1..xxxxx"
   ssh_public_key_path    = "C:/Users/<you>/.ssh/oci_vm.pub"
   ```

   All other variables have sensible defaults — see
   [Configuration Reference](#configuration-reference).

3. Initialize the working directory:

   ```bash
   terraform init
   ```

## Usage

Standard Terraform workflow, run from inside `weekOne/` or `weekTwo/`:

```bash
terraform plan      # preview changes
terraform apply      # provision resources
terraform output     # view outputs (e.g. instance IP, load balancer IP)
terraform destroy    # tear everything down when you're done
```

**Week 2 specifics:**

- The compute instance has no public IP — reach the app via the load
  balancer's public IP (`terraform output load_balancer_public_ip`) and SSH
  into it via an OCI Bastion managed session (`terraform output bastion_id`).
- `moved.tf` and `import_demo.tf` exist to demonstrate `terraform state mv`
  and `terraform import` and aren't required for a normal apply/destroy cycle.

## Configuration Reference

Full variable and output definitions live in each week's `variables.tf` /
`outputs.tf` — they're kept close to the code so they don't drift out of sync.
Notable Week 2 variables:

| Variable | Purpose | Default |
|---|---|---|
| `subnet_tiers` | Map driving `for_each` subnet creation (public/private) | 2 tiers, `10.1.1.0/24` / `10.1.2.0/24` |
| `public_ingress_rules` / `private_ingress_rules` | Security list rules, consumed by `dynamic` blocks | HTTP-only public; app/SSH/NFS private |
| `app_port` | Port the app listens on behind the load balancer | `8080` |
| `bastion_client_cidr_allow_list` | CIDRs allowed to open Bastion sessions | `0.0.0.0/0` (narrow this for anything beyond a lab) |

## Documentation & Diagrams

- [`weekTwo/docs/Step1_Console_Walkthrough.md`](weekTwo/docs/Step1_Console_Walkthrough.md) —
  guided walkthrough for building the same architecture by hand in the OCI
  Console before automating it with Terraform.
- [`weekTwo/docs/Week2_Network_Diagram_Ali_Yousef.drawio`](weekTwo/docs/Week2_Network_Diagram_Ali_Yousef.drawio) —
  network architecture diagram (draw.io, official OCI icon set). Open with
  [draw.io / diagrams.net](https://app.diagrams.net/).
- `weekOne/ejadaWeekOne.pdf` and `weekTwo/weekTwoDocumentation.pdf` — per-week
  write-ups submitted as deliverables.

## Security Notes

- Never commit `terraform.tfvars`, `*.tfstate*`, `.terraform/`, or `*.pem` —
  all are excluded via [`.gitignore`](.gitignore) because they can contain
  tenancy/user OCIDs, API fingerprints, private key paths, and full resource
  state.
- Auth-related variables (`tenancy_ocid`, `user_ocid`, `fingerprint`,
  `private_key_path`) are marked `sensitive = true` so Terraform redacts them
  from plan/apply output.
- `bastion_client_cidr_allow_list` defaults to `0.0.0.0/0` for lab
  convenience. Narrow it to your own IP (`x.x.x.x/32`) before leaving an
  environment running for any length of time.
- State is local (no remote backend configured) — treat the `weekTwo`
  directory itself as sensitive, since a local `terraform.tfstate` stores
  resource attributes in plaintext.

## Status

4-week program, currently in **Week 3**. Weeks 1-2 are complete and folders
exist for both (`weekOne/`, `weekTwo/`); `weekThree/` and `weekFour/` land as
each week is finished.

This is an active internship lab, not a production environment — expect
resources to be applied and destroyed between sessions rather than kept
running continuously. Check `terraform state list` / `terraform plan` in the
relevant week's folder before assuming an environment is deployed.
