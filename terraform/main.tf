terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWSプロバイダー設定
provider "aws" {
  region = "ap-northeast-1"
}

# VPC作成
resource "aws_vpc" "main" {
  cidr_block           = local.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                   = "${local.project_name}-vpc"
    "${local.project_tag}" = local.project_name
  }
}

# Internet Gateway作成
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name                   = "${local.project_name}-igw"
    "${local.project_tag}" = local.project_name
  }
}

resource "aws_subnet" "public-subnet" {
  count = length(local.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                   = "${local.project_name}-public-${substr(local.availability_zones[count.index], -2, 2)}"
    "${local.project_tag}" = local.project_name
    Type                   = "public"
  }
}

# プライベートサブネット
resource "aws_subnet" "private-subnet" {
  count = length(local.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]

  tags = {
    Name                   = "${local.project_name}-private-${substr(local.availability_zones[count.index], -2, 2)}"
    "${local.project_tag}" = local.project_name
    Type                   = "private"
  }
}

# パブリックルートテーブル
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name                   = "${local.project_name}-public-route-table"
    "${local.project_tag}" = local.project_name
    Type                   = "public"
  }
}

resource "aws_route" "public-route" {
  route_table_id         = aws_route_table.public-route-table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public-route-table-association" {
  count = length(local.availability_zones)

  subnet_id      = aws_subnet.public-subnet[count.index].id
  route_table_id = aws_route_table.public-route-table.id
}

#　プライベートルートテーブル
resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name                   = "${local.project_name}-private-route-table"
    "${local.project_tag}" = local.project_name
    Type                   = "private"
  }
}

resource "aws_route_table_association" "private-route-table-association" {
  count = length(local.availability_zones)

  subnet_id      = aws_subnet.private-subnet[count.index].id
  route_table_id = aws_route_table.private-route-table.id
}

# ALB
resource "aws_lb" "alb" {
  name                       = "${local.project_name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb-sg.id]
  subnets                    = aws_subnet.public-subnet[*].id
  enable_deletion_protection = var.enable_deletion_protection

  tags = {
    Name                   = "${local.project_name}-alb"
    "${local.project_tag}" = local.project_name
  }
}

# ALB security group
resource "aws_security_group" "alb-sg" {
  name        = "${local.project_name}-alb-sg"
  description = "security group for ${local.project_name} ALB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name                   = "${local.project_name}-alb-sg"
    "${local.project_tag}" = local.project_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb-sg-http" {
  security_group_id = aws_security_group.alb-sg.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb-sg-https" {
  security_group_id = aws_security_group.alb-sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb-sg-egress" {
  security_group_id            = aws_security_group.alb-sg.id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backend-api-sg.id
}


# ECS Security group
resource "aws_security_group" "backend-api-sg" {
  name        = "${local.project_name}-backend-api-sg"
  description = "security group for ecs api"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name                   = "${local.project_name}-ecs-sg"
    "${local.project_tag}" = local.project_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "backend-api-sg-ingress" {
  security_group_id            = aws_security_group.backend-api-sg.id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb-sg.id
}

resource "aws_vpc_security_group_egress_rule" "backend-api-sg-vpc-endpoint-egress" {
  security_group_id = aws_security_group.backend-api-sg.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = local.cidr_block
}
