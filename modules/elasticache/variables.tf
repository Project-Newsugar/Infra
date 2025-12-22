variable "project_name" {}
variable "env" {}
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "node_type" {}
variable "num_cache_nodes" { type = number }
