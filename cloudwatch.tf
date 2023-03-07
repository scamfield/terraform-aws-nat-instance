resource "aws_cloudwatch_event_rule" "nat_instance_asg_rule" {
  name        = "nat-failure-recovery-rule"
  description = "Trigger NAT failover/recovery when EC2 instance event happens within Auto Scaling"

  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail_type = ["EC2 Instance Launch Successful", "EC2 Instance Terminate Successful"]
    detail = {
      "AutoScalingGroupName" : [for asg in aws_autoscaling_group.asg : asg.name]
    }
  })
}

resource "aws_cloudwatch_event_target" "event_bridge_target" {
  rule      = aws_cloudwatch_event_rule.nat_instance_asg_rule.name
  arn       = aws_lambda_function.nat_failover_lambda.arn
  target_id = "nat_failover_lambda"
}

resource "aws_cloudwatch_log_group" "nat_failover_logs" {
  name              = "/aws/lambda/${aws_lambda_function.nat_failover_lambda.function_name}"
  retention_in_days = 7
}
