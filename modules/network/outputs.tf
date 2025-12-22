output "vpc_id" { value = aws_vpc.main.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "app_subnet_ids" { value = aws_subnet.app[*].id }

# 이게 없으면 DB 모듈이 서브넷을 못 찾아서 에러 발생
output "data_subnet_ids" { 
  description = "Private Data Subnet IDs for RDS/Redis"
  value       = aws_subnet.data[*].id 
}
