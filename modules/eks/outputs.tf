output "cluster_name" { value = aws_eks_cluster.main.name }
output "cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "cluster_certificate_authority_data" { value = aws_eks_cluster.main.certificate_authority[0].data }

output "oidc_provider_arn" { 
  description = "EKS IRSA OIDC Provider ARN"
  value       = aws_iam_openid_connect_provider.eks_irsa.arn 
}

output "oidc_provider_url" { 
  value = aws_iam_openid_connect_provider.eks_irsa.url 
}

# Provider 설정 시 필요한 토큰
output "cluster_auth_token" {
  value = data.aws_eks_cluster_auth.cluster.token
  # 주의: main.tf에 data "aws_eks_cluster_auth" "cluster" { name = aws_eks_cluster.main.name } 추가 필요할 수 있음.
  # 만약 토큰 오류가 계속되면 provider.tf에서 exec 플러그인을 쓰는 방식으로 전환해야 함.
  # 일단은 2단계 배포(EKS 완료 후 Addon) 전략이므로 패스해도 됨.
}

output "node_group_name" {
  description = "EKS node group name"
  value       = aws_eks_node_group.main.node_group_name
}
