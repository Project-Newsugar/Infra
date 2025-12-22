# --- 프로젝트 공통 ---
variable "project_name" {
  description = "Project Name Prefix"
  type        = string
}

variable "env" {
  description = "Environment (prod/dev/dr)"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
}

# --- 네트워크 (VPC) ---
variable "vpc_cidr" {
  description = "VPC CIDR Block"
  type        = string
}

variable "azs" {
  description = "Availability Zones"
  type        = list(string)
}

variable "nat_count" {
  description = "Number of NAT Gateways"
  type        = number
}

# --- EKS (Compute) ---
variable "access_cidrs" {
  description = "Public Access CIDRs for EKS API"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Database (Aurora RDS) ---
variable "db_name" {
  description = "Database Name"
  type        = string
}

variable "db_engine_version" {
  description = "Aurora MySQL Engine Version"
  type        = string
}

variable "db_instance_class" {
  description = "RDS Instance Class"
  type        = string
}

variable "db_master_username" {
  description = "DB Master Username"
  type        = string
}

# --- ElastiCache (Redis) ---
variable "redis_node_type" {
  description = "ElastiCache Node Type"
  type        = string
}

variable "redis_num_cache_nodes" {
  description = "Number of Redis Cache Nodes"
  type        = number
}

# DB 인스턴스 개수 제어용 변수
variable "db_instance_count" {
  description = "Number of DB Instances (Writer + Reader)"
  type        = number
  default     = 1 # 생성 삭제를 반복하는 테스트용을 write 1 운영시 2(read 1 추가)
}

# DB 삭제 시 최종 스냅샷 생성 여부 (테스트=true, 운영=false)
variable "db_skip_final_snapshot" {
  description = "Skip final snapshot when destroying DB"
  type        = bool
  default     = true
}

# Global DB 설정
variable "db_enable_global_cluster" {
  description = "Enable Aurora Global Database"
  type        = bool
  default     = false
}

variable "db_global_identifier" {
  description = "Identifier for Global Database"
  type        = string
  default     = "newsugar-global-db"
}

