variable "project_name" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment (e.g., prod, dr)"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
}

variable "eks_region" {
  description = "EKS Cluster Region"
  type        = string
}

variable "global_cluster_identifier" {
  description = "RDS Global Cluster Identifier to failover"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS Cluster Name to scale up"
  type        = string
}

variable "eks_node_group_name" {
  description = "EKS Node Group Name to scale up"
  type        = string
}
