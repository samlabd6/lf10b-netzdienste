#!/bin/bash
# backup-status: shows the state of all backups from Prometheus as a table
set -uo pipefail
PROM=http://localhost:9090/api/v1/query                  # Prometheus query API on mon01
q() { curl -sfG "$PROM" --data-urlencode "query=$1"; }   # runs one PromQL query and returns JSON

echo "Restic backups (layer B laptop, layer C cloud)"
printf '%-8s %-8s %-8s %s\n' HOST TARGET RESULT "LAST SUCCESS"
q 'restic_backup_success' | jq -r '.data.result[] | "\(.metric.host) \(.metric.repo) \(.value[1])"' | sort | while read -r HOST REPO OK; do
  AGE=$(q "time() - restic_last_success_timestamp_seconds{host=\"$HOST\",repo=\"$REPO\"}" | jq -r '.data.result[0].value[1] // "0"')
  RESULT=$([ "$OK" = "1" ] && echo OK || echo FAILED)
  printf '%-8s %-8s %-8s %s min ago\n' "$HOST" "$REPO" "$RESULT" "$(( ${AGE%.*} / 60 ))"
done

echo
echo "VM images (layer A, vzdump on the Proxmox host)"
printf '%-8s %s\n' VMID "LAST SUCCESS"
q 'time() - vzdump_last_success_timestamp_seconds' | jq -r '.data.result[] | "\(.metric.vmid) \(.value[1])"' | sort | while read -r VMID AGE; do
  printf '%-8s %s h ago\n' "$VMID" "$(( ${AGE%.*} / 3600 ))"
done

echo
echo "Firing backup alarms:"
curl -sf http://localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | select(.state=="firing" and (.labels.alertname | test("Backup|Vzdump"))) | "  \(.labels.alertname) \(.labels.host // "") \(.labels.repo // .labels.vmid // "")"'
