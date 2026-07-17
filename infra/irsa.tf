# IRSA: the backend pod assumes this role through the cluster's OIDC provider.
# No AWS credentials are ever stored in the cluster or the repo.
data "aws_iam_policy_document" "backend_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.namespace}:${local.backend_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend" {
  name               = "${var.project_name}-backend"
  assume_role_policy = data.aws_iam_policy_document.backend_assume.json
}

# Least privilege: exactly the DynamoDB operations the app performs, on this
# table and its indexes only.
data "aws_iam_policy_document" "backend_dynamodb" {
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:DescribeTable",
    ]
    resources = [
      aws_dynamodb_table.scores.arn,
      "${aws_dynamodb_table.scores.arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "backend_dynamodb" {
  name   = "dynamodb-scores"
  role   = aws_iam_role.backend.id
  policy = data.aws_iam_policy_document.backend_dynamodb.json
}
