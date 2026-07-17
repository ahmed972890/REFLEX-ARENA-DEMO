def test_api_rejected_without_token(client_with_token):
    assert client_with_token.get("/api/leaderboard").status_code == 401


def test_api_rejected_with_wrong_token(client_with_token):
    response = client_with_token.get(
        "/api/leaderboard", headers={"x-internal-token": "not-the-token"}
    )
    assert response.status_code == 401


def test_api_accepted_with_token(client_with_token):
    response = client_with_token.get("/api/leaderboard", headers={"x-internal-token": "test-token"})
    assert response.status_code == 200

    submit = client_with_token.post(
        "/api/scores",
        json={"player": "Proxied", "score_ms": 240},
        headers={"x-internal-token": "test-token"},
    )
    assert submit.status_code == 200


def test_probes_and_metrics_stay_open(client_with_token):
    """Kubelet probes and Prometheus scrapes must work without the token."""
    assert client_with_token.get("/healthz").status_code == 200
    assert client_with_token.get("/readyz").status_code == 200
    assert client_with_token.get("/metrics").status_code == 200


def test_api_open_when_token_not_configured(client):
    assert client.get("/api/leaderboard").status_code == 200
