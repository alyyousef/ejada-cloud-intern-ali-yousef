# subnet module

Creates one OCI subnet along with its own route table, security list, and
(optionally) a VCN flow log. Every value that could differ between a public
LB subnet, a private worker subnet, or a private pod subnet is passed in
through variables - nothing here is hardcoded to a specific environment, so
the same module is called four times from the Week 3 root config (endpoint,
workers, pods, load balancer) with different inputs.

## Resources created

- `oci_core_subnet.this`
- `oci_core_route_table.this` (rules built with a `dynamic "route_rules"` block)
- `oci_core_security_list.this` (ingress/egress rules built with `dynamic` blocks,
  each with nested `dynamic "tcp_options" / "udp_options" / "icmp_options"` blocks
  that only render when that option object is actually supplied)
- `oci_logging_log.flow_log` (count-gated on `var.enable_logs`; this is the
  conditional-resource pattern, since OCI has no native "no-op" flow log)

## Example call

```hcl
module "workers_subnet" {
  source = "./modules/subnet"

  compartment_id       = var.compartment_id
  vcn_id                = oci_core_vcn.this.id
  subnet_display_name  = "oke-workers-subnet"
  subnet_cidr_block    = "10.0.16.0/20"
  dns_label             = "workers"
  is_public             = false

  route_table_display_name   = "oke-workers-rt"
  security_list_display_name = "oke-workers-sl"

  route_rules = [
    {
      destination       = "0.0.0.0/0"
      network_entity_id = oci_core_nat_gateway.this.id
    }
  ]

  ingress_rules = [
    {
      source      = var.vcn_cidr_block
      protocol    = "6"
      description = "Kubelet / control plane traffic"
      tcp_options = { min = 10250, max = 10250 }
    }
  ]

  egress_rules = [
    {
      destination = "0.0.0.0/0"
      protocol    = "all"
      description = "Allow all outbound"
    }
  ]

  enable_logs   = var.enable_flow_logs
  log_group_id  = var.log_group_id
  freeform_tags = var.freeform_tags
}
```

See `variables.tf` for the full shape of `route_rules`, `ingress_rules`, and
`egress_rules` - each is a plain list of objects, so the root config can
generate them however it wants (hardcoded, `for_each` over a map, etc.).
