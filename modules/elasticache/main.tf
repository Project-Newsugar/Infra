# 1. Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-${var.env}-redis-subnet-group"
  subnet_ids = var.subnet_ids
}

# 2. Redis Replication Group (Cluster Mode Disabled)
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project_name}-${var.env}-redis"
  description          = "Newsugar Redis Replication Group"
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_nodes # 2개 (Primary + Replica)
  
  port                 = 6379
  parameter_group_name = "default.redis7" # Redis 7.0
  
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = var.security_group_ids

  automatic_failover_enabled = var.num_cache_nodes > 1 ? true : false

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # 실습 편의상 false (운영 시 true 권장)
  auto_minor_version_upgrade = true
}
