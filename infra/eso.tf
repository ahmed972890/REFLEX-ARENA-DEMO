# External Secrets Operator: watches ExternalSecret resources (k8s/) and
# materializes k8s Secrets from AWS Secrets Manager.
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
  timeout          = 600
  # Chart version intentionally floating for this exercise; pin in production.

  depends_on = [module.eks]
}

# IRSA identity the SecretStore uses (spec.provider.aws.auth.jwt) — scoped to
# reading exactly one secret.
data "aws_iam_policy_document" "eso_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.namespace}:reflex-eso"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.project_name}-eso"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
}

data "aws_iam_policy_document" "eso_read_secret" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.internal_token.arn]
  }
}

resource "aws_iam_role_policy" "eso_read_secret" {
  name   = "read-internal-token"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_read_secret.json
}

resource "kubernetes_service_account" "eso" {
  metadata {
    name      = "reflex-eso"
    namespace = kubernetes_namespace.reflex.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.eso.arn
    }
  }
}
