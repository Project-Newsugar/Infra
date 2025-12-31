# 1. Aurora RDS (MySQL)
module "database" {
  source = "../../modules/database"

  project_name      = var.project_name
  env               = var.env
  vpc_id            = module.network.vpc_id
  
  is_primary = true

  # Private Data Subnet에 배치 (보안 필수)
  subnet_ids        = module.network.data_subnet_ids
  
  # DB Security Group 적용
  security_group_ids = [module.security_groups.db_sg_id]
  
  # tfvars에서 입력받은 값 전달
  db_name           = var.db_name
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  master_username   = var.db_master_username
  instance_count    = var.db_instance_count
  skip_final_snapshot = var.db_skip_final_snapshot

  # [피드백 반영] Global Cluster 생성 활성화
  create_global_cluster     = var.db_enable_global_cluster
  global_cluster_identifier = var.db_global_identifier
}

# 2. ElastiCache (Redis)
module "elasticache" {
  source = "../../modules/elasticache"

  project_name      = var.project_name
  env               = var.env
  
  # Private Data Subnet에 배치
  subnet_ids        = module.network.data_subnet_ids
  
  # Cache Security Group 적용
  security_group_ids = [module.security_groups.cache_sg_id]
  
  node_type         = var.redis_node_type
  num_cache_nodes   = var.redis_num_cache_nodes
}
