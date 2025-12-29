## 일일 배포 가이드

### 사전 준비
- AWS CLI 설정 (aws configure 또는 SSO 로그인)
- Terraform 설치
- kubectl 설치

### 사용 방법
```bash
chmod +x setup.sh
./setup.sh seoul    # 서울(Primary)만 배포
./setup.sh all      # 서울 + 도쿄(DR) 순차 배포
```

### 참고
- 레포 루트(Infra/)에서 실행하세요.
- "You must be logged in to the server" 오류가 나오면 AWS 로그인 상태와 aws-auth.yaml의 IAM ARN 등록을 확인하세요.
