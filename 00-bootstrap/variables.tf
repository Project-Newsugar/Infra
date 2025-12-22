variable "project_name" {
  description = "Project Name"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
}

variable "bucket_name" {
  description = "Terraform State 저장용 S3 버킷 이름 (전세계 유일해야 함)"
  type        = string
}

variable "dynamodb_name" {
  description = "Terraform Locking용 DynamoDB 테이블 이름"
  type        = string
}

