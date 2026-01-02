#!/bin/bash
set -e

# === 사용법 안내 ===
usage() {
  echo "사용법: $0 [seoul|all]"
  echo "  seoul : 서울 리전만 삭제"
  echo "  all   : 서울 + 도쿄 리전 모두 삭제 (도쿄 -> 서울 순서)"
  exit 1
}

if [ -z "$1" ]; then
  usage
fi

MODE=$1
BASE_DIR="environments"
DESTROY_TIMEOUT=${DESTROY_TIMEOUT:-25m}
DESTROY_TIMEOUT_LONG=${DESTROY_TIMEOUT_LONG:-30m}

# === 삭제 함수 ===
tfvar_value() {
  local tf_path=$1
  local key=$2
  local tfvars_file="$tf_path/terraform.tfvars"

  if [ ! -f "$tfvars_file" ]; then
    return
  fi

  awk -F'=' -v k="$key" '
    $1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
      v=$2
      sub(/#.*/, "", v)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      gsub(/"/, "", v)
      print v
      exit
    }
  ' "$tfvars_file"
}

list_vpcs() {
  local region=$1
  aws ec2 describe-vpcs --region "$region" \
    --query "Vpcs[].{VpcId:VpcId,Cidr:CidrBlock,Name:Tags[?Key=='Name']|[0].Value}" \
    --output table 2>/dev/null || true
}

get_vpc_id() {
  local tf_path=$1
  local region=$2
  local cluster_name=$3
  local vpc_id

  vpc_id=$(terraform -chdir="$tf_path" state show module.network.aws_vpc.main 2>/dev/null | awk '$1=="id"{print $3}')
  if [ -n "$vpc_id" ]; then
    echo "$vpc_id"
    return
  fi

  if [ -n "$cluster_name" ]; then
    vpc_id=$(aws eks describe-cluster --region "$region" --name "$cluster_name" \
      --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null)
    if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
      echo "$vpc_id"
      return
    fi
  fi

  local project_name
  local env_name
  local vpc_cidr
  project_name=$(tfvar_value "$tf_path" "project_name")
  env_name=$(tfvar_value "$tf_path" "env")
  if [ -n "$project_name" ] && [ -n "$env_name" ]; then
    vpc_id=$(aws ec2 describe-vpcs --region "$region" \
      --filters "Name=tag:Name,Values=${project_name}-${env_name}-vpc" \
      --query "Vpcs[].VpcId" --output text 2>/dev/null | awk 'NF{print $1; exit}')
    if [ -n "$vpc_id" ]; then
      echo "$vpc_id"
      return
    fi
  fi

  vpc_cidr=$(tfvar_value "$tf_path" "vpc_cidr")
  if [ -n "$vpc_cidr" ]; then
    vpc_id=$(aws ec2 describe-vpcs --region "$region" \
      --filters "Name=cidr-block,Values=$vpc_cidr" \
      --query "Vpcs[].VpcId" --output text 2>/dev/null | awk 'NF{print $1; exit}')
    if [ -n "$vpc_id" ]; then
      echo "$vpc_id"
      return
    fi
  fi

  echo "⚠️ VPC ID 조회 실패. 현재 리전 VPC 목록:" >&2
  list_vpcs "$region" >&2
}

list_lb_arns() {
  aws elbv2 describe-load-balancers \
    --region "$REGION_CODE" \
    --query "LoadBalancers[?VpcId=='$CLEAN_VPC_ID'].LoadBalancerArn" \
    --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d'
}

wait_for_lbs_deleted() {
  local wait_seconds=$1
  local start
  start=$(date +%s)
  while true; do
    local lb_arns
    lb_arns=$(list_lb_arns)
    if [ -z "$lb_arns" ]; then
      break
    fi
    if [ $(( $(date +%s) - start )) -ge "$wait_seconds" ]; then
      echo "    로드밸런서 삭제 대기 시간 초과 (잔존 있음)"
      break
    fi
    sleep 20
  done
}

wait_for_nat_deleted() {
  local wait_seconds=$1
  local start
  start=$(date +%s)
  while true; do
    local nat_ids
    nat_ids=$(aws ec2 describe-nat-gateways --region "$REGION_CODE" \
      --filter "Name=vpc-id,Values=$CLEAN_VPC_ID" "Name=state,Values=pending,available,deleting" \
      --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)
    if [ -z "$nat_ids" ]; then
      break
    fi
    if [ $(( $(date +%s) - start )) -ge "$wait_seconds" ]; then
      echo "    NAT Gateway 삭제 대기 시간 초과 (잔존 있음)"
      break
    fi
    sleep 20
  done
}

