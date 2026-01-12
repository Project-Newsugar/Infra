provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

module "app_services" {
  source = "../../modules/app_services"

  project_name = var.project_name
  env          = var.env

}

module "lambda" {
    source = "../../modules/lambda"

    providers = {
      aws = aws.use1
    }

    project_name              = var.project_name
    env                       = var.env
    region                    = "us-east-1"
    eks_region                = var.region
    global_cluster_identifier = var.db_global_identifier
    eks_cluster_name          = var.eks_cluster_name
    eks_node_group_name       = var.eks_node_group_name
}

# Route53 Health Check (us-east-1)
resource "aws_route53_health_check" "seoul_primary" {
  provider          = aws.use1
  fqdn              = var.healthcheck_fqdn
  port              = 80
  type              = "HTTP"
  resource_path     = var.healthcheck_path
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "${var.project_name}-seoul-health-check" }
}

# CloudWatch Alarm (us-east-1)
resource "aws_cloudwatch_metric_alarm" "seoul_health_alarm" {
  provider            = aws.use1
  alarm_name          = "${var.project_name}-seoul-down-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1

  dimensions = {
    HealthCheckId = aws_route53_health_check.seoul_primary.id
  }
}

# EventBridge Rule (us-east-1)
resource "aws_cloudwatch_event_rule" "dr_trigger_rule" {
  provider = aws.use1
  name     = "${var.project_name}-dr-trigger-rule"
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"],
    detail-type = ["CloudWatch Alarm State Change"],
    detail = {
      alarmName = ["${var.project_name}-seoul-down-alarm"],
      state     = { value = ["ALARM"] }
    }
  })
}

# EventBridge Target -> Lambda (us-east-1)
resource "aws_cloudwatch_event_target" "dr_lambda_target" {
  provider = aws.use1
  rule     = aws_cloudwatch_event_rule.dr_trigger_rule.name
  arn      = module.lambda.lambda_function_arn
}

# Lambda Permission (allow EventBridge)
resource "aws_lambda_permission" "allow_eventbridge" {
  provider     = aws.use1
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dr_trigger_rule.arn
}
