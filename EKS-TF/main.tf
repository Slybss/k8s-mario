# Define IAM Policy Document for Assume Role for EKS Cluster
data "aws_iam_policy_document" "assume_role_eks" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Define IAM Policy Document for Assume Role for EKS Node Group
data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Create IAM Role for EKS Cluster
resource "aws_iam_role" "example" {
  name               = "eks-cluster-cloud1"
  assume_role_policy = data.aws_iam_policy_document.assume_role_eks.json
}

# Attach AmazonEKSClusterPolicy to IAM Role
resource "aws_iam_role_policy_attachment" "example-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.example.name
}

# Attach AmazonEKSVPCResourceController to IAM Role
resource "aws_iam_role_policy_attachment" "example-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.example.name
}

# Get Default VPC Data
data "aws_vpc" "default" {
  default = true
}

# Get All Subnets in the Default VPC
data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get Details for Each Subnet
data "aws_subnet" "all" {
  count = length(data.aws_subnets.all.ids)
  id    = element(data.aws_subnets.all.ids, count.index)
}

# Filter Subnets in Supported Availability Zones
locals {
  supported_azs = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  public_subnet_ids = [
    for subnet in data.aws_subnet.all : subnet.id
    if contains(local.supported_azs, subnet.availability_zone)
  ]
}

# Provision EKS Cluster
resource "aws_eks_cluster" "example" {
  name     = "SYLVUDE_EKS_CLOUD"
  role_arn = aws_iam_role.example.arn

  vpc_config {
    subnet_ids = local.public_subnet_ids
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.example-AmazonEKSVPCResourceController,
  ]
}

# Output the EKS Cluster Endpoint
output "endpoint" {
  value = aws_eks_cluster.example.endpoint
}

# Output the EKS Cluster Certificate Authority Data
output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.example.certificate_authority[0].data
}

# Create IAM Role for EKS Node Group
resource "aws_iam_role" "node_group" {
  name               = "eks-node-group-cloud1"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
}

# Attach AmazonEKSWorkerNodePolicy to IAM Role
resource "aws_iam_role_policy_attachment" "example-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

# Attach AmazonEKS_CNI_Policy to IAM Role
resource "aws_iam_role_policy_attachment" "example-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

# Attach AmazonEC2ContainerRegistryReadOnly to IAM Role
resource "aws_iam_role_policy_attachment" "example-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# Create Node Group for EKS Cluster
resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.example.name
  node_group_name = "Node-cloud"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = local.public_subnet_ids

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  instance_types = ["t2.medium"]

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.example-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.example-AmazonEC2ContainerRegistryReadOnly,
  ]
}
