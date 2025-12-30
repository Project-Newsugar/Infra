module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  env          = var.env

  region = var.region

  # 생성할 ECR 리포지토리 이름 (Frontend, Backend)
  ecr_repo_names = [
    "${var.project_name}-frontend",
    "${var.project_name}-backend"
  ]

  # GitHub Actions 권한을 줄 레포지토리 (User/Repo)
  github_repos = [
    "Project-Newsugar/newsugar-frontend",
    "Project-Newsugar/newsugar-backend"
  ]
}
