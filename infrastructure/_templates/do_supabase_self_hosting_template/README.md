# DigitalOcean Supabase Self-Hosting Template

Deploys a full Supabase stack on DigitalOcean Kubernetes (DOKS). All 13 services run as K8s Deployments with nginx-ingress for TLS termination and cert-manager for automatic Let's Encrypt certificates.

Estimated cost: ~$60-70/mo (single s-4vcpu-8gb node + DO Load Balancer).

## Local Testing

The default backend is S3 (DO Spaces), used by Staticbot in production. For local testing, switch to a local backend:

```bash
# 1. Remove any existing state/lock from a previous init
rm -rf .terraform .terraform.lock.hcl

# 2. Switch to local backend
cp backend_override.tf.local backend_override.tf

# 3. Create your tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with real values (DO API token, domain, secrets)

# 4. Init and plan
tofu init
tofu plan

# 5. Apply (creates real DO resources — costs money!)
tofu apply

# 6. Point your DNS A record to the load balancer IP from the output
# 7. Clean up when done
tofu destroy
```

The `backend_override.tf` file is gitignored (`*_override.tf` pattern). It overrides the S3 backend in `backend.tf` with a local file backend so `tofu init` doesn't prompt for Spaces credentials.

## Architecture

```
Internet → DO Load Balancer → nginx-ingress → Kong (API Gateway) → Supabase services
                                            → Studio (Dashboard)
```

All services run in a `supabase` K8s namespace. Inter-service communication uses K8s DNS (e.g. `db.supabase.svc.cluster.local`).

### Services

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| PostgreSQL | supabase/postgres:15.8.1.085 | 5432 | Database (custom extensions) |
| Kong | kong/kong:3.9.1 | 8000 | API gateway, routing |
| Auth (GoTrue) | supabase/gotrue:v2.186.0 | 9999 | Authentication |
| PostgREST | postgrest/postgrest:v14.6 | 3000 | Auto-generated REST API |
| Realtime | supabase/realtime:v2.76.5 | 4000 | WebSocket subscriptions |
| Storage + ImgProxy | supabase/storage-api:v1.44.2 + darthsim/imgproxy:v3.30.1 | 5000/5001 | File storage (shared pod) |
| Studio | supabase/studio:2026.03.16-sha-5528817 | 3000 | Dashboard UI |
| Meta | supabase/postgres-meta:v0.95.2 | 8080 | Database management API |
| Analytics | supabase/logflare:1.31.2 | 4000 | Log analytics |
| Functions | supabase/edge-runtime:v1.71.2 | 9000 | Edge functions (Deno) |
| Supavisor | supabase/supavisor:2.7.4 | 5432/6543 | Connection pooler |
| Vector | timberio/vector:0.53.0-alpine | 9001 | Log forwarding |

### Storage

- **PostgreSQL data**: 10Gi DO Block Storage PVC
- **Storage files**: 10Gi DO Block Storage PVC (shared between Storage and ImgProxy via multi-container pod)
- **Functions**: 1Gi DO Block Storage PVC (seeded with default functions via init container)

## Production Use (via Staticbot)

The S3 backend in `backend.tf` uses DO Spaces (S3-compatible) for remote state. Staticbot generates `backend.hcl` with the user's Spaces credentials:

```bash
tofu init -backend-config=backend.hcl
```

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Providers (DO, K8s, Helm) |
| `variables.tf` | All configurable variables |
| `backend.tf` | S3 backend (DO Spaces, for production) |
| `backend_override.tf.local` | Local backend template (copy to `backend_override.tf` for local testing) |
| `backend.hcl` | DO Spaces backend config template |
| `network.tf` | DO VPC |
| `cluster.tf` | DOKS cluster + node pool |
| `storage.tf` | PVCs (db, storage, functions) |
| `k8s-namespace.tf` | Namespace, Secrets, ConfigMaps, RBAC |
| `k8s-services-data.tf` | PostgreSQL, Vector |
| `k8s-services-core.tf` | Auth, PostgREST, Realtime, Storage+ImgProxy |
| `k8s-services-gateway.tf` | Kong, Studio, Meta, Analytics, Functions, Supavisor |
| `ingress.tf` | nginx-ingress, cert-manager, Ingress rules |
| `outputs.tf` | Cluster endpoint, URLs, LB IP |
| `docker/` | Shared config files (kong.yml, SQL init scripts, vector.yml, pooler.exs, edge functions) |
