resource "aws_autoscaling_group" "asg" {
  for_each = aws_launch_template.launch_template

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  launch_template {
    id      = each.value.id
    version = each.value.latest_version
  }

  availability_zones = [data.aws_subnet.eni_subnet[each.key].availability_zone]
}

resource "aws_eip" "eip" {
  for_each = aws_network_interface.eni

  vpc               = true
  network_interface = each.value.id
}

resource "aws_launch_template" "launch_template" {
  for_each = aws_network_interface.eni

  name_prefix = format("%s-nat-instance-%s", var.name, data.aws_subnet.subnets[each.key].availability_zone)

  image_id      = data.aws_ami.ami.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.nat_profile.arn
  }

  user_data = data.template_cloudinit_config.cloudinit[local.public_to_private_subnets_mapping[each.key]].rendered

  key_name = var.aws_key_name

  network_interfaces {
    delete_on_termination = false
    network_interface_id  = each.value.id
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.tags, {
      Name = format("%s-nat-instance-%s", var.name, substr(data.aws_subnet.subnets[each.key].availability_zone, -1, 1))
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_network_interface" "eni" {
  for_each = toset(var.public_subnet_ids)

  subnet_id         = each.value
  security_groups   = [aws_security_group.sg_nat.id]
  source_dest_check = false

  tags = merge(local.tags, {
    Name = format("%s-nat-instance", var.name)
  })
}
