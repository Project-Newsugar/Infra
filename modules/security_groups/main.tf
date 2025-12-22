# 1. ALB SG (외부 -> ALB)
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.env}-alb-sg"
  description = "Allow HTTP/HTTPS inbound"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.env}-alb-sg" }
}

# 2. App SG (ALB -> EKS Pods)
resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.env}-app-sg"
  description = "Allow access from ALB"
  vpc_id      = var.vpc_id

  # ALB에서의 접근만 허용 (8080)
  ingress {
    description     = "Traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  # 노드 간 통신 허용 (Self Reference)
  # 이게 없으면 파드 생성, DNS 조회 등 클러스터 내부 동작이 실패.
  ingress {
    description = "Allow self communication (Nodes/Pods)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # 모든 프로토콜
    self        = true # 자기 자신(app-sg)을 가진 리소스끼리는 허용
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.env}-app-sg" }
}

# 3. DB SG (App -> RDS)
resource "aws_security_group" "db" {
  name        = "${var.project_name}-${var.env}-db-sg"
  description = "Allow MySQL access from App"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from App"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  
  # S3 백업, OS 업데이트 등을 위해 아웃바운드 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.env}-db-sg" }
}

# 4. Cache SG (App -> Redis)
resource "aws_security_group" "cache" {
  name        = "${var.project_name}-${var.env}-cache-sg"
  description = "Allow Redis access from App"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from App"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # 필수
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.env}-cache-sg" }
}
