# Get available AZs
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# VPC Module with proper tagging and NAT configuration
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags for EKS
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

# EKS Cluster with IRSA and proper add-ons
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  /* cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    kube-proxy = {}
    vpc-cni = {
      preserve = true
    }
  } */

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["t3.small"]
    capacity_type  = "SPOT"

    # Required for proper cleanup
    create_launch_template = true
    launch_template_name   = ""
  }

  eks_managed_node_groups = {
    primary = {
      name           = "node-group-primary"
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      instance_types = ["t3.small"]
    }
  }

  # CloudWatch logging
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  cloudwatch_log_group_retention_in_days = 7

  tags = {
    Environment = var.environment
  }
}

# EBS CSI IAM Role
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  depends_on = [module.eks]
  source     = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version    = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

# GitHub Actions OIDC Provider
/* resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1" # GitHub's current thumbprint
  ]
} */

# GitHub Actions IAM Role with least privilege
/* resource "aws_iam_role" "github_actions_deploy" {
  name = "github-actions-deploy-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}",
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "github_ecr_access" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "github_eks_access" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
} */

# Kubernetes Providers
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.aws_eks_cluster.this.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# Cert-Manager with proper dependency handling
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.13.2"

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "prometheus.enabled"
    value = "false"
  }
}

resource "time_sleep" "wait_for_cert_manager" {
  depends_on      = [helm_release.cert_manager]
  create_duration = "300s"
}

resource "kubernetes_manifest" "cluster_issuer" {
  depends_on = [time_sleep.wait_for_cert_manager]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [{
          http01 = {
            ingress = {
              class = "nginx"
            }
          }
        }]
      }
    }
  }
}

# Application Deployment Resources
resource "kubernetes_service_v1" "nodejs_service" {
  metadata {
    name = "nodejs-service"
  }
  spec {
    selector = {
      app = "nodejs-${var.active_color}"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

# Metrics Server for HPA
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.0"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}


# New Changes
resource "helm_release" "cloudwatch_agent" {
  name             = "cloudwatch-agent"
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  namespace        = "amazon-cloudwatch"
  create_namespace = true

  #values = ["${path.module}/helm/cloudwatch-values.yaml"]
  values = [<<EOF
cloudWatch:
  enabled: true
  logGroupName: "/aws/containerinsights/nodejs-eks-cluster/application"
  logStreamPrefix: "fluentbit"
  region: "us-east-1"

extraOutputs:
  createLogGroup: true

serviceAccount:
  create: true
  name: "fluentbit-sa"
EOF
  ]
}

resource "helm_release" "container_insights" {
  name             = "aws-cloudwatch-metrics"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-cloudwatch-metrics"
  namespace        = "amazon-cloudwatch"
  create_namespace = true

  values = [<<EOF
clusterName: ${var.cluster_name}
region: ${var.aws_region}
serviceAccount:
  create: true
  name: cloudwatch-agent
EOF
  ]
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "High-CPU-Usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 60
  metric_name         = "cpu_usage_total"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  dimensions = {
    ClusterName = var.cluster_name
  }

  alarm_description = "Triggers if CPU usage > 60%"
  alarm_actions     = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "High-Memory-Usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 60
  metric_name         = "memory_usage_total"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"

  dimensions = {
    ClusterName = var.cluster_name
  }

  alarm_description = "Triggers if Memory usage > 60%"
  alarm_actions     = [aws_sns_topic.alerts.arn]
}

resource "aws_sns_topic" "alerts" {
  name = "eks-alerts-topic"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email
}
