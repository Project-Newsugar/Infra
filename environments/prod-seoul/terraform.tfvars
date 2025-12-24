# 공통
project_name = "newsugar"
env          = "prod"
region       = "ap-northeast-2"

# 네트워크
vpc_cidr     = "192.168.0.0/16"
azs          = ["ap-northeast-2a", "ap-northeast-2c"]
nat_count    = 2

# EKS
access_cidrs = ["0.0.0.0/0"]

# Database (Aurora MySQL)
db_name            = "news_db"
db_engine_version  = "8.0.mysql_aurora.3.08.2" # Aurora MySQL 3.08 (MySQL 8.0 호환)
db_instance_class  = "db.t3.medium"
db_master_username = "admin"
# 1 = Writer만(빠르게 테스트), 2 = Writer+Reader(운영/HA)
db_instance_count  = 1
db_skip_final_snapshot = true

# 서울 리전 배포 시 Global Cluster도 같이 만듦
db_enable_global_cluster = false
db_global_identifier     = null
# "newsugar-global-db"

# Redis (ElastiCache)
redis_node_type       = "cache.t3.micro"
redis_num_cache_nodes = 2                      # HA 구성 (Primary + Replica)

# [Observability] Grafana 관리자 비밀번호 (보안 주의)
grafana_admin_password = "admin_password_secret_123!"

# [EKS] Cluster Name (이미 있다면 생략)
cluster_name = "newsugar-prod-eks"

