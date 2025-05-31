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

# Route53
resource "aws_route53_zone" "host-zone" {
  name = var.domain_name

  lifecycle {
    prevent_destroy = true # 削除防止
  }

  tags = {
    Name                   = "${local.project_name}-host-zone"
    "${local.project_tag}" = local.project_name
  }
}

# ALBへのAliasレコード
resource "aws_route53_record" "alb" {
  zone_id = aws_route53_zone.host-zone.id
  name    = "${var.subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

# ACM
resource "aws_acm_certificate" "acm" {
  domain_name       = "${var.subdomain}.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true # 削除防止
  }

  tags = {
    Name                   = "${local.project_name}-acm-certificate"
    "${local.project_tag}" = local.project_name
  }
}

resource "aws_route53_record" "cert-validation" {
  for_each = {
    for dvo in aws_acm_certificate.acm.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.host-zone.id
}

# 証明書検証の完了待ち
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.acm.arn
  validation_record_fqdns = [for record in aws_route53_record.cert-validation : record.fqdn]

  timeouts {
    create = "5m"
  }
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

# ALBリスナー
resource "aws_lb_listener" "alb-http-listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name                   = "${local.project_name}-alb-listener"
    "${local.project_tag}" = local.project_name
  }
}

resource "aws_lb_listener" "alb-https-listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  # certificate_arn   = aws_acm_certificate_validation.main.certificate_arn # FIXME: ACM証明書のARNを指定

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }

  tags = {
    Name                   = "${local.project_name}-alb-https-listener"
    "${local.project_tag}" = local.project_name
  }
}

# ALB Target Group
resource "aws_lb_target_group" "ecs" {
  name        = "${local.project_name}-ecs-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health_check"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name                   = "${local.project_name}-ecs-tg"
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

# ECR Repository
resource "aws_ecr_repository" "backend-ecr" {
  name                 = "${local.project_name}-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # セキュリティスキャン有効
  }

  lifecycle {
    prevent_destroy = true # 削除防止（イメージ保護）
  }

  tags = {
    Name                   = "${local.project_name}-ecr-repo"
    "${local.project_tag}" = local.project_name
  }
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "backend-ecr-lifecycle-policy" {
  repository = aws_ecr_repository.backend-ecr.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
