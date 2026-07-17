# Key technical decisions

Short ADR-style notes: what was chosen, why, and what was consciously traded away.

## 1. EKS (Kubernetes) rather than ECS/App Runner

**Chosen:** a real EKS cluster with a managed node group, HPA, probes, PDBs.
**Why:** the scaling/reliability requirements map naturally onto Kubernetes primitives, and
they're demonstrable (`kubectl get hpa -w` during a load test is a great demo). It also
reflects the platform I'd expect to operate in production.
**Traded away:** cost and setup time — a managed container service would be cheaper and
simpler for an app this small. Kept lean deliberately: one node group, no service mesh, no
extra controllers.

## 2. DynamoDB rather than RDS Postgres

**Chosen:** single-table DynamoDB, on-demand billing.
**Why:** the access pattern is tiny and known (submit score, top-N leaderboard, stats); the
load story is the centerpiece of the exercise, and on-demand DynamoDB absorbs spikes with no
capacity management, no connection pools, no failover drills. The "keep only your personal
best" rule is a **conditional write** (`attribute_not_exists(pk) OR best_ms > :new`), which is
race-free under concurrency without transactions. Pennies at demo volume.
**Traded away:** SQL expressiveness and familiarity. Known limit: the leaderboard GSI uses a
single `LB` partition — fine to ~1000 writes/s; beyond that the standard fix is write-sharding
(`LB#0..N` + scatter-gather reads).

## 3. NLB via the Service, not the AWS Load Balancer Controller

**Chosen:** `Service type=LoadBalancer` (in-tree NLB) on the frontend only.
**Why:** zero extra controllers/IAM/webhooks to install and debug in a 3-day window; a public
URL with the same reliability properties.
**Traded away:** ALB features (path routing, ACM TLS, WAF). Upgrade path is documented and
non-breaking: install the LB controller, switch to Ingress. TLS is omitted because there's no
domain to attach a cert to — the pragmatic add-on would be CloudFront in front of the NLB.

## 4. Zero static credentials: GitHub OIDC + IRSA

**Chosen:** CI assumes an IAM role via GitHub's OIDC provider (trust bound to
`repo:<owner>/<repo>:ref:refs/heads/main`); pods get DynamoDB access via IRSA.
**Why:** leaked-credential risk drops to ~zero, rotation is a non-issue, and each principal
gets least privilege (CI: push to two ECR repos + describe the cluster + namespace-scoped k8s
rights via EKS access entries; backend: five DynamoDB actions on one table).
**Traded away:** slightly more Terraform. Worth it everywhere, not just in interviews.

## 5. kustomize rather than Helm

**Chosen:** plain manifests + kustomize, CI pins images with `kustomize edit set image`.
**Why:** one app, one environment — there's nothing to template. Manifests stay readable and
`kubectl diff`-able; the git SHA image tag makes every release immutable and traceable.
**Traded away:** multi-env value files. If a second environment appears, kustomize overlays
cover it before Helm is needed.

## 6. Public subnets for nodes (no NAT gateway)

**Chosen:** nodes in public subnets behind security groups, public IPs for egress.
**Why:** a NAT gateway is ~$35/month + per-GB — the single most expensive line item this
exercise doesn't need. Security groups still only admit NLB traffic to the node ports.
**Traded away:** the production-grade layout (private subnets + NAT or VPC endpoints for
ECR/DynamoDB). Called out rather than hidden.

## 7. k6 rather than Locust

**Chosen:** k6 scripts with thresholds (`p95 < 800ms`, `errors < 1%`) as code.
**Why:** single binary, already available; thresholds make the load test pass/fail rather
than eyeball-judged; the ramp/spike/cooldown profile is 10 lines.
**Traded away:** Locust would match the Python stack, but adds a runtime for no extra signal.

## 8. Same-origin API through the nginx proxy (no CORS)

**Chosen:** the SPA calls `/api/*` on its own origin; nginx proxies to the backend Service.
**Why:** no CORS configuration to get wrong, the backend (with `/docs` and `/metrics`) is
never internet-reachable, and request IDs can be injected at the edge (`$request_id`) for
end-to-end log correlation.
**Traded away:** an extra hop (~1ms in-cluster) and the frontend/backend can't be split
across domains without revisiting.

## 9. Remote Terraform state: S3 + DynamoDB locking

**Chosen:** state in a versioned, encrypted, access-blocked S3 bucket with a DynamoDB lock
table, bootstrapped by an idempotent script (`scripts/bootstrap-state.sh`) that generates the
gitignored `infra/backend.hcl`.
**Why:** the state contains sensitive material (the internal token, cluster CA); versioning
gives state history/recovery; locking prevents concurrent-apply corruption. The
bootstrap-script pattern solves the chicken-and-egg (the backend can't create itself).
**Traded away:** a small out-of-band bootstrap step. Next step on a team: plan-on-PR /
apply-on-merge pipeline using the same backend.

## 10. Backend isolation: token + NetworkPolicy, not just ClusterIP

**Chosen:** three layers — (1) the backend Service is ClusterIP (no external route),
(2) a NetworkPolicy admits only frontend pods (enforced by the VPC CNI network-policy
agent), (3) nginx injects an `X-Internal-Token` header on every proxied `/api` request and
the backend 401s anything without it (constant-time compare).
**Why:** defense in depth — each layer fails independently (a misconfigured Service, a
CNI without policy enforcement, a compromised neighbouring pod). The token also gives the
secrets pipeline something real to manage end-to-end.
**Traded away:** a shared static token is not per-client auth (no identity, no rotation on
compromise without redeploy). Real user-facing auth would be OIDC/JWT at the edge; this is
service-to-service hardening for an internal hop.

## 11. External Secrets Operator + AWS Secrets Manager

**Chosen:** the token is generated by Terraform (`random_password`), stored only in AWS
Secrets Manager, and synced into a k8s Secret by ESO through an IRSA role that can read
exactly that one secret. Workload manifests reference the k8s Secret; CI never sees the value.
**Why:** one source of truth with rotation support and audit; no secret material in git,
GitHub variables, or kustomize output. ESO is the k8s-idiomatic bridge and the SecretStore /
ExternalSecret resources are plain namespaced YAML the pipeline can own.
**Traded away:** an extra controller. Alternatives considered: Secrets Store CSI driver
(mount-based, no k8s Secret object — but clunkier env-var story), sealed-secrets (secret
ciphertext lives in git — exactly what we want to avoid demonstrating).
