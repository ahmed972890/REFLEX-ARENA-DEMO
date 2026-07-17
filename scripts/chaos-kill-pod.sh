#!/usr/bin/env bash
# Reliability demo: delete a random backend pod mid-load-test and watch the
# error rate stay flat — readiness probes + multiple replicas + the Service
# absorb the failure, and the Deployment immediately replaces the pod.
set -euo pipefail

POD=$(kubectl -n reflex get pods -l app=reflex-backend -o name |
  awk 'BEGIN{srand()} {a[NR]=$0} END{print a[int(rand()*NR)+1]}')

[ -n "$POD" ] || { echo "no backend pods found"; exit 1; }

echo "💥 Deleting $POD"
kubectl -n reflex delete "$POD" --wait=false
echo
kubectl -n reflex get pods -l app=reflex-backend
