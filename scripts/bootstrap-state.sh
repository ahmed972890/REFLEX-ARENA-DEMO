#!/usr/bin/env bash
# One-time bootstrap of the Terraform remote-state backend:
#   - S3 bucket (versioned, encrypted, public access blocked) for the state
#   - DynamoDB table for state locking
# Then writes infra/backend.hcl (gitignored: contains the account-specific
# bucket name). Idempotent — safe to re-run.
set -euo pipefail

REGION="${AWS_REGION:-eu-west-3}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="reflex-tfstate-${ACCOUNT}"
TABLE="reflex-tf-locks"

if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "creating state bucket s3://${BUCKET}"
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=${REGION}"
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

if ! aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "creating lock table ${TABLE}"
  aws dynamodb create-table --table-name "$TABLE" --region "$REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
fi

cat > "$(cd "$(dirname "$0")/.." && pwd)/infra/backend.hcl" <<EOF
bucket         = "${BUCKET}"
key            = "reflex/terraform.tfstate"
region         = "${REGION}"
dynamodb_table = "${TABLE}"
encrypt        = true
EOF

echo "✔ backend ready: s3://${BUCKET} + dynamodb ${TABLE} → infra/backend.hcl"
