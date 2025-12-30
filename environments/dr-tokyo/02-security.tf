module "security_groups" {
  source = "../../modules/security_groups"

  project_name = var.project_name
  env          = var.env
  vpc_id       = module.network.vpc_id
}
