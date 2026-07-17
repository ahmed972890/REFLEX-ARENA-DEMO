module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  # Public endpoint so GitHub-hosted runners and your laptop can reach the API.
  # Production hardening: private endpoint + self-hosted runners or a bastion.
  cluster_endpoint_public_access = true

  # Grants the identity running `terraform apply` cluster-admin via EKS access
  # entries, so kubectl works immediately after apply.
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = {
      most_recent = true
      # Enforce NetworkPolicy resources (k8s/networkpolicy.yaml) natively.
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    # Required by the HorizontalPodAutoscaler (CPU metrics).
    metrics-server = { most_recent = true }
    # CloudWatch agent + Fluent Bit: Container Insights metrics + pod logs.
    amazon-cloudwatch-observability = { most_recent = true }
  }

  # The metrics-server EKS addon serves the aggregated metrics API on pod
  # port 10251; the API server must reach it or HPA gets no CPU metrics
  # (APIService stays FailedDiscoveryCheck). Not in the module's defaults.
  node_security_group_additional_rules = {
    ingress_cluster_metrics_server = {
      description                   = "API server to metrics-server"
      protocol                      = "tcp"
      from_port                     = 10251
      to_port                       = 10251
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_min_size
      desired_size   = var.node_desired_size
      max_size       = var.node_max_size

      iam_role_additional_policies = {
        # Lets the CloudWatch observability addon ship metrics + logs.
        cloudwatch = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }
    }
  }
}
