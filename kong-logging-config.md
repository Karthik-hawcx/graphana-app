# Kong HTTP-Log Plugin -> Loki Integration

## Problem

The Kong `http-log` global plugin currently points to a non-existent service:

```yaml
http_endpoint: http://kong-log-ingestor.kong-logging-dev.svc.cluster.local/logs
```

This service does not exist in the cluster. Logs from Kong are being silently dropped.

## Target Architecture

Route Kong access logs to Loki (`loki-service.monitoring.svc.cluster.local:3100`) with auth-enriched custom fields for the Kong Auth Security dashboard.

## Important: Format Mismatch

**Kong's http-log plugin sends Kong's standard JSON log format** (one JSON object per request with fields like `request`, `response`, `route`, `service`, `latencies`, etc.).

**Loki's `/loki/api/v1/push` endpoint expects the Loki push format:**
```json
{
  "streams": [
    {
      "stream": { "label": "value" },
      "values": [ [ "<nanosecond-timestamp>", "<log-line>" ] ]
    }
  ]
}
```

These formats are **incompatible**. You cannot point Kong's http-log directly at Loki's push API.

## Solution Options

### Option A: Lightweight Log Forwarder (Recommended)

Deploy a small log forwarder service (e.g., a simple Go/Python container or Vector/Fluentbit) in the `monitoring` namespace that:

1. Receives Kong's http-log JSON at `POST /logs`
2. Extracts labels from the custom fields (`auth_type`, `tenant_id`, `route_name`, etc.)
3. Wraps the log entry in Loki's push format
4. Forwards to `http://loki-service.monitoring.svc.cluster.local:3100/loki/api/v1/push`

**Kong http-log config change:**
```yaml
http_endpoint: http://kong-log-forwarder.monitoring.svc.cluster.local/logs
```

A minimal forwarder (e.g., using Vector) could look like:

```yaml
# vector.yaml config
sources:
  kong_http:
    type: http_server
    address: "0.0.0.0:80"
    path: "/logs"

transforms:
  enrich:
    type: remap
    inputs: ["kong_http"]
    source: |
      .timestamp = now()
      .labels.namespace = "kong"
      .labels.app = "kong-dataplane"
      .labels.auth_type = .auth_type || "unknown"
      .labels.tenant_id = .tenant_id || "unknown"
      .labels.route_name = .route_name || "unknown"

sinks:
  loki:
    type: loki
    inputs: ["enrich"]
    endpoint: "http://loki-service.monitoring.svc.cluster.local:3100"
    labels:
      namespace: "{{ .labels.namespace }}"
      app: "{{ .labels.app }}"
      auth_type: "{{ .labels.auth_type }}"
      tenant_id: "{{ .labels.tenant_id }}"
      route_name: "{{ .labels.route_name }}"
    encoding:
      codec: json
```

### Option B: Promtail Sidecar on Kong Pod

Since this is Fargate (no DaemonSet support), add a Promtail sidecar container to the Kong dataplane pod that tails Kong's stdout logs and pushes to Loki. This requires modifying the Kong Helm chart values, which may conflict with Konnect management.

### Option C: kubectl logs pipe (Development/Debugging Only)

```bash
kubectl logs -f -n kong dataplane-kong-dataplane-7rzcr-bc4f4fcd6-n4x9m | \
  while read line; do
    curl -s -X POST http://loki-service.monitoring.svc.cluster.local:3100/loki/api/v1/push \
      -H "Content-Type: application/json" \
      -d "{\"streams\":[{\"stream\":{\"namespace\":\"kong\",\"app\":\"kong-dataplane\"},\"values\":[[\"$(date +%s)000000000\",$(echo $line | jq -Rs .)]]}]}"
  done
```

Not suitable for production.

## Required decK Config Changes

In `kong_alabasta_dpop_config.yaml`, update the global `http-log` plugin:

### Current Config (BROKEN)
```yaml
plugins:
- config:
    content_type: application/json
    custom_fields_by_lua:
      cf_connecting_ip: kong.request.get_header('cf-connecting-ip')
      cf_ipcountry: kong.request.get_header('cf-ipcountry')
      real_client_ip: kong.request.get_header('cf-connecting-ip')
      x_forwarded_for: kong.request.get_header('x-forwarded-for')
      x_real_ip: kong.request.get_header('x-real-ip')
    http_endpoint: http://kong-log-ingestor.kong-logging-dev.svc.cluster.local/logs
    ...
  enabled: true
  name: http-log
```

### Updated Config
```yaml
plugins:
- config:
    content_type: application/json
    custom_fields_by_lua:
      # Auth enrichment fields (for Grafana dashboard)
      auth_type: |
        local h = kong.request.get_header('Authorization') or ''
        if h:find('^DPoP ') then return 'dpop'
        elseif h:find('^Bearer ') then return 'bearer'
        else return 'missing' end
      dpop_present: return kong.request.get_header('DPoP') and 'true' or 'false'
      tenant_id: return kong.request.get_header('x-tenant-id') or kong.request.get_header('x-consumer-id') or 'unknown'
      route_name: |
        local r = kong.router.get_route()
        return r and r.name or 'unknown'
      jwt_sub: return kong.request.get_header('x-jwt-claim-sub') or 'none'
      # Existing IP fields
      cf_connecting_ip: return kong.request.get_header('cf-connecting-ip')
      cf_ipcountry: return kong.request.get_header('cf-ipcountry')
      real_client_ip: return kong.request.get_header('cf-connecting-ip')
      x_forwarded_for: return kong.request.get_header('x-forwarded-for')
      x_real_ip: return kong.request.get_header('x-real-ip')
    http_endpoint: http://kong-log-forwarder.monitoring.svc.cluster.local/logs
    keepalive: 60000
    method: POST
    queue:
      concurrency_limit: 1
      initial_retry_delay: 0.01
      max_batch_size: 1
      max_bytes: null
      max_coalescing_delay: 1
      max_entries: 10000
      max_retry_delay: 60
      max_retry_time: 60
    timeout: 10000
  enabled: true
  name: http-log
  protocols:
  - grpc
  - grpcs
  - http
  - https
```

## Deployment Steps

1. **Deploy the log forwarder** in the `monitoring` namespace (Option A)
2. **Update Kong config** via Konnect with the changes above (`deck gateway sync`)
3. **Verify logs reach Loki**: `logcli query '{namespace="kong"}' --limit=5`
4. **Import the Kong Auth Security dashboard** (already added to grafana-dashboards ConfigMap)

## Loki Queries for Verification

Once logs are flowing, these queries should return data:

```logql
# All Kong logs
{namespace="kong", app="kong-dataplane"}

# Auth type distribution
{namespace="kong"} | json | line_format "{{.auth_type}}"

# DPoP requests only
{namespace="kong"} | json | auth_type="dpop"

# Failed requests by tenant
{namespace="kong"} | json | response_status >= 400
```
