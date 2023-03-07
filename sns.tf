resource "aws_sns_topic" "nat_failover_topic" {
  name = "nat-failover-recovery-topic"
}

resource "aws_sns_topic_subscription" "nat_failover_lambda" {
  topic_arn = aws_sns_topic.nat_failover_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.nat_failover_lambda.arn
}
