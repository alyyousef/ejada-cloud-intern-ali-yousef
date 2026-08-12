resource "oci_load_balancer_load_balancer" "app_lb" {
  compartment_id = local.my_compartment_id
  display_name   = "${local.name_prefix}-lb-${local.owner}"
  shape          = "flexible"

  shape_details {
    minimum_bandwidth_in_mbps = var.lb_min_bandwidth_mbps
    maximum_bandwidth_in_mbps = var.lb_max_bandwidth_mbps
  }

  subnet_ids    = [oci_core_subnet.tier["public"].id]
  is_private    = false
  freeform_tags = local.common_freeform_tags
}

resource "oci_load_balancer_backend_set" "app_backend_set" {
  name             = "${local.name_prefix}-backend-set-${local.owner}"
  load_balancer_id = oci_load_balancer_load_balancer.app_lb.id
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "HTTP"
    port              = var.app_port
    url_path          = "/"
    return_code       = 200
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}

resource "oci_load_balancer_backend" "app_backend" {
  load_balancer_id = oci_load_balancer_load_balancer.app_lb.id
  backendset_name  = oci_load_balancer_backend_set.app_backend_set.name
  ip_address       = oci_core_instance.linux_instance.private_ip
  port             = var.app_port
}

resource "oci_load_balancer_listener" "app_listener" {
  load_balancer_id         = oci_load_balancer_load_balancer.app_lb.id
  name                     = "${local.name_prefix}-listener-${local.owner}"
  default_backend_set_name = oci_load_balancer_backend_set.app_backend_set.name
  port                     = 80
  protocol                 = "HTTP"
}
