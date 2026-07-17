from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """All runtime configuration comes from environment variables.

    Locally these are set by docker-compose; on EKS by a ConfigMap.
    No secrets live here: AWS access is ambient (IRSA in-cluster,
    dummy credentials against DynamoDB Local in dev).
    """

    environment: str = "local"
    aws_region: str = "eu-west-3"
    dynamodb_table: str = "reflex-scores"
    dynamodb_endpoint: str | None = None  # set to http://dynamodb:8000 for DynamoDB Local
    auto_create_table: bool = False  # local/dev convenience; the real table is Terraform-managed
    log_level: str = "INFO"
    leaderboard_max_limit: int = 50
    # When set, /api/* requests must carry a matching X-Internal-Token header.
    # The frontend proxy injects it (sourced from AWS Secrets Manager via
    # External Secrets in-cluster), so the backend only serves proxied traffic.
    internal_api_token: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
