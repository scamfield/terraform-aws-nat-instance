resource "aws_lambda_function" "nat_failover_lambda" {
  filename         = "${path.module}/src/nat-failover-recovery.zip"
  source_code_hash = filebase64sha256("${path.module}/src/nat-failover-recovery.zip")
  function_name    = "nat-failover-recovery"
  role             = aws_iam_role.nat_failover_lambda.arn
  handler          = "nat-failover-recovery.lambda_handler"
  runtime          = "python3.9"
  memory_size      = 128
  timeout          = 3
  architectures    = ["arm64"]

  environment {
    variables = {
      REGION = data.aws_region.current.name
    }
  }

  tags = merge(local.tags, {
    "Run Time" = "24x7"
  })
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nat_failover_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.nat_failover_topic.arn
}

resource "aws_lambda_permission" "allow_event_bridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nat_failover_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.nat_instance_asg_rule.arn
}
