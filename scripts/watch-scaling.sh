#!/usr/bin/env bash
# Live view for the autoscaling demo — run this in a second terminal while
# `make loadtest URL=...` hammers the app, and watch replicas climb.
set -euo pipefail

NS=reflex
while true; do
  clear
  date
  echo
  echo "── HPA ─────────────────────────────────────────────"
  kubectl -n "$NS" get hpa
  echo
  echo "── Deployments ─────────────────────────────────────"
  kubectl -n "$NS" get deploy
  echo
  echo "── Pod CPU / memory ────────────────────────────────"
  kubectl -n "$NS" top pods 2>/dev/null || echo "(metrics-server still warming up)"
  sleep 3
done
