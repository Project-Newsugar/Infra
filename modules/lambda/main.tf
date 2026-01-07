data "aws_caller_identity" "current" {}

# 1. Lambda Code Packaging
data "archive_file" "failover_code" {
  type        = "zip"
  source_file = "${path.module}/failover.py"
  output_path = "${path.module}/failover.zip"
}

# 2. IAM Role for Lambda
resource "aws_iam_role" "dr_lambda_role" {
  name = "${var.project_name}-${var.env}-dr-failover-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# 3. IAM Policies (Logs, RDS, EKS)
resource "aws_iam_role_policy" "dr_lambda_policy" {
  name = "dr-failover-permissions"
  role = aws_iam_role.dr_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudWatch Logs
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        # RDS Global Cluster Control
        Effect = "Allow"
        Action = [
          "rds:DescribeGlobalClusters",
          "rds:FailoverGlobalCluster",
          "rds:RemoveFromGlobalCluster" # In case failover isn't possible
        ]
        Resource = "*"
      },
      {
        # EKS Node Scaling
        Effect = "Allow"
        Action = [
          "eks:DescribeNodegroup",
          "eks:UpdateNodegroupConfig"
        ]
        Resource = "arn:aws:eks:${var.eks_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.eks_cluster_name}/*"
      }
    ]
  })
}

# 4. Lambda Function
resource "aws_lambda_function" "failover" {
  filename         = data.archive_file.failover_code.output_path
  function_name    = "${var.project_name}-${var.env}-dr-failover"
  role             = aws_iam_role.dr_lambda_role.arn
  handler          = "failover.lambda_handler"
  runtime          = "python3.14"
  source_code_hash = data.archive_file.failover_code.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      GLOBAL_CLUSTER_ID   = var.global_cluster_identifier
      EKS_CLUSTER_NAME    = var.eks_cluster_name
      EKS_NODE_GROUP_NAME = var.eks_node_group_name
      TARGET_CAPACITY     = "2" # Default target capacity for DR activation
      TARGET_REGION = var.eks_region
    }
  }
}
