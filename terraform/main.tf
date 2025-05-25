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
  cidr_block           = "10.0.0.0/16"
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
