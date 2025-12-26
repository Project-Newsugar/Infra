# EKS가 설치되었다고 해도, 내부의 EBS 드라이버가 실제로 작동하려면 시간이 필요합니다.
# 안전하게 120초 정도 뜸을 들입니다.
resource "time_sleep" "wait_for_ebs_csi_driver" {
  create_duration = "120s" # 2분 대기

  # EKS 모듈(EBS 드라이버 포함)이 다 만들어진 후 타이머 시작
  depends_on = [module.eks]
}

module "observability" {
  source = "../../modules/observability"  # 모듈 경로 주의 (상위로 두 번 이동)

  cluster_name           = module.eks.cluster_name
  grafana_admin_password = var.grafana_admin_password
  
  # gp3 사용 설정 (기본값이 gp3라면 생략 가능하지만 명시 권장)
  storage_class_name     = "gp3"
  enable_persistence     = true

  # 대시보드용 변수 (일단 null로 두어도 대시보드는 생성됨)
  alb_arn_suffix         = null

  db_cluster_identifier  = "newsugar-prod-aurora-cluster"
  # 모듈 간 연결: App Services에서 만든 SNS Topic 연결
  sns_topic_arn          = module.app_services.sns_topic_arn


  # EKS(compute)가 다 만들어지고 '타이머'가 끝난 뒤에 EBS CSI Driver까지 깔린 후 실행
  depends_on = [time_sleep.wait_for_ebs_csi_driver]
}
