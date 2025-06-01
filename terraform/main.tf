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

# ECR API VPCエンドポイント
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.ap-northeast-1.ecr.api"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private-subnet[*].id
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]

  private_dns_enabled = true

  tags = {
    Name                   = "${local.project_name}-ecr-api-endpoint"
    "${local.project_tag}" = local.project_name
  }
}

# ECR DKR VPCエンドポイント
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.ap-northeast-1.ecr.dkr"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private-subnet[*].id
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]

  private_dns_enabled = true

  tags = {
    Name                   = "${local.project_name}-ecr-dkr-endpoint"
    "${local.project_tag}" = local.project_name
  }
}

# CloudWatch Logs VPCエンドポイント
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.ap-northeast-1.logs"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private-subnet[*].id
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]

  private_dns_enabled = true

  tags = {
    Name                   = "${local.project_name}-logs-endpoint"
    "${local.project_tag}" = local.project_name
  }
}

# S3 Gateway VPCエンドポイント（無料）
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.ap-northeast-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private-route-table.id]

  tags = {
    Name                   = "${local.project_name}-s3-endpoint"
    "${local.project_tag}" = local.project_name
  }
}

# VPCエンドポイント用Security Group
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "${local.project_name}-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name                   = "${local.project_name}-vpc-endpoint-sg"
    "${local.project_tag}" = local.project_name
  }
}

# ECSからVPCエンドポイントへのHTTPS通信
resource "aws_vpc_security_group_ingress_rule" "vpc_endpoint_https" {
  security_group_id            = aws_security_group.vpc_endpoint_sg.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backend-api-sg.id
}

# VPCエンドポイント用アウトバウンド（全許可）
resource "aws_vpc_security_group_egress_rule" "vpc_endpoint_egress" {
  security_group_id = aws_security_group.vpc_endpoint_sg.id
  from_port         = 0
  to_port           = 0
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
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
  certificate_arn   = aws_acm_certificate_validation.main.certificate_arn

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

resource "aws_vpc_security_group_egress_rule" "backend-api-sg-rds-egress" {
  security_group_id            = aws_security_group.backend-api-sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.rds_sg.id
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

# ECS Service
resource "aws_ecs_service" "backend-api" {
  name            = "${local.project_name}-api-service"
  cluster         = aws_ecs_cluster.backend-cluster.id
  task_definition = aws_ecs_task_definition.backend-api.arn
  desired_count   = 1 # タスク数
  launch_type     = "FARGATE"

  # Network設定
  network_configuration {
    subnets          = aws_subnet.private-subnet[*].id
    security_groups  = [aws_security_group.backend-api-sg.id]
    assign_public_ip = false # プライベートサブネット
  }

  # Load Balancer設定
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "fastapi"
    container_port   = 8000
  }

  # Auto Scaling対応
  lifecycle {
    ignore_changes = [desired_count]
  }

  # Load Balancerヘルスチェック待ち
  depends_on = [aws_lb_listener.alb-https-listener]

  tags = {
    Name                   = "${local.project_name}-ecs-service"
    "${local.project_tag}" = local.project_name
  }
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 2 # 最大2タスク
  min_capacity       = 1 # 最小1タスク
  resource_id        = "service/${aws_ecs_cluster.backend-cluster.name}/${aws_ecs_service.backend-api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy（CPU使用率ベース）
resource "aws_appautoscaling_policy" "ecs_cpu_scaling" {
  name               = "${local.project_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0 # CPU 70%でスケールアウト
  }
}

# Auto Scaling Policy（メモリ使用率ベース）
resource "aws_appautoscaling_policy" "ecs_memory_scaling" {
  name               = "${local.project_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 80.0 # メモリ 80%でスケールアウト
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "backend-cluster" {
  name = "${local.project_name}-cluster"

  # Container Insights有効化（監視・ログ集約）
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name                   = "${local.project_name}-ecs-cluster"
    "${local.project_tag}" = local.project_name
  }
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "backend-cluster-capacity-providers" {
  cluster_name = aws_ecs_cluster.backend-cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE_SPOT"
  }
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.project_name}"
  retention_in_days = 7 # ログ保持期間（コスト削減）

  tags = {
    Name                   = "${local.project_name}-ecs-logs"
    "${local.project_tag}" = local.project_name
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name                   = "${local.project_name}-ecs-task-execution-role"
    "${local.project_tag}" = local.project_name
  }
}

