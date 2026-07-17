# Runbook

Operational cheat-sheet for the deployed system. All commands assume
`make kubeconfig` has been run.

## Where is everything?

```bash
make url                                   # public URL (NLB hostname)
kubectl -n reflex get all                  # pods, services, deployments, HPA
terraform -chdir=infra output              # cluster name, ECR URLs, role ARNs
```

## Logs

```bash
kubectl -n reflex logs deploy/reflex-backend -f          # live backend logs (JSON)
kubectl -n reflex logs deploy/reflex-frontend -f         # nginx access/error logs
```

CloudWatch Logs Insights (log group `/aws/containerinsights/reflex-eks/application`):

```
fields ts, message, method, path, status, duration_ms, request_id
| filter kubernetes.namespace_name = "reflex"
| filter status >= 500
| sort ts desc
| limit 50
```

Trace one request end-to-end: take the `x-request-id` response header and filter
`request_id = "<id>"` — nginx injects it, FastAPI logs it, and it comes back on the response.

## Metrics

- CloudWatch → Container Insights → cluster `reflex-eks`: CPU/memory per pod, replica
  counts, restarts, network.
- Raw Prometheus metrics (cluster-internal by design):
  `kubectl -n reflex port-forward deploy/reflex-backend 8000:8000` →
  `curl localhost:8000/metrics`

## Deploy / rollback

Every push to `main` deploys. Manual operations:

```bash
kubectl -n reflex rollout undo deploy/reflex-backend     # instant rollback to previous SHA
kubectl -n reflex rollout history deploy/reflex-backend  # what ran when
```

(Or re-run the "deploy" job of any previous green pipeline run — images are tagged by
commit SHA and stay in ECR, so any historical version is redeployable.)

## Scale manually

```bash
kubectl -n reflex scale deploy/reflex-backend --replicas=6   # HPA will reconcile later
kubectl -n reflex edit hpa reflex-backend                    # change min/max/target
```

Node capacity is a Terraform variable: `node_desired_size` / `node_max_size` in
`infra/variables.tf`, then `make tf-apply`.

## Common failures

| Symptom | Likely cause / fix |
|---|---|
| Pods `Pending` during scale-out | Nodes full — raise `node_max_size` or use `t3.medium` (`infra/variables.tf`). This is the HPA hitting the node ceiling: expected at max load on 2×t3.small. |
| `ImagePullBackOff` | Image tag not in ECR (pipeline pushed?) or manually-built arm64 image from a Mac — CI builds amd64; build locally with `--platform linux/amd64`. |
| Backend `/readyz` failing, pods not Ready | DynamoDB unreachable: check the ServiceAccount annotation (`kubectl -n reflex get sa reflex-backend -o yaml`) matches the IAM role, and the table exists. |
| Frontend LB stuck `<pending>` | Subnets missing the `kubernetes.io/role/elb` tag (Terraform sets it) or AWS LB quota reached. |
| Pipeline "could not assume role" | `AWS_ROLE_ARN` repo variable unset, or repo/branch doesn't match the OIDC trust (`infra/variables.tf` → `github_repository`, `main` only). |
| Pods stuck `CreateContainerConfigError` | The `reflex-internal` Secret is missing — ESO hasn't synced. `kubectl -n reflex describe externalsecret reflex-internal` (look at status), check the `reflex-eso` ServiceAccount annotation and that the ESO pods in `external-secrets` namespace are running. |
| API returns 401 through the frontend | Frontend and backend pods hold different token versions (e.g. after a rotation) — `kubectl -n reflex rollout restart deploy` to re-read the Secret. |
| Backend unreachable from a debug pod | Expected! The NetworkPolicy only admits frontend pods. Test through the frontend, or temporarily label your debug pod `app=reflex-frontend`. |
| `terraform destroy` hangs on VPC | The k8s-created NLB still exists — run `make down-cloud` instead (deletes Service first). |

## Rotate the internal token

```bash
aws secretsmanager put-secret-value --secret-id reflex/internal-api-token \
  --secret-string "$(openssl rand -hex 32)" --region eu-west-3
kubectl -n reflex annotate externalsecret reflex-internal force-sync=$(date +%s) --overwrite
kubectl -n reflex rollout restart deploy/reflex-backend deploy/reflex-frontend
```

## Terraform state

State lives in `s3://reflex-tfstate-<account-id>` (versioned — old states recoverable via
S3 versions) with locks in the `reflex-tf-locks` DynamoDB table. `make tf-init` re-creates
`infra/backend.hcl` on a new machine. These two bootstrap resources are intentionally
outside Terraform — delete them manually at the very end if you're closing the account.

## Full teardown

```bash
make down-cloud    # kubectl delete -k k8s/ → wait for NLB release → terraform destroy
```

Verify nothing is left billing: `aws elbv2 describe-load-balancers --region eu-west-3` should
list none, EC2 console shows no running instances, EKS console shows no cluster.
