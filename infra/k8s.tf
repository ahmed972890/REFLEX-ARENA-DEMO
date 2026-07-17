# Identity plumbing lives with the infrastructure; workloads (Deployments,
# Services, HPA...) are applied by the CI pipeline from k8s/.
resource "kubernetes_namespace" "reflex" {
  metadata {
    name = local.namespace
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_account" "backend" {
  metadata {
    name      = local.backend_service_account
    namespace = kubernetes_namespace.reflex.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.backend.arn
    }
  }
}
