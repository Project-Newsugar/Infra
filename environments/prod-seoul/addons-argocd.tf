# [Helm] ArgoCD 설치
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.51.6"

  # 초기 접근을 위해 LoadBalancer 타입으로 노출 (운영 시 Ingress 전환 권장)
  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }
  
  set {
    name  = "server.insecure"
    value = "true"
  }

  depends_on = [module.eks]
}
