output "identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.identifier
}

output "address" {
  description = "Hostname of the instance (DB_HOST)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port of the instance (DB_PORT)."
  value       = aws_db_instance.this.port
}

output "engine_version_actual" {
  description = "Running PostgreSQL version."
  value       = aws_db_instance.this.engine_version_actual
}

output "master_username" {
  description = "Master user name."
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret (JSON with username/password) holding the RDS-managed master credentials."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "Security group of the database."
  value       = aws_security_group.this.id
}
