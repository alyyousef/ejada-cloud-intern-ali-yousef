# Ejada OCI + Terraform Internship — Week 2 Full Summary (context for Week 3)

Paste this whole file into a new chat at the start of Week 3 so Claude has full context
without re-deriving it.

## Who / Where

- Intern: Ali Yousef (aliyousef.aca@gmail.com)
- Program: Ejada, Cloud Build track
- OCI compartment: `intern-02-ali-youssef-cmp`, region **Saudi Arabia West (Jeddah)** (`me-jeddah-1`)
- GitHub repo: `github.com/alyyousef/ejada-cloud-intern-ali-yousef` (branch `main`), `weekOne/` and
  `weekTwo/` folders inside it, do not touch `weekOne/`
- Local Terraform project: `C:\Users\yinya\Documents\oci-terraform-lab\weekTwo\`
- Local documentation project (separate git repo, separately maintained):
  `C:\D-\Internships\ejada\weekTwo\documentationW2\`
- SSH keypair used throughout: `C:\Users\yinya\.ssh\oci_vm` / `oci_vm.pub` (Ed25519)

## Week 2 Assignment (real text, from the team)

**Part A — OCI Concepts & Architecture:** Application Tier Architecture (web/app/db/storage
tiers, public vs private vs isolated subnets), Load Balancer Concepts (listener, backend set,
health check, end-to-end traffic flow), Connecting to Private VMs (compare OCI Cloud Shell,
Jump VM, OCI Bastion Service, SSH port forwarding/tunneling).

**Part B — Terraform Intermediate Concepts:** Variables & tfvars, Local Values, `count` and
`for_each`, BONUS Dynamic Blocks, Lifecycle Rules (`ignore_changes`, `prevent_destroy`), The
State File, `terraform state mv`, `terraform import`, The `moved` Block, Remote State (Object
Storage backend).

**Deliverables required:** push to GitHub in a new folder (don't remove Week 1 code);
documentation with a **draw.io diagram using official OCI icon libraries**; and critically,
**Step 1 — build the resources manually in the OCI Console first** (especially the load
balancer), understand each piece, **then destroy and rebuild the same thing with Terraform**
(Step 2), rather than only ever doing it through Terraform.

## What's Actually Done

### 1. Terraform code (`weekTwo/*.tf`)

Full refactor demonstrating every Part B concept: `variables.tf`, `locals.tf`, `main.tf`
(VCN/subnets/security lists via `for_each` and nested `dynamic` blocks), `loadbalancer.tf`,
`bastion.tf` (written, but **never successfully applied** — see IAM gap below),
`moved.tf`, `import_demo.tf`, `outputs.tf`, `provider.tf` (remote Object Storage backend
documented, left commented out). All comments were stripped per explicit request. `terraform
state mv` and `terraform import` (against a manually-created NSG) were both demoed live
earlier in the week. A full `terraform destroy` was run successfully (18 resources destroyed).

**Current state: `terraform.tfstate` is empty (0 resources).** The real
`tf-lab-*-AliYousef` environment is **not currently deployed**. `terraform apply` needs to be
re-run to bring it back up and capture final Step 2 evidence/screenshots, unless that already
happened between sessions.

### 2. Manual Console Build — Step 1 (`explore-*` resources)

Built by hand, prefixed `explore-` to avoid confusion with Terraform's `tf-lab-*` naming:
VCN, IGW, NAT gateway, two route tables, two security lists (six ingress rules per list,
hand-typed to mirror what the `dynamic` block generates), two subnets, `explore-linux`
compute instance in the private subnet with no public IP, and a File Storage stack
(`explore-fs`, `explore-mount-target`, `/explore-export`).

**Two real environment findings hit and documented, not fabricated:**

- **Bastion IAM policy gap.** Creating a Bastion against `explore-private-subnet` failed
  silently. Browser DevTools showed `POST .../20210331/bastions -> 404
  NotAuthorizedOrNotFound`. The Identity & Security → Policies page in this compartment threw
  the identical error just trying to *list* policies, confirming the account can't even read
  IAM policy state here, not just create Bastion resources. **This needs a tenancy admin to
  add a policy** (`Allow group <group> to manage bastion-family in compartment
  intern-02-ali-youssef-cmp`). Reported to the team in the Week 2 status update.
  **Unresolved as of end of Week 2.**
- **Cloud Shell's FIPS-restricted SSH client rejected the Ed25519 key.** Per the supervisor's
  direction, used OCI Cloud Shell (attached directly into `explore-vcn` via a private network
  definition) as the path into the private instance instead of Bastion. Cloud Shell's bundled
  OpenSSH (`8.0p1`, FIPS-restricted OpenSSL) refused to sign with the Ed25519 key
  (`sign_and_send_pubkey: no mutual signature supported`) since FIPS mode disallows
  Curve25519. Fixed by generating a fresh RSA keypair inside Cloud Shell and delivering its
  public half to `explore-linux` via OCI's **Run Command** instance-agent plugin (since SSH
  itself wasn't the working path yet). **SSH access confirmed working after this fix.**
- Also caught and fixed mid-build: a copy-paste bug where 5 of 6 ingress rules on
  `explore-private-sl` had inherited the wrong source CIDR (`10.1.1.0/24` instead of
  `10.1.0.0/16`) from the port-8080 rule typed just above them.
- The load balancer (Phase 4 of the walkthrough) and a jump-box workaround were both
  **never actually built** — abandoned once the Cloud Shell path started working.

**Current state: teardown of all `explore-*` resources is in progress, not finished.**
Already deleted: a stray auto-created duplicate mount target/export, `explore-public-subnet`.
`explore-private-subnet` deletion was blocked by a lingering VNIC reference (either
`explore-linux` not fully finished terminating, or `explore-cloudshell-net`'s network
definition still attached) — this needs to be resolved and the rest of the teardown finished:
subnets → gateways → route tables → security lists → VCN last, in that dependency order.
**Check this first in Week 3 before assuming the compartment is clean.**

### 3. Documentation — two efforts exist, only one is real

- **Obsolete, do not use:** an earlier two-PDF (Part A / Part B) LaTeX attempt was built
  mid-session, but its final compiled output never made it out of a scratch/temp directory and
  is effectively lost. Not a deliverable, don't reference it.
- **The actual, final documentation:** a pre-existing, separately-maintained LaTeX
  thesis-style project at `C:\D-\Internships\ejada\weekTwo\documentationW2\` (its own git repo,
  distinct from `oci-terraform-lab`). Uses the `book` class; chapters: `overview`,
  `context_and_sources`, `approach`, `findings`, `takeaways`, `next_steps`, `appendix`,
  `bibliography`. A new section, **"3.1 Manual Console Build Before Automation,"** was added to
  `chapters/approach.tex`, with 12 curated OCI Console screenshots (copied into `Figures/` as
  `step1_*.png`) documenting the `explore-*` build and both findings above. Verified to compile
  cleanly (57 pages, no errors) in a throwaway test copy; also fixed one unrelated pre-existing
  bug in the real file (`Sections/01_class_and_packages.tex` was missing
  `\usepackage{ifthen}`, needed by `\setboolean` in `chapters/appendix.tex`).
  Master file: `Research_Thesis.tex` → `Research_Thesis.pdf`.
  **Status: the user said they're still actively working on this themselves** — not confirmed
  finalized/compiled/delivered as of end of Week 2. Its relationship to the main
  `oci-terraform-lab` GitHub repo (separate repo vs. needs merging/copying in) was **not
  resolved** — clarify in Week 3.

### 4. draw.io diagram

`weekTwo/docs/Week2_Network_Diagram_Ali_Yousef.drawio` — rebuilt from scratch for full
symmetry, orthogonal `rounded=0` edges, explicit connection points, no em/en dashes anywhere.
Valid mxGraph XML. Pushed to GitHub.

### 5. GitHub

Confirmed pushed by the user (both the Terraform code / drawio / `Step1_Console_Walkthrough.md`
earlier, and their own local push after an `.git/index.lock` issue was resolved). `git status`
on `oci-terraform-lab` shows a clean working tree, up to date with `origin/main`.

### 6. Status email

A status email was drafted and sent to the team reporting Week 2 as complete and pushed,
including an honest note about the unresolved Bastion IAM policy gap. Keep future
communication consistent with what was actually claimed there.

## Open Items to Pick Up in Week 3

1. **Finish the `explore-*` teardown** (was mid-progress, blocked on a VNIC issue with
   `explore-private-subnet` at end of session).
2. **Bastion IAM policy gap is still unresolved** — check whether the team/tenancy admin has
   added the `bastion-family` policy yet.
3. **Re-apply Terraform** to bring the real `tf-lab-*-AliYousef` environment back up (state is
   currently empty) and capture the actual Step 2 deliverable evidence, if not already done.
4. **Finalize `documentationW2`'s `Research_Thesis.pdf`** and confirm where/how it actually
   gets delivered to the team (its repo is separate from the main one).
5. Stale/unclear internal tracking items from earlier in the week that may now be superseded:
   Week 1 documentation handoff, a generic Week 2 checklist rewrite (likely replaced by
   `documentationW2` at this point — confirm rather than assume).

## Key Paths Reference

- Terraform: `C:\Users\yinya\Documents\oci-terraform-lab\weekTwo\*.tf`
- Step 1 walkthrough doc: `C:\Users\yinya\Documents\oci-terraform-lab\weekTwo\docs\Step1_Console_Walkthrough.md`
- draw.io diagram: `C:\Users\yinya\Documents\oci-terraform-lab\weekTwo\docs\Week2_Network_Diagram_Ali_Yousef.drawio`
- Documentation project (separate repo): `C:\D-\Internships\ejada\weekTwo\documentationW2\`
- Documentation master file: `documentationW2\Research_Thesis.tex`
- SSH key: `C:\Users\yinya\.ssh\oci_vm` / `oci_vm.pub`
