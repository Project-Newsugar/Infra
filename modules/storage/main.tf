# 1. ECR Repository 생성 (Frontend, Backend)
resource "aws_ecr_repository" "repos" {
  for_each             = toset(var.ecr_repo_names)
  name                 = each.value
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = each.value }
}

# 수명 주기 정책 추가 (이미지 10개만 남기고 삭제 -> 비용 절감)
resource "aws_ecr_lifecycle_policy" "main" {
  for_each   = aws_ecr_repository.repos
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection    = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ECR Cross-Region Replication (Primary only)
resource "aws_ecr_replication_configuration" "main" {
  count = var.is_primary ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = "ap-northeast-1" # 도쿄
        registry_id = data.aws_caller_identity.current.account_id
      }
    }
  }
}

# OIDC Provider를 "생성"하지 않고 "조회"만 함 (중복 방지)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
# 3. GitHub Actions용 IAM Role
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-${var.env}-${var.region}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        # data 소스로 조회한 ARN 사용
        Federated = data.aws_iam_openid_connect_provider.github.arn
      }
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            for repo in var.github_repos : "repo:${repo}:*"
          ]
        }
      }
    }]
  })
}

# 4. ECR Push 권한 부여
resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 로그인 권한 (Resource = "*" 필수)
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      # 나머지 조작 권한 (우리가 만든 Repo만 허용)
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        # "*" 대신, 우리가 만든 레포지토리들의 ARN만 허용
        Resource = [for repo in aws_ecr_repository.repos : repo.arn]
      }
    ]
  })
}
