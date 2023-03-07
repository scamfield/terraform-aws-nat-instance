locals {
  subnet_pairs = [for p in setproduct(var.public_subnet_ids, var.private_subnet_ids) : [p[0], p[1]]
    if data.aws_subnet.subnets[p[0]].availability_zone == data.aws_subnet.subnets[p[1]].availability_zone
  ]
  public_to_private_subnets_mapping = zipmap([for p in local.subnet_pairs : p[0]], [for p in local.subnet_pairs : p[1]])

  tags = {
    Name        = var.name
    Terraform   = "true"
    Application = "nat-instance"
  }
}
