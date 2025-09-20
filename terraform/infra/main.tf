variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

locals {
  postgres_db_name  = "tinyuka_app_db"
  postgres_username = "tinyuka_user"
}

terraform {
  required_version = ">= 1.0"

  backend "s3" {
    # Values to be provided via -backend-config
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Random Password Generation
resource "random_password" "postgres_password" {
  length  = 16
  special = true
}

resource "random_password" "redis_password" {
  length  = 16
  special = false # Redis AUTH doesn't work well with some special characters
}

resource "random_password" "in_cluster_postgres_password" {
  length  = 16
  special = true
}

resource "random_password" "mysql_password" {
  length  = 16
  special = true
}

resource "random_password" "in_cluster_mysql_password" {
  length  = 16
  special = true
}

resource "random_password" "rabbitmq_password" {
  length  = 16
  special = true
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                = "tinyuka-eks-vpc"
    "kubernetes.io/cluster/eks-cluster" = "shared"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "tinyuka-eks-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                = "tinyuka-eks-public-subnet-${count.index + 1}"
    "kubernetes.io/cluster/eks-cluster" = "shared"
    "kubernetes.io/role/elb"            = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "tinyuka-eks-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "eks_cluster" {
  name_prefix = "tinyuka-eks-cluster-"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tinyuka-eks-cluster-sg"
  }
}

resource "aws_security_group" "eks_nodes" {
  name_prefix = "tinyuka-eks-nodes-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tinyuka-eks-nodes-sg"
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "tinyuka-rds-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = {
    Name = "tinyuka-rds-sg"
  }
}

resource "aws_security_group" "elasticache" {
  name_prefix = "tinyuka-elasticache-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = {
    Name = "tinyuka-elasticache-sg"
  }
}

resource "aws_security_group" "mysql" {
  name_prefix = "tinyuka-mysql-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = {
    Name = "tinyuka-mysql-sg"
  }
}

# EKS IAM Roles
resource "aws_iam_role" "eks_cluster" {
  name = "tinyuka-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role" "eks_nodes" {
  name = "tinyuka-eks-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# AWS Load Balancer Controller IAM Role
data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role_policy.json
  name               = "tinyuka-aws-load-balancer-controller"
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name = "tinyuka-AWSLoadBalancerControllerIAMPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:GetSecurityGroupsForVpc"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = [
              "CreateTargetGroup",
              "CreateLoadBalancer"
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_attach" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

# EKS OIDC Identity Provider
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "tinyuka-eks-irsa"
  }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "tinyuka-tinyuka-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.28"

  vpc_config {
    subnet_ids         = aws_subnet.public[*].id
    security_group_ids = [aws_security_group.eks_cluster.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "tinyuka-main-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.public[*].id

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  instance_types = ["t3.small"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "tinyuka-eks-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "tinyuka-eks-db-subnet-group"
  }
}

# RDS PostgreSQL
resource "aws_db_instance" "postgres" {
  identifier        = "tinyuka-eks-postgres"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = local.postgres_db_name
  username = local.postgres_username
  password = random_password.postgres_password.result

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = 0
  skip_final_snapshot     = true

  tags = {
    Name = "tinyuka-eks-postgres"
  }
}

# ElasticCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "tinyuka-eks-cache-subnet-group"
  subnet_ids = aws_subnet.public[*].id
}

# ElasticCache Redis
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "tinyuka-eks-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.elasticache.id]

  tags = {
    Name = "tinyuka-eks-redis"
  }
}

# RDS MySQL
resource "aws_db_instance" "mysql" {
  identifier        = "tinyuka-eks-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = "tinyuka_mysql_db"
  username = "mysql_user"
  password = random_password.mysql_password.result

  vpc_security_group_ids = [aws_security_group.mysql.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = 0
  skip_final_snapshot     = true

  tags = {
    Name = "tinyuka-eks-mysql"
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name         = "tinyuka-dynamodb-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "tinyuka-dynamodb-table"
  }
}

# Kubernetes Resources
resource "kubernetes_namespace" "storage" {
  metadata {
    name = "storage"
  }

  depends_on = [aws_eks_node_group.main]
}

# In-cluster PostgreSQL StatefulSet
resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    service_name = "postgres"
    replicas     = 1

    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:15"

          env {
            name  = "POSTGRES_DB"
            value = local.postgres_db_name
          }

          env {
            name  = "POSTGRES_USER"
            value = local.postgres_username
          }

          env {
            name  = "POSTGRES_PASSWORD"
            value = random_password.in_cluster_postgres_password.result
          }

          port {
            container_port = 5432
          }

          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "postgres-storage"
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "10Gi"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.storage]
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    selector = {
      app = "postgres"
    }

    port {
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_stateful_set.postgres]
}

