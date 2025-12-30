   #!/bin/bash
   set -e

   # === 사용법 안내 ===
   usage() {
     echo "사용법: $0 [seoul|tokyo|all]"
     echo "  seoul : 서울 리전만 삭제"
     echo "  all   : 서울 + 도쿄 리전 모두 삭제 (도쿄 -> 서울 순서)"
     exit 1
   }

   if [ -z "$1" ]; then
     usage
   fi

   MODE=$1
   BASE_DIR="environments"

   # === 삭제 함수 ===
   get_vpc_id() {
     terraform -chdir="$TF_PATH" state show module.network.aws_vpc.main 2>/dev/null | awk '$1=="id"{print $3}'
   }

   cleanup_vpc_deps() {
     local VPC_ID=$1
     local CLUSTER_NAME=$2
     if [ -z "$VPC_ID" ]; then
       echo "⚠️ VPC ID를 찾지 못해 VPC 의존 리소스 정리를 건너뜁니다."
       return
     fi

     echo " NAT Gateway 삭제 시도..."
     NAT_IDS=$(aws ec2 describe-nat-gateways \
       --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
       --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)
     for NAT_ID in $NAT_IDS; do
       aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" >/dev/null 2>&1 || true
     done

     echo " NAT 삭제 전파 대기..."
     for _ in 1 2 3 4 5; do
       NAT_LEFT=$(aws ec2 describe-nat-gateways \
         --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,deleting,available" \
         --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)
       [ -z "$NAT_LEFT" ] && break
       sleep 20
     done

     echo " 남은 ENI 정리 시도..."
     ENI_IDS=$(aws ec2 describe-network-interfaces \
       --filters \
         "Name=vpc-id,Values=$VPC_ID" \
         "Name=status,Values=available" \
         "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned,shared" \
       --query 'NetworkInterfaces[].NetworkInterfaceId' \
       --output text 2>/dev/null)
     for ENI_ID in $ENI_IDS; do
       aws ec2 delete-network-interface --network-interface-id "$ENI_ID" >/dev/null 2>&1 || true
     done
   }
   destroy_region() {
     local TARGET=$1
     local REGION_CODE=$2
     local CLUSTER_NAME=$3
     local VAR_FILE=$4

     echo "============================================"
     echo " [$TARGET] 삭제 프로세스 시작..."
     echo "============================================"

     local TF_PATH="$BASE_DIR/$TARGET"

     # 1. [청소] K8s LoadBalancer & Ingress 삭제 (ALB/NLB 제거)
     #    이걸 먼저 안 지우면 VPC가 절대 안 지워짐!
     echo "[1/4] K8s 로드밸런서 리소스 정리 중..."

     # Kubeconfig 갱신 (접속 가능할 때만 시도)
     if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION_CODE" >/dev/null 2>&1; then
       aws eks update-kubeconfig --region "$REGION_CODE" --name "$CLUSTER_NAME"

       # Ingress와 LoadBalancer 타입 서비스 강제 삭제
       # (오류가 나도 무시하고 계속 진행하도록 || true 붙임)
       kubectl delete ingress --all --all-namespaces --timeout=20s || true
       kubectl delete svc --all --all-namespaces --field-selector spec.type=LoadBalancer --timeout=20s || true

       echo " AWS가 로드밸런서를 삭제하는 동안 30초 대기..."
       sleep 30
     else
       echo " 클러스터가 이미 없거나 접속 불가. K8s 리소스 정리 스킵."
     fi

     # 2. Terraform Destroy 시도
     echo " [2/4] Terraform Destroy 실행..."

     # 실패하더라도 스크립트가 멈추지 않도록 set +e 잠시 적용
     set +e
     # 변수 파일이 있으면 적용하여 destroy
     if [ -n "$VAR_FILE" ] && [ -f "$TF_PATH/$VAR_FILE" ]; then
       terraform -chdir="$TF_PATH" destroy -auto-approve -var-file="$VAR_FILE"
     else
       terraform -chdir="$TF_PATH" destroy -auto-approve
     fi
     EXIT_CODE=$?
     set -e

     # 3. [에러 핸들링] Helm/K8s 관련 에러로 실패했을 경우
     if [ $EXIT_CODE -ne 0 ]; then
       echo " Terraform Destroy 실패! (아마도 Helm/EKS 연결 끊김 문제)"
       echo " [3/4] Helm State 강제 제거 후 재시도..."

       # EKS가 죽었는데 Helm 제거를 시도하다 에러나는 경우, State에서만 지워줌
       terraform -chdir="$TF_PATH" state rm helm_release.aws_load_balancer_controller || true
       terraform -chdir="$TF_PATH" state rm helm_release.argocd || true
       terraform -chdir="$TF_PATH" state rm module.eks.kubernetes_config_map_v1_data.aws_auth || true

       # VPC 의존 리소스 정리 (NAT/ENI) 후 재시도
       VPC_ID=$(get_vpc_id)
       cleanup_vpc_deps "$VPC_ID" "$CLUSTER_NAME"

       # 다시 Destroy 시도
       echo " [4/4] Terraform Destroy 재실행..."
       # 재시도 시에도 변수 파일 적용
       if [ -n "$VAR_FILE" ] && [ -f "$TF_PATH/$VAR_FILE" ]; then
         terraform -chdir="$TF_PATH" destroy -auto-approve -var-file="$VAR_FILE"
       else
         terraform -chdir="$TF_PATH" destroy -auto-approve
       fi
     fi

     echo " [$TARGET] 삭제 완료!"
     echo ""
   }

   # === 메인 실행 로직 ===
   # 삭제는 생성의 역순! (도쿄 먼저 지우고 서울 지우기)
   case "$MODE" in
     seoul)
       destroy_region "prod-seoul" "ap-northeast-2" "newsugar-prod-eks"
       ;;
     all)
       echo " 전체 리전(Seoul + Tokyo) 삭제를 시작합니다."
       destroy_region "dr-tokyo" "ap-northeast-1" "newsugar-dr-eks"
       destroy_region "prod-seoul" "ap-northeast-2" "newsugar-prod-eks" "global-db.tfvars"
       ;;
     *)
       usage
       ;;
   esac

   echo "모든 리소스가 삭제되었습니다."
