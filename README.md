![Terraform](https://img.shields.io/badge/Terraform-1.3+-623CE4?logo=terraform&style=flat-square) ![AWS](https://img.shields.io/badge/AWS-EKS-orange?logo=amazon-aws&style=flat-square) ![Kubernetes](https://img.shields.io/badge/Kubernetes-1.27+-blue?logo=kubernetes&style=flat-square)

## 인프라 레포 소개  
이 레포는 AWS 상에서 EKS 기반 서비스를 배포하기 위한 Terraform 인프라 구성을 담고 있습니다.  
환경별 설정과 모듈화를 통해 반복 작업을 줄이고, 운영에 필요한 리소스를 일관되게 구성하도록 설계했습니다.  
구성 대상은 네트워크, EKS 클러스터, 데이터베이스, 스토리지, 관측/모니터링 리소스까지 포함합니다.

**자동화된 배포/삭제 흐름이 이 레포의 핵심입니다.**

---

### 프로젝트 구조
```text
Infra/
├── 00-bootstrap/           # Terraform backend (S3/DynamoDB) 초기 설정
├── environments/           # 환경별 인프라 배포 정의
│   ├── prod-seoul/         # Primary 리전 (서울)
│   └── dr-tokyo/           # DR 리전 (도쿄)
├── modules/                # 재사용 가능한 Terraform 모듈
│   ├── network/            # VPC, Subnet, NAT Gateway
│   ├── eks/                # EKS Cluster, Node Group, Add-ons
│   ├── database/           # Aurora RDS Global DB
│   ├── elasticache/        # Redis Cluster
│   ├── security_groups/    # SG 관리
│   ├── storage/            # ECR, GitHub Actions OIDC Role
│   ├── observability/      # CloudWatch, Prometheus/Grafana
│   └── lambda/             # DR Failover 자동화 로직
├── setup.sh                # 인프라 통합 배포 스크립트
├── destroy.sh              # 인프라 통합 삭제 스크립트
└── aws-auth.yaml           # EKS RBAC 권한 설정
```

---

### 개요  
- **Primary/DR 분리**: 서울(Primary)과 도쿄(DR) 환경을 분리해 장애 대응을 고려합니다.  
- **모듈화된 구성**: 네트워크/보안/EKS/DB/스토리지/관측 요소를 모듈로 분리합니다.  
- **자동화 스크립트**: `setup.sh`, `destroy.sh`로 배포/삭제 흐름을 표준화합니다.  

---

### 흐름  

#### 트래픽 흐름 (ASCII)  
```
User
  |
  v
ALB (aws-load-balancer-controller)
  |
  v
EKS Service -> Pods
  |
  +--> Aurora MySQL (Primary/Replica)
  |
  +--> ElastiCache Redis

Observability:
Pods -> Prometheus/Grafana (metrics)
DB/ALB -> CloudWatch Metrics/Alarms -> SNS Alerts
```

#### 개발자 배포 흐름 (ASCII)  
```
GitHub Actions
  |
  v
ECR (Primary)
  |
  v
EKS (Seoul/Tokyo) pulls image
```

#### 운영자 관측/알림 흐름 (ASCII)  
```
Prometheus/Grafana (Helm)
  |
  v
K8s Metrics

CloudWatch Dashboard/Alarm
  |
  v
SNS Alerts
```

#### DR 자동화 흐름 (ASCII)  
```
Route53 HealthCheck (Seoul)
  -> CloudWatch Alarm
     -> EventBridge Rule
        -> Lambda (us-east-1)
           - Global DB Failover
           - EKS NodeGroup Scale-up (Tokyo)
```

---

### 구성  

#### AWS 인프라 구성  
- **공통(전역)**: Terraform state 저장용 S3/DynamoDB, GitHub OIDC Provider (`00-bootstrap/main.tf`)  
- **Seoul(Primary)**: VPC/EKS/Aurora Primary/Redis/ECR Primary/관측 스택  
- **Tokyo(DR)**: VPC/EKS/Aurora Secondary/Redis/DR 자동화 Lambda  
- **리전 간 연계**: Aurora Global DB, ECR Cross-Region Replication  

#### 아키텍처 구성  
- **데이터 계층**: Aurora Global DB로 Primary/Secondary 복제  
- **컴퓨트 계층**: 각 리전 EKS 독립 구성, 필요 시 DR 스케일업  
- **관측/알림**: Prometheus/Grafana + CloudWatch Dashboard/Alarm + SNS  

#### 모듈별 상세 (핵심 리소스)  
- **network**: VPC, Public/App/Data Subnet, NAT, 라우팅  
- **security_groups**: ALB/App/DB/Cache 보안 그룹 분리  
- **eks**: EKS 클러스터, 노드그룹, 핵심 애드온  
- **database**: Aurora MySQL, Global DB 옵션, 비밀번호는 Secrets Manager에 저장  
- **elasticache**: Redis (Primary/Replica 구성)  
- **storage**: ECR 리포지토리, 이미지 수명주기 정책, GitHub Actions OIDC  
- **observability**: Prometheus/Grafana, CloudWatch 대시보드/알람  
- **app_services**: SNS 알림 채널, 이벤트 버스  
- **lambda**: DR Failover 자동화 함수    

---

### 자동화 스크립트  

#### setup.sh 자동화 범위  
1) 환경별 Terraform 초기화 및 apply 과정을 순차 실행합니다.  
2) 필요 시 Global DB 변수 파일을 적용해 서울/도쿄 구성을 연결합니다.  
3) EKS kubeconfig를 갱신해 이후 작업이 가능한 상태로 만듭니다.  
4) 매니페스트 적용 여부를 단계별로 분리해 안정적인 배포 흐름을 유지합니다.  
5) 마지막에 `aws-auth.yaml`을 적용해 접근 권한을 설정합니다.  