# In-cluster Redis StatefulSet
resource "kubernetes_stateful_set" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    service_name = "redis"
    replicas     = 1

    selector {
      match_labels = {
        app = "redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "redis"
        }
      }

      spec {
        container {
          name  = "redis"
          image = "redis:7-alpine"

          port {
            container_port = 6379
          }

          volume_mount {
            name       = "redis-storage"
            mount_path = "/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "redis-storage"
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "5Gi"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.storage]
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    selector = {
      app = "redis"
    }

    port {
      port        = 6379
      target_port = 6379
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_stateful_set.redis]
}

# In-cluster MySQL StatefulSet
resource "kubernetes_stateful_set" "mysql" {
  metadata {
    name      = "mysql"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    service_name = "mysql"
    replicas     = 1

    selector {
      match_labels = {
        app = "mysql"
      }
    }

    template {
      metadata {
        labels = {
          app = "mysql"
        }
      }

      spec {
        container {
          name  = "mysql"
          image = "mysql:8.0"

          env {
            name  = "MYSQL_ROOT_PASSWORD"
            value = random_password.in_cluster_mysql_password.result
          }

          env {
            name  = "MYSQL_DATABASE"
            value = "tinyuka_mysql_db"
          }

          env {
            name  = "MYSQL_USER"
            value = "mysql_user"
          }

          env {
            name  = "MYSQL_PASSWORD"
            value = random_password.in_cluster_mysql_password.result
          }

          port {
            container_port = 3306
          }

          volume_mount {
            name       = "mysql-storage"
            mount_path = "/var/lib/mysql"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "mysql-storage"
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "10Gi"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.storage]
}

resource "kubernetes_service" "mysql" {
  metadata {
    name      = "mysql"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    selector = {
      app = "mysql"
    }

    port {
      port        = 3306
      target_port = 3306
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_stateful_set.mysql]
}

# In-cluster DynamoDB Local StatefulSet
resource "kubernetes_stateful_set" "dynamodb" {
  metadata {
    name      = "dynamodb"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    service_name = "dynamodb"
    replicas     = 1

    selector {
      match_labels = {
        app = "dynamodb"
      }
    }

    template {
      metadata {
        labels = {
          app = "dynamodb"
        }
      }

      spec {
        container {
          name  = "dynamodb"
          image = "amazon/dynamodb-local:latest"

          args = ["-jar", "DynamoDBLocal.jar", "-sharedDb", "-dbPath", "/data"]

          port {
            container_port = 8000
          }

          volume_mount {
            name       = "dynamodb-storage"
            mount_path = "/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "dynamodb-storage"
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "5Gi"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.storage]
}

resource "kubernetes_service" "dynamodb" {
  metadata {
    name      = "dynamodb"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    selector = {
      app = "dynamodb"
    }

    port {
      port        = 8000
      target_port = 8000
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_stateful_set.dynamodb]
}

# In-cluster RabbitMQ StatefulSet
resource "kubernetes_stateful_set" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    service_name = "rabbitmq"
    replicas     = 1

    selector {
      match_labels = {
        app = "rabbitmq"
      }
    }

    template {
      metadata {
        labels = {
          app = "rabbitmq"
        }
      }

      spec {
        container {
          name  = "rabbitmq"
          image = "rabbitmq:3.12-management-alpine"

          env {
            name  = "RABBITMQ_DEFAULT_USER"
            value = "rabbitmq_user"
          }

          env {
            name  = "RABBITMQ_DEFAULT_PASS"
            value = random_password.rabbitmq_password.result
          }

          port {
            container_port = 5672
            name           = "amqp"
          }

          port {
            container_port = 15672
            name           = "management"
          }

          volume_mount {
            name       = "rabbitmq-storage"
            mount_path = "/var/lib/rabbitmq"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "rabbitmq-storage"
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "5Gi"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.storage]
}

resource "kubernetes_service" "rabbitmq" {
  metadata {
    name      = "rabbitmq"
    namespace = kubernetes_namespace.storage.metadata[0].name
  }

  spec {
    selector = {
      app = "rabbitmq"
    }

    port {
      port        = 5672
      target_port = 5672
      name        = "amqp"
    }

    port {
      port        = 15672
      target_port = 15672
      name        = "management"
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_stateful_set.rabbitmq]
}

# App Namespace
resource "kubernetes_namespace" "app" {
  metadata {
    name = "app"
  }

  depends_on = [aws_eks_node_group.main]
}

# Storage Config Map (Non-sensitive values)
resource "kubernetes_config_map" "storage_configs" {
  metadata {
    name      = "storage-configs"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    # AWS RDS PostgreSQL
    aws_postgres_host     = aws_db_instance.postgres.address
    aws_postgres_port     = "5432"
    aws_postgres_database = aws_db_instance.postgres.db_name
    aws_postgres_username = aws_db_instance.postgres.username

    # AWS RDS MySQL
    aws_mysql_host     = aws_db_instance.mysql.address
    aws_mysql_port     = "3306"
    aws_mysql_database = aws_db_instance.mysql.db_name
    aws_mysql_username = aws_db_instance.mysql.username

    # AWS ElastiCache Redis
    aws_redis_host = aws_elasticache_cluster.redis.cache_nodes[0].address
    aws_redis_port = tostring(aws_elasticache_cluster.redis.cache_nodes[0].port)

    # AWS DynamoDB
    aws_dynamodb_table_name = aws_dynamodb_table.main.name
    aws_dynamodb_region     = var.aws_region

    # In-cluster PostgreSQL
    in_cluster_postgres_host     = "postgres.storage.svc.cluster.local"
    in_cluster_postgres_port     = "5432"
    in_cluster_postgres_database = local.postgres_db_name
    in_cluster_postgres_username = local.postgres_username

    # In-cluster MySQL
    in_cluster_mysql_host     = "mysql.storage.svc.cluster.local"
    in_cluster_mysql_port     = "3306"
    in_cluster_mysql_database = "tinyuka_mysql_db"
    in_cluster_mysql_username = "mysql_user"

    # In-cluster Redis
    in_cluster_redis_host = "redis.storage.svc.cluster.local"
    in_cluster_redis_port = "6379"

    # In-cluster DynamoDB Local
    in_cluster_dynamodb_host = "dynamodb.storage.svc.cluster.local"
    in_cluster_dynamodb_port = "8000"

    # In-cluster RabbitMQ
    in_cluster_rabbitmq_host            = "rabbitmq.storage.svc.cluster.local"
    in_cluster_rabbitmq_port            = "5672"
    in_cluster_rabbitmq_management_port = "15672"
    in_cluster_rabbitmq_username        = "rabbitmq_user"
  }

  depends_on = [
    kubernetes_service.postgres,
    kubernetes_service.redis,
    kubernetes_service.mysql,
    kubernetes_service.dynamodb,
    kubernetes_service.rabbitmq,
    aws_db_instance.postgres,
    aws_db_instance.mysql,
    aws_elasticache_cluster.redis,
    aws_dynamodb_table.main
  ]
}

# Storage Credentials Secret (Sensitive values only)
resource "kubernetes_secret" "storage_credentials" {
  metadata {
    name      = "storage-credentials"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    # AWS Passwords and Connection Strings
    aws_postgres_password = random_password.postgres_password.result
    aws_postgres_url      = "postgresql://${aws_db_instance.postgres.username}:${random_password.postgres_password.result}@${aws_db_instance.postgres.endpoint}/${aws_db_instance.postgres.db_name}"
    aws_mysql_password    = random_password.mysql_password.result
    aws_mysql_url         = "mysql://${aws_db_instance.mysql.username}:${random_password.mysql_password.result}@${aws_db_instance.mysql.endpoint}:3306/${aws_db_instance.mysql.db_name}"
    aws_redis_password    = random_password.redis_password.result
    aws_redis_url         = "redis://:${random_password.redis_password.result}@${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"

    # In-cluster Passwords and Connection Strings
    in_cluster_postgres_password = random_password.in_cluster_postgres_password.result
    in_cluster_postgres_url      = "postgresql://${local.postgres_username}:${random_password.in_cluster_postgres_password.result}@postgres.storage.svc.cluster.local:5432/${local.postgres_db_name}"
    in_cluster_mysql_password    = random_password.in_cluster_mysql_password.result
    in_cluster_mysql_url         = "mysql://mysql_user:${random_password.in_cluster_mysql_password.result}@mysql.storage.svc.cluster.local:3306/tinyuka_mysql_db"
    in_cluster_rabbitmq_password = random_password.rabbitmq_password.result
    in_cluster_rabbitmq_url      = "amqp://rabbitmq_user:${random_password.rabbitmq_password.result}@rabbitmq.storage.svc.cluster.local:5672"
  }

  type = "Opaque"

  depends_on = [
    kubernetes_service.postgres,
    kubernetes_service.redis,
    kubernetes_service.mysql,
    kubernetes_service.dynamodb,
    kubernetes_service.rabbitmq,
    aws_db_instance.postgres,
    aws_db_instance.mysql,
    aws_elasticache_cluster.redis,
    aws_dynamodb_table.main
  ]
}

# AWS Load Balancer Controller Service Account
resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_load_balancer_controller.arn
    }
  }
}

# AWS Load Balancer Controller Helm Release
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  depends_on = [
    kubernetes_service_account.aws_load_balancer_controller,
    aws_iam_role_policy_attachment.aws_load_balancer_controller_attach
  ]
}

# Developer IAM Role for EKS Read-Only Access
resource "aws_iam_role" "eks_developer" {
  name = "tinyuka-eks-developer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    ]
  })

  tags = {
    Name = "tinyuka-eks-developer-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_developer_attach" {
  role       = aws_iam_role.eks_developer.name
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
}

# Admin IAM Role for EKS Admin Access
resource "aws_iam_role" "eks_admin" {
  name = "tinyuka-eks-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    ]
  })

  tags = {
    Name = "tinyuka-eks-admin-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_admin_attach" {
  role       = aws_iam_role.eks_admin.name
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

# Data source for current AWS identity
data "aws_caller_identity" "current" {}

# EKS Cluster ConfigMap for IAM authentication
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_nodes.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = aws_iam_role.eks_admin.arn
        username = "admin"
        groups   = ["system:masters"]
      },
      {
        rolearn  = aws_iam_role.eks_developer.arn
        username = "developer"
        groups   = ["tinyuka:developers"]
      }
    ])
    mapUsers = yamlencode([
      {
        userarn  = data.aws_caller_identity.current.arn
        username = "admin"
        groups   = ["system:masters"]
      }
    ])
  }

  depends_on = [aws_eks_node_group.main]
}


# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "rds_postgres_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "rds_postgres_connection_string" {
  description = "RDS PostgreSQL connection string"
  value       = "postgresql://${local.postgres_username}:${random_password.postgres_password.result}@${aws_db_instance.postgres.endpoint}/${local.postgres_db_name}"
  sensitive   = true
}

output "elasticache_redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "elasticache_redis_port" {
  description = "ElastiCache Redis port"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].port
}

output "elasticache_redis_auth_token" {
  description = "ElastiCache Redis auth token"
  value       = random_password.redis_password.result
  sensitive   = true
}

output "in_cluster_postgres_service" {
  description = "In-cluster PostgreSQL service endpoint"
  value       = "postgres.storage.svc.cluster.local:5432"
}

output "in_cluster_redis_service" {
  description = "In-cluster Redis service endpoint"
  value       = "redis.storage.svc.cluster.local:6379"
}

output "storage_credentials_secret" {
  description = "Kubernetes secret containing all database credentials"
  value       = "storage-credentials (in app namespace)"
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region eu-west-1 --name ${aws_eks_cluster.main.name}"
}
