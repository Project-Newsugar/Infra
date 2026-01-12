variable "project_name" {}
variable "env" {}
variable "region" {}

# 프론트/백엔드 레포지토리 이름을 리스트로 받음
variable "ecr_repo_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
}

# GitHub 조직/레포지토리 경로 (OIDC 인증용)
variable "github_repos" {
  description = "List of GitHub repositories (org/repo) allowed to push to ECR"
  type        = list(string)
}

# ECR 도쿄로 자동 복제 위한 변수
variable "is_primary" {
  description = "Primary region flag"
  type        = bool
}
