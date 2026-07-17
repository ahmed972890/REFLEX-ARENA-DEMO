# The internal service token: generated here, stored ONLY in AWS Secrets
# Manager, synced into the cluster by External Secrets. It never appears in
# the repo, in GitHub, or in Terraform variables (it does live in TF state —
# which is why state is in a private, encrypted S3 bucket).
resource "random_password" "internal_token" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "internal_token" {
  name        = "reflex/internal-api-token"
  description = "Shared token the frontend proxy presents to the Reflex backend"
  # No recovery window so destroy/recreate cycles work during the exercise.
  # Production would keep the default 30-day window.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "internal_token" {
  secret_id     = aws_secretsmanager_secret.internal_token.id
  secret_string = random_password.internal_token.result
}
