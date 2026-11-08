output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones used by the subnets."
  value       = var.azs
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB, NAT)."
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of the private application subnets (ECS Fargate)."
  value       = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  description = "IDs of the private data subnets (RDS)."
  value       = aws_subnet.private_data[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "private_app_route_table_id" {
  description = "ID of the private-app route table (default route via fck-nat)."
  value       = aws_route_table.private_app.id
}

output "private_data_route_table_id" {
  description = "ID of the isolated private-data route table."
  value       = aws_route_table.private_data.id
}

output "nat_eip" {
  description = "Public Elastic IP used for all outbound traffic from private-app subnets."
  value       = aws_eip.nat.public_ip
}

output "nat_eip_allocation_id" {
  description = "Allocation ID of the NAT Elastic IP."
  value       = aws_eip.nat.allocation_id
}

output "nat_eni_id" {
  description = "ID of the static fck-nat ENI that private routes point at."
  value       = module.fck_nat.eni_id
}

output "nat_security_group_ids" {
  description = "Security group IDs attached to the fck-nat ENIs."
  value       = module.fck_nat.security_group_ids
}
