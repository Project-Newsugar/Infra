# 1. EKS Cluster IAM Role (Control Plane용)
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# 2. EKS Cluster 생성
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = []
    endpoint_private_access = true
    endpoint_public_access  = true # 실습 편의상 Public 허용
    public_access_cidrs     = var.access_cidrs 
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# 3. Node Group IAM Role (Worker Node용)
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}
resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}
resource "aws_iam_role_policy_attachment" "node_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# 4. 노드 그룹 설정을 위한 Launch Template
resource "aws_launch_template" "node" {
  name = "${var.cluster_name}-node-lt"

  vpc_security_group_ids = concat(
    var.security_group_ids, 
    [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-node"
    }
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }
}

# 5. Managed Node Group 생성 (t3.medium)
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  # Launch Template 연결 (이게 있어야 SG가 노드에 붙음)
  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  force_update_version = true

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"] # 비용 절감 (또는 t3.small)

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_registry,
  ]
}

# 6. OIDC Provider (AWS Load Balancer Controller 등을 위해 필수)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_irsa" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# 7. Cluster Auth Data Source (필수 추가)
# 이 블록이 있어야 outputs.tf에서 토큰 값을 가져올 수 있습니다.
data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.name
}

# 8. EKS Add-ons (CoreDNS, Kube-proxy, VPC-CNI)
# 이미 설치된 애드온을 Terraform 관리하에 두기 위해 OVERWRITE 설정 필수
# 순서: Node Group 생성 -> VPC-CNI 설치 -> CoreDNS/Kube-proxy 설치

# 1 VPC-CNI (가장 중요: 노드가 생기면 바로 네트워크부터 깔아야 함)
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  # 노드 그룹이 완전히 다 만들어진 뒤에 설치
  depends_on = [aws_eks_node_group.main]
}

# 2 CoreDNS (네트워크가 있어야 DNS가 작동함)
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  # CNI(네트워크)가 설치가 끝난 뒤에 DNS를 띄우게 설정
  depends_on = [aws_eks_node_group.main, aws_eks_addon.vpc_cni]
}

# 3 Kube-proxy (네트워크 규칙 관리)
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"

  # 이것도 노드랑 CNI가 있어야 함
  depends_on = [aws_eks_node_group.main, aws_eks_addon.vpc_cni]
}
