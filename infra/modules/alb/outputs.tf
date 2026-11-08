output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch LoadBalancer dimension)."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "ALB DNS name (target of the Cloudflare CNAME)."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Hosted zone ID of the ALB."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ALB security group (the only source the targets should accept)."
  value       = aws_security_group.this.id
}

output "target_group_arn" {
  description = "Target group ARN for the ECS service load_balancer block."
  value       = aws_lb_target_group.this.arn
  # ECS rejects a target group that is not attached to a listener yet.
  depends_on = [aws_lb_listener.https]
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch TargetGroup dimension)."
  value       = aws_lb_target_group.this.arn_suffix
}

output "https_listener_arn" {
  description = "HTTPS listener ARN."
  value       = aws_lb_listener.https.arn
}

output "http_listener_arn" {
  description = "HTTP (redirect) listener ARN."
  value       = aws_lb_listener.http.arn
}
