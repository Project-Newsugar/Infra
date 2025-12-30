# 배포 후 터미널에 중요한 ID들을 출력해주는 파일

# 1. 네트워크 및 보안 그룹 정보 (기존 내용)
output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnets" {
  value = module.network.public_subnet_ids
}

output "private_app_subnets" {
  value = module.network.app_subnet_ids
}

output "alb_security_group_id" {
  value = module.security_groups.alb_sg_id
}

output "app_security_group_id" {
  value = module.security_groups.app_sg_id
}

output "db_security_group_id" {
  value = module.security_groups.db_sg_id
}

# 2. [필수] EKS 접속 정보 (이게 있어야 kubectl 사용 가능)
output "eks_cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API 서버 엔드포인트"
  value       = module.eks.cluster_endpoint
}

# 3. [편의 기능] 접속 테스트 명령어 가이드
output "configure_kubectl_command" {
  description = "kubectl 설정 명령어"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# 4. Database & Redis Endpoints
output "rds_writer_endpoint" {
  description = "Aurora Writer Endpoint (앱 연결용)"
  value       = module.database.endpoint
}

output "rds_reader_endpoint" {
  description = "Aurora Reader Endpoint"
  value       = module.database.reader_endpoint
}

output "redis_primary_endpoint" {
  description = "Redis Primary Endpoint"
  value       = module.elasticache.primary_endpoint
}

# 5. Secrets Manager ARN (앱에서 비밀번호 가져올 때 사용)
output "db_secret_arn" {
  description = "Secrets Manager ARN for DB Auth"
  value       = module.database.secret_arn
}

# 도쿄 리전 구축 시 이 ID가 필요함
output "rds_global_cluster_id" {
  description = "Aurora Global Cluster ID (For DR Region)"
  value       = module.database.global_cluster_id
}
