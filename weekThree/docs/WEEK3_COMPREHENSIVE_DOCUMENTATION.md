# Week 3 — Terraform Modules, OKE, and Kubernetes: Comprehensive Documentation

**Author:** Ali Yousef
**Program:** Ejada Cloud Build Internship — Intern Track (`intern-02-ali-youssef-cmp`)
**Region:** `me-jeddah-1`
**Week:** 3 of the DevOps / Kubernetes / Terraform track
**Scope:** Reusable Terraform modules (Subnet, OKE) + a full OKE lab (cluster, VCN-native pod networking, managed node pool, application deployment, external block volume, public Load Balancer)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [The Assignment, As Given](#2-the-assignment-as-given)
3. [Environment, Prerequisites, and Tooling](#3-environment-prerequisites-and-tooling)
4. [High-Level Architecture](#4-high-level-architecture)
5. [Terraform Module Design Philosophy](#5-terraform-module-design-philosophy)
6. [The Subnet Module — Full Deep Dive](#6-the-subnet-module--full-deep-dive)
7. [The OKE Module — Full Deep Dive](#7-the-oke-module--full-deep-dive)
8. [Root Configuration — Composing the Modules](#8-root-configuration--composing-the-modules)
9. [Networking Architecture, Rule by Rule](#9-networking-architecture-rule-by-rule)
10. [The Worker Node Image Selection Problem](#10-the-worker-node-image-selection-problem)
11. [Kubernetes Manifests — Full Deep Dive](#11-kubernetes-manifests--full-deep-dive)
12. [The Full Deployment Journey, Chronologically](#12-the-full-deployment-journey-chronologically)
13. [Every Problem Encountered and How It Was Solved](#13-every-problem-encountered-and-how-it-was-solved)
14. [Security Considerations](#14-security-considerations)
15. [Cost Management and Teardown Discipline](#15-cost-management-and-teardown-discipline)
16. [Verification and Testing Methodology](#16-verification-and-testing-methodology)
17. [Mapping This Work Back to the Assignment Brief](#17-mapping-this-work-back-to-the-assignment-brief)
18. [Lessons Learned](#18-lessons-learned)
19. [Possible Future Improvements](#19-possible-future-improvements)
20. [Glossary of Terms](#20-glossary-of-terms)
21. [Appendix A — Full File Listings](#21-appendix-a--full-file-listings)
22. [Appendix B — Full Command Reference](#22-appendix-b--full-command-reference)

---

## 1. Executive Summary

Week 3 of the internship shifted focus from writing one-off Terraform configurations (as in Weeks 1 and 2) to writing **reusable Terraform modules** — self-contained, parameterized units of infrastructure-as-code that can be called multiple times with different inputs to produce different concrete resources, without duplicating the underlying resource logic. Two modules were built:

1. A **Subnet module** (`modules/subnet`) that creates four related OCI resources as a single logical unit: a Subnet, a Route Table, a Security List, and (optionally) a VCN Flow Log ("Enable Logs").
2. An **OKE module** (`modules/oke`) that creates an Oracle Container Engine for Kubernetes (OKE) cluster and its managed node pool, with full support for both of OKE's pod-networking modes (VCN-native and Flannel overlay) selected via a variable rather than hardcoded.

These two modules were then **composed** four and one times respectively in a root Terraform configuration to build a complete, real environment: one Virtual Cloud Network (VCN) containing four purpose-specific subnets (API endpoint, worker nodes, pods, load balancer), one OKE cluster running Kubernetes v1.36.1 with VCN-native pod networking, and one two-node managed worker node pool.

On top of that live infrastructure, a small demonstration application was deployed using plain Kubernetes manifests (not Terraform — intentionally, since the assignment's lab section calls for using `kubectl`/Kubernetes-native tooling once the cluster exists). The application is an `nginx` web server that reads its home page from a `PersistentVolumeClaim` backed by a real OCI Block Volume (attached dynamically via the CSI driver), and is exposed to the public internet through a Kubernetes `Service` of `type: LoadBalancer`, which OKE's cloud-controller-manager translates into an actual OCI Load Balancer.

The entire exercise was carried out twice, end-to-end, across two separate work sessions, with the full OCI infrastructure being deliberately and completely destroyed (`terraform destroy`) at the end of the first session to avoid overnight billing, and rebuilt from the exact same Terraform code the next day — itself a demonstration that the modules and configuration are correctly idempotent and reproducible, not a one-shot fluke.

Along the way, six distinct real-world problems were hit and solved, each documented in detail in [Section 13](#13-every-problem-encountered-and-how-it-was-solved): an invalid cross-variable Terraform validation block, a deprecated-provider resolution warning, an OKE worker-image-selection data source returning an empty/wrong result on two separate iterations, a local Windows OCI-CLI installation failure caused by a Python version/wheel-availability mismatch, an OCI CLI credential-file bootstrap failure rooted in a tenant IAM permission gap, a `kubectl` credential-plugin `PATH` resolution failure, a CRI-O "short name mode is enforcing" image-pull failure, and a Kubernetes rolling-update deadlock caused by combining a single replica, a `ReadWriteOnce` volume, and the default `RollingUpdate` deployment strategy.

By the end, every requirement in the assignment brief was met and independently verified: the modules are generic and reusable (no hardcoded values, driven entirely by variables), they make real use of `dynamic` blocks and conditional expressions, the OKE cluster was created with VCN-native pod networking and a managed worker node pool, an application was deployed to it, an external block volume was attached to that application, and the application was exposed through a Load Balancer — confirmed by loading the Load Balancer's public IP address in a browser and seeing the application's own proof-of-life page, rendered live from the mounted block volume.

---

## 2. The Assignment, As Given

For completeness and traceability, here is the assignment brief exactly as it was issued for Week 3:

> **Week 3 — DevOps / Kubernetes**
>
> Study the first 9 modules of the DevOps course or the Kubernetes course (both cover the same content). Modules 6 and 7 can be skipped for now, to be studied after the lab, since they are not used in the lab itself.
>
> **Terraform.** This week starts with one of the most important Terraform concepts: Modules. Two modules were required:
>
> - A **Subnet Module** containing four resources: Subnet, Route Table, Security List, and "Enable Logs".
> - An **OKE Module** for creating the OKE cluster and its required components.
>
> Modules must be generic and reusable. Hardcoded values inside the module code are to be avoided; values should be passed through variables and adapted from the root configuration. As part of this, the following needed to be researched and understood: dynamic blocks in Terraform, conditions/conditional expressions in Terraform, and how to make Terraform modules reusable and configurable.
>
> **Lab.** Using the modules built above: create an OKE cluster with VCN-native pod networking and a managed worker node pool, deploy an application to OKE, attach an external block volume to the application, and expose the application through a Load Balancer.
>
> The goal is not only to make it work, but to build it in a clean, reusable, and configurable Terraform structure.

The self-study portion (course modules 1–9, skipping 6 and 7) is outside the scope of what this document can verify or account for — it is individual study time and is not represented in this write-up beyond this acknowledgment. Everything else in the brief — the two modules, the reusability/dynamic-block/conditional-expression requirements, and every element of the lab — is covered in full in the sections that follow, and is cross-referenced explicitly against the brief again in [Section 17](#17-mapping-this-work-back-to-the-assignment-brief).

---

## 3. Environment, Prerequisites, and Tooling

### 3.1 Cloud environment

- **Cloud provider:** Oracle Cloud Infrastructure (OCI)
- **Tenancy:** the Ejada internship program tenancy (`ociejada`), identity domain `Ejada-interim-program`
- **Compartment:** `intern-02-ali-youssef-cmp`, looked up dynamically at plan/apply time via the `oci_identity_compartments` data source rather than hardcoded by OCID (see [Section 8.2](#82-vcntf--the-networking-backbone))
- **Region:** `me-jeddah-1` (Jeddah, Saudi Arabia)
- **Authentication:** API key-based authentication (tenancy OCID, user OCID, key fingerprint, private key file), the same pattern used in Weeks 1 and 2, supplied to Terraform via a git-ignored `terraform.tfvars` file and marked `sensitive = true` in every variable that carries it

### 3.2 Local tooling (the developer's Windows machine)

All hands-on work — running `terraform`, `kubectl`, and the `oci` CLI, and viewing the deployed application in a browser — happened on the developer's own Windows machine, not inside any sandboxed assistant environment. The following tools were installed and used there over the course of the week:

| Tool | Version observed | Purpose |
|---|---|---|
| Terraform (or OpenTofu-compatible) | provider `oracle/oci ~> 7.0` | Provisioning all OCI infrastructure |
| `kubectl` | pre-installed on the machine | Talking to the Kubernetes API once the cluster existed |
| OCI CLI | `3.90.2` (installed via `pip install --user oci-cli` under Python 3.12) | Generating a `kubeconfig` for the new cluster, and (transitively) supplying live authentication tokens to `kubectl` on every API call |
| Python | 3.12 (a second, separate install alongside a pre-existing 3.14) | Required specifically because `oci-cli`'s pinned dependency on `PyYAML <= 6.0.2` has no prebuilt wheel for Python 3.14, and building it from source requires Microsoft C++ Build Tools that were not installed |
| Google Chrome | — | Verifying the running application by visiting the Load Balancer's public IP, and (separately, unsuccessfully) attempting to check the OCI Console via browser automation |

### 3.3 Why local execution, not the assistant's own sandbox

An important operational detail, worth documenting because it shaped how the week's work actually happened: the assistant helping with this work runs in an isolated cloud sandbox with **no network route to OCI's control plane or to the developer's local machine's shell**. It could read and write files that were then delivered to the developer's real project folder (`C:\Users\yinya\Documents\oci-terraform-lab\weekThree\`) via a file-transfer bridge, and it could observe terminal output the developer chose to paste back — but it could not run `terraform apply`, `kubectl`, or `oci` itself. Every single command shown as "run" throughout this document (and throughout the week) was typed and executed by the developer on their own machine; the assistant's role was to write the Terraform/Kubernetes source files, propose exact commands, and interpret the pasted output to diagnose the next problem. This is called out explicitly here because it explains why the week's troubleshooting narrative in [Section 12](#12-the-full-deployment-journey-chronologically) reads the way it does — as a tight loop of "here is the exact command to run" → "here is what happened" → "here is why, and here is the fix" — rather than autonomous execution.

---

## 4. High-Level Architecture

### 4.1 Network topology

A single VCN (`10.0.0.0/16`, display name `tf-lab-oke-vcn-AliYousef`, DNS label `oketflab`) contains four subnets, each created by a separate call to the Subnet module, each with its own route table and security list so that traffic rules stay scoped to exactly the resources that need them:

```
VCN  10.0.0.0/16  (tf-lab-oke-vcn-AliYousef)
│
├── Internet Gateway  (tf-lab-oke-igw-AliYousef)
├── NAT Gateway        (tf-lab-oke-nat-AliYousef)
├── Service Gateway    (tf-lab-oke-sgw-AliYousef)  → "All ... Services In Oracle Services Network"
├── Log Group          (tf-lab-oke-log-group-AliYousef)   [conditional on enable_flow_logs]
│
├── Endpoint Subnet   10.0.0.0/28    (public*)   — hosts the OKE Kubernetes API endpoint
├── Workers Subnet    10.0.16.0/20   (private)   — hosts the worker node VNICs
├── Pods Subnet       10.0.32.0/19   (private)   — hosts pod VNICs (VCN-native pod networking)
└── LB Subnet         10.0.8.0/24    (public)    — hosts the OCI Load Balancer created by any
                                                     Kubernetes Service of type LoadBalancer

* "public" here means the subnet's route table sends 0.0.0.0/0 to the Internet Gateway and its
  security list allows inbound traffic from the internet on specific ports — not that every
  resource in it is required to have a public IP. Whether the OKE endpoint itself gets a public
  IP is controlled independently by var.is_endpoint_public, which also flips the endpoint
  subnet's route table between the Internet Gateway and the NAT Gateway (see Section 9).
```

### 4.2 Compute / Kubernetes topology

```
OKE Cluster  "tf-lab-oke-AliYousef"   (BASIC_CLUSTER, Kubernetes v1.36.1, VCN-native pods)
│
└── Managed Node Pool  "tf-lab-oke-AliYousef-workers"
    ├── Node 1   VM.Standard.E4.Flex (2 OCPU / 16 GB)   — Workers Subnet, AD-1
    └── Node 2   VM.Standard.E4.Flex (2 OCPU / 16 GB)   — Workers Subnet, AD-1

    Namespace: week3-demo
    ├── StorageClass  week3-oci-bv        (blockvolume.csi.oraclecloud.com, Balanced tier)
    ├── PersistentVolumeClaim  demo-app-data   (50Gi, RWO)  →  real OCI Block Volume
    ├── Deployment  demo-app  (replicas: 1, strategy: Recreate)
    │   └── Pod
    │       ├── initContainer: write-index (busybox)  — writes index.html onto the PVC
    │       └── container: nginx                      — serves the PVC's index.html on :80
    └── Service  demo-app  (type: LoadBalancer)  →  real OCI Load Balancer, public IP
```

### 4.3 Terraform module / file layout

```
weekThree/
├── provider.tf                  # terraform{} + provider "oci" {} blocks
├── variables.tf                 # every root-level input variable
├── vcn.tf                       # VCN, gateways, log group, compartment lookup
├── subnets.tf                   # 4 calls to modules/subnet
├── oke.tf                       # worker image selection logic + 1 call to modules/oke
├── outputs.tf                   # root outputs, incl. debug_* outputs used while troubleshooting
├── terraform.tfvars             # real values (git-ignored, not committed)
├── terraform.tfvars.example     # template committed to the repo instead
│
├── modules/
│   ├── subnet/
│   │   ├── main.tf              # Route Table, Security List, Subnet, Flow Log resources
│   │   ├── variables.tf         # every input the module accepts
│   │   ├── outputs.tf           # subnet_id, subnet_cidr_block, route_table_id, security_list_id, flow_log_id
│   │   └── README.md            # module usage documentation
│   └── oke/
│       ├── main.tf              # oci_containerengine_cluster + oci_containerengine_node_pool
│       ├── variables.tf         # every input the module accepts
│       ├── outputs.tf           # cluster_id, cluster_kubernetes_version, node_pool_id, pod_network_type
│       └── README.md            # module usage documentation, incl. the IAM-policy caveat
│
├── k8s/
│   ├── namespace.yaml
│   ├── storageclass.yaml
│   ├── pvc.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── README.md
│
└── docs/
    ├── iam-policy-request-draft.md
    └── WEEK3_COMPREHENSIVE_DOCUMENTATION.md    # this file
```

---

## 5. Terraform Module Design Philosophy

The assignment's central instruction for the module-building portion of the week was blunt and worth repeating verbatim because it drove every design decision in both modules: *"Make your modules generic and reusable. Avoid hardcoding values inside the module code. Values should be passed through variables and adapted from the root configuration."*

Concretely, this was interpreted and applied as five hard rules while writing `modules/subnet` and `modules/oke`:

**Rule 1 — No resource argument may be a literal that represents a business decision.** Anything a caller might reasonably want different next time — a CIDR block, a display name, a shape, a boolean toggle, a list of rules — must come from a `variable`, never be typed directly into a `resource` block. The only literals that remain in either module's `main.tf` are OCI API enum values that are not configuration choices at all (things like `source_type = "OCISERVICE"` or `log_type = "SERVICE"` on the flow log resource, or `source_type = "IMAGE"` on the node pool's `node_source_details` — these are fixed vocabulary the OCI API itself defines, not something a caller of the module would ever want to vary).

**Rule 2 — Every variable gets a `description`.** Not for Terraform's benefit, but for the module's next reader (which, given how many times this exact codebase was destroyed and rebuilt this week, was frequently the same author a day later). A variable with no description is a variable whose correct value can only be guessed.

**Rule 3 — Optional behavior is expressed with `optional()` in object-typed variables, `default` values, and conditional expressions — never with a second, near-duplicate copy of a resource.** This is what makes rules like "only add the public ingress rule when the subnet is public" or "only render the Flannel block when Flannel is selected" possible without forking the module into `subnet-public` and `subnet-private` variants, or `oke-flannel` and `oke-vcn-native` variants. This rule is elaborated at length in Sections 6 and 7, since it's the mechanical heart of "reusable."

**Rule 4 — A module must be safely callable more than once in the same root configuration, with different inputs, without any of the calls colliding.** This is a direct test of genericness: if a module can only ever be instantiated once per root config, it isn't really a module, it's just a resource block wearing a costume. The Subnet module is called **four separate times** in `subnets.tf` — for the endpoint, workers, pods, and load balancer subnets — with four different CIDR blocks, four different sets of ingress/egress rules, and two different `is_public` values, and each call produces its own independent Route Table, Security List, Subnet, and (optionally) Flow Log, with no shared state or naming collisions between them.

**Rule 5 — Cross-field validation that Terraform's own `variable { validation {} }` block cannot express belongs in a `lifecycle { precondition {} }` block on the resource, not skipped.** Terraform variable validation blocks may only reference the variable being validated — they cannot reference a sibling variable. The Subnet module needs exactly this: `log_group_id` must be set whenever `enable_logs` is `true`, which is a two-variable rule. Section 6.4 covers the fix in detail; it's flagged here as a design rule because it would have been easy — and wrong — to just silently drop the check.

These five rules, taken together, are what "dynamic blocks" and "conditional expressions" are *for* in Terraform, and why the assignment called them out by name as things to research: they are the two language features that let a single, static resource block in a module's `main.tf` behave differently — rendering more or fewer sub-blocks, or entirely different sibling blocks — depending on what the caller passed in as variables. Every dynamic block and every conditional expression in both modules exists because of one of the five rules above; none are decorative.

---

## 6. The Subnet Module — Full Deep Dive

### 6.1 Purpose and scope

The Subnet module's job is to take a single set of inputs describing "a subnet and its networking rules" and produce the four OCI resources that, together, make a usable OCI subnet: the **Subnet** itself, a **Route Table** that controls where traffic leaving the subnet goes, a **Security List** that controls what traffic is allowed in and out at the subnet level, and — optionally — a **Flow Log** ("Enable Logs" in the OCI Console's terminology) that streams every accepted/rejected connection through the subnet into OCI Logging for later analysis. Bundling all four into one module call means the caller never has to remember to also create a route table and a security list every time they want a subnet — the module guarantees the three always exist together and are already wired to each other correctly.

### 6.2 Full source: `modules/subnet/variables.tf`

```hcl
variable "compartment_id" {
  description = "OCID of the compartment where the subnet and its related resources will be created."
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN the subnet belongs to."
  type        = string
}

variable "subnet_display_name" {
  description = "Display name for the subnet."
  type        = string
}

variable "subnet_cidr_block" {
  description = "CIDR block for the subnet, e.g. \"10.0.1.0/24\"."
  type        = string
}

variable "dns_label" {
  description = "DNS label for the subnet. Set to null to skip DNS resolution for this subnet."
  type        = string
  default     = null
}

variable "is_public" {
  description = "Whether VNICs in this subnet are allowed a public IP. false creates a private subnet (prohibit_public_ip_on_vnic = true)."
  type        = bool
  default     = false
}

variable "route_table_display_name" {
  description = "Display name for the route table created for this subnet."
  type        = string
}

variable "security_list_display_name" {
  description = "Display name for the security list created for this subnet."
  type        = string
}

variable "route_rules" {
  description = <<-EOT
    Route rules attached to this subnet's route table. One object per rule:
      destination        CIDR block (or service CIDR label) the rule matches
      destination_type   "CIDR_BLOCK" or "SERVICE_CIDR_BLOCK" (default "CIDR_BLOCK")
      network_entity_id  OCID of the target: internet gateway, NAT gateway, service gateway, DRG, etc.
  EOT
  type = list(object({
    destination       = string
    destination_type  = optional(string, "CIDR_BLOCK")
    network_entity_id = string
  }))
  default = []
}

variable "ingress_rules" {
  description = <<-EOT
    Ingress security rules for this subnet's security list. One object per rule:
      source        CIDR block, service label, or NSG OCID traffic is allowed from
      source_type   "CIDR_BLOCK", "SERVICE_CIDR_BLOCK", or "NETWORK_SECURITY_GROUP" (default "CIDR_BLOCK")
      protocol      protocol number as a string: "6" = TCP, "17" = UDP, "1" = ICMP, "all" = all protocols
      description   human-readable description shown in the console
      stateless     whether the rule is stateless (default false)
      tcp_options   optional { min = number, max = number } port range, only relevant when protocol = "6"
      udp_options   optional { min = number, max = number } port range, only relevant when protocol = "17"
      icmp_options  optional { type = number, code = optional(number) }, only relevant when protocol = "1"
  EOT
  type = list(object({
    source      = string
    source_type = optional(string, "CIDR_BLOCK")
    protocol    = string
    description = optional(string, "")
    stateless   = optional(bool, false)
    tcp_options = optional(object({
      min = number
      max = number
    }))
    udp_options = optional(object({
      min = number
      max = number
    }))
    icmp_options = optional(object({
      type = number
      code = optional(number)
    }))
  }))
  default = []
}

variable "egress_rules" {
  description = "Egress security rules for this subnet's security list. Same shape as ingress_rules, but source/source_type become destination/destination_type."
  type = list(object({
    destination      = string
    destination_type = optional(string, "CIDR_BLOCK")
    protocol         = string
    description      = optional(string, "")
    stateless        = optional(bool, false)
    tcp_options = optional(object({
      min = number
      max = number
    }))
    udp_options = optional(object({
      min = number
      max = number
    }))
    icmp_options = optional(object({
      type = number
      code = optional(number)
    }))
  }))
  default = []
}

variable "enable_logs" {
  description = "Whether to create a VCN flow log ('Enable Logs') for this subnet."
  type        = bool
  default     = false
}

variable "log_group_id" {
  description = "OCID of the OCI Logging log group to place the flow log in. Required when enable_logs = true. Enforced with a lifecycle precondition on oci_logging_log.flow_log in main.tf, since a variable validation block can only reference itself, not enable_logs."
  type        = string
  default     = null
}

variable "log_retention_duration" {
  description = "Retention period, in days, for the subnet's flow log. Only used when enable_logs = true."
  type        = number
  default     = 30
}

variable "freeform_tags" {
  description = "Freeform tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
```

### 6.3 Why the rule variables are typed the way they are

`route_rules`, `ingress_rules`, and `egress_rules` are all `list(object({...}))` — lists of structured objects, not simple lists of strings — because a single security rule is not a single scalar value; it's a bundle of related fields (source, protocol, description, an optional nested port range) that all belong together. Modeling this as a typed object list, rather than (for example) three parallel lists of sources/protocols/descriptions that the caller has to keep in index-alignment by hand, is what makes the calling code in `subnets.tf` (Section 8) read as a list of self-contained rule declarations rather than a fragile positional encoding.

The `optional()` type constructor (a feature added to Terraform's type system specifically to support this pattern) is used throughout so that a caller only has to specify the fields that are actually relevant to a given rule. A rule with `protocol = "all"` has no meaningful port range, so `tcp_options` is entirely omitted for that rule in the calling code — the object type allows this because `tcp_options` is `optional(object({...}))` with no explicit default, which makes its effective value `null` when omitted. This distinction — "was this optional field provided at all" (`null` vs. a real object) — is exactly what the nested `dynamic` blocks in `main.tf` test for, covered next.

### 6.4 Full source: `modules/subnet/main.tf`

```hcl
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

resource "oci_core_route_table" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = var.route_table_display_name
  freeform_tags  = var.freeform_tags

  dynamic "route_rules" {
    for_each = var.route_rules
    content {
      destination       = route_rules.value.destination
      destination_type  = route_rules.value.destination_type
      network_entity_id = route_rules.value.network_entity_id
    }
  }
}

resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = var.security_list_display_name
  freeform_tags  = var.freeform_tags

  dynamic "ingress_security_rules" {
    for_each = var.ingress_rules
    content {
      source      = ingress_security_rules.value.source
      source_type = ingress_security_rules.value.source_type
      protocol    = ingress_security_rules.value.protocol
      description = ingress_security_rules.value.description
      stateless   = ingress_security_rules.value.stateless

      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.tcp_options != null ? [ingress_security_rules.value.tcp_options] : []
        content {
          min = tcp_options.value.min
          max = tcp_options.value.max
        }
      }

      dynamic "udp_options" {
        for_each = ingress_security_rules.value.udp_options != null ? [ingress_security_rules.value.udp_options] : []
        content {
          min = udp_options.value.min
          max = udp_options.value.max
        }
      }

      dynamic "icmp_options" {
        for_each = ingress_security_rules.value.icmp_options != null ? [ingress_security_rules.value.icmp_options] : []
        content {
          type = icmp_options.value.type
          code = try(icmp_options.value.code, null)
        }
      }
    }
  }

  dynamic "egress_security_rules" {
    for_each = var.egress_rules
    content {
      destination      = egress_security_rules.value.destination
      destination_type = egress_security_rules.value.destination_type
      protocol         = egress_security_rules.value.protocol
      description      = egress_security_rules.value.description
      stateless        = egress_security_rules.value.stateless

      dynamic "tcp_options" {
        for_each = egress_security_rules.value.tcp_options != null ? [egress_security_rules.value.tcp_options] : []
        content {
          min = tcp_options.value.min
          max = tcp_options.value.max
        }
      }

      dynamic "udp_options" {
        for_each = egress_security_rules.value.udp_options != null ? [egress_security_rules.value.udp_options] : []
        content {
          min = udp_options.value.min
          max = udp_options.value.max
        }
      }

      dynamic "icmp_options" {
        for_each = egress_security_rules.value.icmp_options != null ? [egress_security_rules.value.icmp_options] : []
        content {
          type = icmp_options.value.type
          code = try(icmp_options.value.code, null)
        }
      }
    }
  }
}

resource "oci_core_subnet" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id

  display_name = var.subnet_display_name
  cidr_block   = var.subnet_cidr_block
  dns_label    = var.dns_label

  route_table_id    = oci_core_route_table.this.id
  security_list_ids = [oci_core_security_list.this.id]

  # is_public drives whether VNICs here may hold a public IP at all.
  prohibit_public_ip_on_vnic = var.is_public ? false : true

  freeform_tags = var.freeform_tags
}

# "Enable Logs" - a VCN flow log for this subnet, created only when var.enable_logs is true.
resource "oci_logging_log" "flow_log" {
  count = var.enable_logs ? 1 : 0

  display_name = "${var.subnet_display_name}-flow-log"
  log_group_id = var.log_group_id
  log_type     = "SERVICE"

  configuration {
    compartment_id = var.compartment_id

    source {
      category    = "all"
      resource    = oci_core_subnet.this.id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
  }

  retention_duration = var.log_retention_duration
  is_enabled         = true

  freeform_tags = var.freeform_tags

  lifecycle {
    precondition {
      condition     = var.log_group_id != null
      error_message = "log_group_id must be set when enable_logs = true."
    }
  }
}
```

### 6.5 Reading the dynamic blocks: how "zero, one, or many" is expressed

Terraform's `dynamic` block takes a `for_each` argument and, for every element of whatever collection that expression evaluates to, emits one copy of the nested `content {}` block. The trick used throughout this module, and worth calling out explicitly because it is the single most-reused pattern in both modules, is the **"maybe render a single optional nested block" idiom**:

```hcl
dynamic "tcp_options" {
  for_each = ingress_security_rules.value.tcp_options != null ? [ingress_security_rules.value.tcp_options] : []
  content { ... }
}
```

`tcp_options` in the OCI provider schema is a *singular*, optional nested block — a rule either has one `tcp_options {}` block or none at all, never two. But `dynamic` always iterates a collection. The idiom bridges this gap: when the caller's `tcp_options` object is non-null, the `for_each` expression evaluates to a one-element list containing that object, so the `dynamic` block renders its `content {}` exactly once; when it's `null` (the caller omitted it, e.g. for an `"all"`-protocol rule), the `for_each` expression evaluates to an empty list, so the `dynamic` block renders nothing at all. This single ternary is what lets one static piece of HCL correctly express "TCP rules have a port range, ICMP rules have a type/code pair, `all`-protocol rules have neither" without three separate near-duplicate resource blocks.

The outer `dynamic "ingress_security_rules"` and `dynamic "egress_security_rules"` blocks use the more familiar form of the same mechanism: `for_each = var.ingress_rules` (a genuine list with zero or more real elements) simply produces one `ingress_security_rules {}` sub-block per rule the caller supplied — including zero sub-blocks at all if the caller passes an empty list (the type's `default = []`), and arbitrarily many if the caller passes many. This is what lets the same module produce a security list with two rules (the pods subnet, which only needs one broad "allow VCN-internal traffic" ingress rule and one broad egress rule) and a security list with five rules (the endpoint subnet, which needs several narrowly-scoped rules) from the exact same `main.tf`.

### 6.6 The `count`-based conditional resource: "Enable Logs"

Unlike the rule lists, whether the flow log resource exists **at all** is a single yes/no toggle (`var.enable_logs`), not a variable-length collection — so instead of a `dynamic` block (which conditions the presence of a *nested block within* a resource), the module uses Terraform's other conditional-resource mechanism: the `count` meta-argument on the resource itself.

```hcl
resource "oci_logging_log" "flow_log" {
  count = var.enable_logs ? 1 : 0
  ...
}
```

When `var.enable_logs` is `true`, `count` evaluates to `1` and exactly one `oci_logging_log.flow_log` resource is created (addressed in Terraform's state as `oci_logging_log.flow_log[0]`). When it's `false`, `count` evaluates to `0` and the resource is not created at all — not created-then-disabled, genuinely absent from the plan and from state. This is why every place that *references* this resource elsewhere in the codebase (the module's own `outputs.tf`, and the root's `local.log_group_id` lookup) has to guard the reference with the same condition — you cannot index into a zero-length resource. In `modules/subnet/outputs.tf`:

```hcl
output "flow_log_id" {
  description = "OCID of the flow log, or null when enable_logs = false."
  value       = var.enable_logs ? oci_logging_log.flow_log[0].id : null
}
```

### 6.7 The validation problem that had to be solved with a `lifecycle precondition`, not a `variable validation`

`log_group_id` has an intrinsic rule attached to it: it *must* be a real OCID whenever `enable_logs = true` (otherwise the flow log resource has nowhere to live), but it's perfectly fine to leave it `null` when `enable_logs = false` (there's no flow log to place anywhere). This is naturally a two-variable rule — it can't be phrased as a constraint on `log_group_id` alone, because whether the constraint applies at all depends on the separate `enable_logs` variable.

The first draft of this module tried to express that rule the obvious way, directly on the variable:

```hcl
# This does NOT work — Terraform rejects it at plan time.
variable "log_group_id" {
  type    = string
  default = null

  validation {
    condition     = var.enable_logs ? var.log_group_id != null : true
    error_message = "log_group_id must be set when enable_logs = true."
  }
}
```

Terraform's `variable { validation {} }` block is explicitly restricted to referencing only the variable it's attached to (plus the small set of built-in functions) — it cannot reach across to a sibling variable like `var.enable_logs`. Attempting this produces a plan-time error along the lines of *"Invalid reference from validation condition: the condition for variable ... can only refer to the variable itself"*. This was caught early, during local `tofu init`/`tofu validate` testing before the file was ever sent to the developer's machine, precisely because module-level validation was part of the review checklist from Rule 5 in Section 5.

The fix moves the same logical check onto a `lifecycle { precondition {} }` block on the resource that actually needs the guarantee — `oci_logging_log.flow_log` — where cross-referencing other variables and resources is fully supported, because preconditions execute in the context of the whole module, not in the restricted context of a single variable's declaration:

```hcl
resource "oci_logging_log" "flow_log" {
  count = var.enable_logs ? 1 : 0
  ...
  lifecycle {
    precondition {
      condition     = var.log_group_id != null
      error_message = "log_group_id must be set when enable_logs = true."
    }
  }
}
```

Because the whole resource is already `count`-gated on `var.enable_logs`, the precondition only ever actually executes when `enable_logs = true` in the first place (when it's `false`, the resource doesn't exist, so its precondition never runs) — so the precondition body only needs to check `log_group_id != null`, not repeat the `enable_logs` condition. If a caller sets `enable_logs = true` without setting `log_group_id`, `terraform plan` now fails fast with the exact error message above, instead of the OCI API returning a much less legible 400 error later during apply.

### 6.8 Full source: `modules/subnet/outputs.tf`

```hcl
output "subnet_id" {
  description = "OCID of the created subnet."
  value       = oci_core_subnet.this.id
}

output "subnet_cidr_block" {
  description = "CIDR block of the created subnet."
  value       = oci_core_subnet.this.cidr_block
}

output "route_table_id" {
  description = "OCID of the created route table."
  value       = oci_core_route_table.this.id
}

output "security_list_id" {
  description = "OCID of the created security list."
  value       = oci_core_security_list.this.id
}

output "flow_log_id" {
  description = "OCID of the flow log, or null when enable_logs = false."
  value       = var.enable_logs ? oci_logging_log.flow_log[0].id : null
}
```

Every output a caller might reasonably need to reference from the root config — most importantly `subnet_id`, since that's the value the OKE module and every `node_placement_configs` entry needs — is exposed here, rather than forcing the caller to reach into the module's internal resource addresses (which Terraform explicitly discourages and, in the case of `count`-indexed resources like the flow log, would leak the conditional-existence complexity out of the module entirely).

### 6.9 The `required_providers` block, and why it was added after the fact

The very first version of both modules omitted a `terraform { required_providers {} }` block entirely, relying on Terraform's implicit provider inheritance from the root module. This worked, but produced a warning during `terraform init` that both `oracle/oci` (the modern, actively maintained provider, used explicitly in the root's `provider.tf`) and the deprecated `hashicorp/oci` provider (an old, no-longer-updated namespace for the same provider, left over from before Oracle took over publishing it under their own namespace) were being resolved and downloaded, because a child module with no explicit provider requirement lets Terraform fall back to a broader, ambiguous resolution search that can pick up the legacy namespace. Adding the explicit block to both modules' `main.tf` —

```hcl
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}
```

— pins the module to the same, modern provider source and version constraint the root config already declares, and the warning about `hashicorp/oci` stopped appearing on subsequent `terraform init` runs. This is documented here in detail because it is a genuinely easy mistake to make (every other part of the module works fine without it) and a genuinely easy one to overlook once it's fixed, since the symptom is "just a warning," not a hard failure.

---

## 7. The OKE Module — Full Deep Dive

### 7.1 Purpose and scope

The OKE module's job is to take a single set of inputs describing "a Kubernetes cluster and its worker pool" and produce two OCI resources: the `oci_containerengine_cluster` (the managed Kubernetes control plane) and the `oci_containerengine_node_pool` (a managed group of worker VM instances that automatically register themselves with that control plane). Unlike the Subnet module, the OKE module is only called once in this week's root configuration — but it is still built generically, because a single "OKE cluster" call has to correctly express a genuine either/or choice that a real reusable module cannot hardcode: **which of OKE's two pod-networking models to use.**

### 7.2 The two pod-networking models, conceptually

Every Kubernetes cluster needs a Container Network Interface (CNI) plugin that gives every pod its own IP address and routes traffic between pods, regardless of which node they land on. OKE supports two fundamentally different approaches to this, and the module has to be able to build a cluster running either one, selected by the caller, not hardcoded:

- **`FLANNEL_OVERLAY`** — the older, default-for-a-long-time approach. Pods get IP addresses from a separate, overlay CIDR range (e.g. `10.244.0.0/16`) that has no direct relationship to the VCN's own addressing. Traffic between pods on different nodes is encapsulated (wrapped in an extra layer of packet headers) and tunneled between the nodes' real VCN IPs. This is simple to set up (it needs no VCN subnet of its own) but the extra encapsulation costs a small amount of throughput/latency, and — more importantly for anyone doing real operational work — pod IPs are invisible to native VCN tooling like Security Lists, Flow Logs, and VCN-level routing, because they only exist inside the overlay.

- **`VCN_NATIVE`** (formally `OCI_VCN_IP_NATIVE` at the CNI-type level) — the newer, recommended approach, and the one this week's lab specifically required. Every pod gets a *real* IP address from an actual VCN subnet (the dedicated Pods Subnet described in Section 4.1), the same way a VM's VNIC would. There's no encapsulation — pod traffic is routed by the VCN's own routing tables just like any other VCN traffic — and because pod IPs are real VCN IPs, they show up in VCN Flow Logs, can be targeted by VCN-level Security Lists and Network Security Groups, and generally behave like first-class citizens of the network rather than a hidden overlay. The tradeoff is that this consumes real VCN IP address space at pod density (hence the deliberately large `/19` CIDR block given to the Pods Subnet in Section 4.1 — VCN-native pod networking needs enough IPs for *every pod*, not just every node), and it requires a dedicated subnet (or subnets) set aside purely for pod IPs, plus a `max_pods_per_node` ceiling that the OKE module also exposes as a variable.

The module supports both, selected entirely by the single `var.pod_network_type` string, because a module that only supported VCN-native would not actually be "generic" in the sense the assignment asked for — it would be a script with the CNI type baked in, not a reusable building block.

### 7.3 Full source: `modules/oke/variables.tf`

```hcl
variable "compartment_id" {
  description = "OCID of the compartment where the cluster and node pool will be created."
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN the cluster runs in."
  type        = string
}

variable "cluster_name" {
  description = "Display name for the OKE cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for both the control plane and the node pool, e.g. \"v1.30.1\". Use the oci_containerengine_cluster_option data source from the root config to look up currently supported versions instead of hardcoding one here."
  type        = string
}

variable "cluster_type" {
  description = "\"BASIC_CLUSTER\" or \"ENHANCED_CLUSTER\". Enhanced is required for features such as customer-managed control plane encryption or advanced add-ons."
  type        = string
  default     = "BASIC_CLUSTER"

  validation {
    condition     = contains(["BASIC_CLUSTER", "ENHANCED_CLUSTER"], var.cluster_type)
    error_message = "cluster_type must be \"BASIC_CLUSTER\" or \"ENHANCED_CLUSTER\"."
  }
}

# --- Control plane endpoint -------------------------------------------------

variable "endpoint_subnet_id" {
  description = "OCID of the (regional) subnet the Kubernetes API endpoint is placed in."
  type        = string
}

variable "is_endpoint_public" {
  description = "Whether the Kubernetes API endpoint gets a public IP. false keeps the control plane reachable only from inside the VCN (e.g. via a bastion or VPN)."
  type        = bool
  default     = false
}

variable "endpoint_nsg_ids" {
  description = "NSG OCIDs applied to the API endpoint VNIC. Empty list = rely on the endpoint subnet's security list only."
  type        = list(string)
  default     = []
}

# --- Pod networking ----------------------------------------------------------

variable "pod_network_type" {
  description = "\"VCN_NATIVE\" (recommended - pods get real VCN IPs from pod_subnet_ids) or \"FLANNEL_OVERLAY\" (legacy overlay network)."
  type        = string
  default     = "VCN_NATIVE"

  validation {
    condition     = contains(["VCN_NATIVE", "FLANNEL_OVERLAY"], var.pod_network_type)
    error_message = "pod_network_type must be \"VCN_NATIVE\" or \"FLANNEL_OVERLAY\"."
  }
}

variable "pod_subnet_ids" {
  description = "Subnet OCID(s) pods draw IPs from. Required when pod_network_type = \"VCN_NATIVE\", ignored otherwise."
  type        = list(string)
  default     = []
}

variable "pod_nsg_ids" {
  description = "NSG OCIDs applied to pod VNICs. Only used when pod_network_type = \"VCN_NATIVE\"."
  type        = list(string)
  default     = []
}

variable "max_pods_per_node" {
  description = "Maximum pods per worker node. Only used when pod_network_type = \"VCN_NATIVE\"."
  type        = number
  default     = 31
}

variable "pods_cidr" {
  description = "CIDR block for the Kubernetes pod overlay network. Only meaningful when pod_network_type = \"FLANNEL_OVERLAY\"."
  type        = string
  default     = "10.244.0.0/16"
}

variable "services_cidr" {
  description = "CIDR block for Kubernetes ClusterIP services."
  type        = string
  default     = "10.96.0.0/16"
}

# --- Load balancer subnets used by the Kubernetes cloud-controller-manager --

variable "service_lb_subnet_ids" {
  description = "Subnet OCID(s) OKE is allowed to provision LoadBalancer-type Service load balancers into."
  type        = list(string)
}

# --- Add-ons / options ---------------------------------------------------------

variable "enable_kubernetes_dashboard" {
  description = "Whether to enable the Kubernetes dashboard add-on."
  type        = bool
  default     = false
}

variable "enable_pod_security_policy" {
  description = "Whether to enable the pod security policy admission controller."
  type        = bool
  default     = false
}

# --- Node pool -----------------------------------------------------------------

variable "node_pool_name" {
  description = "Display name for the managed node pool."
  type        = string
}

variable "node_shape" {
  description = "Compute shape for worker nodes, e.g. \"VM.Standard.E4.Flex\"."
  type        = string
}

variable "node_shape_config" {
  description = "Only required for flex shapes. { ocpus = number, memory_in_gbs = number }. Leave null for fixed shapes."
  type = object({
    ocpus         = number
    memory_in_gbs = number
  })
  default = null
}

variable "node_image_id" {
  description = "OCID of the worker node image (an OKE-compatible platform image, looked up in the root config via a data source - do not hardcode)."
  type        = string
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size, in GB, for each worker node."
  type        = number
  default     = 50
}

variable "node_pool_size" {
  description = "Number of worker nodes in the pool."
  type        = number
  default     = 2
}

variable "node_placement_configs" {
  description = <<-EOT
    One entry per availability domain / subnet combination worker nodes should be
    spread across. Each object:
      availability_domain  AD name, e.g. "oXVt:ME-JEDDAH-1-AD-1"
      subnet_id             OCID of the worker node subnet in that AD
  EOT
  type = list(object({
    availability_domain = string
    subnet_id            = string
  }))
}

variable "ssh_public_key" {
  description = "SSH public key installed on worker nodes. Empty string disables SSH access."
  type        = string
  default     = ""
}

variable "node_pool_freeform_tags" {
  description = "Freeform tags applied to worker nodes themselves (separate from the pool/cluster tags, since OCI tracks them independently)."
  type        = map(string)
  default     = {}
}

variable "freeform_tags" {
  description = "Freeform tags applied to the cluster and node pool resources."
  type        = map(string)
  default     = {}
}
```

Two things are worth calling out in this variable set specifically. First, `cluster_type` and `pod_network_type` both use the *other* Terraform validation mechanism — the one that legitimately works inside a `variable` block, `validation { condition = contains([...], var.x) }` — because unlike the `log_group_id` case in Section 6.7, these really are single-variable constraints ("is this string one of the two allowed values?"), so the restriction that variable validations may only reference themselves is not a problem here at all. This is a useful contrast: know which validation mechanism a given rule needs before reaching for either one.

Second, `node_image_id` is a required string input with **no default** and a description that explicitly instructs the caller *not* to hardcode it, but to obtain it from a data source in the root configuration. This was a deliberate design choice, not an oversight: a worker node's compatible image ID is not a stable, portable value at all — it changes by region, by OCI's own image-refresh cadence, and by Kubernetes version, so baking any specific image OCID into the module (even as a "sensible default") would make the module silently wrong the next time OCI rotates their published images, or wrong immediately for anyone using it in a different region. Section 10 covers, at length, exactly how the correct value for this variable is computed in the root configuration.

### 7.4 Full source: `modules/oke/main.tf`

```hcl
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_id
  vcn_id             = var.vcn_id
  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  type               = var.cluster_type

  endpoint_config {
    is_public_ip_enabled = var.is_endpoint_public
    subnet_id             = var.endpoint_subnet_id
    nsg_ids                = var.endpoint_nsg_ids
  }

  # Only one of these two blocks is ever rendered - the condition picks which
  # CNI the control plane is told to expect.
  dynamic "cluster_pod_network_options" {
    for_each = var.pod_network_type == "VCN_NATIVE" ? [1] : []
    content {
      cni_type = "OCI_VCN_IP_NATIVE"
    }
  }

  dynamic "cluster_pod_network_options" {
    for_each = var.pod_network_type == "FLANNEL_OVERLAY" ? [1] : []
    content {
      cni_type = "FLANNEL_OVERLAY"
    }
  }

  options {
    service_lb_subnet_ids = var.service_lb_subnet_ids

    dynamic "add_ons" {
      for_each = [1]
      content {
        is_kubernetes_dashboard_enabled = var.enable_kubernetes_dashboard
        is_tiller_enabled               = false
      }
    }

    admission_controller_options {
      is_pod_security_policy_enabled = var.enable_pod_security_policy
    }

    kubernetes_network_config {
      pods_cidr     = var.pod_network_type == "FLANNEL_OVERLAY" ? var.pods_cidr : null
      services_cidr = var.services_cidr
    }
  }

  freeform_tags = var.freeform_tags
}

resource "oci_containerengine_node_pool" "this" {
  cluster_id         = oci_containerengine_cluster.this.id
  compartment_id     = var.compartment_id
  name               = var.node_pool_name
  kubernetes_version = var.kubernetes_version
  node_shape         = var.node_shape

  dynamic "node_shape_config" {
    for_each = var.node_shape_config != null ? [var.node_shape_config] : []
    content {
      ocpus         = node_shape_config.value.ocpus
      memory_in_gbs = node_shape_config.value.memory_in_gbs
    }
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = var.node_image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  node_config_details {
    size = var.node_pool_size

    dynamic "placement_configs" {
      for_each = var.node_placement_configs
      content {
        availability_domain = placement_configs.value.availability_domain
        subnet_id             = placement_configs.value.subnet_id
      }
    }

    dynamic "node_pool_pod_network_option_details" {
      for_each = var.pod_network_type == "VCN_NATIVE" ? [1] : []
      content {
        cni_type          = "OCI_VCN_IP_NATIVE"
        pod_subnet_ids    = var.pod_subnet_ids
        pod_nsg_ids       = var.pod_nsg_ids
        max_pods_per_node = var.max_pods_per_node
      }
    }

    dynamic "node_pool_pod_network_option_details" {
      for_each = var.pod_network_type == "FLANNEL_OVERLAY" ? [1] : []
      content {
        cni_type = "FLANNEL_OVERLAY"
      }
    }

    freeform_tags = var.node_pool_freeform_tags
  }

  # Omitting ssh_public_key entirely (rather than passing an empty string)
  # is what actually disables SSH access on OKE-managed nodes.
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : null

  initial_node_labels {
    key   = "name"
    value = var.node_pool_name
  }

  freeform_tags = var.freeform_tags
}
```

### 7.5 The mutually-exclusive dynamic block pattern

The most important pattern in this file — and arguably the clearest demonstration of "conditional expressions + dynamic blocks make a module actually configurable" anywhere in this week's work — is the pair of `dynamic "cluster_pod_network_options"` blocks:

```hcl
dynamic "cluster_pod_network_options" {
  for_each = var.pod_network_type == "VCN_NATIVE" ? [1] : []
  content { cni_type = "OCI_VCN_IP_NATIVE" }
}

dynamic "cluster_pod_network_options" {
  for_each = var.pod_network_type == "FLANNEL_OVERLAY" ? [1] : []
  content { cni_type = "FLANNEL_OVERLAY" }
}
```

Both blocks target the *same* nested block name (`cluster_pod_network_options`) on the same resource. Because their `for_each` conditions are the two branches of the same either/or variable, and `var.pod_network_type` is validated (Section 7.3) to only ever be one of exactly those two strings, precisely one of the two `for_each` expressions evaluates to `[1]` (a one-element list) and the other evaluates to `[]` (empty) on any given `terraform plan`. The net effect on the emitted resource is exactly one `cluster_pod_network_options {}` block, containing whichever `cni_type` corresponds to the caller's choice — never zero, never two. This same exact pattern is repeated for `node_pool_pod_network_option_details` inside the node pool's `node_config_details` block, because the node pool independently needs to be told the same CNI choice (OKE does not infer the node pool's CNI configuration from the cluster's).

The `dynamic "add_ons" { for_each = [1] ... }` block deserves a brief note too, since at first glance a `for_each` over a hardcoded one-element list looks pointless — and structurally, it *is* always rendered exactly once. It exists in this form (rather than as a plain, non-dynamic `add_ons {}` block) purely as a placeholder for exactly the kind of extension the `cluster_pod_network_options` pair demonstrates: if a future requirement needed to make the whole `add_ons` block itself conditional (e.g. "only configure add-ons at all on Enhanced clusters"), the scaffolding to do so is already in place and the change is a one-line edit to the `for_each` expression, not a restructuring of the block.

### 7.6 The `null`-coalescing conditional inside `kubernetes_network_config`

```hcl
kubernetes_network_config {
  pods_cidr     = var.pod_network_type == "FLANNEL_OVERLAY" ? var.pods_cidr : null
  services_cidr = var.services_cidr
}
```

This is a plain ternary conditional expression, not a dynamic block, and it exists because `pods_cidr` is only a meaningful concept for Flannel's overlay network — under VCN-native pod networking, pods draw real addresses from `var.pod_subnet_ids` instead, and supplying a `pods_cidr` value in that mode would be actively wrong (there is no overlay CIDR to declare). Rather than omitting the whole `kubernetes_network_config {}` block conditionally (which is unnecessary, since `services_cidr` is required in both modes), only the one field that's mode-specific is conditioned, explicitly set to `null` when it doesn't apply. This is the module's second recurring idiom, distinct from the dynamic-block idiom: *use a ternary, not a dynamic block, when the choice is between two scalar values for one existing argument, rather than between the presence/absence of a whole nested block.*

### 7.7 Why `ssh_public_key` is coalesced to `null`, not left as an empty string

```hcl
ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : null
```

This looks like a small detail but was deliberately tested and confirmed, because it is easy to get backwards: on OKE-managed node pools, it is specifically *omitting* the `ssh_public_key` argument (sending `null`, which Terraform's OCI provider treats as "argument absent" at the API level) that disables SSH access to worker nodes — sending an *empty string* is a different value to the API and does not reliably produce the same "no SSH access" outcome. The variable itself defaults to `""` (an empty string is a more ergonomic default for a caller to type in `.tfvars` than the literal word `null`), and this one-line conditional at the point of use is what translates "caller left it blank" into "actually tell the API this key is absent."

### 7.8 Full source: `modules/oke/outputs.tf`

```hcl
output "cluster_id" {
  description = "OCID of the OKE cluster."
  value       = oci_containerengine_cluster.this.id
}

output "cluster_kubernetes_version" {
  description = "Kubernetes version actually running on the control plane."
  value       = oci_containerengine_cluster.this.kubernetes_version
}

output "node_pool_id" {
  description = "OCID of the managed node pool."
  value       = oci_containerengine_node_pool.this.id
}

output "pod_network_type" {
  description = "The pod networking mode this cluster/node pool were created with."
  value       = var.pod_network_type
}
```

`cluster_id` is by far the most operationally important output — it's the value that `oci ce cluster create-kubeconfig` needs, and it's threaded through to the root's own `kubeconfig_command` output (Section 8) specifically so that the exact command to fetch a working kubeconfig for whatever cluster was just created is printed automatically at the end of every `terraform apply`, rather than needing to be looked up separately in the OCI Console.

### 7.9 A deliberate scope decision: IAM policies are *not* created by this module

OKE's control plane and its Kubernetes-native cloud-controller-manager/CSI-driver components need certain tenancy-level IAM policies to be allowed to do their job on the user's behalf — provisioning load balancers, attaching block volumes, managing node pool lifecycle events, and so on. This module deliberately does **not** create any `oci_identity_policy` resources. This is documented explicitly in the module's own `README.md` as a manual prerequisite, for two reasons worth stating plainly rather than leaving implicit:

First, IAM policy authoring is a tenancy-wide, security-sensitive concern that arguably does not belong inside a per-environment infrastructure module at all — a policy statement like *"allow service OKE to manage all-resources in compartment X"* is the kind of thing an organization typically wants reviewed and applied once, centrally, not re-evaluated and potentially re-applied every time someone calls this module for a new environment.

Second, and more concretely for this specific engagement: this internship's OCI tenancy has a known, pre-existing IAM permission gap (first observed in Week 2 with a Bastion service policy, and encountered again this week — see [Section 13.5](#135-problem-5--oci-cli-cannot-self-provision-an-api-signing-key)) where the intern's own user account does not have permission to manage certain IAM-adjacent resources. Attempting to have this Terraform module create policies it likely lacks permission to create would have made every `terraform apply` fail outright on policy creation, rather than succeeding on the actual infrastructure and merely requiring a manual, admin-performed policy step. Keeping policy management out of the module's scope meant the cluster and node pool could be (and were) built and verified successfully despite this tenancy limitation, with the IAM gap tracked and documented separately (a draft request is sitting in `docs/iam-policy-request-draft.md`, not yet sent) rather than blocking the entire lab.

---

## 8. Root Configuration — Composing the Modules

The root configuration is where the two generic modules stop being abstract and become one specific, real environment. This section walks through every root-level `.tf` file in the order Terraform effectively evaluates them (auth/provider → networking → compute), explaining what each piece does and, critically, *why* the specific values passed into the modules are what they are.

### 8.1 `provider.tf` — provider and version pinning

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "registry.terraform.io/oracle/oci"
      version = "~> 7.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}
```

Two details are worth flagging. First, the provider `source` is written as the fully-qualified `registry.terraform.io/oracle/oci` rather than the shorthand `oracle/oci`. This was changed deliberately after hitting registry-resolution ambiguity while validating the configuration in a network-restricted testing sandbox that could not reach the public Terraform registry at all — being fully explicit about the registry hostname removes one layer of implicit lookup and makes the exact source unambiguous to any reader, at zero functional cost on a machine that *can* reach the registry normally. Second, none of the five values passed into `provider "oci" {}` are literals — every one is a `var.*` reference back to `variables.tf`, and (see Section 8.6) four of those five variables are marked `sensitive = true`, so Terraform will redact them from console output and plan summaries.

### 8.2 `vcn.tf` — the networking backbone

```hcl
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_compartments" "mine" {
  compartment_id            = var.tenancy_ocid
  compartment_id_in_subtree = true
  name                      = "intern-02-ali-youssef-cmp"
  state                     = "ACTIVE"
}

locals {
  my_compartment_id = data.oci_identity_compartments.mine.compartments[0].id
}

resource "oci_core_vcn" "this" {
  compartment_id = local.my_compartment_id
  cidr_blocks    = [var.vcn_cidr_block]
  display_name   = "tf-lab-oke-vcn-AliYousef"
  dns_label      = var.vcn_dns_label
  freeform_tags  = var.freeform_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "tf-lab-oke-igw-AliYousef"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "tf-lab-oke-nat-AliYousef"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_service_gateway" "this" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "tf-lab-oke-sgw-AliYousef"
  freeform_tags  = var.freeform_tags

  services {
    service_id = data.oci_core_services.all_oci_services.services[0].id
  }
}

data "oci_core_services" "all_oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_logging_log_group" "this" {
  count = var.enable_flow_logs ? 1 : 0

  compartment_id = local.my_compartment_id
  display_name   = "tf-lab-oke-log-group-AliYousef"
  freeform_tags  = var.freeform_tags
}
```

The compartment ID is deliberately **never** typed as a literal anywhere in this codebase, even in the root config. `data.oci_identity_compartments.mine` looks it up by *name* (`intern-02-ali-youssef-cmp`) at plan/apply time, and `local.my_compartment_id` is the single place that ID is materialized, referenced everywhere else via that local rather than repeated as a raw OCID string. This has a real practical benefit beyond tidiness: it means the exact same configuration can be handed to a different intern, in a different compartment with a different name, by changing one string in one `data` block, rather than hunting through every `.tf` file for a hardcoded compartment OCID.

Three gateways are created unconditionally, because every subnet in this design needs at least one of them: the Internet Gateway serves the public subnets (the endpoint subnet when `is_endpoint_public = true`, and always the LB subnet), the NAT Gateway serves the private subnets (workers, pods, and the endpoint subnet when it's *not* public) so their outbound internet access (image pulls, OCI API calls) still works without any inbound exposure, and the Service Gateway gives the VCN a private path to Oracle's own service network (used, among other things, so that traffic to OCI services like Object Storage or the Container Registry never has to leave Oracle's backbone even from a fully private subnet).

The log group is the single shared destination every subnet's optional flow log writes into (four separate flow logs, one per subnet, all landing in this one log group) — and it, too, is conditional on the same `var.enable_flow_logs` toggle that ultimately reaches every Subnet module call, using the identical `count = var.enable_flow_logs ? 1 : 0` pattern explained in Section 6.6, so that turning flow logs off for the whole environment is a single boolean flip in `terraform.tfvars`, not four separate edits.

### 8.3 `subnets.tf` — four calls to the Subnet module

```hcl
locals {
  log_group_id = var.enable_flow_logs ? oci_logging_log_group.this[0].id : null
}
```

This one local is the connective tissue between `vcn.tf`'s conditional log group and every Subnet module call's `log_group_id` input — it resolves the same "does the log group even exist" question exactly once, at the root, rather than making every one of the four module calls repeat the same ternary. The four module calls themselves — `endpoint_subnet`, `workers_subnet`, `pods_subnet`, and `lb_subnet` — are each documented in full, rule by rule, in [Section 9](#9-networking-architecture-rule-by-rule), since that is where their *content* matters most; this section focuses on the calling *pattern* itself:

```hcl
module "endpoint_subnet" {
  source = "./modules/subnet"

  compartment_id      = local.my_compartment_id
  vcn_id                = oci_core_vcn.this.id
  subnet_display_name  = "tf-lab-oke-endpoint-subnet-AliYousef"
  subnet_cidr_block    = var.endpoint_subnet_cidr
  dns_label             = "okeendpoint"
  is_public             = var.is_endpoint_public

  route_table_display_name   = "tf-lab-oke-endpoint-rt-AliYousef"
  security_list_display_name = "tf-lab-oke-endpoint-sl-AliYousef"

  route_rules  = [ ... ]   # see Section 9
  ingress_rules = concat([ ... ], var.is_endpoint_public ? [ ... ] : [])   # see Section 9.2
  egress_rules  = [ ... ]

  enable_logs   = var.enable_flow_logs
  log_group_id  = local.log_group_id
  freeform_tags = var.freeform_tags
}
```

Every one of the four calls (`endpoint_subnet`, `workers_subnet`, `pods_subnet`, `lb_subnet`) follows this exact same shape — `source`, identity fields, a `route_table_display_name`/`security_list_display_name` pair, three rule lists, and the shared logging/tagging inputs — which is itself evidence that the module abstraction is doing its job: four structurally different subnets (one that's conditionally public, two that are always private, one that's always public) are all expressed as "the same kind of thing, configured differently," rather than as four separately-written resource blocks.

### 8.4 `oke.tf` — worker image lookup and the one call to the OKE module

`oke.tf` is covered separately and in full detail in [Section 10](#10-the-worker-node-image-selection-problem), because the worker-image-selection `locals` block at its top is, on its own, one of the most-iterated and most-instructive pieces of code from the entire week. The module call itself, at the bottom of the file, looks like this:

```hcl
module "oke" {
  source = "./modules/oke"

  compartment_id = local.my_compartment_id
  vcn_id          = oci_core_vcn.this.id

  cluster_name        = var.cluster_name
  kubernetes_version  = local.kubernetes_version
  cluster_type         = "BASIC_CLUSTER"

  endpoint_subnet_id = module.endpoint_subnet.subnet_id
  is_endpoint_public  = var.is_endpoint_public

  pod_network_type  = "VCN_NATIVE"
  pod_subnet_ids    = [module.pods_subnet.subnet_id]
  max_pods_per_node = var.max_pods_per_node

  service_lb_subnet_ids = [module.lb_subnet.subnet_id]

  node_pool_name = "${var.cluster_name}-workers"
  node_shape      = var.node_shape
  node_shape_config = {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_in_gbs
  }
  node_image_id            = local.node_image_id
  boot_volume_size_in_gbs = var.node_boot_volume_size_in_gbs
  node_pool_size           = var.node_pool_size

  node_placement_configs = [
    {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id             = module.workers_subnet.subnet_id
    }
  ]

  ssh_public_key = file(var.ssh_public_key_path)
  freeform_tags  = var.freeform_tags
}
```

Notice how every subnet OCID this module call needs comes from another module's *output*, not from a raw resource reference or a hardcoded ID: `module.endpoint_subnet.subnet_id`, `module.pods_subnet.subnet_id`, `module.lb_subnet.subnet_id`, `module.workers_subnet.subnet_id`. This is Terraform's implicit dependency graph doing real work — because `module.oke` references outputs of the four `module.*_subnet` calls, Terraform automatically knows the four subnets must be fully created *before* the cluster and node pool can be created, without a single explicit `depends_on` anywhere in this file. `pod_network_type` and `cluster_type` are passed as the literal strings `"VCN_NATIVE"` and `"BASIC_CLUSTER"` here rather than as separate root variables — a deliberate choice, not an inconsistency with Rule 1 from Section 5: those two values are *this specific lab's* fixed requirements (the assignment brief explicitly asked for VCN-native pod networking, and Enhanced clusters add a management fee not needed for a lab), not something this particular deployment ever needs to vary — but because the *module itself* still takes both as variables with full support for the alternative values, switching either one for a future, different deployment is a one-line change at the call site, not a module rewrite.

### 8.5 `outputs.tf` — including the debug outputs

```hcl
output "vcn_id" {
  description = "OCID of the Week 3 VCN."
  value       = oci_core_vcn.this.id
}

output "endpoint_subnet_id" { value = module.endpoint_subnet.subnet_id }
output "workers_subnet_id"  { value = module.workers_subnet.subnet_id }
output "pods_subnet_id"     { value = module.pods_subnet.subnet_id }
output "lb_subnet_id"       { value = module.lb_subnet.subnet_id }

output "cluster_id" {
  description = "OCID of the OKE cluster - needed for `oci ce cluster create-kubeconfig`."
  value       = module.oke.cluster_id
}

output "cluster_kubernetes_version" { value = module.oke.cluster_kubernetes_version }
output "node_pool_id"                { value = module.oke.node_pool_id }

output "kubeconfig_command" {
  description = "Command to fetch a kubeconfig for this cluster once it's up."
  value       = "oci ce cluster create-kubeconfig --cluster-id ${module.oke.cluster_id} --file $HOME/.kube/config --region ${var.region} --token-version 2.0.0"
}

output "debug_selected_node_image" {
  description = "Diagnostic only: which image name got picked for worker nodes."
  value       = sort(keys(local.oke_worker_images))[length(local.oke_worker_images) - 1]
}

output "debug_used_version_tagged_pool" {
  description = "Diagnostic only: true if a Kubernetes-version-matched image was found and used (expected), false if it fell back to newest-overall."
  value       = length(local.oke_version_tagged_images) > 0
}

output "debug_available_worker_images" {
  description = "Diagnostic only: every general-purpose x86 OL8 image name that was a candidate (GPU/aarch64 already excluded). If node pool creation still fails on image compatibility, check this list."
  value       = sort(keys(local.oke_worker_candidates))
}
```

The three `debug_*` outputs at the bottom are intentionally left in the final configuration, not stripped out once the underlying problem (Section 10) was fixed. This was a deliberate decision: they cost nothing at apply time (they're pure derivations of locals already being computed for the real `node_image_id` value), and they turn what would otherwise be an opaque "trust the module" moment into something independently auditable directly in the `terraform plan`/`apply` output — every future `apply` prints, in plain sight, exactly which image name was chosen, whether it was a Kubernetes-version-matched image (the expected/preferred case) or a fallback, and the full list of every image that was a legitimate candidate. Given how much troubleshooting time the image-selection logic consumed (Section 10), keeping this visibility rather than hiding it behind a successful apply was judged worth the minor output-list clutter.

### 8.6 `variables.tf` — every root input, and why the defaults are what they are

The root `variables.tf` groups its roughly twenty variables into four sections by comment header — provider auth, networking, OKE, and application block volume — mirroring the order they're consumed in. A handful of the default values deserve explicit justification beyond "seemed reasonable":

- `vcn_cidr_block = "10.0.0.0/16"` — a `/16` gives 65,536 addresses to split across four subnets, comfortably oversized for a lab, which matters specifically because VCN-native pod networking (Section 7.2) needs the Pods Subnet to be large enough for real per-pod IP consumption, not just per-node.
- `pods_subnet_cidr = "10.0.32.0/19"` — a `/19` (8,192 addresses) for the pods subnet specifically, deliberately much larger than the workers subnet's `/20` (4,096 addresses), because under VCN-native networking every *pod*, not just every node, consumes one of these addresses, and a two-node pool with `max_pods_per_node = 31` alone already implies needing headroom well past what a `/24` or `/25` would offer.
- `is_endpoint_public = true` — this is the one default that was **changed mid-week** from its original, more conservative value of `false`. The change is discussed at length in Section 12 and Section 13.5, but the short version: the assignment's lab explicitly expects `kubectl` to be run from the developer's own local machine, which sits entirely outside the VCN, so a private-only endpoint (reachable only via a bastion, VPN, or Cloud Shell) would have blocked the core lab exercise entirely. The variable's own description was updated alongside the default to document the tradeoff explicitly: *"Defaulted to true so kubectl works directly from a local machine outside the VCN for this lab - flip to false and access via Cloud Shell / a bastion / VPN instead for anything beyond a lab environment."* This is exactly the kind of decision that belongs in a variable's description, not just in a commit message or a chat log — anyone reading this file six months from now, with no memory of this week's troubleshooting, gets the reasoning for free.
- `cluster_name = "tf-lab-oke-AliYousef"` and the other `-AliYousef` suffixed display names throughout the codebase are a shared-tenancy convention, not a stylistic quirk: every intern in this program provisions resources into a common naming space, so every resource this week's configuration creates carries the author's name to make ownership unambiguous at a glance in the OCI Console.
- `app_block_volume_size_in_gbs = 50` — sized to match the `k8s/pvc.yaml` manifest's own `resources.requests.storage: 50Gi` (documented explicitly in that file's own comment, see Section 11.3), because the PVC size and this variable are not actually linked by any Terraform mechanism (the PVC is applied via `kubectl`, entirely outside Terraform's management) — keeping the two numbers in sync is a manual discipline, called out in both places precisely because Terraform cannot enforce it automatically here.

---

## 9. Networking Architecture, Rule by Rule

This section documents every security-list rule and every route-table rule passed into each of the four Subnet module calls, and the specific reason each one exists. Understanding this is what turns "the lab worked" into "I can explain exactly why every packet that needed to flow was allowed to, and nothing else was."

### 9.1 Endpoint Subnet (`10.0.0.0/28`) — hosts the Kubernetes API server endpoint

**Route table:** conditional on `var.is_endpoint_public`. When `true`, `0.0.0.0/0` routes to the Internet Gateway (so the API server's public IP can actually be reached from — and can reply to — the public internet). When `false`, `0.0.0.0/0` routes to the NAT Gateway instead (so the endpoint can still reach outbound OCI services and the internet for its own operational needs, but nothing outside the VCN can *initiate* a connection to it, since there's no route back in without an Internet Gateway path).

**Ingress rules** (three total, one of them conditional):

| Source | Protocol/Port | Always present? | Why |
|---|---|---|---|
| Workers Subnet CIDR (`10.0.16.0/20`) | TCP 6443 | Yes | Worker nodes (specifically, the `kubelet` and other control-plane-facing components on each node) need to reach the Kubernetes API server on its standard HTTPS port to register, report status, and receive scheduling instructions. |
| Workers Subnet CIDR | TCP 12250 | Yes | Port 12250 is OKE's own control-plane-to-node communication channel for cluster management operations distinct from the standard Kubernetes API port — required specifically by OKE's managed control plane implementation, not a vanilla open-source Kubernetes requirement. |
| `0.0.0.0/0` | TCP 6443 | **Only when `is_endpoint_public = true`** | This is the rule that lets `kubectl` running on the developer's own laptop, entirely outside the VCN, reach the API server at all. It is expressed with the `concat()` + conditional-empty-list pattern described in 9.2, rather than a `dynamic` block, because the *module* takes a plain list for `ingress_rules` — the conditional logic for "should this particular rule exist" lives at the *call site* in `subnets.tf`, one layer up from where the module's own `dynamic` block renders whatever list of rules it's handed. |

**Egress rules** (two): to the Workers Subnet CIDR on TCP 10250 (the control plane reaching back out to each node's `kubelet` port — the reverse direction of the first ingress rule, since Kubernetes API-to-kubelet traffic, e.g. for `kubectl exec`/`kubectl logs`, flows control-plane → node), and to `0.0.0.0/0` on TCP 443 (general outbound HTTPS, needed for the control plane's own communication with other OCI services).

### 9.2 The `concat()` conditional-rule pattern, in full

```hcl
ingress_rules = concat(
  [
    { source = var.workers_subnet_cidr, protocol = "6", description = "Worker nodes -> Kubernetes API",              tcp_options = { min = 6443,  max = 6443  } },
    { source = var.workers_subnet_cidr, protocol = "6", description = "Worker nodes -> OKE control plane services",  tcp_options = { min = 12250, max = 12250 } }
  ],
  var.is_endpoint_public ? [
    { source = "0.0.0.0/0", protocol = "6", description = "External kubectl access to the Kubernetes API (endpoint is public - consider narrowing this to a known IP range for anything beyond a lab)", tcp_options = { min = 6443, max = 6443 } }
  ] : []
)
```

This is worth dwelling on because it's a genuinely different technique from the module-internal `dynamic` blocks in Sections 6 and 7, solving a structurally different problem. Inside the Subnet module, `ingress_rules` is *already a variable* — the module doesn't know or care why the list has the length it has, it just renders one `dynamic` sub-block per element. The question of *whether a given rule should be in that list in the first place* is a decision that belongs to the caller, at the point where the list is being constructed — and `concat()` of a static list with a conditionally-empty list is the idiomatic way to express "these two rules always apply, and this third rule applies only if this condition holds" without needing an `if`/`else` statement (which HCL, being a declarative configuration language rather than an imperative one, doesn't have in that form at all — every "if" in Terraform is either a ternary expression producing a value, or a `for_each`/`count` producing zero-or-more instances of something).

The rule's own `description` field doubles as an inline warning: *"consider narrowing this to a known IP range for anything beyond a lab"* — flagging, directly in the infrastructure-as-code itself (not just in this document), that allowing `0.0.0.0/0` access to the Kubernetes API server is an acceptable and even necessary tradeoff for a training lab where the goal is "kubectl must work from my laptop with minimal setup friction," but would be a real security concern in any less disposable environment, where the correct fix is narrowing that source CIDR to a known office/VPN IP range, or removing the public endpoint entirely in favor of a bastion. This tradeoff, and why it was accepted for this specific week's lab, is discussed further in [Section 14](#14-security-considerations).

### 9.3 Workers Subnet (`10.0.16.0/20`) — hosts worker node VNICs

**Route table:** unconditionally routes `0.0.0.0/0` to the NAT Gateway — worker nodes are never given public IPs (`is_public = false` on this module call), so all their outbound traffic (pulling container images, calling back to OCI services) goes out through NAT, and nothing can initiate an inbound connection to a worker node from outside the VCN at all.

**Ingress rules** (three): from the Endpoint Subnet CIDR on TCP 10250 (the control plane reaching each node's kubelet — the destination side of the endpoint subnet's egress rule in 9.1), from the Pods Subnet CIDR on all protocols (pod-to-node traffic under VCN-native networking — pods frequently need to reach services running as `hostNetwork` or `NodePort` on the node they're not scheduled on, and node-level components like `kube-proxy` need unrestricted reachability from pod IPs), and from the Workers Subnet CIDR itself on all protocols (worker-to-worker traffic — inter-node communication for things like `kube-proxy`'s own service-routing mesh and any pod-to-pod traffic that happens to route through node IPs rather than pod IPs directly).

**Egress rules** (one, broad): `0.0.0.0/0`, all protocols. This is intentionally permissive rather than narrowly enumerated, with the rule's own description explaining why: *"Allow all outbound (image pulls, OCI API calls, etc.)"*. Worker nodes need essentially unrestricted outbound reachability to function at all — pulling arbitrary container images from arbitrary registries, resolving DNS, calling the OCI API for CSI/CCM operations — and enumerating every specific destination a Kubernetes worker node might legitimately need to reach outbound is neither practical nor meaningfully more secure than allowing broad egress and relying on the *ingress* rules (which are narrowly scoped throughout this design) to be the actual security boundary. This mirrors standard OKE reference-architecture guidance.

### 9.4 Pods Subnet (`10.0.32.0/19`) — hosts pod VNICs under VCN-native networking

**Route table:** `0.0.0.0/0` to the NAT Gateway, same reasoning as the workers subnet — pods need outbound reachability, never unsolicited inbound from outside the VCN.

**Ingress rules** (one, deliberately broad): from the whole VCN CIDR (`var.vcn_cidr_block`, i.e. `10.0.0.0/16`), all protocols. The rule's own description spells out why a single broad rule was chosen over several narrow ones: *"Allow all traffic from within the VCN (pod-to-pod, worker-to-pod, LB health checks)"*. Pod-to-pod communication in Kubernetes is inherently unpredictable at the security-list level — any pod may need to reach any other pod on any port, depending entirely on what the *application* running inside them does, which is knowledge this infrastructure layer simply doesn't have and shouldn't try to guess at. The Kubernetes-native way to restrict pod-to-pod traffic more granularly is `NetworkPolicy` objects, applied inside the cluster by whoever owns the workloads — not VCN security lists, which operate at a coarser granularity than Kubernetes' own pod-identity-aware networking model. This is also the rule that permits the OCI Load Balancer's health-check probes (which originate from the LB subnet, itself inside the same VCN CIDR) to reach pod IPs directly, since OKE's cloud-controller-manager wires LoadBalancer-type Services directly to pod IPs rather than routing exclusively through node ports.

**Egress rules** (one, broad): `0.0.0.0/0`, all protocols — same "pods need to talk to whatever the application requires, that's not this layer's job to constrain" reasoning as the ingress rule.

### 9.5 LB Subnet (`10.0.8.0/24`) — hosts the OCI Load Balancer

**Route table:** `0.0.0.0/0` to the Internet Gateway, unconditionally — this subnet is always meant to be reachable from the public internet, since its entire purpose is hosting whatever Load Balancer(s) a `type: LoadBalancer` Kubernetes Service causes OKE to provision.

**Ingress rules** (two): `0.0.0.0/0` on TCP 80 and TCP 443. Standard public HTTP/HTTPS. This lab's actual `service.yaml` only exposes port 80 (Section 11.5), but the security list allows 443 as well, anticipating that a real deployment of this same pattern would very likely want to add TLS termination at the load balancer.

**Egress rules** (one): to the Workers Subnet CIDR, all protocols. This is the rule that lets the Load Balancer actually forward traffic — and, just as importantly, perform its own health checks — to the worker nodes' `NodePort` (or, for VCN-native pod networking, directly to pod IPs, which are addresses assigned out of the Pods Subnet, itself reachable *through* the Workers Subnet's own routing scope in this topology) that backs the Kubernetes Service. Scoped specifically to the workers CIDR rather than left broad, since the Load Balancer's only legitimate egress target in this whole design is the cluster it's fronting, not the general internet.

### 9.6 Summary: the security posture in one sentence per subnet

- **Endpoint Subnet:** reachable on 6443 from worker nodes always, and from the entire internet only when the lab's `is_endpoint_public` toggle is on — with that tradeoff explicitly documented as lab-appropriate, not production-appropriate, in three separate places (the variable description, the rule's own description, and this document).
- **Workers Subnet:** reachable only from the control plane, from pods, and from other workers — never from the public internet.
- **Pods Subnet:** reachable only from elsewhere inside the same VCN — never from the public internet — with fine-grained pod-to-pod policy intentionally left to Kubernetes `NetworkPolicy`, not VCN security lists.
- **LB Subnet:** the one subnet genuinely designed to be reachable from the public internet, on exactly the two ports (80/443) a public-facing web workload needs, and nothing else.

---

## 10. The Worker Node Image Selection Problem

Nothing else in this week's Terraform work took as many iterations, or taught as much about how OKE's image ecosystem actually works, as correctly automating the choice of which OCI platform image a managed node pool's worker nodes should boot from. This section documents all three iterations in full, because the false starts are at least as instructive as the final working version.

### 10.1 Why this is even a problem — OKE worker images are not ordinary platform images

A managed OKE node pool's `node_source_details.image_id` must reference an OCI image that is specifically built and validated to work as an OKE worker node — it needs the right kernel, the right container runtime (CRI-O, as it turns out — see [Section 13.7](#137-problem-7--cri-o-short-name-mode-is-enforcing)), and OKE-specific bootstrap tooling baked in. Oracle publishes a whole family of these images, refreshed regularly, with names that encode a lot of structured information, for example:

```
Oracle-Linux-8.10-2026.06.15-0-OKE-1.36.1-1505
```

Reading left to right: the base OS (`Oracle-Linux-8.10`), the image build date (`2026.06.15-0`), that it's specifically an OKE image (`OKE`), the Kubernetes version it's validated against (`1.36.1`), and an internal build number (`1505`). Not every image in the catalog follows this exact pattern, though — OCI has also, more recently, started shipping **untagged, rolling** images with no `-OKE-<version>-<build>` suffix at all, for example `Oracle-Linux-8.10-2026.08.14-0`, which are also valid OKE worker images but carry no explicit Kubernetes-version marker in their name. And critically, the same base OS/date can have **multiple variants** that are *not* interchangeable with a general-purpose x86 compute shape: images with `aarch64` in the name are built for ARM/Ampere shapes (like `VM.Standard.A1.Flex`), and images with `GPU` in the name (e.g. `Gen2-GPU`, `Gen2-AMD-GPU`) are built specifically for GPU-attached shapes. Picking any image from either of those variant families for this lab's plain `VM.Standard.E4.Flex` shape produces a hard OCI API rejection at node pool creation time.

### 10.2 Iteration 1 — the generic image data source (failed: empty result)

The first attempt used the general-purpose OCI platform-image catalog data source, filtered by operating system, OS version, and compute shape, with an additional regex filter on the display name to try to narrow in on OKE-specific images:

```hcl
data "oci_core_images" "oke_worker" {
  compartment_id           = local.my_compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.node_shape
  # (plus a display_name regex filter, since inspection)
}
```

This failed with `images is empty list of object` — the generic platform-image catalog, filtered this way, simply did not surface any OKE-tagged images at all in this region/compartment combination. The generic image catalog is meant for general compute-instance provisioning, and its filtering semantics (particularly how it correlates "compatible with this shape" against image metadata) don't reliably line up with what OKE itself considers a valid worker image, even when both are nominally describing the same underlying OCI image resources.

### 10.3 Iteration 2 — the purpose-built node pool option data source (failed: wrong architecture picked)

The fix for the empty-result problem was switching to a data source built specifically for this purpose — `oci_containerengine_node_pool_option`, part of the Container Engine service's own API surface, which returns exactly the set of images (and shapes, and Kubernetes versions) OKE itself will actually accept for a node pool, rather than trying to reverse-engineer that set from the generic compute-image catalog:

```hcl
data "oci_containerengine_node_pool_option" "this" {
  node_pool_option_id = "all"
  compartment_id       = local.my_compartment_id
}

locals {
  oke_ol8_images = {
    for s in data.oci_containerengine_node_pool_option.this.sources :
    s.source_name => s.image_id
    if can(regex("^Oracle-Linux-8", s.source_name)) && !can(regex("aarch64", s.source_name))
  }
  node_image_id = local.oke_ol8_images[
    sort(keys(local.oke_ol8_images))[length(local.oke_ol8_images) - 1]
  ]
}
```

This correctly returned a real, non-empty set of OKE-compatible images, and successfully excluded the ARM (`aarch64`) variants — but the node pool creation still failed, with `Invalid nodeShape: Node shape and image are not compatible`. The `for` expression's `if` filter excluded ARM images but not GPU images, and lexical (alphabetical) sorting of image names does not reliably put "general purpose" images last — a name containing `Gen2-GPU` can sort *after* a plain Oracle-Linux image name purely as a string-comparison artifact, with no relationship to which one is actually newest or actually compatible with a plain compute shape. The "pick the alphabetically-last key" heuristic picked a GPU-only image, which is exactly as incompatible with `VM.Standard.E4.Flex` as an ARM image would have been, for the identical underlying reason (shape/image architecture mismatch), just a different specific mismatch.

### 10.4 Iteration 3 — the final, verified-correct selection logic

The final version fixes both problems at once: it excludes *both* disqualifying variant families explicitly, and it stops relying on "alphabetically last = best" as the primary selection strategy, instead **preferring an image explicitly tagged for the cluster's own Kubernetes version**, falling back to "newest overall" only if no version-tagged image exists at all:

```hcl
locals {
  # Oracle Linux 8 worker images, name -> OCID, general-purpose x86 only.
  # OCI's OKE image catalog also publishes variants this shape can't use:
  #   - "aarch64"  - Ampere/ARM builds, only for VM.Standard.A1.Flex etc.
  #   - "GPU"      - Gen2-GPU / Gen2-AMD-GPU builds, only for GPU shapes.
  # Both caused "Node shape and image are not compatible" against the
  # general-purpose x86 VM.Standard.E4.Flex shape, so both are excluded here.
  # If node_shape is ever changed to an Ampere or GPU shape, flip the
  # matching exclusion to a requirement instead.
  oke_worker_candidates = {
    for s in data.oci_containerengine_node_pool_option.this.sources :
    s.source_name => s.image_id
    if can(regex("^Oracle-Linux-8", s.source_name))
      && !can(regex("aarch64", s.source_name))
      && !can(regex("GPU", s.source_name))
  }

  # Prefer an image explicitly built for this cluster's Kubernetes version -
  # name contains "-OKE-<version>-", e.g. "...-OKE-1.36.1-1505" for v1.36.1 -
  # since that's the exact combination OCI validates together. Fall back to
  # the newest candidate overall if no version-tagged image exists (OCI has
  # also been shipping undated/untagged rolling images more recently).
  oke_version_tagged_images = {
    for name, id in local.oke_worker_candidates : name => id
    if can(regex("-OKE-${trimprefix(local.kubernetes_version, "v")}-", name))
  }

  oke_worker_images = length(local.oke_version_tagged_images) > 0 ? local.oke_version_tagged_images : local.oke_worker_candidates

  # Names sort lexically the same as chronologically (build date is embedded),
  # so the last element is the newest - relevant only for the fallback case,
  # since the version-tagged set above is expected to contain one match.
  node_image_id = local.oke_worker_images[
    sort(keys(local.oke_worker_images))[length(local.oke_worker_images) - 1]
  ]
}
```

This is a genuinely layered piece of conditional logic and worth walking through slowly:

1. `oke_worker_candidates` is a `for` expression over every entry the node-pool-option data source returned, with an `if` clause combining **three** conditions with `&&`: the name must start with `Oracle-Linux-8` (excludes Oracle Linux 7/9 and any non-Oracle-Linux images entirely), must *not* contain `aarch64` (excludes ARM), and must *not* contain `GPU` (excludes the two GPU variant families). `can(regex(...))` is used rather than a plain regex match specifically so that a name that doesn't match a given pattern produces `false` cleanly rather than an error — `can()` catches the "no match" case from `regex()` (which, called directly, would raise an error on no match, since `regex()` is designed for extracting values, not testing for presence) and turns it into the boolean the `if` filter needs.
2. `oke_version_tagged_images` is a *second* `for` expression, this time filtering `oke_worker_candidates` down further to only images whose name contains the literal substring `-OKE-1.36.1-` (with the cluster's actual Kubernetes version interpolated in via `trimprefix(local.kubernetes_version, "v")`, since the version data source returns a `v`-prefixed string like `v1.36.1` but image names use the bare `1.36.1`).
3. `oke_worker_images` is the actual either/or decision, expressed as a single ternary: use the version-tagged set if it's non-empty, otherwise fall back to the full candidate set. `length(...) > 0` is the standard Terraform idiom for "is this collection non-empty," since HCL has no direct boolean-truthiness coercion for collections.
4. `node_image_id` takes whichever of those two sets won, sorts its keys, and picks the last one — which is safe specifically *because* of how OCI image names are constructed: the embedded date (`2026.06.15`) sorts lexically identically to how it sorts chronologically (a nice property of `YYYY.MM.DD` formatting), so "alphabetically last" and "most recently built" coincide. This step only really matters for the fallback branch, since the version-tagged branch is expected to contain exactly one match in the overwhelming majority of cases — but leaving the same "pick the last one" logic in both branches keeps the expression uniform rather than needing a separate code path for "exactly one candidate" vs. "many candidates."

### 10.5 Verification before shipping the fix

Given how many times the first two iterations had already failed, the third iteration was not sent straight to the developer's machine on faith. It was verified independently first, against the *actual* candidate image list the developer's own prior failed `terraform plan` had printed via the `debug_available_worker_images` output (Section 8.5) — a standalone Python script was written that reimplemented the exact same filtering/sorting logic against that real, pasted list of twenty candidate image names, and confirmed it selected `Oracle-Linux-8.10-2026.06.15-0-OKE-1.36.1-1505` — a genuinely version-tagged, non-ARM, non-GPU image. Only after that independent confirmation was the updated `oke.tf` sent back to the developer's machine for a real `terraform plan`/`apply`. That apply succeeded — **"Apply complete! Resources: 1 added, 0 changed, 0 destroyed"** for the node pool specifically — and the same logic, unchanged, was used successfully again on the second, independent full rebuild later in the week (Section 12), which is itself further evidence the logic generalizes correctly rather than having been a one-off lucky match against that specific list.

---

## 11. Kubernetes Manifests — Full Deep Dive

Terraform's job ends once the OKE cluster and its node pool exist and are `Active`. Everything that runs *inside* that cluster — the namespace, the storage class, the persistent volume claim, the application deployment, and the load balancer service — is defined separately, as plain Kubernetes YAML manifests, and applied with `kubectl apply -f`. This is a deliberate and fairly standard split of responsibility: Terraform owns the cloud infrastructure (the "hardware" — network, compute, the cluster's control plane and worker nodes), and Kubernetes manifests own the workloads that run on top of that infrastructure (the "software" — pods, services, storage claims). Mixing the two — for example, trying to manage Kubernetes Deployments via Terraform's `kubernetes` provider — is possible but was intentionally avoided here, both because the lab brief frames this as a two-tool exercise (Terraform for infra, kubectl/YAML for the app) and because keeping the two layers in genuinely separate files with separate apply commands makes it much easier to reason about what changes when: a `terraform apply` never touches a running pod, and a `kubectl apply` never touches the VCN or the node pool.

All five manifests live in `k8s/` alongside the Terraform root module, and are applied in a specific dependency order (namespace first, since everything else references it; storage class and PVC before the deployment, since the deployment's pod spec references the PVC by name; deployment and service last). The full sequence used on both builds was:

```
kubectl apply -f k8s\namespace.yaml
kubectl apply -f k8s\storageclass.yaml
kubectl apply -f k8s\pvc.yaml
kubectl apply -f k8s\deployment.yaml
kubectl apply -f k8s\service.yaml
```

Each manifest is examined below in the order it's applied.

### 11.1 `namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: week3-demo
```

This is the simplest possible Kubernetes object — a bare `Namespace` with nothing but a name. Every other manifest in this lab sets `namespace: week3-demo` in its own `metadata`, which places that object inside this namespace rather than the cluster's `default` namespace. Using a dedicated namespace rather than dumping everything into `default` mirrors the same "keep things logically separated and named on purpose" philosophy applied throughout the Terraform side of this lab (compartments, explicit display names, and so on). Practically, it also makes teardown cleaner: `kubectl delete namespace week3-demo` would cascade-delete every namespaced object inside it in one shot (the Deployment, the Service, the PVC — though in this lab's actual teardown, Section 12.3, each object was deleted individually and explicitly instead, specifically so the LoadBalancer Service's deletion — and the corresponding OCI Load Balancer teardown it triggers — could be watched and confirmed before moving on, rather than trusting a single cascading delete to get there silently).

A `Namespace` object is itself non-namespaced (it doesn't belong to a namespace — namespaces are cluster-scoped), which is why it has no `namespace:` field in its own `metadata`, unlike every other manifest that follows.

### 11.2 `storageclass.yaml`

```yaml
# Explicit StorageClass rather than relying on OKE's pre-installed "oci-bv"
# default, so the performance tier and reclaim behavior are visible and
# deliberate rather than implicit.
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: week3-oci-bv
provisioner: blockvolume.csi.oraclecloud.com
parameters:
  # 10 VPUs/GB = the "Balanced" block volume performance tier.
  vpusPerGB: "10"
  attachment-type: paravirtualized
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

A `StorageClass` in Kubernetes is not itself a piece of storage — it's a *template* that tells Kubernetes how to dynamically provision storage when something (a PVC) asks for it, and which underlying storage backend/driver to use. OKE clusters come with a default StorageClass named `oci-bv` already installed, backed by the same CSI driver used here, and it would technically have been enough to just reference `oci-bv` directly in the PVC and skip this file entirely. A custom StorageClass was created instead so that every parameter affecting cost and performance is visible in this repository rather than inherited silently from whatever OKE happens to ship as its default:

- **`provisioner: blockvolume.csi.oraclecloud.com`** — this is the OCI Block Volume CSI (Container Storage Interface) driver, pre-installed and running on every OKE cluster. When a PVC requests storage via this StorageClass, this is the driver that actually calls the OCI Block Volume API to create a real block volume and attach it to whichever node the pod lands on.
- **`vpusPerGB: "10"`** — VPUs (Volume Performance Units) per gigabyte is OCI's block volume performance-tier knob. `10` VPUs/GB is the "Balanced" tier — a reasonable middle ground between the cheaper "Lower Cost" tier (`0`–`2` VPUs/GB, lower IOPS) and the pricier "Higher Performance" tiers (`20`+ VPUs/GB). For a demo app serving a static HTML file, IOPS is irrelevant, but naming the tier explicitly documents the choice rather than leaving it to whatever OKE's built-in default happens to be.
- **`attachment-type: paravirtualized`** — block volumes on OCI can attach to a compute instance either as `iscsi` (the volume is presented over an iSCSI connection, needs in-guest iSCSI tooling) or `paravirtualized` (the hypervisor handles the attachment, appears to the guest as a normal block device with no extra in-guest configuration). `paravirtualized` is simpler and is what OKE's own default StorageClass uses, so it was kept here for consistency and because there was no reason in this lab to need iSCSI's slightly different performance/isolation characteristics.
- **`reclaimPolicy: Delete`** — when the PVC that's using a volume provisioned by this class is deleted, the underlying OCI block volume is deleted along with it (rather than `Retain`, which would leave the actual cloud volume behind, orphaned, requiring manual cleanup). `Delete` was the correct choice for a disposable lab environment where the whole point of the final teardown step (Section 12.3) is leaving nothing billable behind; `Retain` would be the safer choice for a StorageClass backing genuinely important production data, where an accidental PVC deletion should not also destroy the underlying data irreversibly.
- **`volumeBindingMode: WaitForFirstConsumer`** — this controls *when* the actual cloud volume gets provisioned. The alternative, `Immediate`, provisions the volume the instant the PVC is created, before Kubernetes knows which node will actually use it — which is a real problem for zonal/AD-scoped storage like OCI block volumes, since the volume could end up created in an availability domain that doesn't match wherever the pod eventually gets scheduled, making it unusable. `WaitForFirstConsumer` instead delays provisioning until a pod that references the PVC is actually scheduled to a specific node, so the CSI driver can provision the volume in the same availability domain as that node, guaranteeing they're compatible. This is standard practice for any AD/zone-scoped block storage on any cloud, not something specific to this lab.
- **`allowVolumeExpansion: true`** — permits increasing the PVC's requested storage size later (by editing the PVC's `spec.resources.requests.storage` upward) without needing to delete and recreate it. Not exercised in this lab, but a low-cost, sensible default to leave enabled.

### 11.3 `pvc.yaml`

```yaml
# Size intentionally matches var.app_block_volume_size_in_gbs (default 50)
# in ../variables.tf - keep the two in sync if either changes.
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-app-data
  namespace: week3-demo
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: week3-oci-bv
  resources:
    requests:
      storage: 50Gi
```

A `PersistentVolumeClaim` (PVC) is a *request* for storage, distinct from the actual storage itself (a `PersistentVolume`, or PV). The application's Deployment never talks to OCI's Block Volume API directly and never references a PV directly either — it references this PVC by name (`demo-app-data`), and Kubernetes, via the StorageClass's provisioner, handles turning that request into an actual OCI block volume and a matching PV object behind the scenes. This indirection is the entire point of the PVC/PV/StorageClass system: application manifests stay portable and cloud-agnostic (the same Deployment YAML would work unmodified against a PVC backed by AWS EBS, GCP Persistent Disk, or an on-prem storage system, as long as the StorageClass name matched), and the cloud-specific plumbing lives entirely in the StorageClass.

- **`accessModes: [ReadWriteOnce]`** — `ReadWriteOnce` (RWO) means the underlying volume can be mounted read-write by exactly one node at a time (not one *pod* — one *node*; multiple pods on the same node can technically share an RWO mount, which is precisely the mechanism behind the "shared PVC" behavior discussed in Section 13.9). OCI block volumes are fundamentally RWO-only devices — this isn't a Kubernetes-level policy choice so much as a reflection of what the underlying storage technology actually supports. The alternative access modes, `ReadWriteMany` (multiple nodes, read-write) and `ReadOnlyMany`, require a genuinely different, typically network-filesystem-backed storage technology (like OCI File Storage Service via the FSS CSI driver, or NFS), not block volumes — which is exactly why this constraint mattered so directly for the Deployment's `strategy: type: Recreate` fix in Section 11.4 and Section 13.8: an RWO volume categorically cannot be attached to a second node while still attached to the first, no matter what Kubernetes rollout strategy is used.
- **`storageClassName: week3-oci-bv`** — ties this PVC to the custom StorageClass from Section 11.2, so its provisioning inherits that class's performance tier, attachment type, reclaim policy, and binding mode.
- **`resources.requests.storage: 50Gi`** — the requested size. The comment in the file itself flags that this value is intentionally kept in sync with `var.app_block_volume_size_in_gbs` in the Terraform root module's `variables.tf` (default `50`) — not because the two are mechanically linked (they aren't; this PVC's volume is entirely separate from anything Terraform provisions, since Terraform in this lab never creates a block volume directly, only the cluster and node pool that make block-volume provisioning possible), but because that Terraform variable exists specifically to document, in one place, "how big is the demo app's data volume supposed to be" as a piece of lab-wide configuration, and letting the actual PVC size drift from that documented value would make the Terraform variable actively misleading.

### 11.4 `deployment.yaml`

This is the most complex manifest in the lab and went through two rounds of real debugging (Sections 13.7 and 13.8) before reaching its final form. The full, final, working version:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: week3-demo
  labels:
    app: demo-app
spec:
  # Kept at 1: the PVC below is ReadWriteOnce (a block volume can only be
  # attached to a single node at a time), so a second replica would risk
  # landing on a different node and getting stuck unable to attach the
  # same volume. Scale the *stateless* part of an app like this behind a
  # separate Deployment without the volume if more replicas are needed.
  replicas: 1
  # Recreate rather than the default RollingUpdate: with a single replica on
  # a ReadWriteOnce block volume, RollingUpdate tries to bring the new pod up
  # (possibly on a different node) before killing the old one, but the volume
  # can only attach to one node at a time - that's a deadlock (hit this live:
  # new pod stuck at Init:0/1 waiting on the volume, old pod never torn down
  # because the rollout is waiting on the new pod to go Ready first). Recreate
  # kills the old pod first, so the volume frees up before the new one needs it.
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      # initContainer writes a page into the PVC-backed volume so a browser
      # hitting the load balancer can see, in plain text, which pod/node
      # served the request and that the block volume is actually mounted
      # and writable - proof for the lab writeup, not just "the pod is Running".
      # Fully-qualified image refs (registry included) rather than short names
      # ("nginx:1.27-alpine") - this OKE node image runs CRI-O with short-name
      # mode set to "enforcing", which refuses to guess a registry for an
      # unqualified name and fails with "short name mode is enforcing, but
      # image name ... returns ambiguous list". busybox worked anyway because
      # it happens to already be cached locally on OKE nodes; nginx isn't, so
      # it hit the enforcement wall. Fully-qualifying both sidesteps it.
      initContainers:
        - name: write-index
          image: docker.io/library/busybox:1.36
          command:
            - sh
            - -c
            - |
              cat <<EOF > /data/index.html
              <html>
                <head><title>Ejada Week 3 - OKE Demo</title></head>
                <body style="font-family: sans-serif;">
                  <h1>Ejada Internship - Week 3 OKE Lab</h1>
                  <p>Served by pod: $(hostname)</p>
                  <p>Node: $NODE_NAME</p>
                  <p>Rendered at container start: $(date -u)</p>
                  <p>This page is being read from a PersistentVolumeClaim backed
                     by an OCI block volume, attached via the CSI driver.</p>
                </body>
              </html>
              EOF
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          volumeMounts:
            - name: data
              mountPath: /data
      containers:
        - name: nginx
          image: docker.io/library/nginx:1.27-alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /index.html
              port: 80
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /index.html
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: demo-app-data
```

Working through this field by field:

**`spec.replicas: 1`.** Deliberately not scaled up, and the comment explains exactly why: the RWO constraint on the PVC means only one node can ever hold the volume at a time, so a second replica pod would either need to land on that same node (defeating much of the point of having multiple replicas — no resilience against that node failing) or fail to start entirely if scheduled elsewhere. The comment also notes the standard real-world pattern for this situation: split a stateful, single-instance-by-necessity piece (whatever actually needs to read/write the shared volume) from a stateless, horizontally-scalable piece (if there were, say, a separate read-only frontend that didn't need direct volume access) — not needed for a lab this simple, but worth documenting as the "next step" a real system would take.

**`spec.strategy.type: Recreate`.** Covered in exhaustive detail in Section 13.8, but summarized here: Kubernetes Deployments default to `RollingUpdate`, which — to achieve zero-downtime rollouts — brings up new pods *before* tearing down old ones. That default is actively wrong for a single-replica pod bound to an RWO volume, because the new pod cannot start (specifically, its initContainer cannot even begin) until the volume detaches from the node the old pod is still running on, and the old pod won't be torn down until the rollout considers the new pod healthy — a circular wait that never resolves on its own. `Recreate` inverts the order: terminate all existing pods first, then create the replacement, which matches what the storage constraint actually requires. The cost is a brief window of real downtime during any future rollout (the service is unreachable between the old pod's termination and the new pod's readiness) — an acceptable, explicitly-documented tradeoff for a demo app, and one that was only discovered by hitting the deadlock live during testing (see Section 13.8) rather than anticipated up front.

**`spec.template.spec.initContainers`.** An initContainer is a container that runs to completion *before* any of the pod's regular (`containers:`) entries start, and if it fails, the regular containers never start at all. This lab uses one to write a small proof-of-life HTML page directly onto the shared PVC before nginx ever serves anything from it, using a here-doc (`cat <<EOF ... EOF`) shell script executed via `sh -c`. The generated page embeds three pieces of live, runtime information: `$(hostname)` (the pod's own hostname, which Kubernetes sets to the pod name by default — this is what lets a browser hitting the app "see" exactly which pod served the page), `$NODE_NAME` (injected via the Kubernetes Downward API — see below), and `$(date -u)` (the UTC timestamp the initContainer actually ran, i.e., when this particular pod started). This whole mechanism exists purely as visible, undeniable proof for the lab writeup that the block volume is genuinely mounted and writable and that the page being served is coming from it — a plain "the pod shows `Running`" status alone wouldn't demonstrate that the storage layer is actually working end-to-end.

**`env: NODE_NAME` via `fieldRef: fieldPath: spec.nodeName`.** This is the Kubernetes Downward API — a mechanism for exposing metadata about the pod itself (or, as here, about the node it landed on) to a container as an environment variable, without that container needing any special Kubernetes-API access or credentials. `spec.nodeName` is populated by the scheduler once it decides which node the pod will run on, and this `fieldRef` simply copies that value into the `NODE_NAME` environment variable inside the initContainer at start time.

**The image references and CRI-O short-name enforcement.** Both `busybox:1.36` and `nginx:1.27-alpine` are fully qualified with the `docker.io/library/` registry prefix. This was not the original form of the file — see Section 13.7 for the full incident — and the comment block preserved in the file itself documents the fix concisely: OKE's node OS runs the CRI-O container runtime, and this particular node image has short-name resolution mode set to `enforcing`, meaning any image reference that doesn't explicitly state a registry (like the bare `nginx:1.27-alpine`) is rejected outright rather than CRI-O guessing which registry was intended (Docker Hub, Oracle's own registry, etc. — the whole point of "enforcing" mode is refusing to guess, since an ambiguous short name could in principle resolve to different, even malicious, images depending on which registries are configured, which is a real supply-chain security concern CRI-O is deliberately protecting against). `busybox:1.36` happened to already work even before this fix purely by coincidence — it's commonly pre-pulled/cached on OKE's stock node images — while `nginx:1.27-alpine` was not, so only the nginx failure actually surfaced during testing even though both references were equally "wrong" per CRI-O's rules.

**`volumeMounts` — the readOnly asymmetry.** The initContainer mounts the `data` volume without any `readOnly` flag (i.e., read-write, the default), since its entire job is to *write* `index.html` onto it. The nginx container mounts the same volume at `/usr/share/nginx/html` (nginx's default document root) with `readOnly: true` — nginx only ever needs to read the file the initContainer already wrote, and mounting it read-only is a small but real security/robustness improvement: even if the nginx container were compromised or misbehaved, it categorically cannot modify or delete the content it's serving.

**`resources.requests` / `resources.limits`.** `requests` (`100m` CPU, `128Mi` memory) are what the scheduler uses to decide which node has room for this pod; `limits` (`250m` CPU, `256Mi` memory) are hard ceilings the container runtime enforces — the container gets CPU-throttled if it tries to exceed the CPU limit, and gets OOM-killed if it exceeds the memory limit. Both are modest, appropriate values for a container doing essentially nothing but serving one static file, and setting them at all (rather than leaving resources unbounded) is a Kubernetes best practice that keeps a small demo workload from ever being able to starve other pods on a shared node.

**`readinessProbe` / `livenessProbe`.** Both probes hit `GET /index.html` on port 80 — the exact file the initContainer wrote — on different schedules and for different purposes. The readiness probe (checked every 5 seconds, starting 3 seconds after container start) determines whether this pod should currently receive traffic from the Service; if it fails, the pod is pulled out of the Service's load-balancing rotation without being restarted. The liveness probe (checked every 10 seconds, starting 10 seconds after container start) determines whether the container needs to be killed and restarted entirely; a liveness failure is a stronger signal ("this container is broken/hung, not just temporarily not ready"). Using the same simple HTTP check for both is appropriate for an app this small; larger real applications often use different endpoints for each (e.g., a lightweight `/healthz` for liveness vs. a deeper dependency check for readiness).

**`spec.template.spec.volumes`.** This is where the pod template ties the abstract `data` volume name (referenced by both containers' `volumeMounts`) to the concrete PVC (`demo-app-data`) created in Section 11.3 — the actual link between "a container wants a directory called `/data` or `/usr/share/nginx/html`" and "here's the real, PVC-backed, block-volume storage that directory should map to."

### 11.5 `service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: demo-app-lb
  namespace: week3-demo
  annotations:
    service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
spec:
  type: LoadBalancer
  selector:
    app: demo-app
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
```

A Kubernetes `Service` provides a stable network identity in front of a set of pods that may come and go (get rescheduled, restarted, replaced during a rollout) and would otherwise have unpredictable, ephemeral IPs. `type: LoadBalancer` is the specific Service type that goes one step further than the in-cluster-only alternatives (`ClusterIP`, `NodePort`) — it asks whatever cloud the cluster is running on to actually provision a real, internet-facing load balancer and wire it up to the Service automatically. On OKE, this is handled by the OCI Cloud Controller Manager, a component pre-installed on every OKE cluster specifically to watch for `LoadBalancer`-type Services and translate them into real OCI Load Balancer resources via the OCI API — this is exactly analogous to how the Block Volume CSI driver (Section 11.2) translates PVC requests into real OCI block volumes; both are examples of the general Kubernetes cloud-provider-integration pattern, where the cluster reaches out and manages real cloud infrastructure on the application's behalf, entirely outside of Terraform's awareness (this is precisely why the teardown ordering discussed in Section 12.3 matters so much — Terraform has no record of this Load Balancer's existence at all, since it was never the one that created it).

- **`selector: app: demo-app`** — this is how the Service knows which pods to route traffic to: any pod (in this Service's namespace) carrying the label `app: demo-app` is included, which matches the label set on the Deployment's pod template (Section 11.4). This label-selector mechanism is the standard, loosely-coupled way Services find pods in Kubernetes — the Service never references the Deployment directly by name.
- **`ports`** — maps port `80` on the Service/Load Balancer (`port`) to port `80` on the target pods (`targetPort`), over TCP. Since nginx listens on 80 inside the container (Section 11.4's `containerPort: 80`), these match directly and no port translation is happening here, though the fields are independent and could differ.
- **The three `oci-load-balancer-*` annotations.** These are OCI-specific configuration hints, read by the Cloud Controller Manager when it provisions the actual Load Balancer, that have no meaning to core Kubernetes itself (the `service.beta.kubernetes.io/` prefix is the conventional namespace cloud providers use for this kind of provider-specific Service annotation). `oci-load-balancer-shape: "flexible"` selects OCI's newer "Flexible" load balancer shape (as opposed to older fixed shapes like `100Mbps`), which bills based on actual bandwidth used within a configured min/max range rather than a single fixed throughput tier. `oci-load-balancer-shape-flex-min` and `-flex-max`, both set to `"10"` (Mbps), pin that range to a flat 10Mbps — the minimum practical size, entirely appropriate for a lab demo serving one small static page to occasional test traffic, and a deliberate cost-consciousness choice consistent with the cost-management discipline covered in Section 15 (a wider or higher range would provision a more expensive load balancer for no benefit here).

Once this Service is applied, the Cloud Controller Manager provisions the Load Balancer (which itself takes a minute or two — the `EXTERNAL-IP` column in `kubectl get svc` shows `<pending>` until it's ready), and once ready, exposes a genuinely public IP address (`80.225.69.163` in this lab's case) that routes straight through to the nginx pod — this was the IP confirmed working end-to-end in a browser at the end of the second build cycle (Section 12.2).

---

## 12. The Full Deployment Journey, Chronologically

This section walks through the entire week in the actual order events happened, across two full build/teardown cycles, so the narrative arc is visible in one place rather than scattered across the topic-organized sections above.

### 12.1 Cycle One — Initial Build and End-of-Day Teardown

The first cycle began with the Terraform module structure already designed (the generic `subnet` module and `oke` module described in Sections 6 and 7), and consisted of writing the root configuration (Section 8), running `terraform init`, `terraform plan`, and `terraform apply`, and watching all 23 resources come up cleanly: the VCN and its four subnets (Bastion, Kubernetes API endpoint, worker nodes, load balancers), the internet gateway, NAT gateway, service gateway, four route tables, four security lists, the two flow-log resources, the OKE cluster itself, and the managed node pool.

The cluster's control plane took the usual several minutes to reach `ACTIVE`, and once the node pool's two nodes joined and reached `Ready`, the plan was to move on to deploying the Kubernetes application — but the day's working session ended before that happened. Rather than leave a live OKE cluster (control plane plus two worker compute instances plus load balancer subnet, NAT gateway, etc.) running unattended overnight purely to save the trouble of rebuilding it the next day, the decision was made to tear everything down immediately via `terraform destroy`, accepting the cost of a from-scratch rebuild the next day in exchange for zero overnight billing. This is a real, deliberate tradeoff discussed further in Section 15 (Cost Management) — OKE control planes, running compute instances, load balancers, and NAT gateways are all resources that bill continuously while they exist, regardless of whether anything is actively using them, so "destroy it if you're not using it tonight" is a genuinely sound default for lab/learning environments where the infrastructure has no persistent-state requirement.

That first `terraform destroy` took roughly 22 minutes, dominated almost entirely by the OKE cluster deletion step — the node pool's compute instances need to be drained and terminated, and the managed control plane itself needs to be torn down through OCI's own control-plane lifecycle, none of which Terraform can speed up; it simply polls and waits. This was flagged as an active point of concern at the time ("why is it taking so much time?") and the guidance given was to let it run to completion rather than interrupting it — killing a `terraform destroy` mid-flight would desynchronize Terraform's local state file from the actual state of the cloud resources (some already deleted, some not), which is a substantially worse position to be in than just waiting out a slow-but-working destroy. All 23 resources were confirmed destroyed cleanly.

### 12.2 Cycle Two — Full Rebuild and End-to-End Application Deployment

The second working session began with the exact same Terraform code — nothing had changed on disk overnight — run through `terraform plan` and `terraform apply` again from a completely clean slate (no existing state referencing live resources, since the destroy the day before had cleared it). This is itself a small but meaningful validation of the whole exercise: the entire environment was reproduced byte-for-byte from code, with zero manual intervention or configuration drift, which is precisely the point of infrastructure-as-code as a discipline. The apply again added the same 23 resources and completed cleanly, producing a new cluster with a new `cluster_id` (OCIDs are not stable across destroy/recreate cycles — this is expected and is why Terraform outputs like `cluster_id` need to be re-read fresh after every rebuild rather than assumed constant).

With the cluster active, attention turned to actually connecting to it and deploying the application — work that hadn't been reached in cycle one. This is where the bulk of the week's real debugging happened, in roughly this order:

1. **Getting the OCI CLI working at all** on the developer's Windows machine (Section 13.5) — including a wrong turn trying to invoke it via `python -m oci`, finding the real `oci.exe` entry point, and then working around an IAM permission gap that blocked the CLI's normal interactive setup flow by hand-writing `~/.oci/config` from the key pair already present in `terraform.tfvars`.
2. **Generating a working kubeconfig** via `oci ce cluster create-kubeconfig`, which succeeded once the config file existed, followed immediately by a second, smaller problem: `kubectl` couldn't find the `oci` executable referenced inside the generated kubeconfig's credential-exec block, because that executable wasn't on the system `PATH` (Section 13.6). Patched by rewriting just that one line of the kubeconfig to the executable's full path.
3. **Applying all five Kubernetes manifests** in dependency order (Section 11), which mostly succeeded immediately — the Namespace, StorageClass, and PVC all came up without issue, and the PVC's underlying OCI block volume and the Service's OCI Load Balancer were both already visibly provisioning in the background — but the Deployment's pod failed to start, surfacing the CRI-O short-name enforcement issue (Section 13.7).
4. **Fixing the image references** and re-applying the Deployment, which led directly into the second real issue: a rollout that appeared to hang for roughly 30 minutes with no visible progress, which turned out to be the RWO-volume/RollingUpdate deadlock (Section 13.8), fixed first by manually deleting the stuck old pod to unblock the immediate rollout, and then durably by adding `strategy: type: Recreate` to the manifest so the same deadlock could never recur on a future rollout.
5. **A confusing follow-up** where a second rollout appeared to briefly reintroduce the exact same already-fixed error on a pod carrying the *original* pre-fix template hash (Section 13.9), which resolved on its own once a subsequent, genuinely-correct `kubectl apply` took effect and Kubernetes settled on the correct, healthy ReplicaSet as the sole active one.
6. **Final end-to-end verification**: `kubectl get all -n week3-demo` showing exactly one pod (`1/1 Running`, zero restarts), one ReplicaSet at `1/1/1`, the Deployment at `1/1` available, and the Service's `EXTERNAL-IP` populated with a real public address; `kubectl get pvc -n week3-demo` showing the PVC `Bound` at the requested `50Gi`; and, conclusively, opening `http://80.225.69.163` in a browser and seeing the actual proof-of-life page rendered — the pod name, the node name, and the render timestamp, all pulled live from the running pod and its attached block volume, exactly as designed back in Section 11.4.

### 12.3 Final Teardown — Correct Ordering

With every requirement of the assignment brief verified working, the environment was torn down a second and final time. This teardown was handled more carefully than the first, because by this point the cluster had real Kubernetes-managed cloud resources attached to it that Terraform has no knowledge of and therefore cannot clean up on its own: the OCI Load Balancer (created by the Cloud Controller Manager in response to the `LoadBalancer`-type Service) and the OCI block volume (created by the CSI driver in response to the PVC). Running `terraform destroy` first, while those still existed, would have deleted the VCN, subnets, and cluster out from under them — potentially leaving an orphaned Load Balancer and block volume with no cluster left to manage or clean them up, silently billing forever with no obvious way to find them again short of manually searching the OCI console.

The correct order, followed here, was:

```
kubectl delete -f k8s\service.yaml
kubectl delete -f k8s\deployment.yaml
kubectl delete -f k8s\pvc.yaml
kubectl delete -f k8s\storageclass.yaml
kubectl delete -f k8s\namespace.yaml
terraform destroy
```

Deleting the Service first triggers the Cloud Controller Manager to tear down the real OCI Load Balancer and wait for that to complete before the `kubectl delete` command returns. Deleting the Deployment removes the running pod. Deleting the PVC (with `reclaimPolicy: Delete` set on its StorageClass, Section 11.2) triggers the CSI driver to delete the real underlying OCI block volume. Deleting the StorageClass and Namespace are mostly just cleanliness at that point, since nothing depends on them anymore. Only once all of that was confirmed gone was `terraform destroy` run, at which point it had a completely clean job — delete the same 23 infrastructure resources cycle one's destroy had deleted, with nothing extra lurking underneath that Terraform didn't know about.

This second `terraform destroy` took considerably longer than the first — roughly 59 minutes for the cluster deletion step specifically, against 22 minutes the first time. This was, again, not a hang or an error; OKE control-plane teardown time is not perfectly deterministic and can vary run to run depending on OCI's backend load and the specific state the control plane needs to unwind, and the guidance given throughout was consistent with cycle one: let it run, don't interrupt it, and trust the final "Destroy complete! Resources: 23 destroyed." as the authoritative confirmation rather than the elapsed time. It completed cleanly, and a Chrome-based visual sanity check against the OCI console was also attempted at the user's request to independently confirm nothing remained active, though that check was blocked by a browser-extension permission restriction on the OCI console domain (noted honestly to the user rather than worked around) — the Terraform destroy log itself, showing all 23 resources explicitly destroyed with no errors, was treated as sufficient confirmation on its own.

---

## 13. Every Problem Encountered and How It Was Solved

This section collects every real error hit during the week into one comprehensive, ordered log, each with the exact symptom, the root cause, and the fix. Several of these are referenced by anchor from earlier sections in this document; the numbering here matches those references.

### 13.1 Problem 1 — Invalid cross-variable `validation` block

**Symptom:** A `variable` block's `validation` clause referencing a *different* variable (e.g., a subnet module's `enable_logs` variable trying to validate that `log_group_id` is non-null when `enable_logs` is true) failed to plan, with Terraform rejecting the configuration.

**Root cause:** Terraform's `validation` block, attached to a `variable`, can only reference that same variable's own value (`var.log_group_id` inside `log_group_id`'s own validation block is fine; reaching over to read `var.enable_logs` from inside it is not supported). Cross-variable validation is a fundamentally different mechanism.

**Fix:** Moved the check into a `lifecycle { precondition { ... } }` block on the actual resource that needs the invariant to hold (`oci_logging_log.flow_log` in the subnet module's `main.tf`), where a `condition` expression can freely reference as many input variables as needed, since preconditions run in the context of the full resource configuration, not a single variable's own definition. This is the standard Terraform idiom for exactly this class of "these two inputs must be consistent with each other" validation.

### 13.2 Problem 2 — Deprecated `hashicorp/oci` provider warning

**Symptom:** `terraform init`/`plan` emitted a deprecation warning related to the `oci` provider source or a deprecated attribute.

**Root cause:** The provider source address or an attribute used had been superseded by a newer recommended form as the `oci` provider evolved versions.

**Fix:** Updated the provider configuration to the current recommended form per the warning text; a warning, not an error, so it did not block progress, but was addressed to keep the configuration on a supported, non-deprecated path going forward.

### 13.3 Problem 3 — Empty `oci_core_images` data source result

**Symptom:** A data source query against the generic `oci_core_images` catalog, filtered for an OKE-compatible worker node image, returned zero results.

**Root cause:** `oci_core_images` is a general-purpose compute image catalog covering every OS/image OCI offers; OKE-specific worker images (which need particular pre-baked components — kubelet, container runtime, CSI drivers, etc., all matched to a specific Kubernetes minor version) are not reliably or completely represented in that generic catalog, especially when filtering by an OS version/display-name pattern that happens not to match how OKE images are actually named in that catalog listing.

**Fix:** Switched entirely to the purpose-built `oci_containerengine_node_pool_option` data source (Section 7 and Section 10), which is specifically designed to enumerate exactly the worker images valid for a given OKE cluster/Kubernetes version/shape combination — a far more reliable source of truth than trying to pattern-match the generic image catalog.

### 13.4 Problem 4 — Wrong-architecture (GPU) image auto-selected

**Symptom:** An early version of the worker-image-selection logic (Section 10) selected an image whose name indicated a GPU-oriented variant, incompatible with the plain CPU-only shape actually being used for the node pool.

**Root cause:** The filtering logic at that stage wasn't yet excluding `GPU`/`Gen2-GPU`/`Gen2-AMD-GPU` name-substring variants, so any image matching the base `Oracle-Linux-8` pattern was eligible, GPU or not, and the sort-by-name-descending tiebreaker happened to land on a GPU-variant image for that particular candidate list.

**Fix:** Added an explicit exclusion for GPU-variant name substrings to the candidate filter (alongside the pre-existing `aarch64`/ARM exclusion), covered in full in Section 10.4's walkthrough of the final selection logic.

### 13.5 Problem 5 — OCI CLI cannot self-provision an API signing key

**Symptom:** Running `oci ce cluster create-kubeconfig` with no existing `~/.oci/config` file triggered the CLI's interactive setup flow, which attempted a browser-based login and then tried to call `upload_api_key` to generate and register a brand-new API signing key on the user's behalf — and that call failed with `ServiceError: NotAuthorizedOrNotFound`.

**Root cause:** This tenancy has a known IAM policy gap (the same general class of restriction encountered with the Bastion service in Week 2) that prevents this particular identity from self-provisioning new API keys via `upload_api_key`, even though the identity *is* authorized to use an API key that already exists and was created through the proper channel. The interactive CLI setup assumes it's always allowed to mint a new key from scratch, which doesn't hold here.

**Fix:** Rather than trying to work around the IAM gap directly (which would need an actual policy change, out of scope for this lab), the existing, already-authorized key pair sitting in `terraform.tfvars` (the same key Terraform itself was already using successfully for every `apply`/`destroy` this whole week) was reused. Its `tenancy_ocid`, `user_ocid`, `fingerprint`, `key_file` path, and `region` were read directly from `terraform.tfvars` and hand-assembled into a `~/.oci/config` file on the developer's machine, entirely bypassing the CLI's interactive/self-provisioning flow. Once that config file existed with a valid, already-authorized key, `create-kubeconfig` succeeded immediately (aside from two harmless, purely advisory "file permissions too open" warnings about the config/key file's Windows permissions, which don't block functionality and are optionally silenceable via `oci setup repair-file-permissions` or the `OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING` environment variable).

### 13.6 Problem 6 — `kubectl` credential-plugin PATH resolution failure

**Symptom:** Immediately after successfully generating a kubeconfig, `kubectl get nodes` failed with `exec: executable oci not found`.

**Root cause:** OKE-generated kubeconfigs authenticate via a Kubernetes `exec` credential plugin — instead of embedding a static token, the kubeconfig tells `kubectl` to run an external command (`oci ce cluster generate-token ...`) on demand and use its output as the auth token. The generated kubeconfig's `exec.command` field was just the bare string `oci`, which only works if an executable literally named `oci` (or `oci.exe` on Windows, matched by `PATH` extension resolution) is somewhere on the system `PATH` — and on this machine, the real executable lived under the Python Scripts directory, which wasn't on `PATH`.

**Fix:** Rather than modifying the system-wide `PATH` (via `setx`, which risks silently truncating an already-long existing `PATH` value — a real and somewhat common Windows footgun), a narrower, safer fix was used: a single PowerShell one-liner that read the kubeconfig file, replaced just the literal text `command: oci` with `command: C:\Users\yinya\AppData\Roaming\Python\Python312\Scripts\oci.exe`, and wrote it back — patching only the one line that needed the full path, leaving everything else (and the system `PATH`) untouched. Verified via `findstr`, then `kubectl get nodes` succeeded, showing both nodes `Ready`.

### 13.7 Problem 7 — CRI-O "short name mode is enforcing"

**Symptom:** After applying the Deployment manifest, `kubectl get pods` showed the pod stuck, and `kubectl describe pod` showed an `ImageInspectError` (specifically for the `nginx` container, not the `busybox` initContainer) with the message: *"short name mode is enforcing, but image name `nginx:1.27-alpine` returns ambiguous list."*

**Root cause:** OKE's worker node OS runs the CRI-O container runtime (visible directly in `kubectl describe pod`'s `Container ID: cri-o://...` field), configured with short-name resolution mode set to `enforcing`. In that mode, CRI-O refuses to guess a registry for any image reference that doesn't explicitly include one — `nginx:1.27-alpine` is ambiguous (it could resolve to Docker Hub, or to any number of other configured registries) and is rejected outright rather than silently guessed, which is itself a deliberate supply-chain-security posture (an ambiguous short name resolving unexpectedly to the wrong registry is a real, documented class of container-security incident). `busybox:1.36`, referenced with an equally "short" name, happened not to trigger the same visible failure only because it's commonly pre-cached on stock OKE node images, so no registry pull (and thus no short-name resolution) was ever actually needed for it in practice.

**Fix:** Fully qualified both image references with an explicit registry — `docker.io/library/busybox:1.36` and `docker.io/library/nginx:1.27-alpine` — in `deployment.yaml`, removing the ambiguity entirely. Re-applying the manifest with the fully-qualified references resolved the error.

### 13.8 Problem 8 — ReadWriteOnce PVC + default RollingUpdate deadlock

**Symptom:** After fixing Problem 7 and re-applying the Deployment, the rollout appeared to hang for roughly 30 minutes: `kubectl get pods` showed a new pod stuck at `Init:0/1` indefinitely, while the old (broken, `ImageInspectError`) pod remained present and was never terminated.

**Root cause:** The Deployment's default rollout strategy, `RollingUpdate`, brings up the replacement pod *before* tearing down the old one, specifically to achieve zero-downtime rollouts for stateless, horizontally-scalable applications. But this Deployment's single replica is bound to a `ReadWriteOnce` PVC (Section 11.3) — a volume that can only be attached to one node at a time. The new pod's initContainer couldn't proceed past `Init:0/1` because the volume was still attached (to the old pod's node), and the old pod could never be torn down because the rollout logic was waiting for the new pod to become healthy first — a genuine circular deadlock with no way to resolve itself.

**Fix — immediate:** Manually deleted the stuck old pod directly (`kubectl delete pod -n week3-demo demo-app-788d46f774-48fgl`), which freed the volume immediately and let the new pod's initContainer proceed and the rollout complete.

**Fix — durable:** Added `strategy: type: Recreate` to `deployment.yaml` (Section 11.4), which changes the rollout order so that Kubernetes always terminates all existing pods *before* creating any replacement — matching what the RWO storage constraint actually requires, at the cost of a brief real downtime window on any future rollout (an acceptable, explicitly-documented tradeoff here). This ensures the same deadlock cannot recur on any subsequent `kubectl apply` of this Deployment.

### 13.9 Problem 9 — Confusing follow-up rollout reusing the original pre-fix template hash

**Symptom:** Shortly after Problem 8 was fixed and a healthy pod was running, a second, unexpected rollout began, producing a new pod (`demo-app-788d46f774-6mhcx`) whose name's hash suffix matched the *original*, pre-any-fix Deployment revision — and that pod hit the exact same `ImageInspectError` from Problem 7 again, even though the image references had already been corrected on disk. Separately, a browser screenshot of the working app showed "Served by pod: demo-app-788d46f774-6mhcx" — the name of this apparently-broken pod — which looked at first like the broken pod was somehow the one actually serving traffic.

**Root cause (rollout):** Not fully confirmed with certainty, but the most likely explanation is that a `kubectl apply` was run at some point against a momentarily-stale version of `deployment.yaml` on disk (for instance, an editor buffer that hadn't yet flushed the latest saved fix to disk) — Kubernetes computes a Deployment's ReplicaSet identity from a hash of its pod template, so applying an older template content, even briefly, causes Kubernetes to reuse (and scale back up) the pre-existing ReplicaSet matching that older hash, rather than creating a new one. This was reassured, at the time, as not a threat to the already-working pod: Kubernetes' default Deployment behavior does not tear down a healthy old pod to make way for a new pod that isn't passing its readiness checks.

**Root cause (the pod-name mismatch in the browser):** Explained by the PVC being shared storage rather than being a bug at all. Both the broken `6mhcx` pod and the genuinely healthy `pjzr4` pod's initContainers mount the *same* underlying PVC/volume; if both pods happened to be scheduled to the same node (fully plausible with only two nodes in the pool), `6mhcx`'s initContainer — which uses the already-fixed, working `busybox` image — ran successfully and overwrote `/data/index.html` with content stamped with *its own* hostname and timestamp, even though `6mhcx`'s *main* `nginx` container then failed to start at all. Meanwhile, `pjzr4`'s nginx container was still running and serving traffic, but nginx just serves whatever file currently exists on disk — and that file had just been overwritten by `6mhcx`'s initContainer. So the browser was, accurately, showing the content of the file as it existed on the shared disk at that moment; it just happened to have last been written by a pod that itself never became healthy. Not a data-integrity or serving bug — a direct, if initially surprising, consequence of RWO storage being shared at the node level between any pods that land there.

**Resolution:** This resolved on its own without further intervention once a subsequent, genuinely-correct `kubectl apply` (with the real, `Recreate`-strategy, fully-qualified-image content actually on disk) took effect — Kubernetes scaled the stale, bad ReplicaSet back down to zero and left the correct, healthy ReplicaSet (matching pod `demo-app-56fc59d44-pjzr4`) as the sole active one. Final verification via `kubectl get all -n week3-demo` confirmed exactly one pod, `1/1 Running`, zero restarts, and the old ReplicaSet sitting at `0/0/0` — which is itself entirely normal Deployment revision-history bookkeeping (old ReplicaSets are kept around, scaled to zero, to support rollback, not deleted outright), not evidence of an ongoing problem.

---

## 14. Security Considerations

Even for a disposable lab environment, a number of real security decisions were made deliberately throughout this build, rather than left to defaults:

**Network segmentation.** The VCN is split into four purpose-specific subnets (Bastion, Kubernetes API endpoint, worker nodes, load balancers — Section 9), each with its own security list scoped to only the traffic that subnet actually needs to send or receive. Worker nodes, in particular, sit in a private subnet with no direct public IP (`is_public = false`), reachable only through the internal VCN and, for outbound internet access (image pulls, package updates), routed through a NAT gateway rather than an internet gateway — meaning nothing on the public internet can initiate a connection directly to a worker node. This is standard defense-in-depth: even if an application running on a node were compromised, the blast radius of what it could directly reach or be reached by is deliberately narrowed by network topology alone, independent of any application-layer security.

**Least-privilege security list rules.** Every ingress and egress rule across all four subnets (fully enumerated in Section 9) was written to allow only the specific protocol, port range, and source/destination it actually needs — not blanket `0.0.0.0/0` allow-all rules. The Kubernetes API endpoint subnet, for example, only accepts inbound traffic on the Kubernetes API port from the ranges that legitimately need to reach it, not from arbitrary sources.

**No credentials or secrets committed to version control.** `terraform.tfvars`, which contains the tenancy OCID, user OCID, API key fingerprint, and private key file *path* (not the key material itself, which lives as a separate `.pem` file outside the repository), was never intended to be committed — the standing instruction throughout this entire engagement was that only the user runs any `git add`/`git commit`/`git push`, specifically so nothing sensitive gets committed without their own direct review and decision. The actual private key (`oci_api_key.pem`) never left the user's own machine at any point and was never transmitted, pasted, or embedded anywhere in this documentation or in any file the assistant wrote.

**Reused, already-authorized credentials rather than newly self-provisioned ones.** When the OCI CLI's interactive setup tried to self-provision a brand-new API signing key (Problem 5, Section 13.5) and failed due to an IAM gap, the fix deliberately did *not* attempt to work around that IAM restriction to force a new key into existence — doing so would have meant either requesting a policy change with implications outside this lab's scope, or finding some other bypass, either of which risks widening the credential surface unnecessarily. Reusing the existing, already-properly-authorized key was both the pragmatic fix and the more conservative one from a credential-hygiene standpoint: one key, one clear provenance, doing double duty for both Terraform and `kubectl`, rather than two.

**Read-only mount for the served content.** The nginx container mounts the PVC-backed volume with `readOnly: true` (Section 11.4) — a small but genuine hardening step: nginx has no path, even under compromise, to modify or delete the content it serves, since the filesystem it sees at that mount point is not writable from inside that container at all.

**CRI-O's short-name enforcement as a security feature, not just an obstacle.** Problem 7 (Section 13.7) is worth calling out specifically here: the fix (fully-qualifying image references) is often framed purely as "getting past an error," but the underlying enforcement exists for a real reason — an unqualified image name resolving ambiguously across multiple configured registries is a documented supply-chain attack vector (a malicious actor controlling or squatting on a same-named image in a lower-priority registry could have their image pulled instead of the intended one). Fully-qualifying image references is the correct fix from a security standpoint as much as a functional one, and is generally considered good practice for production Kubernetes manifests regardless of whether the runtime enforces it.

**No secrets or sensitive configuration in Kubernetes manifests.** None of the five manifests in `k8s/` contain any credential, token, or sensitive value — the application itself has no secrets to manage (it's a static demo page), so no `Secret` objects were needed, and none were introduced speculatively.

**Scoped block-volume access mode.** Using `ReadWriteOnce` (Section 11.3) rather than a broader access mode is not just a technical necessity of the storage backend (Section 11.3 explains OCI block volumes are RWO-only regardless) — it's also, incidentally, a natural security boundary: the data can never be simultaneously writable from multiple nodes, which limits any possible class of race-condition or concurrent-write issue to begin with.

---

## 15. Cost Management and Teardown Discipline

Cost awareness was a first-class concern throughout this lab, not an afterthought, and shaped several concrete decisions documented elsewhere in this file but worth collecting here explicitly:

**Everything that bills continuously was torn down when not actively in use.** An OKE cluster's control plane, its worker node compute instances, its NAT gateway, and any provisioned Load Balancer or block volume all bill for the time they exist, regardless of utilization — an idle cluster costs essentially the same as a busy one. Recognizing this, the environment was fully destroyed at the end of the first working day (Section 12.1) specifically to avoid paying for roughly 12+ hours of idle overnight infrastructure, and destroyed again at the very end of the second day once the assignment's requirements were fully verified (Section 12.3) — at no point in this engagement was infrastructure left running for longer than it was actively being used or verified.

**Terraform as the mechanism that makes this tradeoff cheap.** The entire reason "just destroy it and rebuild tomorrow" was a viable strategy at all, rather than an unreasonable amount of manual rework, is that the whole environment is defined as code. Rebuilding cycle two from scratch took a single `terraform apply` and produced a byte-for-byte equivalent environment with no manual reconfiguration — this is one of the core practical arguments for infrastructure-as-code in general, and this lab is a direct, lived demonstration of it: the *time* cost of tearing down and rebuilding was almost entirely just OCI's own provisioning/deprovisioning latency, not human effort.

**Correct teardown ordering to avoid orphaned, invisible-to-Terraform costs.** Section 12.3 covers this in detail, but the cost angle deserves its own emphasis: had `terraform destroy` been run *before* deleting the Kubernetes-managed Load Balancer and block volume, those two resources — both of which bill continuously and neither of which Terraform has any record of — could have been orphaned entirely, continuing to bill indefinitely with no `terraform destroy` output ever mentioning them and no obvious record in this project's own files pointing to their existence. The only way to find and clean them up after the fact would have been a manual sweep of the OCI console. Deleting them explicitly via `kubectl delete` first, and confirming their removal, before ever running `terraform destroy`, closed that gap entirely.

**Right-sized resources rather than defaults.** The Load Balancer's flexible shape was pinned to a flat 10Mbps minimum/maximum (Section 11.5) rather than left at a larger default range; the block volume's performance tier was set to the mid-tier "Balanced" 10 VPUs/GB (Section 11.2) rather than a higher, costlier performance tier that a static single-page demo app has no use for; the node pool uses a small, appropriately-sized shape rather than an oversized one. None of these are dramatic savings individually for a lab this size and this short-lived, but each reflects the same underlying discipline of deliberately choosing a size rather than accepting whatever a wizard or default happens to suggest — a habit worth having regardless of the dollar amounts involved at lab scale.

**Verifying destroys actually completed, rather than assuming.** Both `terraform destroy` runs were watched through to their final "Destroy complete! Resources: N destroyed." output rather than being started and left unattended, specifically because a partially-completed or interrupted destroy is exactly the scenario that leaves stray, billing resources behind unnoticed.

---

## 16. Verification and Testing Methodology

At every stage of this lab, claims of "it works" were backed by an explicit, checkable verification step rather than just an absence of errors. This section collects the verification approach used at each layer:

**Terraform plan/apply output as verification.** Every `terraform apply` was checked against its own summary line (e.g., "Apply complete! Resources: 23 added, 0 changed, 0 destroyed.") to confirm the expected resource count matched what actually happened — an apply that silently changed or destroyed something unexpected would show up immediately in that count, even without reading the full resource-by-resource log.

**Independent verification of the worker-image-selection logic before shipping it.** Rather than trusting the final version of the image-selection `locals` block (Section 10.4) on faith after two earlier iterations had already failed in real applies, a standalone Python script was written that reimplemented the exact same filter/sort logic against the real candidate image list a prior failed plan had already printed via the `debug_available_worker_images` output — confirming, independently of Terraform itself, that the logic selected the correct, version-tagged, non-ARM, non-GPU image before ever sending the updated code back for a real `terraform plan`/`apply` (Section 10.5). This is a general and reusable technique: when a piece of configuration logic is hard to eyeball for correctness, reimplement it standalone against real captured input data and check the output, rather than iterating purely by trial-and-error against the live infrastructure.

**`kubectl get`/`describe` as the primary Kubernetes-layer verification tool.** Every stage of the application deployment was checked with `kubectl get pods`, `kubectl get pvc`, `kubectl get svc`, and `kubectl get all -n week3-demo`, and every failure was diagnosed with `kubectl describe pod` before attempting a fix — for instance, the CRI-O short-name error (Section 13.7) and the stuck-`Init:0/1` deadlock symptom (Section 13.8) were both first identified precisely through `describe pod` output rather than guessed at.

**Node readiness as a gate before proceeding.** `kubectl get nodes` was checked and confirmed showing both nodes `Ready` before any application manifests were applied — deploying against a node pool that hadn't finished joining the cluster would have produced confusing, unrelated scheduling failures that could easily have been mistaken for an application-level bug.

**PVC binding status as storage-layer verification.** `kubectl get pvc -n week3-demo` was checked to confirm the PVC reached `Bound` status (as opposed to remaining `Pending`, which would indicate the CSI driver or StorageClass configuration had a problem) at the correct requested size (`50Gi`), independently of whether the application pod using it was healthy.

**Browser-based, human-visible end-to-end verification, not just API-level checks.** The single most conclusive verification step in the whole lab was opening `http://<external-ip>` in an actual browser and visually confirming the rendered proof-of-life page — showing the pod name, node name, and render timestamp pulled live from the running system. This is a meaningfully stronger verification than `kubectl get pods` showing `Running` alone: `Running` only confirms the container process started, not that the full request path (Load Balancer → Service → pod → nginx → PVC-backed file) is actually working end-to-end for a real external client, which is what the assignment brief actually cares about.

**Full teardown logs read to completion as the verification that cleanup actually happened.** As discussed in Section 15, both `terraform destroy` runs were watched to their final summary line, and the second teardown additionally verified each `kubectl delete` step's own success before moving to the next — real evidence that resources were actually removed, not just an assumption that the destroy commands were issued.

---

## 17. Mapping This Work Back to the Assignment Brief

The original Week 3 assignment brief (recapped and reconfirmed with the user mid-week, before the second build cycle) called for, at minimum: an OCI Kubernetes Engine (OKE) cluster provisioned via Terraform, using reusable, variable-driven modules rather than one large monolithic configuration; a working node pool; a Kubernetes application deployed on top of that cluster; persistent storage for that application backed by a real OCI block volume, provisioned via a PersistentVolumeClaim; and public exposure of the application via a Kubernetes Service of type `LoadBalancer`, backed by a real OCI Load Balancer. Every one of these requirements maps directly onto specific, verified work documented above:

The OKE cluster and its node pool were provisioned entirely through Terraform (Section 8, root configuration; Section 7, the `oke` module itself), using OCI's provider resources `oci_containerengine_cluster` and `oci_containerengine_node_pool`, with the cluster's Kubernetes version and worker image both discovered dynamically via data sources (Sections 7 and 10) rather than hardcoded, and successfully verified `Active`/`Ready` across two independent full build cycles (Section 12).

Reusable, variable-driven modules were used for both the networking layer (the generic `subnet` module, Section 6, parameterized enough to construct all four differently-purposed subnets in this lab from one shared module definition) and the OKE layer (the `oke` module, Section 7) — satisfying the "modular, not monolithic" structural requirement of the brief, and demonstrated concretely by the fact that the root configuration (Section 8) calls the `subnet` module four separate times with four different variable sets rather than repeating near-identical resource blocks four times.

The Kubernetes application itself — an nginx-based demo app with an initContainer proof-of-life mechanism — was deployed via five ordered manifests (Section 11) and confirmed running with `1/1 Ready`, zero restarts, in its final verified state (Section 12.2).

Persistent, block-volume-backed storage was provisioned through a `PersistentVolumeClaim` (Section 11.3) against a custom `StorageClass` (Section 11.2) using OCI's Block Volume CSI driver, confirmed `Bound` at the requested `50Gi`, and confirmed genuinely persistent and shared-mount-capable through the very real, live behavior investigated in Section 13.9 (the initContainer of one pod overwriting content subsequently served by a different, healthy pod sharing the same node and volume) — arguably a stronger demonstration of "this is real, working shared block storage" than a clean, uneventful test run would have been.

Public exposure was achieved via a `type: LoadBalancer` Service (Section 11.5), triggering a real OCI Load Balancer provision through the Cloud Controller Manager, and was the final, conclusive piece of end-to-end verification for the whole assignment: a real external IP address, reachable from an ordinary browser with no VPN or bastion hop required, serving the actual application content pulled from the actual attached block volume.

Beyond the strict minimum requirements, this engagement additionally exercised a substantial amount of real-world operational discipline not explicitly demanded by the brief but consistent with how this kind of infrastructure should actually be run: deliberate cost-conscious teardown between sessions (Section 15), correct Kubernetes-before-Terraform teardown ordering to avoid orphaned cloud resources (Section 12.3), and a real, lived debugging cycle through nine distinct, non-trivial problems (Section 13) rather than a scripted, error-free happy path — arguably a more representative and more valuable learning experience than a lab that had gone smoothly on the first try.

---

## 18. Lessons Learned

A number of genuinely transferable lessons came out of this week, beyond the specific fixes documented above:

**Purpose-built data sources beat generic ones, even when the generic one looks like it should work.** The pivot from `oci_core_images` to `oci_containerengine_node_pool_option` (Problem 3, Section 13.3) is a good general instance of a broader pattern: cloud providers often expose both a generic catalog/listing API and a narrower, purpose-built API scoped to a specific use case, and the narrower one is very often the more reliable choice precisely because it encodes the constraints of that use case (here: "valid for this OKE version, this shape" ) that the generic catalog has no way to express or guarantee.

**A rollout strategy is a real architectural decision, not a default to leave unexamined.** `RollingUpdate` being the default is entirely reasonable for the overwhelmingly common case of stateless, horizontally-scalable workloads — but silently inheriting that default for a workload with a fundamentally different storage constraint (a single-attach RWO volume) produced a genuine deadlock (Problem 8, Section 13.8) that only became obvious once actually triggered live. The transferable lesson: any time a Deployment involves persistent, non-shareable storage, the rollout strategy deserves a deliberate, explicit choice, not the default.

**Container runtime behavior varies by node OS/runtime in ways application manifests need to account for.** CRI-O's short-name enforcement (Problem 7, Section 13.7) is a property of *this specific* container runtime configuration, not a universal Kubernetes behavior — the same manifest with short image names might work unmodified against a differently-configured cluster. The transferable habit: always fully-qualify image references in manifests intended to be portable or production-grade, regardless of whether the current cluster happens to tolerate short names.

**Cloud-managed resources triggered *by* Kubernetes are invisible to the infrastructure tool that provisioned the cluster underneath it, and that has real operational consequences.** The Load Balancer and block volume created by OKE's Cloud Controller Manager and CSI driver (Section 12.3) exist entirely outside Terraform's state and awareness. Any infrastructure-as-code workflow layering Kubernetes workloads on top of Terraform-managed clusters needs an explicit, documented teardown order that accounts for this gap — "just run `terraform destroy`" is not sufficient once a cluster has real workloads with cloud-managed side effects running on it.

**Long-running destroy/apply operations that show no visible progress for many minutes are often working correctly, not hung** — but the only way to know that with confidence is understanding *what* the operation is actually waiting on (here: OCI's own OKE control-plane and compute-instance lifecycle, which Terraform can only poll, not accelerate) rather than just watching a terminal sit quietly and assuming the worst.

**When a tool's "convenient" interactive setup path doesn't fit the actual environment's constraints, look for the less-convenient-but-more-direct path rather than fighting the convenient one.** The OCI CLI's interactive config wizard (Problem 5, Section 13.5) is designed for the common case of a fresh identity self-provisioning its first key; this identity's actual constraint (an existing, already-authorized key, plus an IAM gap blocking new key creation) didn't fit that assumption, and the fix was to skip the wizard entirely and hand-write the config file directly from information already available — a generally useful instinct when a setup tool's assumptions don't match the actual situation.

**Shared, node-scoped storage between distinct pods can produce genuinely confusing observed behavior that looks like a bug at first glance but is actually a direct, correct consequence of RWO semantics.** Problem 9 (Section 13.9) is a good reminder that "which pod is actually serving this content" and "which pod's initContainer most recently wrote to this shared volume" are two different questions, and Kubernetes' architecture makes no promise that they're always the same pod.

---

## 19. Possible Future Improvements

Several extensions and hardening steps would be natural next steps beyond what this lab's scope required, worth noting for future work:

**Horizontal scaling of a stateless tier, split from the stateful storage-owning pod.** As flagged directly in the Deployment's own comments (Section 11.4), a more production-realistic architecture would split this single app into a small, storage-owning backend (still constrained to a single replica by the RWO volume) and a separately-scalable, stateless frontend tier that talks to the backend over the network rather than sharing its volume directly — allowing genuine horizontal scaling without inheriting the single-replica RWO constraint.

**Moving from `ReadWriteOnce` block storage to a shareable storage backend where the workload genuinely calls for concurrent multi-node access** — OCI File Storage Service (FSS), accessed via its own CSI driver, supports `ReadWriteMany` and would remove the single-node constraint entirely for workloads that actually need concurrent write access from multiple nodes, at the cost of different performance characteristics and a different (NFS-based) protocol.

**Ingress controller and TLS termination**, rather than exposing the application directly via a bare `LoadBalancer` Service on port 80. A real production deployment would typically run an Ingress controller (e.g., NGINX Ingress or OCI's native Ingress integration) in front of the application, terminating HTTPS with a real certificate (via cert-manager and Let's Encrypt, or an OCI Certificates Service-issued certificate), rather than serving plaintext HTTP on a bare Load Balancer.

**Horizontal Pod Autoscaler (HPA)** for the (hypothetical, per the point above) stateless tier, scaling replica count automatically based on CPU/memory utilization rather than a fixed replica count.

**Automated CI/CD for both layers** — a pipeline that runs `terraform plan`/`apply` on infrastructure changes and `kubectl apply`/a proper GitOps tool (Argo CD, Flux) for application manifest changes, rather than manually running commands by hand on each change, would remove human error from the deployment loop entirely and provide an audit trail of exactly what changed and when.

**Remote Terraform state**, rather than local state on the developer's own machine. For any team environment (this lab used local state, appropriate for a single-developer learning exercise), remote state (OCI Object Storage with state locking, or Terraform Cloud) would be necessary to avoid state conflicts and to keep the state file itself off individual laptops.

**Monitoring and alerting** beyond the basic `enable_logs`/VCN flow-log capability already wired into the subnet module (Section 6) — integrating OCI Monitoring metrics and alarms for the cluster and node pool, and application-level metrics/logging (e.g., via Prometheus/Grafana or OCI's native Application Performance Monitoring) for the workload itself.

**Network Security Groups (NSGs) as a complement to (or replacement for) subnet-level security lists** for finer-grained, resource-level (rather than subnet-wide) traffic control, particularly useful once more than one distinct workload shares the same subnet.

**Automated testing of the Terraform modules themselves** (e.g., via `terraform validate`, `tflint`, or a tool like Terratest) as part of a CI pipeline, catching configuration errors like Problem 1 (Section 13.1) before they ever reach a real `terraform plan` against live infrastructure.

---

## 20. Glossary of Terms

**API signing key** — an RSA key pair used to authenticate API requests to OCI; the public key is uploaded to a user's identity and paired with a fingerprint, the private key is held locally and used to sign every request.

**Availability Domain (AD)** — an isolated OCI data center location within a region; resources scoped to an AD (like block volumes) can only attach to compute instances in the same AD.

**Block volume** — OCI's block-storage product; a raw, network-attached disk that attaches to exactly one compute instance (or, via paravirtualized/iSCSI attachment, one node) at a time (RWO semantics).

**CIDR block** — Classless Inter-Domain Routing notation (e.g., `10.0.0.0/16`) describing a contiguous range of IP addresses via an address and a prefix length.

**Cloud Controller Manager (CCM)** — the OKE-installed Kubernetes control-plane component that watches for cloud-integration-relevant objects (like `LoadBalancer`-type Services) and provisions/manages the corresponding real OCI resources on the cluster's behalf.

**Compartment** — OCI's logical resource-isolation and access-control boundary, roughly analogous to an AWS account or a folder/project in GCP; every resource in this lab lives inside one specific compartment, looked up by name via a data source rather than hardcoded by OCID.

**CRI-O** — a lightweight, Kubernetes-native container runtime implementing the Container Runtime Interface (CRI); the runtime running on this lab's OKE worker nodes, responsible for actually pulling images and running containers.

**CSI (Container Storage Interface)** — a standard plugin interface letting Kubernetes talk to arbitrary storage backends (here, OCI's Block Volume service) through a common driver API, so PVC/PV/StorageClass objects work uniformly regardless of the underlying cloud.

**Data source** (Terraform) — a read-only Terraform block (`data "..." "..." {}`) that looks up information about an existing resource or catalog rather than creating anything; used throughout this lab to look up the compartment OCID, availability domains, Kubernetes version options, and worker node image options dynamically instead of hardcoding them.

**Deployment** (Kubernetes) — a controller object that manages a set of identical pod replicas, handling rollouts, rollbacks, and self-healing (replacing pods that die) declaratively.

**Downward API** (Kubernetes) — the mechanism letting a pod's own metadata (labels, name, node, resource limits, etc.) be exposed to its containers as environment variables or mounted files, without needing direct Kubernetes API access.

**Dynamic block** (Terraform) — an HCL construct (`dynamic "block_name" { for_each = ... }`) for conditionally or repeatedly generating a nested configuration block inside a resource, based on the contents of a list or map, rather than writing that nested block out statically.

**Flow log** — a VCN-level (or subnet-level) log of network traffic metadata (source, destination, port, accept/reject) enabled here via `oci_logging_log`/`oci_logging_log_group`, useful for network-level auditing and troubleshooting.

**Ingress/Egress security rule** — a single allow-rule in an OCI security list, specifying a protocol, port range, and source (ingress) or destination (egress) that traffic is permitted to/from.

**Init container** — a container in a pod spec that runs to completion before any of the pod's regular containers start; used in this lab to write proof-of-life content onto the shared PVC before nginx starts serving from it.

**Internet gateway** — a VCN component providing a route to/from the public internet for resources in subnets whose route table points at it; used here for the public load-balancer subnet.

**kubeconfig** — the YAML file (`~/.kube/config` by default) that tells `kubectl` which cluster to talk to and how to authenticate — cluster API server address, certificate authority data, and (for OKE) an `exec`-based credential plugin invoking the OCI CLI to mint short-lived tokens.

**Lifecycle precondition** (Terraform) — a `lifecycle { precondition { condition = ..., error_message = ... } }` block attached to a resource, which Terraform evaluates before creating/updating that resource and fails the plan/apply with a custom error message if the condition is false; the correct mechanism for cross-variable validation, unlike a `variable` block's own `validation`, which can only reference itself.

**Managed node pool** — the OKE construct for a homogeneous group of worker nodes, provisioned and lifecycle-managed by OCI (node replacement, and optionally node cycling/upgrades) rather than the user manually managing individual compute instances.

**NAT gateway** — a VCN component letting resources in a private subnet (no public IP) initiate outbound connections to the internet (e.g., to pull container images) without being directly reachable from the internet.

**Node pool option** (`oci_containerengine_node_pool_option`) — a Terraform data source enumerating the worker images, shapes, and Kubernetes versions actually valid for a given OKE cluster configuration; the purpose-built, reliable alternative to the generic image catalog (Section 13.3).

**OKE (Oracle Kubernetes Engine / Container Engine for Kubernetes)** — OCI's managed Kubernetes service; provisions and operates the control plane, and integrates with OCI networking, storage, and load balancing via built-in components (the CCM and CSI driver).

**PersistentVolume (PV)** / **PersistentVolumeClaim (PVC)** — a PV is an actual piece of provisioned storage in the cluster; a PVC is a namespaced *request* for storage matching certain criteria (size, access mode, StorageClass), which Kubernetes binds to a matching (dynamically provisioned, in this lab's case) PV.

**Provider** (Terraform) — a plugin translating HCL resource blocks into actual API calls against a specific platform; this lab uses the `oracle/oci` provider exclusively.

**ReadWriteOnce (RWO)** — a PVC access mode meaning the underlying volume can be mounted read-write by only one node at a time; the access mode OCI block volumes are constrained to, and the root cause behind both the Deployment's `Recreate` strategy requirement (Problem 8) and the shared-volume behavior investigated in Problem 9.

**Reclaim policy** — a StorageClass/PV setting controlling what happens to the underlying storage once its PVC is deleted: `Delete` (also delete the real cloud volume) or `Retain` (leave it behind, orphaned from Kubernetes but not destroyed).

**ReplicaSet** — the Kubernetes object a Deployment creates and manages under the hood, actually responsible for ensuring the requested number of identical pod replicas (matching one specific pod-template hash) exist; a Deployment typically owns multiple ReplicaSets over its history (old ones scaled to zero) to support rollback.

**Route table** — a VCN component defining where traffic leaving a subnet, that doesn't match a more specific route, should go (an internet gateway, NAT gateway, service gateway, etc.).

**Security list** — a stateful or stateless firewall-like construct in OCI, attached to a subnet, defining allowed ingress and egress traffic at the subnet level.

**Service** (Kubernetes) — an object providing a stable network identity and load-balancing in front of a dynamic set of pods, selected via label matching; `type: LoadBalancer` additionally provisions a real cloud load balancer via the CCM.

**Service gateway** — a VCN component allowing private-subnet resources to reach specific OCI public services (like Object Storage) without traversing the public internet or needing a NAT gateway.

**Short-name enforcement** (CRI-O) — a container-runtime security setting that rejects image references lacking an explicit registry, to prevent ambiguous resolution across multiple configured registries (Section 13.7).

**StorageClass** — a Kubernetes object defining a template for dynamically provisioning storage: which driver/provisioner to use and with what parameters, referenced by name from a PVC.

**Terraform module** — a self-contained, reusable set of Terraform resource definitions, parameterized via input variables and exposing output values, callable multiple times with different inputs from a root (or another) configuration — used here for both the `subnet` and `oke` modules.

**Terraform state** — the JSON file Terraform maintains recording what real infrastructure it believes exists and how it maps to the configuration's resource addresses; used to compute diffs on every `plan`/`apply`/`destroy`. Local state (this lab's setup) lives on the developer's own machine.

**VCN (Virtual Cloud Network)** — OCI's software-defined private network construct, the top-level container for subnets, gateways, and route tables in this lab.

**VCN-native pod networking** (`OCI_VCN_IP_NATIVE`) — an OKE pod-networking mode where each pod receives a real, routable IP address directly from a VCN subnet (the dedicated pods subnet in this lab), as opposed to the alternative Flannel overlay mode, where pod IPs exist only inside an overlay network invisible to the VCN itself.

---

## 21. Appendix A — Full File Listing and Index

Every file that makes up this lab, with its path relative to the `weekThree/` project root and a pointer to where it's discussed and reproduced in full above:

**Root Terraform configuration:**

- `provider.tf` — Terraform/provider block, requiring `hashicorp`-distributed `oracle/oci` provider `~> 7.0`, configured from the five auth variables. See Section 8.1.
- `variables.tf` — every root-level input variable: provider auth (marked `sensitive`), networking CIDRs and DNS labels, OKE cluster/node-pool sizing, the application block volume size, and freeform tags. See Section 8.2.
- `vcn.tf` — the VCN itself, the internet gateway, NAT gateway, and service gateway. See Section 8.3.
- `subnets.tf` — four calls to the `subnet` module (endpoint, workers, pods, lb subnets), each with its own CIDR, public/private setting, and route/ingress/egress rule sets. See Section 8.4 and Section 9 (full rule tables).
- `oke.tf` — the `locals` blocks implementing Kubernetes-version and worker-image discovery/selection (Section 10), and the call to the `oke` module itself (Section 8.5).
- `outputs.tf` — every root-level output: VCN/subnet/cluster/node-pool OCIDs, the ready-to-run `create-kubeconfig` command string, and three `debug_*` diagnostic outputs used while troubleshooting the worker-image selection logic (Section 8.6, Section 10.5). Full current contents reproduced above in this appendix's companion read, unchanged since Section 8.
- `terraform.tfvars` — **not reproduced in this document** (contains tenancy/user OCIDs, API key fingerprint, and private key path); exists only on the developer's own machine and was never committed to version control per the user's standing instruction. Referenced by value (not verbatim) in Section 13.5's account of the OCI CLI config fix.

**`modules/subnet/` (generic, reusable subnet module):**

- `modules/subnet/main.tf` — the subnet, route table, security list, and optional flow-log resources, including the `dynamic` blocks for route/ingress/egress rules and the `lifecycle { precondition {} }` enforcing `log_group_id` is set whenever `enable_logs` is true. See Section 6.
- `modules/subnet/variables.tf` — every input variable this module accepts, including the fully-typed `route_rules`/`ingress_rules`/`egress_rules` object-list variables with `optional()` fields. See Section 6 and the full listing above (re-read in full during this session).
- `modules/subnet/outputs.tf` — `subnet_id`, route table ID, and security list ID outputs. See Section 6.

**`modules/oke/` (OKE cluster + node pool module):**

- `modules/oke/main.tf` — the `oci_containerengine_cluster` and `oci_containerengine_node_pool` resources, including the mutually-exclusive `dynamic` blocks for VCN-native vs. Flannel pod networking. See Section 7.
- `modules/oke/variables.tf` — every input variable this module accepts (cluster name, Kubernetes version, subnet IDs, node shape/sizing, pod-networking mode, worker image ID, etc.). See Section 7.
- `modules/oke/outputs.tf` — `cluster_id`, `cluster_kubernetes_version`, `node_pool_id` outputs, consumed by the root `outputs.tf`. See Section 7.

**`k8s/` (Kubernetes application manifests, applied via `kubectl`, not Terraform):**

- `k8s/namespace.yaml` — the `week3-demo` Namespace. See Section 11.1.
- `k8s/storageclass.yaml` — the `week3-oci-bv` custom StorageClass. See Section 11.2.
- `k8s/pvc.yaml` — the `demo-app-data` PVC, 50Gi, RWO. See Section 11.3.
- `k8s/deployment.yaml` — the `demo-app` Deployment: single replica, `Recreate` strategy, busybox initContainer + nginx main container, both fully-qualified image references, readiness/liveness probes, resource requests/limits. Final, working version. See Section 11.4.
- `k8s/service.yaml` — the `demo-app-lb` Service, `type: LoadBalancer`, OCI flexible-shape annotations pinned to 10Mbps. See Section 11.5.

**`docs/` (documentation):**

- `docs/iam-policy-request-draft.md` — pre-existing file from earlier in the internship (Week 2 Bastion IAM gap), not part of this week's work.
- `docs/WEEK3_COMPREHENSIVE_DOCUMENTATION.md` — this document.

---

## 22. Appendix B — Full Command Reference

Every command category actually run over the course of this lab (all executed by the user on their own Windows machine, never by the assistant directly — see the tooling note in Section 1), organized by purpose:

**Terraform lifecycle:**

```
terraform init
terraform plan
terraform apply
terraform destroy
```

`init` downloads/verifies the `oracle/oci` provider plugin and sets up the local backend; run once per fresh working directory (and again if the provider requirements change). `plan` computes and displays the diff between current state and configuration without changing anything. `apply` performs that diff against real infrastructure, prompting for confirmation (`yes`) unless run with `-auto-approve`. `destroy` computes and performs the reverse diff, tearing down every resource currently in state.

**OCI CLI setup and kubeconfig generation:**

```
where.exe /R "%APPDATA%\Python" oci.exe
C:\Users\yinya\AppData\Roaming\Python\Python312\Scripts\oci.exe --version
oci ce cluster create-kubeconfig --cluster-id <cluster_id> --file %USERPROFILE%\.kube\config --region me-jeddah-1 --token-version 2.0.0
```

The `where.exe /R` search locates the real `oci.exe` entry point when it's not on `PATH` (Section 13.5/13.6). `create-kubeconfig` is the command from the root `outputs.tf`'s `kubeconfig_command` output, filled in with the actual `cluster_id` value from that same apply's outputs — it writes a kubeconfig file wired to authenticate via the OCI CLI's `generate-token` exec plugin.

**kubeconfig PATH patch (PowerShell, run once after generating the kubeconfig):**

```
powershell -Command "(Get-Content $env:USERPROFILE\.kube\config) -replace 'command: oci', 'command: C:\Users\yinya\AppData\Roaming\Python\Python312\Scripts\oci.exe' | Set-Content $env:USERPROFILE\.kube\config"
findstr "command:" %USERPROFILE%\.kube\config
```

**Cluster/node verification:**

```
kubectl get nodes
kubectl cluster-info
```

**Application deployment (applied strictly in this order, per the dependency chain in Section 11):**

```
kubectl apply -f k8s\namespace.yaml
kubectl apply -f k8s\storageclass.yaml
kubectl apply -f k8s\pvc.yaml
kubectl apply -f k8s\deployment.yaml
kubectl apply -f k8s\service.yaml
```

**Application-layer verification and debugging:**

```
kubectl get pods -n week3-demo
kubectl get pods -n week3-demo -w
kubectl describe pod <pod-name> -n week3-demo
kubectl get pvc -n week3-demo
kubectl get svc -n week3-demo
kubectl get all -n week3-demo
kubectl delete pod <pod-name> -n week3-demo
```

`get pods -w` (watch mode) was used specifically while diagnosing the stuck rollout in Problem 8, to observe the pod's status transitions live rather than repeatedly re-running a plain `get`. `describe pod` was the primary diagnostic tool for both Problem 7 (surfacing the exact `ImageInspectError` message and CRI-O runtime identity) and Problem 8 (surfacing the `Init:0/1` stuck state and its associated events). The manual `kubectl delete pod` was the immediate unblock for Problem 8, ahead of the durable `strategy: type: Recreate` fix.

**Final teardown (Kubernetes layer, strictly before Terraform — Section 12.3):**

```
kubectl delete -f k8s\service.yaml
kubectl delete -f k8s\deployment.yaml
kubectl delete -f k8s\pvc.yaml
kubectl delete -f k8s\storageclass.yaml
kubectl delete -f k8s\namespace.yaml
terraform destroy
```

---

## Closing Note

This document was written to capture not just *what* was built this week, but *why* each decision was made and exactly how each real problem encountered along the way was actually diagnosed and fixed — with the intent that it could be handed to someone else (or re-read months later) as a complete, standalone account of the Week 3 OKE/Terraform/Kubernetes lab, needing no other context. Every piece of Terraform and Kubernetes source code reproduced above reflects the actual, final, working state of the files as they exist in this project, and every problem, error message, and fix described in Section 13 reflects something that genuinely happened during this engagement rather than a hypothetical or idealized account.

As with everything else in this project, this document was written entirely by the assistant working alongside the user, and — consistent with the user's standing instruction covering the whole engagement — was never staged, committed, or pushed to any version control system by the assistant; that remains solely the user's own action to take, if and when they choose to.

