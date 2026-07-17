# ---- build stage: install dependencies into an isolated venv ----
FROM python:3.12-slim AS build
WORKDIR /src
RUN python -m venv /venv
ENV PATH="/venv/bin:$PATH"
COPY pyproject.toml ./
COPY app ./app
RUN pip install --no-cache-dir .

# ---- runtime stage: minimal image, non-root, no build tools ----
FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/venv/bin:$PATH"
COPY --from=build /venv /venv
COPY app /app/app
WORKDIR /app
RUN useradd --uid 10001 --no-create-home appuser
USER 10001
EXPOSE 8000
# Used by docker-compose; Kubernetes relies on its own probes instead.
HEALTHCHECK --interval=15s --timeout=3s --retries=3 CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status==200 else 1)"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--no-access-log", "--no-server-header", "--timeout-graceful-shutdown", "10"]
