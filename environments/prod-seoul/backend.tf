terraform {
  backend "s3" {
    # bootstrap에서 정의한 이름과 일치시킴
    bucket         = "newsugar-tf-state-team4-v1"
    key            = "prod/seoul/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "newsugar-tf-lock"
    encrypt        = true
  }
}
