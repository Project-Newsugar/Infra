output "endpoint" { value = aws_rds_cluster.main.endpoint }
output "reader_endpoint" { value = aws_rds_cluster.main.reader_endpoint }
output "secret_arn" { value = aws_secretsmanager_secret.db_auth.arn }
output "global_cluster_id" {
  description = "Global Cluster ID"
  value       = var.create_global_cluster ? aws_rds_global_cluster.main[0].id : null
}
