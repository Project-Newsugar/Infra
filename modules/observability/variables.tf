variable "cluster_name" {
  description = "EKS Cluster Name (for tagging / naming)"
  type        = string
}

variable "namespace" {
  description = "Namespace to install observability stack"
  type        = string
  default     = "monitoring"
}

variable "chart_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "56.6.0"
}

variable "grafana_admin_password" {
  description = "Password for Grafana admin user"
  type        = string
  sensitive   = true
}

variable "enable_persistence" {
  description = "Enable Prometheus PVC persistence (requires EBS CSI Driver + StorageClass)"
  type        = bool
  default     = false
}

variable "storage_class_name" {
  description = "StorageClass for Prometheus PVC (e.g., gp3 or gp2)"
  type        = string
  default     = "gp3"
}

variable "prometheus_storage_size" {
  description = "Prometheus PVC size"
  type        = string
  default     = "10Gi"
}

variable "timeout_seconds" {
  description = "Helm release timeout seconds"
  type        = number
  default     = 900
}

variable "grafana_service_type" {
  description = "Grafana service type (ClusterIP/LoadBalancer/NodePort)"
  type        = string
  default     = "ClusterIP"
}

# ALB Suffix (값이 없으면 대시보드/알람 생성 안함)
variable "alb_arn_suffix" {
  description = "ALB ARN Suffix for CloudWatch Dashboard & Alarm"
  type        = string
  default     = null
}

# 하드코딩 제거를 위한 DB 식별자 변수
variable "db_cluster_identifier" {
  description = "RDS Aurora Cluster Identifier"
  type        = string
  default     = null
}

# 알림을 보낼 SNS Topic ARN (app_services 모듈에서 받아옴)
variable "sns_topic_arn" {
  description = "SNS Topic ARN for Alarms"
  type        = string
  default     = null
}
