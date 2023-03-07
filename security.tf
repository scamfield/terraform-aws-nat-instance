resource "aws_security_group" "sg_nat" {
  description = "The security group for the NAT instance"
  name        = "nat"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = format("%s-nat-instance", var.name)
  })
}

resource "aws_security_group_rule" "sgr_nat_inbound" {
  description       = "Inbound"
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.sg_nat.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "sgr_nat_out" {
  description       = "Outbound"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  security_group_id = aws_security_group.sg_nat.id
  cidr_blocks       = ["0.0.0.0/0"]
}
