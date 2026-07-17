def test_healthz(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readyz(client):
    assert client.get("/readyz").status_code == 200


def test_submit_and_leaderboard_ordering(client):
    client.post("/api/scores", json={"player": "Slow Sam", "score_ms": 480})
    client.post("/api/scores", json={"player": "Fast Fatma", "score_ms": 190})
    client.post("/api/scores", json={"player": "Mid Mo", "score_ms": 300})

    body = client.get("/api/leaderboard").json()
    players = [entry["player"] for entry in body["entries"]]
    assert players == ["Fast Fatma", "Mid Mo", "Slow Sam"]
    assert [entry["rank"] for entry in body["entries"]] == [1, 2, 3]


def test_personal_best_is_kept(client):
    first = client.post("/api/scores", json={"player": "ahmed", "score_ms": 250}).json()
    assert first["improved"] is True and first["best_ms"] == 250

    worse = client.post("/api/scores", json={"player": "ahmed", "score_ms": 400}).json()
    assert worse["improved"] is False
    assert worse["best_ms"] == 250  # best untouched

    better = client.post("/api/scores", json={"player": "ahmed", "score_ms": 180}).json()
    assert better["improved"] is True and better["best_ms"] == 180

    entries = client.get("/api/leaderboard").json()["entries"]
    assert len(entries) == 1  # one row per player, not one per attempt
    assert entries[0]["games"] == 3


def test_rank_reflects_other_players(client):
    client.post("/api/scores", json={"player": "Ace", "score_ms": 150})
    result = client.post("/api/scores", json={"player": "Rookie", "score_ms": 500}).json()
    assert result["rank"] == 2


def test_validation_rejected(client):
    bad_payloads = [
        {"player": "x", "score_ms": 200},  # name too short
        {"player": "notre-équipe!", "score_ms": 200},  # disallowed characters
        {"player": "Cheater", "score_ms": 10},  # sub-human reaction time
        {"player": "Sleeper", "score_ms": 999_999},  # absurdly slow
    ]
    for payload in bad_payloads:
        assert client.post("/api/scores", json=payload).status_code == 422, payload


def test_leaderboard_limit_bounds(client):
    assert client.get("/api/leaderboard?limit=0").status_code == 422
    assert client.get("/api/leaderboard?limit=9999").status_code == 422


def test_stats(client):
    client.post("/api/scores", json={"player": "ahmed", "score_ms": 250})
    client.post("/api/scores", json={"player": "ahmed", "score_ms": 300})
    client.post("/api/scores", json={"player": "Nour", "score_ms": 210})

    body = client.get("/api/stats").json()
    assert body["total_submissions"] == 3
    assert body["players"] == 2


def test_metrics_exposed(client):
    client.get("/api/leaderboard")
    text = client.get("/metrics").text
    assert "http_requests_total" in text
    assert "http_request_duration_seconds" in text


def test_request_id_propagation(client):
    response = client.get("/healthz", headers={"x-request-id": "trace-me-123"})
    assert response.headers["x-request-id"] == "trace-me-123"
