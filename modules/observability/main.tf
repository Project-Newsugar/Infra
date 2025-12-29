# 0. 현재 리전 정보 가져오기 (자동 감지)
data "aws_region" "current" {}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = var.namespace
  create_namespace = true
  version          = var.chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = var.timeout_seconds

  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "grafana.service.type"
    value = var.grafana_service_type
  }

  # 불필요한 리소스 비활성화
  set {
    name  = "coreDns.enabled"
    value = "false"
  }
  set {
    name  = "kubeDns.enabled"
    value = "false"
  }
  set {
    name  = "kubeControllerManager.enabled"
    value = "false"
  }
  set {
    name  = "kubeEtcd.enabled"
    value = "false"
  }
  set {
    name  = "kubeScheduler.enabled"
    value = "false"
  }

  # Prometheus PVC 설정
  dynamic "set" {
    for_each = var.enable_persistence ? [1] : []
    content {
      name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName"
      value = var.storage_class_name
    }
  }
  dynamic "set" {
    for_each = var.enable_persistence ? [1] : []
    content {
      name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]"
      value = "ReadWriteOnce"
    }
  }
  dynamic "set" {
    for_each = var.enable_persistence ? [1] : []
    content {
      name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
      value = var.prometheus_storage_size
    }
  }
}

# ---------------------------------------------------------
# CloudWatch Dashboard (리전 자동 감지 적용)
# ---------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.cluster_name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      # 1. ALB 섹션
      {
        type   = "metric"
        x      = 0
        y = 0
        width = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix != null ? var.alb_arn_suffix : "loading...", { "stat" : "Sum", "period" : 60 }],
            [".", "TargetResponseTime", ".", ".", { "stat" : "p95", "period" : 60 }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { "stat" : "Sum", "period" : 60, "color": "#d62728" }]
          ]
          # 현재 리전을 자동으로 사용
          region = data.aws_region.current.name
          title  = "ALB Traffic & Performance"
        }
      },
      # 2. RDS 섹션
      {
        type   = "metric"
        x      = 0
        y = 6
        width = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", var.db_cluster_identifier != null ? var.db_cluster_identifier : "loading...", { "stat" : "Average", "period" : 60 }],
            [".", "DatabaseConnections", ".", ".", { "stat" : "Maximum", "period" : 60 }]
          ]
          # 현재 리전을 자동으로 사용
          region = data.aws_region.current.name
          title  = "Aurora DB Load"
        }
      },
      {
        type   = "metric"
        x      = 12
        y = 6
        width = 12
        height = 6
        properties = {
          metrics = [
             # 변수 사용
            ["AWS/RDS", "AuroraReplicaLag", "DBClusterIdentifier", var.db_cluster_identifier != null ? var.db_cluster_identifier : "loading...", { "stat" : "Maximum", "period" : 60, "label": "Replica Lag (ms)" }]
          ]
          view    = "timeSeries"
          stacked = false
          # 현재 리전을 자동으로 사용
          region  = data.aws_region.current.name
          title   = "Aurora Replica Lag"
        }
      },
      # 3. EKS Node 섹션
      {
        type   = "metric"
        x      = 0
        y = 12
        width = 24
        height = 6
        properties = {
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", var.cluster_name, { "stat" : "Average", "period" : 60 }],
            ["ContainerInsights", "node_memory_utilization", "ClusterName", var.cluster_name, { "stat" : "Average", "period" : 60 }],
            ["ContainerInsights", "pod_cpu_utilization", "ClusterName", var.cluster_name, { "stat" : "Average", "period" : 60 }]
          ]
          view    = "timeSeries"
          stacked = false
          # 현재 리전을 자동으로 사용
          region  = data.aws_region.current.name
          title   = "EKS Cluster Resources (Requires CloudWatch Agent)"
        }
      }
    ]
  })
}

# ---------------------------------------------------------
# CloudWatch Alarms
# ---------------------------------------------------------

# 1. [사이트 터짐] ALB 5xx 에러 급증 알람
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count               = var.alb_arn_suffix != null ? 1 : 0
  
  alarm_name          = "${var.cluster_name}-ALB-5XX-High"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_description = "ALB returned 5XX errors. Backend might be down."
  alarm_actions     = [var.sns_topic_arn]
  ok_actions        = [var.sns_topic_arn]
}

# 2. [서버 과부하] DB CPU 부하 알람
resource "aws_cloudwatch_metric_alarm" "db_cpu_high" {
  count               = var.db_cluster_identifier != null ? 1 : 0

  alarm_name          = "${var.cluster_name}-DB-CPU-High"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 75
  
  dimensions = {
    DBClusterIdentifier = var.db_cluster_identifier
  }

  alarm_description = "Database CPU is high (>75%). System overload."
  alarm_actions     = [var.sns_topic_arn]
  ok_actions        = [var.sns_topic_arn]
}
