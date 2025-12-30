terraform {
  backend "s3" {
    # bootstrap에서 정의한 이름과 일치시킴
    bucket         = "newsugar-tf-state-team4-v1"
    key            = "dr/tokoy/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "newsugar-tf-lock"
    encrypt        = true
  }
}
