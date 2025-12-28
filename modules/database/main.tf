# 1. DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.env}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = { Name = "${var.project_name}-${var.env}-db-subnet-group" }
}

# 2. Random Password (보안을 위해, 비번 자동 생성)
resource "random_password" "master" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
# 2-1. 시크릿 이름 충돌 방지용 랜덤 접미사
resource "random_id" "secret_suffix" {
  byte_length = 4
}

# 3. Secrets Manager (비밀번호 저장)
resource "aws_secretsmanager_secret" "db_auth" {
  # 고정 이름 + 랜덤 접미사 (예: newsugar/prod/db/auth-a1b2c3d4)
  # 고정된 이름 사용 (앱이 찾기 쉽도록)
  name = "${var.project_name}/${var.env}/db/auth-${random_id.secret_suffix.hex}"
  
  # 즉시 삭제 설정 (테스트 편의성)
  # destroy 시 즉시 삭제되므로, 바로 다시 apply 해도 이름 충돌이 안 난다.
  # (나중에 최종 운영 전환 시에만 7일로 변경)
  description = "RDS Master Credentials"
  recovery_window_in_days = 0 

  tags = {
    Name = "${var.project_name}-${var.env}-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db_auth" {
  secret_id     = aws_secretsmanager_secret.db_auth.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "aurora-mysql"
    host     = aws_rds_cluster.main.endpoint
  })
}

# Global Cluster 생성 (서울 리전용)
resource "aws_rds_global_cluster" "main" {
  count                     = var.create_global_cluster ? 1 : 0
  global_cluster_identifier = var.global_cluster_identifier
  engine                    = "aurora-mysql"
  engine_version            = var.engine_version
  storage_encrypted         = true
}

# 4. Aurora Cluster
resource "aws_rds_cluster" "main" {
  cluster_identifier      = "${var.project_name}-${var.env}-aurora-cluster"
  engine                  = "aurora-mysql"
  engine_version          = var.engine_version

  # Global Cluster에 소속되도록 설정
  global_cluster_identifier = var.create_global_cluster ? aws_rds_global_cluster.main[0].id : var.global_cluster_identifier
  database_name           = var.db_name
  master_username         = var.master_username
  master_password         = random_password.master.result
  
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = var.security_group_ids
  
  # 스냅샷 변수로 제어. true 안찍고 삭제, false 찍고 삭제
  skip_final_snapshot     = var.skip_final_snapshot
  # 스냅샷 찍을 경우를 대비해 식별자 지정
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-${var.env}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  storage_encrypted       = true

# 스냅샷 이름이 시간 때문에 바뀌어도 무시하도록 설정
  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }  
  tags = { Name = "${var.project_name}-${var.env}-aurora" }
}

# 5. Aurora Instances (Writer + Reader)
resource "aws_rds_cluster_instance" "cluster_instances" {
  count              = var.instance_count
  identifier         = "${var.project_name}-${var.env}-aurora-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
  
  publicly_accessible = false
}
