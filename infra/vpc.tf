module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.16"

  name = "${var.project_name}-vpc"
  cidr = "10.42.0.0/16"

  azs            = local.azs
  public_subnets = ["10.42.1.0/24", "10.42.2.0/24"]

  # Cost/simplicity tradeoff for this exercise: nodes live in public subnets
  # behind security groups, avoiding a NAT gateway (~$35/month + per-GB).
  # Production layout: nodes in private subnets + NAT or VPC endpoints.
  enable_nat_gateway      = false
  map_public_ip_on_launch = true

  enable_dns_support   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1" # lets Kubernetes place load balancers here
  }
}
