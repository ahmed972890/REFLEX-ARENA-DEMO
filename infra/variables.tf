variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3" # Paris
}

variable "project_name" {
  description = "Prefix for all resources. If you change it, update k8s/configmap.yaml to match."
  type        = string
  default     = "reflex"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "node_instance_type" {
  description = "Node instance type. Bump to t3.medium if pods stay Pending during scale-out."
  type        = string
  default     = "t3.small"
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "github_repository" {
  description = "GitHub repo (owner/name) allowed to deploy via OIDC from its main branch"
  type        = string
  default     = "ahmed972890/REFLEX-ARENA-DEMO"
}

variable "create_github_oidc_provider" {
  description = "Set to false if this AWS account already has the GitHub Actions OIDC provider"
  type        = bool
  default     = true
}
