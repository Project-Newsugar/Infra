variable "project_name" {}
variable "env" {}
variable "vpc_id" {}
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "db_name" {}
variable "engine_version" {}
variable "instance_class" {}
variable "master_username" {}

# 비용/시간 절감을 위해 인스턴스 개수 조절 (테스트=1, 운영=2)
variable "instance_count" {
  description = "DB instances 1 or 2 (Writer/Reader)"
  type        = number
  default     = 1
}

# 테스트 시 스냅샷 생성을 건너뛰기 위한 스위치 변수
variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying DB (true for test, false for prod)"
  type        = bool
  default     = true # 기본값은 안전하게 테스트 모드
}

# Global Cluster 생성 여부 제어
variable "create_global_cluster" {
  description = "Create Aurora Global Cluster (True for Primary Region)"
  type        = bool
  default     = false
}

# Global Cluster 식별자
variable "global_cluster_identifier" {
  description = "Global Cluster Identifier (Required if create_global_cluster is true)"
  type        = string
  default     = null
}

# 현재 리전이 Primary(Writer)인지 여부
variable "is_primary" {
  description = "Primary region flag for Aurora Global DB"
  type        = bool
  default     = false
}

variable "source_region" {
  description = "Source Region for Secondary Cluster (e.g. ap-northeast-2)"
  type        = string
  default     = null
}

variable "replication_source_identifier" {
  description = "Primary cluster ARN for creating a secondary cluster"
  type        = string
  default     = null
}
