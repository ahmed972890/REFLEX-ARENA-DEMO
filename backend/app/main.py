import hmac
import logging
import time
import uuid
from contextlib import asynccontextmanager

from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, Query, Request, Response
from fastapi.responses import JSONResponse

from . import db, metrics
from .config import get_settings
from .logging_setup import request_id_var, setup_logging
from .schemas import LeaderboardResponse, ScoreSubmission, Stats, SubmissionResult

logger = logging.getLogger("reflex")

# Probes and metrics are scraped constantly — keep them out of metrics/access logs.
QUIET_PATHS = {"/healthz", "/readyz", "/metrics"}


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    setup_logging(settings.log_level)
    if settings.auto_create_table:
        db.ensure_table()
    logger.info(
        "starting reflex-backend env=%s table=%s endpoint=%s",
        settings.environment,
        settings.dynamodb_table,
        settings.dynamodb_endpoint or "aws",
    )
    yield
    logger.info("shutting down reflex-backend")


app = FastAPI(title="Reflex Arena API", version="1.0.0", lifespan=lifespan)


# NOTE: Starlette runs the most recently registered middleware first, so this
# must be defined BEFORE `observability` — that way rejected requests are
# still logged and counted in metrics.
@app.middleware("http")
async def internal_auth(request: Request, call_next):
    """Only serve /api traffic that came through the frontend proxy.

    Defense in depth on top of network isolation (ClusterIP + NetworkPolicy):
    even a pod that can reach us can't use the API without the shared token.
    Health probes and metrics scraping stay tokenless.
    """
    expected = get_settings().internal_api_token
    if expected and request.url.path.startswith("/api"):
        supplied = request.headers.get("x-internal-token", "")
        if not hmac.compare_digest(supplied.encode(), expected.encode()):
            return JSONResponse(
                status_code=401, content={"detail": "missing or invalid internal token"}
            )
    return await call_next(request)


@app.middleware("http")
async def observability(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or uuid.uuid4().hex[:16]
    token = request_id_var.set(request_id)
    start = time.perf_counter()
    try:
        response = await call_next(request)
    finally:
        request_id_var.reset(token)
    duration = time.perf_counter() - start
    route = request.scope.get("route")
    path = route.path if route else "unmatched"
    if request.url.path not in QUIET_PATHS:
        metrics.HTTP_REQUESTS.labels(request.method, path, response.status_code).inc()
        metrics.HTTP_DURATION.labels(request.method, path).observe(duration)
        logger.info(
            "request",
            extra={
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": round(duration * 1000, 1),
                "client": request.client.host if request.client else None,
            },
        )
    response.headers["x-request-id"] = request_id
    return response


@app.exception_handler(ClientError)
@app.exception_handler(BotoCoreError)
async def datastore_error(request: Request, exc: Exception):
    logger.exception("datastore error")
    return JSONResponse(status_code=503, content={"detail": "datastore unavailable"})


@app.get("/")
def root():
    return {"service": "reflex-backend", "docs": "/docs", "health": "/healthz"}


@app.get("/healthz")
def healthz():
    """Liveness: the process is up and serving."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    """Readiness: we can reach the datastore. Failing pods are pulled from Service endpoints."""
    db.check_ready()
    return {"status": "ready"}


@app.get("/metrics")
def prometheus_metrics():
    payload, content_type = metrics.render()
    return Response(content=payload, media_type=content_type)


@app.post("/api/scores", response_model=SubmissionResult)
def submit_score(submission: ScoreSubmission):
    result = db.submit_score(submission.player, submission.score_ms)
    metrics.SCORES_SUBMITTED.labels(str(result["improved"]).lower()).inc()
    return result


@app.get("/api/leaderboard", response_model=LeaderboardResponse)
def get_leaderboard(limit: int = Query(default=10, ge=1, le=get_settings().leaderboard_max_limit)):
    return {"entries": db.leaderboard(limit)}


@app.get("/api/stats", response_model=Stats)
def get_stats():
    return db.stats()
