# 1. SNS Topic (장애 알림 채널)
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.env}-alerts-topic"
}

# 3. EventBridge Bus (이벤트 버스) - 필요 시 확장
resource "aws_cloudwatch_event_bus" "main" {
  name = "${var.project_name}-${var.env}-event-bus"
}

# 4. (예시) DR Failover 등을 위한 Lambda 함수용 IAM Role
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-${var.env}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Lambda용 기본 로깅 정책 연결
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------
# [Future Plan] 슬랙(Slack) 및 디스코드(Discord) 알림 확장 가이드
# ---------------------------------------------------------

# 1) Slack 연동 (AWS Chatbot 사용 권장)
# resource "awscc_chatbot_slack_channel_configuration" "slack" {
#   configuration_name = "slack-alerts"
#   iam_role_arn       = aws_iam_role.chatbot.arn
#   slack_channel_id   = "C012345678" # 슬랙 채널 ID
#   slack_workspace_id = "T012345678" # 슬랙 워크스페이스 ID
#   sns_topic_arns     = [aws_sns_topic.alerts.arn]
# }

# 2) Discord 연동 (Lambda 사용 필요 - AWS Chatbot 미지원)
# resource "aws_lambda_function" "discord_notifier" {
#   function_name = "${var.project_name}-discord-alert"
#   handler       = "index.handler"
#   runtime       = "python3.9"
#   # ... (Discord Webhook URL을 환경변수로 주입하여 SNS 이벤트를 디스코드 포맷으로 변환 전송)
# }
#
# resource "aws_sns_topic_subscription" "discord_lambda" {
#   topic_arn = aws_sns_topic.alerts.arn
#   protocol  = "lambda"
#   endpoint  = aws_lambda_function.discord_notifier.arn
# }