# ECS Task Execution Role Policy Attachment
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECR追加権限（VPCエンドポイント使用時）
resource "aws_iam_role_policy" "ecs_task_execution_ecr_policy" {
  name = "${local.project_name}-ecs-ecr-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# ECS Task Role（アプリケーション用）
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name                   = "${local.project_name}-ecs-task-role"
    "${local.project_tag}" = local.project_name
  }
}

# ECS Task Execution Role Policy（最小権限 - 必要に応じて拡張）
resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${local.project_name}-ecs-task-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Secrets Manager アクセス権限（Task Execution Role用）
resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "${local.project_name}-ecs-secrets-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "backend-api" {
  family                   = "${local.project_name}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # 0.25 vCPU
  memory                   = "512" # 512 MB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "fastapi"
      image = "${aws_ecr_repository.backend-ecr.repository_url}:latest"

      # ポート設定
      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]

      # 必須設定
      essential = true

      # 環境変数（非機密情報のみ）
      environment = [
        {
          name  = "ENV"
          value = var.environment
        },
        {
          name  = "LOG_LEVEL"
          value = "INFO"
        },
        {
          name  = "DB_HOST"
          value = aws_db_instance.mysql.endpoint
        },
        {
          name  = "DB_PORT"
          value = "3306"
        },
        {
          name  = "DB_NAME"
          value = "appdb"
        },
        {
          name  = "DB_USER"
          value = "admin"
        }
      ]

      # 機密情報（Secrets Manager から取得）
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
        }
      ]

      # ヘルスチェック
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:8000/health_check || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # ログ設定
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # リソース制限
      memoryReservation = 256
    }
  ])

  tags = {
    Name                   = "${local.project_name}-task-definition"
    "${local.project_tag}" = local.project_name
  }
}

# Database Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${local.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private-subnet[*].id

  tags = {
    Name                   = "${local.project_name}-db-subnet-group"
    "${local.project_tag}" = local.project_name
  }
}

# RDS Parameter Group (MySQL最適化)
resource "aws_db_parameter_group" "mysql" {
  family = "mysql8.0"
  name   = "${local.project_name}-mysql-params"

  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}" # メモリの75%をバッファプールに
  }

  tags = {
    Name                   = "${local.project_name}-mysql-params"
    "${local.project_tag}" = local.project_name
  }
}

# RDS Instance (MySQL)
resource "aws_db_instance" "mysql" {
  identifier        = "${local.project_name}-mysql"
  allocated_storage = 20
  storage_type      = "gp2"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro" # 最小構成

  # Database設定
  db_name  = "appdb"
  username = "admin"
  password = var.db_password # variables.tfで定義

  # ネットワーク設定
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  # 可用性設定（コスト削減）
  multi_az            = false # Single-AZ（安価）
  publicly_accessible = false # プライベート

  # バックアップ設定（コスト削減）
  backup_retention_period = 0    # バックアップ無効
  backup_window           = null # バックアップ無効時は不要

  # メンテナンス設定
  maintenance_window = "sun:03:00-sun:04:00"

  # 削除設定（開発用）
  deletion_protection      = false # 削除可能
  skip_final_snapshot      = true  # 最終スナップショット無効
  delete_automated_backups = true  # 自動バックアップ削除

  # パフォーマンス設定
  parameter_group_name = aws_db_parameter_group.mysql.name

  # 監視設定（コスト削減）
  monitoring_interval = 0 # 拡張監視無効

  tags = {
    Name                   = "${local.project_name}-mysql"
    "${local.project_tag}" = local.project_name
  }
}

# RDS用Security Group
resource "aws_security_group" "rds_sg" {
  name        = "${local.project_name}-rds-sg"
  description = "Security group for RDS MySQL"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name                   = "${local.project_name}-rds-sg"
    "${local.project_tag}" = local.project_name
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${local.project_name}-db-credentials"
  description = "Database credentials for ${local.project_name}"

  tags = {
    Name                   = "${local.project_name}-db-credentials"
    "${local.project_tag}" = local.project_name
  }
}

# Database Secrets Value
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username             = "admin"
    password             = var.db_password
    engine               = "mysql"
    host                 = aws_db_instance.mysql.endpoint
    port                 = 3306
    dbname               = "appdb"
    dbInstanceIdentifier = aws_db_instance.mysql.id
  })
}

# ECSからRDSへのMySQL通信
resource "aws_vpc_security_group_ingress_rule" "rds_mysql" {
  security_group_id            = aws_security_group.rds_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backend-api-sg.id
}

# RDS用アウトバウンド（基本的に不要だが念のため）
resource "aws_vpc_security_group_egress_rule" "rds_egress" {
  security_group_id = aws_security_group.rds_sg.id
  from_port         = 0
  to_port           = 0
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
