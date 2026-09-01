provider "aws" {
  region = var.aws_region
}

# ============================================================
# DATA - Availability Zones
# ============================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "hospital-vpc"
  }
}

# ============================================================
# INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "hospital-igw"
  }
}

# ============================================================
# PUBLIC SUBNET 1
# ============================================================

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "hospital-public-subnet-1"
  }
}

# ============================================================
# PUBLIC SUBNET 2
# ============================================================

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "hospital-public-subnet-2"
  }
}

# ============================================================
# PRIVATE SUBNET 1 - RDS
# ============================================================

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "hospital-private-subnet-1"
  }
}

# ============================================================
# PRIVATE SUBNET 2 - RDS
# ============================================================

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "hospital-private-subnet-2"
  }
}

# ============================================================
# PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "hospital-public-route-table"
  }
}

# ============================================================
# PUBLIC ROUTE TABLE ASSOCIATION - SUBNET 1
# ============================================================

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# PUBLIC ROUTE TABLE ASSOCIATION - SUBNET 2
# ============================================================

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# EKS CLUSTER IAM ROLE
# ============================================================

resource "aws_iam_role" "eks_role" {
  name = "hospital-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "hospital-eks-cluster-role"
  }
}

# ============================================================
# EKS CLUSTER POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "eks_policy" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ============================================================
# EKS CLUSTER
# ============================================================

resource "aws_eks_cluster" "hospital" {
  name     = "hospital-eks-cluster"
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id
    ]

    endpoint_public_access  = true
    endpoint_private_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_policy
  ]

  tags = {
    Name = "hospital-eks-cluster"
  }
}

# ============================================================
# EKS NODE IAM ROLE
# ============================================================

resource "aws_iam_role" "node_role" {
  name = "hospital-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "hospital-eks-node-role"
  }
}

# ============================================================
# EKS WORKER NODE POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# ============================================================
# EKS CNI POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ============================================================
# ECR READ ONLY POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ============================================================
# EKS NODE GROUP
# ============================================================

resource "aws_eks_node_group" "hospital_nodes" {
  cluster_name    = aws_eks_cluster.hospital.name
  node_group_name = "hospital-nodes"

  node_role_arn = aws_iam_role.node_role.arn

  subnet_ids = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  instance_types = [
    "t3.micro"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy
  ]

  tags = {
    Name = "hospital-eks-node-group"
  }
}

# ============================================================
# S3 BUCKET
# ============================================================

resource "aws_s3_bucket" "patient_records" {
  bucket = "hospital-patient-records-bucket"

  tags = {
    Name = "hospital-patient-records"
  }
}

# ============================================================
# S3 VERSIONING
# ============================================================

resource "aws_s3_bucket_versioning" "patient_records" {
  bucket = aws_s3_bucket.patient_records.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================================
# RDS SECURITY GROUP
# ============================================================

resource "aws_security_group" "rds" {
  name        = "hospital-rds-sg"
  description = "Security group for Hospital PostgreSQL RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"

    cidr_blocks = [
      "10.0.0.0/16"
    ]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "hospital-rds-sg"
  }
}

# ============================================================
# RDS SUBNET GROUP
# ============================================================

resource "aws_db_subnet_group" "hospital_db" {
  name = "hospital-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]

  tags = {
    Name = "hospital-db-subnet-group"
  }
}

# ============================================================
# RDS POSTGRESQL
# ============================================================

resource "aws_db_instance" "hospital_db" {
  identifier = "hospital-postgres-db"

  allocated_storage = 20
  storage_type      = "gp3"

  engine         = "postgres"
  engine_version = "18.6"

  instance_class = "db.t3.micro"

  db_name  = "hospitaldb"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name = aws_db_subnet_group.hospital_db.name

  vpc_security_group_ids = [
    aws_security_group.rds.id
  ]

  publicly_accessible = false

  skip_final_snapshot = true

  deletion_protection = false

  tags = {
    Name = "hospital-postgres-db"
  }
}