---

#### destroy.sh 자동화 범위  
1) EKS 리소스(서비스/Ingress/PVC 등)를 정리해 삭제 실패를 줄입니다.  
2) VPC 의존 리소스(LB, NAT, ENI 등)를 선제 정리합니다.  
3) Terraform state를 정리/갱신한 뒤 destroy를 실행합니다.  
4) 타임아웃 발생 시 정리 작업을 반복하고 재시도합니다.  
5) 서울/도쿄 삭제 순서를 고정해 안전성을 확보합니다.  

---

### 주요 특징  
- **자동화된 배포/삭제**: 스크립트로 반복 작업을 줄이고 흐름을 표준화했습니다.  
- **2단계 배포**: 인프라 먼저 생성 후 매니페스트를 적용해 안정성을 높입니다.  
- **재현 가능성**: 환경별 변수 파일로 동일한 구성을 반복 적용할 수 있습니다.  
- **운영 고려**: 삭제 시 의존 리소스까지 정리해 실패 가능성을 낮춥니다.  

---

## 일일 배포 가이드

### 사전 준비
- AWS CLI 설정 (aws configure 또는 SSO 로그인)
- Terraform 설치
- kubectl 설치

### 사용 방법
```bash
chmod +x setup.sh
./setup.sh seoul    # 서울(Primary)만 배포 (t3.medium)
./setup.sh all      # 서울 + 도쿄(DR) 순차 배포 (r6g.large, Global DB)
```

### 삭제 방법
- Infra 삭제전에 먼저 프론트엔드와 백엔드 자동화 시킨 ArgoCD 애플리케이션을 삭제한다. 
```bash
chmod +x destroy.sh
./destroy.sh seoul  # 서울 리전만 삭제
./destroy.sh all    # 도쿄 -> 서울 순서로 삭제
```

### 참고
- 레포 루트(Infra/)에서 실행하세요.
- "You must be logged in to the server" 오류가 나오면 AWS 로그인 상태와 aws-auth.yaml의 IAM ARN 등록을 확인하세요.
