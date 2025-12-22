variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "env" {
  description = "Environment (prod/dev/dr)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}
