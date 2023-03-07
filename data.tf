data "aws_ami" "ami" {
  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "name"
    values = ["debian-11*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  most_recent = true
  owners      = [136693071363]
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_subnet" "eni_subnet" {
  for_each = aws_network_interface.eni

  id = each.value.subnet_id
}

data "aws_subnet" "first" {
  id = var.public_subnet_ids[0]
}

data "aws_subnet" "subnets" {
  for_each = toset(concat(var.private_subnet_ids, var.public_subnet_ids))
  id       = each.value
}

data "aws_vpc" "vpc" {
  id = data.aws_subnet.first.vpc_id
}

data "template_cloudinit_config" "cloudinit" {
  for_each      = toset(var.private_subnet_ids)
  base64_encode = true
  gzip          = true

  part {
    content      = data.template_file.cloudinit_base.rendered
    content_type = "text/cloud-config"
    merge_type   = "dict(recurse_array)+list(append)"
  }
}

data "template_file" "cloudinit_base" {
  template = file("${path.module}/templates/cloudinit_base.tpl")

  vars = {
    nat_script_file    = base64gzip(data.template_file.nat_failover_trigger_script.rendered)
    nat_add_route_file = base64gzip(data.template_file.nat_add_route_script.rendered)
    nat_systemd_file   = base64gzip(data.template_file.nat_failover_systemd.rendered)
    vpc_cidr           = data.aws_vpc.vpc.cidr_block
  }
}

data "template_file" "nat_failover_systemd" {
  template = file("${path.module}/templates/etc/systemd/system/nat-failover.service.tpl")
}

data "template_file" "nat_failover_trigger_script" {
  template = file("${path.module}/templates/usr/local/bin/nat-failover-trigger.py.tpl")

  vars = {
    sns_arn = aws_sns_topic.nat_failover_topic.arn
  }
}

data "template_file" "nat_add_route_script" {
  template = file("${path.module}/templates/usr/local/bin/add_default_route.py.tpl")
}
