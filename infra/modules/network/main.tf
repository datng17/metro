locals {
  # Subnet layout inside the /16 (2 AZs):
  #   public       10.20.0.0/24,   10.20.1.0/24    ALB, fck-nat
  #   private-app  10.20.16.0/20,  10.20.32.0/20   ECS Fargate tasks (4091 IPs each)
  #   private-data 10.20.200.0/24, 10.20.201.0/24  RDS (no internet route)
  public_cidrs       = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_app_cidrs  = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 4, i + 1)]
  private_data_cidrs = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 200)]
}

# ---------------------------------------------------------------------------
# VPC + Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for Cloud Map private DNS and RDS endpoints

  tags = {
    Name = "${var.name}-vpc"
  }
}

# Strip all rules from the default security group so nothing uses it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-default-locked"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = local.public_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private_app" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = local.private_app_cidrs[count.index]

  tags = {
    Name = "${var.name}-private-app-${var.azs[count.index]}"
    Tier = "private-app"
  }
}

resource "aws_subnet" "private_data" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = local.private_data_cidrs[count.index]

  tags = {
    Name = "${var.name}-private-data-${var.azs[count.index]}"
    Tier = "private-data"
  }
}

# ---------------------------------------------------------------------------
# Route tables
# ---------------------------------------------------------------------------
# Public: default route to the Internet Gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-rt-public"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private-app: one table shared by both AZs (there is a single NAT instance).
# The 0.0.0.0/0 route to the fck-nat ENI is added by the fck-nat module
# (update_route_tables = true), so it is not declared here.
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-rt-private-app"
  }
}

resource "aws_route_table_association" "private_app" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# Private-data: local VPC route only. RDS never needs to reach the internet,
# so this tier is fully isolated.
resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-rt-private-data"
  }
}

resource "aws_route_table_association" "private_data" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data.id
}

# ---------------------------------------------------------------------------
# fck-nat (t4g.nano) with a fixed Elastic IP
# ---------------------------------------------------------------------------
# The EIP is owned here (not by the module) so it survives NAT instance
# replacement and stays the single egress IP allow-listed in MongoDB Atlas.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.this]
}

module "fck_nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "1.6.1"

  name          = "${var.name}-fck-nat"
  vpc_id        = aws_vpc.this.id
  subnet_id     = aws_subnet.public[0].id
  instance_type = var.nat_instance_type

  # ASG of size 1: a failed instance is replaced automatically, re-attaching
  # the same static internal ENI (route target) and the same EIP.
  ha_mode            = true
  eip_allocation_ids = [aws_eip.nat.allocation_id]

  update_route_tables = true
  route_tables_ids = {
    "private-app" = aws_route_table.private_app.id
  }

  depends_on = [aws_route.public_internet]
}
