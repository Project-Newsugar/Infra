module "app_services" {
  source = "../../modules/app_services"

  project_name = var.project_name
  env          = var.env

}
