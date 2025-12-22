module "eks" {
  source = "../../modules/eks"

  project_name       = var.project_name
  env                = var.env
  cluster_name       = "${var.project_name}-${var.env}-eks"
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.app_subnet_ids
  security_group_ids = [module.security_groups.app_sg_id]
  access_cidrs       = var.access_cidrs
}
