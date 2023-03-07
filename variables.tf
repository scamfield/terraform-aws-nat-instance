variable "name" {
  type    = string
  default = "default"
}

variable "instance_type" {
  type    = string
  default = "t4g.micro"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)

  validation {
    condition = (
      length(var.public_subnet_ids) >= 2
    )
    error_message = "To achieve high availability, you will require a minimum of two public subnets."
  }
}

variable "private_subnet_ids" {
  type = list(string)

  validation {
    condition = (
      length(var.private_subnet_ids) >= 2
    )
    error_message = "To achieve high availability, you will require a minimum of two private subnets."
  }
}

variable "aws_key_name" {
  type    = string
  default = ""
}
