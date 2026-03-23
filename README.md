# hawcx-monitoring

Hawcx platform monitoring stack -- Prometheus, Grafana, and Loki deployed as a Helm chart to the Alabasta EKS cluster.

## Quick Start

```bash
# Deploy to Alabasta
git tag deploy_aws_alabasta_v$(date +%Y%m%d.%H%M%S)
git push origin <tag>

# Access Grafana
kubectl port-forward svc/grafana-service -n monitoring 13000:3000
# http://localhost:13000  (admin / hawcx)
```

## Components

- **Prometheus** (v2.51.0) -- metrics collection with 3 scrape targets (hx-auth, hawcx-core-oauth, hx-tenant-config)
- **Grafana** (v10.4.0) -- 6 dashboards (system-health, auth-flows, risk-engine, infrastructure, tenant-overview, session-debug)
- **Loki** (v3.0.0) -- log aggregation with S3 backend storage

See [CLAUDE.md](./CLAUDE.md) for detailed architecture and operational docs.
