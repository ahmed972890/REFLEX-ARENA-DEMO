import os

# Must be set before the app modules are imported (Settings reads env at first use).
os.environ.update(
    {
        "ENVIRONMENT": "test",
        "AWS_REGION": "eu-west-3",
        "DYNAMODB_TABLE": "reflex-scores-test",
        "AUTO_CREATE_TABLE": "true",
        "AWS_ACCESS_KEY_ID": "testing",
        "AWS_SECRET_ACCESS_KEY": "testing",
        "AWS_SECURITY_TOKEN": "testing",
        "AWS_SESSION_TOKEN": "testing",
    }
)

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from moto import mock_aws  # noqa: E402

from app import db  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402


def _fresh_client():
    get_settings.cache_clear()  # settings are cached; re-read the (monkeypatched) env
    db._table = None  # force a fresh boto3 resource inside the moto context
    return TestClient(app)  # entering it runs the lifespan → creates the table


@pytest.fixture
def client(monkeypatch):
    monkeypatch.delenv("INTERNAL_API_TOKEN", raising=False)
    with mock_aws():
        with _fresh_client() as test_client:
            yield test_client
    db._table = None
    get_settings.cache_clear()


@pytest.fixture
def client_with_token(monkeypatch):
    monkeypatch.setenv("INTERNAL_API_TOKEN", "test-token")
    with mock_aws():
        with _fresh_client() as test_client:
            yield test_client
    db._table = None
    get_settings.cache_clear()
