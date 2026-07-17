output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_backend" {
  value = aws_ecr_repository.service["backend"].repository_url
}

output "ecr_frontend" {
  value = aws_ecr_repository.service["frontend"].repository_url
}

output "dynamodb_table" {
  value = aws_dynamodb_table.scores.name
}

output "github_deploy_role_arn" {
  description = "Set this as the AWS_ROLE_ARN variable on the GitHub repository"
  value       = aws_iam_role.github_deploy.arn
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "frontend_url_command" {
  description = "Run after the first deploy to get the public URL"
  value       = "kubectl get svc reflex-frontend -n reflex -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}'"
}
