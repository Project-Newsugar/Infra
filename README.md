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
Infra 삭제전에 먼저 프론트엔드와 백엔드 자동화 시킨 ArogoCD 애플리케이션을 삭제한다. 
```bash
chmod +x destroy.sh
./destroy.sh seoul  # 서울 리전만 삭제
./destroy.sh all    # 도쿄 -> 서울 순서로 삭제
```

### 참고
- 레포 루트(Infra/)에서 실행하세요.
- "You must be logged in to the server" 오류가 나오면 AWS 로그인 상태와 aws-auth.yaml의 IAM ARN 등록을 확인하세요.
