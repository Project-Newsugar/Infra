provider "aws" {
  region = var.region
}

# 1. State 저장용 S3 버킷
resource "aws_s3_bucket" "tf_state" {
  bucket = var.bucket_name # 변수 사용

  tags = {
    Name = "Terraform State Storage"
  }
}

# 1-1. 버킷 버전 관리 (실수 방지)
resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 2. Locking용 DynamoDB 테이블
resource "aws_dynamodb_table" "tf_lock" {
  name         = var.dynamodb_name # 변수 사용
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID" # Terraform 규칙으로 변경 금지

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "Terraform Lock Table"
  }
}

# 3. 출력값 (나중에 backend.tf에 넣을 값 확인용)
output "s3_bucket_name" {
  value = aws_s3_bucket.tf_state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}

# [피드백 반영] GitHub Actions OIDC Provider (계정 전역 설정)
# 이 리소스는 리전과 상관없이 계정에 딱 하나만 존재해야 하므로 여기서 생성합니다.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

output "github_oidc_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

