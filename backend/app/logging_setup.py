import json
import logging
from contextvars import ContextVar
from datetime import UTC, datetime

# Propagated by the middleware so every log line within a request carries the same id.
request_id_var: ContextVar[str] = ContextVar("request_id", default="-")

_EXTRA_FIELDS = ("method", "path", "status", "duration_ms", "client")


class JsonFormatter(logging.Formatter):
    """One JSON object per line — directly queryable in CloudWatch Logs Insights."""

    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": datetime.now(UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": request_id_var.get(),
        }
        for key in _EXTRA_FIELDS:
            value = getattr(record, key, None)
            if value is not None:
                entry[key] = value
        if record.exc_info:
            entry["exc_info"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def setup_logging(level: str) -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())
    # Uvicorn's plain-text access log is replaced by our structured one in main.py.
    logging.getLogger("uvicorn.access").disabled = True
