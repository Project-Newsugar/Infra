#!/bin/bash
set -e

# === 사용법 안내 ===
usage() {
  echo "사용법: $0 [ seoul | all ]"
  echo "  seoul : 서울 리전(Primary)만 배포"
  echo "  all   : 서울 + 도쿄 리전 모두 배포"
  exit 1
}

# 인자가 없으면 사용법 출력
if [ -z "$1" ]; then
  usage
fi

MODE=$1
# [중요] setup.sh 파일과 environments 폴더 사이의 경로 관계를 정의합니다.
# 현재 구조상 setup.sh가 레포 루트(Infra/)에 있고 environments/가 같은 레벨에 있으므로:
BASE_DIR="environments"

# === 배포 함수 ===
deploy_region() {
  local TARGET=$1        # 예: prod-seoul
  local REGION_CODE=$2   # 예: ap-northeast-2
  local CLUSTER_NAME=$3  # 예: newsugar-prod-eks

  echo "============================================"
  echo " [$TARGET] 배포 시작..."
  echo "============================================"

  local TF_PATH="$BASE_DIR/$TARGET"
  
  # 경로 유효성 체크
  if [ ! -d "$TF_PATH" ]; then
    echo "❌ 에러: $TF_PATH 폴더를 찾을 수 없습니다."
    echo "   현재 위치: $(pwd)"
    echo "   확인할 경로: $TF_PATH"
    return 1
  fi

  # 1. Terraform init & apply
  echo "Terraform 실행 중... (경로: $TF_PATH)"
  terraform -chdir="$TF_PATH" init
  terraform -chdir="$TF_PATH" apply -auto-approve

  # 2. Kubeconfig 업데이트
  echo "Kubeconfig 업데이트 ($CLUSTER_NAME)"
  aws eks update-kubeconfig --region "$REGION_CODE" --name "$CLUSTER_NAME"

  # 3. aws-auth 적용
  # 우선순위 1: 해당 환경 폴더 내의 aws-auth.yaml
  # 우선순위 2: 스크립트가 있는 현재 위치의 aws-auth.yaml
  if [ -f "$TF_PATH/aws-auth.yaml" ]; then
    echo "aws-auth 적용 (환경별 설정: $TF_PATH/aws-auth.yaml)"
    kubectl apply -f "$TF_PATH/aws-auth.yaml"
  elif [ -f "aws-auth.yaml" ]; then
    echo "aws-auth 적용 (공통 설정: aws-auth.yaml)"
    kubectl apply -f "aws-auth.yaml"
  else
    echo "⚠️ aws-auth.yaml 파일을 찾을 수 없어 권한 설정을 건너뜁니다."
  fi
  
  echo "[$TARGET] 배포 완료!"
  echo ""
}

# === 메인 실행 로직 ===
case "$MODE" in
  seoul)
    deploy_region "prod-seoul" "ap-northeast-2" "newsugar-prod-eks"
    ;;
  all)
    echo "전체 리전(Seoul + Tokyo) 순차 배포를 시작합니다."
    deploy_region "prod-seoul" "ap-northeast-2" "newsugar-prod-eks"
    deploy_region "dr-tokyo" "ap-northeast-1" "newsugar-dr-eks"
    ;;
  *)
    usage
    ;;
esac

echo "모든 작업이 성공적으로 끝났습니다!"
