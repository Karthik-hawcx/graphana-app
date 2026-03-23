# CLAUDE.md

## What This Repo Is

Standalone Helm chart for the Hawcx platform monitoring stack (Prometheus + Grafana + Loki). Extracted from hx_tenant_config's embedded monitoring templates into its own deployment lifecycle.

Deploys to the `monitoring` namespace on the Alabasta EKS cluster.

## Deployment

Tag-based deployment via GitHub Actions:

```bash
git tag deploy_aws_alabasta_v$(date +%Y%m%d.%H%M%S)
git push origin deploy_aws_alabasta_v<version>
```

Manual deployment:

```bash
helm upgrade --install hawcx-monitoring ./chart \
  -f chart/values-alabasta.yaml \
  -n monitoring \
  --create-namespace
```

## Accessing Grafana

```bash
kubectl port-forward svc/grafana-service -n monitoring 13000:3000
# Open http://localhost:13000
# Login: admin / hawcx
```

## Dashboards

Six dashboards are provisioned automatically:

| Dashboard | UID | Description |
|-----------|-----|-------------|
| System Health | `system-health` | Request rates, latency, error rates for all 3 services |
| Auth Flows | `auth-flows` | Flow funnel, outcomes, duration, success rate |
| Risk Engine | `risk-engine` | Risk decisions, evaluation latency, per-tenant breakdown |
| Infrastructure | `infrastructure` | DB pools, PgBouncer, Redis ops, circuit breaker, analytics |
| Tenant Overview | `tenant-overview` | Active tenants, provisioning, aggregation, per-tenant traffic |
| Session Debug | `session-debug` | Loki log search by session_id, request_id, tenant_id |

### Adding a New Dashboard

1. Design the dashboard in Grafana UI
2. Export as JSON (Share > Export > Save to file)
3. Add the JSON to `chart/templates/grafana.yaml` in the `grafana-dashboards` ConfigMap `data:` section as `<name>.json: |`
4. Deploy

## Prometheus Scrape Targets

Three scrape jobs are configured:

| Job | Target | Discovery |
|-----|--------|-----------|
| hx-auth | hx-auth pods | Kubernetes SD (pod label `app: hx-auth`) |
| hawcx-core-oauth | hawcx-core-oauth-service:8080 | Static config |
| hx-tenant-config | hx-tenant-config-service:8000 | Static config |

### Adding a New Scrape Target

Add to `chart/values-alabasta.yaml` under `prometheus.scrapeTargets`:

```yaml
- jobName: my-new-service
  metricsPath: /metrics
  scrapeInterval: 15s
  targets: ["my-service.my-namespace.svc.cluster.local:8080"]
```

Or for Kubernetes service discovery:

```yaml
- jobName: my-new-service
  metricsPath: /metrics
  kubernetesSD:
    namespaces: ["my-namespace"]
    appLabel: my-app-label
```

## Architecture Notes

- **Prometheus** uses emptyDir for TSDB storage (7-day retention). Metrics survive pod restarts within the node but not node replacement.
- **Loki** uses emptyDir for local index/cache and S3 (`s3://us-west-2/hawcx-alabasta-loki-logs`) for chunk storage. IRSA via service account provides S3 access. Do NOT use EFS -- it caused write latency issues.
- **Grafana** is stateless; all config is provisioned from ConfigMaps.
- Datasources: Prometheus at `prometheus-service:9090`, Loki at `loki-service:3100`.

## Git Conventions

- Never add Co-Authored-By lines to commits
- Use conventional commit format: `feat:`, `fix:`, `chore:`, `refactor:`, etc.