cleanup_vpc_deps() {
  local VPC_ID=$1
  local CLUSTER_NAME=$2
  local REGION_CODE=$3

  # VPC ID 따옴표 제거 (안전장치)
  local CLEAN_VPC_ID
  CLEAN_VPC_ID=$(echo "$VPC_ID" | tr -d '"')

  if [ -z "$CLEAN_VPC_ID" ]; then
    echo "⚠️ VPC ID를 찾지 못해 VPC 의존 리소스 정리를 건너뜁니다."
    return
  fi

  echo "🔍 [강제 청소] VPC($CLEAN_VPC_ID, $REGION_CODE) 내부 잔존 리소스 스캔 및 삭제..."

  # 3회 반복 정리 (전파 지연 대비)
  for pass in 1 2 3; do
    echo "  - 청소 패스 ${pass}/3"

    # 1. 로드밸런서(ALB/NLB) 강제 삭제
    echo "    로드밸런서(ALB/NLB) 조회 및 삭제..."
    list_lb_arns | while read ARN;
 do
      if [ -z "$ARN" ] || [ "$ARN" == "None" ]; then continue; fi
      echo "      삭제 보호 해제 및 삭제 중: $ARN"
      aws elbv2 modify-load-balancer-attributes --region "$REGION_CODE" --load-balancer-arn "$ARN" --attributes Key=deletion_protection.enabled,Value=false >/dev/null 2>&1 || true
      aws elbv2 delete-load-balancer --region "$REGION_CODE" --load-balancer-arn "$ARN" >/dev/null 2>&1 || true
    done

    echo "      로드밸런서 삭제 상태 확인 및 대기..."
    wait_for_lbs_deleted 180

    # 2. 타겟 그룹 강제 삭제
    echo "    타겟 그룹(Target Group) 조회 및 삭제..."
    TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION_CODE" --query "TargetGroups[?VpcId=='$CLEAN_VPC_ID'].TargetGroupArn" --output text 2>/dev/null)
    for ARN in $TG_ARNS;
 do
      aws elbv2 delete-target-group --region "$REGION_CODE" --target-group-arn "$ARN" >/dev/null 2>&1 || true
    done

    # 3. VPC Endpoint 강제 삭제
    echo "    VPC Endpoint 조회 및 삭제..."
    VPCE_IDS=$(aws ec2 describe-vpc-endpoints --region "$REGION_CODE" --filters "Name=vpc-id,Values=$CLEAN_VPC_ID" --query "VpcEndpoints[].VpcEndpointId" --output text 2>/dev/null)
    if [ -n "$VPCE_IDS" ]; then
      aws ec2 delete-vpc-endpoints --region "$REGION_CODE" --vpc-endpoint-ids $VPCE_IDS >/dev/null 2>&1 || true
      sleep 20
    fi

    # 4. NAT Gateway 삭제
    echo "    NAT Gateway 삭제 시도..."
    NAT_IDS=$(aws ec2 describe-nat-gateways --region "$REGION_CODE" \
      --filter "Name=vpc-id,Values=$CLEAN_VPC_ID" "Name=state,Values=available,pending" \
      --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)
    for NAT_ID in $NAT_IDS;
 do
      aws ec2 delete-nat-gateway --region "$REGION_CODE" --nat-gateway-id "$NAT_ID" >/dev/null 2>&1 || true
    done

    echo "    NAT 삭제 전파 대기..."
    wait_for_nat_deleted 180

    # 4.5. Lambda 및 기타 ENI 강제 정리 (중요: 서브넷 삭제 방해 요소)
    echo "    Lambda/Requester-Managed ENI 강제 정리..."
    # Description에 'AWS Lambda'가 포함되거나, InterfaceType이 'lambda'인 ENI 조회
    LAMBDA_ENIS=$(aws ec2 describe-network-interfaces --region "$REGION_CODE" \
      --filters "Name=vpc-id,Values=$CLEAN_VPC_ID" \
      --query "NetworkInterfaces[?contains(Description, 'AWS Lambda') || InterfaceType=='lambda'].NetworkInterfaceId" \
      --output text 2>/dev/null)
    
    for ENI_ID in $LAMBDA_ENIS;
 do
       if [ -z "$ENI_ID" ]; then continue; fi
       echo "      Lambda ENI 삭제: $ENI_ID"
       # Lambda ENI는 바로 지워지지 않는 경우가 많아 detach 시도 후 삭제
       ATTACH_ID=$(aws ec2 describe-network-interfaces --region "$REGION_CODE" --network-interface-ids "$ENI_ID" --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text 2>/dev/null)
       if [ "$ATTACH_ID" != "None" ] && [ -n "$ATTACH_ID" ]; then
         aws ec2 detach-network-interface --region "$REGION_CODE" --attachment-id "$ATTACH_ID" --force >/dev/null 2>&1 || true
       fi
       aws ec2 delete-network-interface --region "$REGION_CODE" --network-interface-id "$ENI_ID" >/dev/null 2>&1 || true
    done

    # 5. 일반 ENI 정리 (available 먼저, in-use는 detach 후 삭제)
    echo "    일반 ENI(네트워크 인터페이스) 정리 시도..."
    ENI_IDS_AVAILABLE=$(aws ec2 describe-network-interfaces --region "$REGION_CODE" \
      --filters "Name=vpc-id,Values=$CLEAN_VPC_ID" "Name=status,Values=available" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' \
      --output text 2>/dev/null)
    for ENI_ID in $ENI_IDS_AVAILABLE;
 do
      aws ec2 delete-network-interface --region "$REGION_CODE" --network-interface-id "$ENI_ID" >/dev/null 2>&1 || true
    done

    ENI_INUSE=$(aws ec2 describe-network-interfaces --region "$REGION_CODE" \
      --filters "Name=vpc-id,Values=$CLEAN_VPC_ID" "Name=status,Values=in-use" \
      --query 'NetworkInterfaces[?Attachment.AttachmentId!=null].[NetworkInterfaceId,Attachment.AttachmentId]' \
      --output text 2>/dev/null)
    while read -r ENI_ID ATTACH_ID;
 do
      if [ -z "$ENI_ID" ] || [ -z "$ATTACH_ID" ]; then continue; fi
      aws ec2 detach-network-interface --region "$REGION_CODE" --attachment-id "$ATTACH_ID" --force >/dev/null 2>&1 || true
      aws ec2 delete-network-interface --region "$REGION_CODE" --network-interface-id "$ENI_ID" >/dev/null 2>&1 || true
    done <<< "$ENI_INUSE"

    # 6. 보안 그룹 정리 (모든 규칙 삭제 후 그룹 삭제)
    echo "    보안 그룹(Security Group) 의존성 제거 및 삭제..."
    SG_IDS=$(aws ec2 describe-security-groups --region "$REGION_CODE" --filters "Name=vpc-id,Values=$CLEAN_VPC_ID" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null)
    if [ -n "$SG_IDS" ]; then
      for SG_ID in $SG_IDS;
 do
        INGRESS=$(aws ec2 describe-security-groups --region "$REGION_CODE" --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null)
        if [ -n "$INGRESS" ] && [ "$INGRESS" != "[]" ]; then
          aws ec2 revoke-security-group-ingress --region "$REGION_CODE" --group-id "$SG_ID" --ip-permissions "$INGRESS" >/dev/null 2>&1 || true
        fi

        EGRESS=$(aws ec2 describe-security-groups --region "$REGION_CODE" --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null)
        if [ -n "$EGRESS" ] && [ "$EGRESS" != "[]" ]; then
          aws ec2 revoke-security-group-egress --region "$REGION_CODE" --group-id "$SG_ID" --ip-permissions "$EGRESS" >/dev/null 2>&1 || true
        fi
      done

      # 의존성 문제로 삭제 안 될 수 있으니 2번 시도
      for SG_ID in $SG_IDS;
 do
        aws ec2 delete-security-group --region "$REGION_CODE" --group-id "$SG_ID" >/dev/null 2>&1 || true
      done
      sleep 2
      for SG_ID in $SG_IDS;
 do
        aws ec2 delete-security-group --region "$REGION_CODE" --group-id "$SG_ID" >/dev/null 2>&1 || true
      done
    fi

    # 잔존 리소스 체크
    REMAIN_LB=$(list_lb_arns)
    REMAIN_NAT=$(aws ec2 describe-nat-gateways --region "$REGION_CODE" \
      --filter "Name=vpc-id,Values=$CLEAN_VPC_ID" "Name=state,Values=pending,available,deleting" \
      --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)
    REMAIN_VPCE=$(aws ec2 describe-vpc-endpoints --region "$REGION_CODE" --filters "Name=vpc-id,Values=$CLEAN_VPC_ID" --query "VpcEndpoints[].VpcEndpointId" --output text 2>/dev/null)
    REMAIN_ENI=$(aws ec2 describe-network-interfaces --region "$REGION_CODE" --filters "Name=vpc-id,Values=$CLEAN_VPC_ID" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null)

    if [ -z "$REMAIN_LB" ] && [ -z "$REMAIN_NAT" ] && [ -z "$REMAIN_VPCE" ] && [ -z "$REMAIN_ENI" ]; then
      echo "  - 잔존 리소스 없음 (패스 ${pass} 종료)"
      break
    fi

    sleep 20
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
  echo "[1/4] K8s 로드밸런서 리소스 정리 중..."

  if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION_CODE" >/dev/null 2>&1; then
    aws eks update-kubeconfig --region "$REGION_CODE" --name "$CLUSTER_NAME"

    # Ingress/Service 삭제 (Safe Strategy: Graceful first -> Force later)
    # 1. Graceful Delete 시도
    echo "    K8s Ingress/LB Service 정상 삭제 시도..."
    kubectl delete ingress --all --all-namespaces --wait=true --timeout=3m --ignore-not-found=true || true
    
    # LB 타입 서비스만 골라서 삭제
    kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
      | while read -r ns name; do
          [ -z "$ns" ] && continue
          kubectl delete svc -n "$ns" "$name" --wait=true --timeout=3m --ignore-not-found=true || true
        done

    # 2. 아직 남은 리소스 확인 및 강제 삭제 (Force)
    echo "    잔존 K8s 리소스 강제 정리..."
    kubectl delete ingress --all --all-namespaces --grace-period=0 --force --ignore-not-found=true >/dev/null 2>&1 || true
    kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
      | while read -r ns name; do
          [ -z "$ns" ] && continue
          kubectl delete svc -n "$ns" "$name" --grace-period=0 --force --ignore-not-found=true >/dev/null 2>&1 || true
        done

    # ArgoCD 등 Helm 리소스 선제 삭제 (Namespace 인식 개선)
    echo "    Helm Release 선제 정리 (Zombie 방지)..."
    helm list -A --no-headers | awk '{print $1" "$2}' | while read -r name ns; do
      if [ -n "$name" ] && [ -n "$ns" ]; then
        echo "      Uninstalling Helm release: $name (ns: $ns)"
        helm uninstall "$name" -n "$ns" --wait --timeout 5m || true
      fi
    done

    echo " AWS가 로드밸런서를 삭제하는 동안 60초 대기..."
    sleep 60
  else
    echo " 클러스터가 이미 없거나 접속 불가. K8s 리소스 정리 스킵."
  fi

  # 2. [선제 청소] VPC 의존 리소스(LB/ENI) 미리 제거
  echo "[2/4] VPC 의존 리소스 선제 정리..."
  VPC_ID=$(get_vpc_id "$TF_PATH" "$REGION_CODE" "$CLUSTER_NAME")
  if [ -n "$VPC_ID" ]; then
    cleanup_vpc_deps "$VPC_ID" "$CLUSTER_NAME" "$REGION_CODE"
  else
    echo " VPC ID를 찾을 수 없어 선제 정리를 건너뜁니다."
  fi

  # 3. Terraform Destroy 시도
  echo " [3/4] Terraform Destroy 실행..."

  # cleanup_vpc_deps로 실제 리소스가 지워졌을 수 있으므로 상태 동기화
  echo "  State Refreshing..."
  if [ -n "$VAR_FILE" ] && [ -f "$TF_PATH/$VAR_FILE" ]; then
    terraform -chdir="$TF_PATH" refresh -var-file="$VAR_FILE" >/dev/null 2>&1 || true
  else
    terraform -chdir="$TF_PATH" refresh >/dev/null 2>&1 || true
  fi

  set +e
  # 변수 파일이 있으면 적용하여 destroy (기본 타임아웃)
  if [ -n "$VAR_FILE" ] && [ -f "$TF_PATH/$VAR_FILE" ]; then
    timeout -k 30s "$DESTROY_TIMEOUT" terraform -chdir="$TF_PATH" destroy -auto-approve -var-file="$VAR_FILE"
  else
    timeout -k 30s "$DESTROY_TIMEOUT" terraform -chdir="$TF_PATH" destroy -auto-approve
  fi
  EXIT_CODE=$?
  set -e

  # 4. [에러 핸들링] 실패 시 재시도
  if [ $EXIT_CODE -ne 0 ]; then
    echo " Terraform Destroy 실패 또는 타임아웃!"
    echo " 잔여 리소스 다시 정리 후 긴 타임아웃으로 재시도합니다..."

    # [중요] 위험한 state rm 자동 실행 제거함.
    # 대신 실제 리소스(VPC/ENI)를 다시 한 번 강력하게 청소
    if [ -n "$VPC_ID" ]; then
      cleanup_vpc_deps "$VPC_ID" "$CLUSTER_NAME" "$REGION_CODE"
    fi

    # 다시 Destroy 시도 (긴 타임아웃)
    echo " [4/4] Terraform Destroy 재실행 (최종)..."
    if [ -n "$VAR_FILE" ] && [ -f "$TF_PATH/$VAR_FILE" ]; then
      timeout -k 30s "$DESTROY_TIMEOUT_LONG" terraform -chdir="$TF_PATH" destroy -auto-approve -var-file="$VAR_FILE"
    else
      timeout -k 30s "$DESTROY_TIMEOUT_LONG" terraform -chdir="$TF_PATH" destroy -auto-approve
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
