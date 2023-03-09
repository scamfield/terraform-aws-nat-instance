resource "aws_iam_instance_profile" "nat_profile" {
  name = "${var.name}-nat-profile"
  role = aws_iam_role.role.name
}

resource "aws_iam_role" "role" {
  name = "${var.name}-nat-role"
  path = "/"

  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["*"]
      type        = "AWS"
    }
    effect = "Allow"
  }
}

resource "aws_iam_role_policy" "modify_routes" {
  name = "NATModifyRoutes"
  role = aws_iam_role.role.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowCreateRoute",
        "Effect" : "Allow",
        "Action" : "ec2:CreateRoute",
        "Resource" : [
          for subnet_id, route_table in data.aws_route_table.private : "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:route-table/${route_table.id}"
        ]
      },
      {
        "Sid" : "AllowDescribeInstancesNetworkInterfacesSubnetsAndRouteTables",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowPublishSnsTopic",
        "Effect" : "Allow",
        "Action" : "sns:Publish",
        "Resource" : aws_sns_topic.nat_failover_topic.arn
      }
    ]
  })
}

resource "aws_iam_role" "nat_failover_lambda" {
  name = "nat-failover-lambda-role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

resource "aws_iam_policy" "nat_failover_lambda_policy" {
  name        = "NATFailoverLambdaPolicy"
  path        = "/"
  description = "IAM policy for nat failover lambda"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeSubnets",
                "ec2:DescribeRouteTables",
                "ec2:ReplaceRoute"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/nat-failover-recovery:*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "nat_failover_lambda" {
  role       = aws_iam_role.nat_failover_lambda.name
  policy_arn = aws_iam_policy.nat_failover_lambda_policy.arn
}
