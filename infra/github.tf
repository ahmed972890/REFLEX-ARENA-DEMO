# GitHub Actions authenticates to AWS with short-lived OIDC tokens —
# no long-lived AWS keys stored as GitHub secrets.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  github_owner             = split("/", var.github_repository)[0]
  github_repo_name         = split("/", var.github_repository)[1]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only the main branch of this exact repository can deploy. Two sub formats
    # are accepted: the classic `repo:owner/name:...` and GitHub's ID-stamped
    # `repo:owner@<owner-id>/name@<repo-id>:...` (rename-attack hardening).
    # Wildcarding only the numeric IDs keeps the trust anchored to the unique
    # owner login + repo name.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        # Plain jobs on main (sub ends in :ref:refs/heads/main)...
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${local.github_owner}@*/${local.github_repo_name}@*:ref:refs/heads/main",
        # ...and the deploy job, whose sub is environment-scoped instead.
        "repo:${var.github_repository}:environment:production",
        "repo:${local.github_owner}@*/${local.github_repo_name}@*:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource scoping
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [for repo in aws_ecr_repository.service : repo.arn]
  }

  statement {
    sid       = "DescribeCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

# Kubernetes-side permissions via EKS access entries (the modern replacement
# for the aws-auth ConfigMap), admin scoped to the app namespace only.
resource "aws_eks_access_entry" "github_deploy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_deploy.arn
  # The AmazonEKSAdminPolicy below covers built-in resources; custom resources
  # (ESO's ExternalSecret/SecretStore) are granted through this group via a
  # namespaced Role — see kubernetes_role.deployer_crds.
  kubernetes_groups = ["reflex-deployers"]
}

resource "kubernetes_role" "deployer_crds" {
  metadata {
    name      = "deployer-external-secrets"
    namespace = kubernetes_namespace.reflex.metadata[0].name
  }

  rule {
    api_groups = ["external-secrets.io"]
    resources  = ["externalsecrets", "secretstores"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  depends_on = [helm_release.external_secrets]
}

resource "kubernetes_role_binding" "deployer_crds" {
  metadata {
    name      = "deployer-external-secrets"
    namespace = kubernetes_namespace.reflex.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.deployer_crds.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "reflex-deployers"
  }
}

resource "aws_eks_access_policy_association" "github_deploy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_deploy.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [local.namespace]
  }

  depends_on = [aws_eks_access_entry.github_deploy]
}
