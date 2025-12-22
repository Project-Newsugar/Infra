variable "project_name" {}
variable "env" {}
variable "cluster_name" {}
variable "vpc_id" {}
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "access_cidrs" {
  description = "Public Access CIDRs"
  type        = list(string)
  default     = ["0.0.0.0/0"] # 기본은 전체 허용
}
