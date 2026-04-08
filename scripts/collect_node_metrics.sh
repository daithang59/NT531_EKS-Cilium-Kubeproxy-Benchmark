#!/usr/bin/env bash
# ==============================================================================
# collect_node_metrics.sh — Thu thập CPU/memory metrics từ Prometheus API
# Dùng kubectl exec vào Prometheus pod để query Prometheus API.
# Tương thích với kube-prometheus-stack.
#
# Usage:
#   bash scripts/collect_node_metrics.sh [output_dir]
# ==============================================================================
set -euo pipefail

NS_MON="${NS_MON:-monitoring}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$REPO_ROOT/results}"
OUTPUT_DIR="${1:-}"

# Tìm Prometheus pod
PROM_POD="$(kubectl get pod -n "$NS_MON" \
  -l 'app.kubernetes.io/name=prometheus,prometheus=prometheus-kube-prometheus-prometheus' \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"

if [[ -z "$PROM_POD" ]]; then
  # Fallback: pod đầu tiên có prefix prometheus-prometheus-
  PROM_POD="$(kubectl get pod -n "$NS_MON" \
    -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' \
    | grep '^prometheus-prometheus-' | head -1)"
fi

if [[ -z "$PROM_POD" ]]; then
  echo "ERROR: Prometheus pod not found in namespace $NS_MON" >&2
  exit 1
fi

echo "Prometheus pod: $PROM_POD"

# Hàm query Prometheus API (URL-encoded)
query_prom() {
  local query="$1"
  local encoded
  encoded="$(python3 -c "import urllib.parse; print(urllib.parse.quote('$query'))" 2>/dev/null)"
  kubectl exec -n "$NS_MON" "$PROM_POD" -- \
    wget -q -O - \
    "http://localhost:9090/api/v1/query?query=${encoded}" 2>/dev/null
}

# Parse và in kết quả JSON từ Prometheus
parse_and_print() {
  local metric_name="$1"
  local query="$2"
  echo ""
  echo "=== $metric_name ==="
  local result status
  result="$(query_prom "$query")"
  status="$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" <<< "$result" 2>/dev/null)"
  if [[ "$status" != "success" ]]; then
    echo "  (no data)"
    return
  fi
  python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('data', {}).get('result', [])
if not results:
    print('  (no data)')
    sys.exit(0)
for r in results:
    m = r.get('metric', {})
    # prefer pod label for container metrics, instance for node metrics
    inst = m.get('pod', m.get('instance', '?'))
    val = float(r['value'][1])
    print(f'  {inst}: {val:.4f}')
" <<< "$result"
}

# ─── Thu thập metrics ────────────────────────────────────────────────────────

parse_and_print "Node CPU Utilization % (idle time inverted, rate 5m)" \
  '100 - (avg by (instance) (rate(node_cpu_seconds_total{job="node-exporter",mode="idle"}[5m])) * 100)'

parse_and_print "Node Memory Usage % (used/total)" \
  '100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))'

parse_and_print "Node Memory Total (GB)" \
  'node_memory_MemTotal_bytes / 1024 / 1024 / 1024'

parse_and_print "Kube-proxy CPU (cores, rate 5m)" \
  'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="kube-system",pod=~"kube-proxy.*"}[5m]))'

parse_and_print "Cilium agent CPU (cores, rate 5m, cadvisor)" \
  'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="kube-system",pod=~"cilium-[a-z0-9]+-[a-z0-9]{5}",container!="cilium-envoy"}[5m]))'

parse_and_print "Cilium Envoy CPU (cores, rate 5m)" \
  'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="kube-system",container="cilium-envoy"}[5m]))'

parse_and_print "Node network transmit rate (bytes/s)" \
  'sum by (instance) (rate(node_network_transmit_bytes_total{device!="lo"}[5m]))'

parse_and_print "Node network receive rate (bytes/s)" \
  'sum by (instance) (rate(node_network_receive_bytes_total{device!="lo"}[5m]))'

parse_and_print "Kube-apiserver request rate by verb (req/s)" \
  'sum by (verb) (rate(apiserver_request_total[5m]))'

echo ""
echo "Collection complete."

# Lưu output nếu OUTPUT_DIR được chỉ định
if [[ -n "$OUTPUT_DIR" && -d "$OUTPUT_DIR" ]]; then
  echo "Writing to $OUTPUT_DIR/node_metrics.txt"
  {
    echo "# Node metrics collected at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "# Prometheus pod: $PROM_POD"
    echo ""
    echo "=== Node CPU Utilization % ==="
    query_prom '100 - (avg by (instance) (rate(node_cpu_seconds_total{job="node-exporter",mode="idle"}[5m])) * 100)'
    echo ""
    echo "=== Node Memory Usage % ==="
    query_prom '100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))'
    echo ""
    echo "=== Kube-proxy CPU (cores) ==="
    query_prom 'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="kube-system",pod=~"kube-proxy.*"}[5m]))'
    echo ""
    echo "=== Cilium Envoy CPU (cores) ==="
    query_prom 'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="kube-system",container="cilium-envoy"}[5m]))'
    echo ""
    echo "=== Node network transmit bytes/s ==="
    query_prom 'sum by (instance) (rate(node_network_transmit_bytes_total{device!="lo"}[5m]))'
    echo ""
    echo "=== Node network receive bytes/s ==="
    query_prom 'sum by (instance) (rate(node_network_receive_bytes_total{device!="lo"}[5m]))'
  } > "$OUTPUT_DIR/node_metrics.txt"
  echo "Done: $OUTPUT_DIR/node_metrics.txt"
fi
