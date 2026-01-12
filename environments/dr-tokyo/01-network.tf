module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  env          = var.env
  vpc_cidr     = var.vpc_cidr
  azs          = var.azs
  nat_count    = var.nat_count
  
  # EKS 클러스터 태깅용 (Subnet 태그)
  cluster_name = "${var.project_name}-${var.env}-eks"
}
