output "lambda_function_arn" {
  description = "The ARN of the DR Failover Lambda function"
  value       = aws_lambda_function.failover.arn
}

output "lambda_function_name" {
  description = "The name of the DR Failover Lambda function"
  value       = aws_lambda_function.failover.function_name
}
