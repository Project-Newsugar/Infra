output "sns_topic_arn" {
  description = "ARN of the SNS alert topic"
  value       = aws_sns_topic.alerts.arn
}

output "event_bus_name" {
  description = "Name of the EventBridge bus"
  value       = aws_cloudwatch_event_bus.main.name
}
