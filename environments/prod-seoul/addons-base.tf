# [Helm] AWS Load Balancer Controller 설치

# 1. IAM Role for ALB Controller (IRSA)
module "lb_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  # 버전을 5.x로 고정하여 경로 오류 방지
  version = "~> 5.0"
  role_name                              = "${var.project_name}-${var.env}-${var.region}-eks-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}



# 2. Helm Release
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.1" 

  timeout = 600

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lb_role.iam_role_arn
  }
  
  # Metrics Server도 여기에 포함 가능 (구조상 addons-base이므로)
  # EKS뿐만 아니라 IRSA Role까지 다 만들어진 뒤 실행
  depends_on = [
    module.eks,
    module.lb_role
  ]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.1"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
  
  depends_on = [module.eks]
}

# === External Secrets Operator (ESO) ===

# 1 IAM Policy for Secrets Manager
resource "aws_iam_policy" "eso_secretsmanager" {
  name        = "${var.project_name}-${var.env}-${var.region}-eso-policy"
  description = "Allow ESO to read from AWS Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
      # KMS를 사용한 Secret이면 아래 권한이 필요할 수 있음
      # {
      #   Effect   = "Allow"
      #   Action   = ["kms:Decrypt"]
      #   Resource = "*"
      # }
    ]
  })
}

# 2 IRSA Role for ESO
module "eso_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-${var.env}-${var.region}-eso-role"

  role_policy_arns = {
    eso = aws_iam_policy.eso_secretsmanager.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}

# 3 Helm Release for ESO
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.10.5"

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eso_role.iam_role_arn
  }

  depends_on = [
    module.eks,
    module.eso_role
  ]
}

# 4 ClusterSecretStore 자동 생성 (K8s Manifest)
resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secretsmanager-global"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          # 변수를 사용하여 서울/도쿄 리전 자동 적용
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }
  # 중요: ESO(Helm Chart)가 먼저 설치되어야 CRD(ClusterSecretStore)를 인식할 수 있음
  depends_on = [helm_release.external_secrets]
}
