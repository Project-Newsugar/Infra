resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = var.namespace
  create_namespace = true
  version          = var.chart_version

  # 재구축 반복 안정성
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.timeout_seconds

  # 비밀번호는 set_sensitive로
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  # Grafana Service 타입 (기본 ClusterIP)
  set {
    name  = "grafana.service.type"
    value = var.grafana_service_type
  }

  # EKS 환경에서 중복/권한 이슈 나는 것들 비활성화
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

  # Prometheus PVC (필요 시만 켜기)
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

