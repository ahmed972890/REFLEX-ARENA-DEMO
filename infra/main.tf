data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name = "${var.project_name}-eks"
  table_name   = "${var.project_name}-scores"

  # Kept in sync with k8s/ manifests (namespace + ServiceAccount are the
  # contract between Terraform-managed identity and CI-deployed workloads).
  namespace               = "reflex"
  backend_service_account = "reflex-backend"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}
