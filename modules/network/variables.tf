variable "project_name" {}
variable "env" {}
variable "vpc_cidr" {}
variable "azs" { type = list(string) }
variable "nat_count" { type = number }
variable "cluster_name" { description = "EKS Cluster Name for tagging" }
