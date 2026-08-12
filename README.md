# OCI Terraform Lab

This is my Terraform + OCI (Oracle Cloud Infrastructure) work from the Ejada Cloud
Build internship, a 4-week program. Each `week*` folder is its own Terraform
root module, and they build on each other: Week 1 is a single public VM with
a basic VCN, Week 2 moves to a proper multi-tier setup with a load balancer,
private compute, Bastion access, and shared file storage. Weeks 3 and 4 will
keep building on top of that.

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

`[██████████░░░░░░░░░░]` 2 / 4 weeks done

- [x] **Week 1** - Core OCI building blocks (VCN, public VM, block + file storage)
- [x] **Week 2** - Intermediate Terraform + application tier architecture (load balancer, bastion, `for_each`/`dynamic` blocks)
- [ ] **Week 3** - In progress
- [ ] **Week 4** - Not started yet

## Overview

| | Week 1 | Week 2 | Week 3 | Week 4 |
|---|---|---|---|---|
| Status | Done | Done | In progress | Not started |
| Focus | Core OCI building blocks | Intermediate Terraform + application tier architecture | TBD | TBD |
| Network | Single public VCN/subnet | Public + private subnets, NAT gateway, tiered security lists | | |
| Compute | 1 public Linux VM | 1 private Linux VM behind a load balancer | | |
| Access | Direct SSH (public IP) | OCI Bastion (SSH), Load Balancer (HTTP) | | |
| Storage | Block Volume + File Storage (NFS) | Block Volume + File Storage (NFS), app files served from NFS | | |
| Terraform concepts | Providers, resources, data sources, variables, outputs | `for_each`, dynamic blocks, locals, lifecycle rules, `moved` blocks, `terraform import` | | |

Both modules target OCI region **Saudi Arabia West (Jeddah)** (`me-jeddah-1`),
running in a single compartment.

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

I'm keeping `terraform.tfstate*`, `.terraform/`, and `terraform.tfvars` out of
git on purpose, see [Security Notes](#security-notes) for why.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- An OCI account with API access enabled and an API signing key pair
- OCI CLI (optional, but handy for double-checking resources) - [install guide](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- An SSH key pair to inject into the compute instances

## Setup

1. Clone the repo and `cd` into whichever week you want to run:

   ```bash
   git clone https://github.com/alyyousef/ejada-cloud-intern-ali-yousef.git
   cd ejada-cloud-intern-ali-yousef/weekTwo   # or weekOne
   ```

2. Create a `terraform.tfvars` file in that folder (it's gitignored, don't
   commit it). At minimum you need the OCI auth variables from
   `variables.tf`:

   ```hcl
   tenancy_ocid         = "ocid1.tenancy.oc1..xxxxx"
   user_ocid             = "ocid1.user.oc1..xxxxx"
   fingerprint           = "xx:xx:xx:...:xx"
   private_key_path      = "C:/Users/<you>/.oci/oci_api_key.pem"
   compartment_ocid       = "ocid1.compartment.oc1..xxxxx"
   ssh_public_key_path    = "C:/Users/<you>/.ssh/oci_vm.pub"
   ```

   Everything else has a sensible default, see
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

- The compute instance has no public IP. Reach the app through the load
  balancer's public IP (`terraform output load_balancer_public_ip`), and SSH
  in through an OCI Bastion managed session (`terraform output bastion_id`).
- `moved.tf` and `import_demo.tf` are just there to demo `terraform state mv`
  and `terraform import`. You don't need them for a normal apply/destroy.

## Configuration Reference

I kept the full variable and output definitions in each week's `variables.tf`
and `outputs.tf` instead of duplicating them here, so they can't drift out of
sync. A few worth calling out for Week 2:

| Variable | Purpose | Default |
|---|---|---|
| `subnet_tiers` | Map driving `for_each` subnet creation (public/private) | 2 tiers, `10.1.1.0/24` / `10.1.2.0/24` |
| `public_ingress_rules` / `private_ingress_rules` | Security list rules, consumed by `dynamic` blocks | HTTP-only public; app/SSH/NFS private |
| `app_port` | Port the app listens on behind the load balancer | `8080` |
| `bastion_client_cidr_allow_list` | CIDRs allowed to open Bastion sessions | `0.0.0.0/0` (narrow this for anything beyond a lab) |

## Documentation & Diagrams

- [`weekTwo/docs/Step1_Console_Walkthrough.md`](weekTwo/docs/Step1_Console_Walkthrough.md),
  a guided walkthrough for building the same architecture by hand in the OCI
  Console before automating it with Terraform.
- [`weekTwo/docs/Week2_Network_Diagram_Ali_Yousef.drawio`](weekTwo/docs/Week2_Network_Diagram_Ali_Yousef.drawio),
  the network diagram (draw.io, official OCI icon set). Open it with
  [draw.io / diagrams.net](https://app.diagrams.net/).
- `weekOne/ejadaWeekOne.pdf` and `weekTwo/weekTwoDocumentation.pdf`, the
  write-ups I submitted for each week.

## Security Notes

- I never commit `terraform.tfvars`, `*.tfstate*`, `.terraform/`, or `*.pem`.
  All of these are excluded in [`.gitignore`](.gitignore) because they can
  contain tenancy/user OCIDs, API fingerprints, private key paths, and full
  resource state.
- The auth variables (`tenancy_ocid`, `user_ocid`, `fingerprint`,
  `private_key_path`) are marked `sensitive = true` so Terraform redacts them
  from plan/apply output.
- `bastion_client_cidr_allow_list` defaults to `0.0.0.0/0` for lab
  convenience. If you're leaving an environment up for more than a quick lab
  session, narrow it to your own IP (`x.x.x.x/32`).
- State is local, there's no remote backend configured, so treat the
  `weekTwo` directory itself as sensitive since a local `terraform.tfstate`
  stores resource attributes in plaintext.

## Status

4-week program, I'm currently in Week 3. Weeks 1 and 2 are done and have
their own folders (`weekOne/`, `weekTwo/`); `weekThree/` and `weekFour/` will
show up as I finish each one.

This is an active lab, not a production environment, so I'm applying and
destroying resources between sessions rather than keeping anything running
continuously. Run `terraform state list` or `terraform plan` in the relevant
week's folder before assuming an environment is actually deployed.
