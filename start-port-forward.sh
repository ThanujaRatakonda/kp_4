#!/usr/bin/env bash
set -euo pipefail

# Default configurations
ADDRESS="${ADDRESS:-0.0.0.0}"     # External access for 10.131.103.92 LAN
NAMESPACE="${NAMESPACE:-default}" # Use your specific namespace
KUBECTL="/usr/local/bin/kubectl"  # Absolute path to kubectl
LOG_DIR="${LOG_DIR:-pf-logs}"     # Log directory for port forwarding
mkdir -p "${LOG_DIR}"

echo "[INFO] Stopping old kubectl port-forward processes..."
# Safely stop only the kubectl port-forward processes
pkill -f "kubectl port-forward" || true

# Check for necessary dependencies
for cmd in "${KUBECTL}" nc lsof sed; do
  command -v "${cmd%% *}" >/dev/null 2>&1 || { echo "[ERROR] Missing ${cmd}"; exit 1; }
done

pids=()
start_pf() {
  local name="$1" resource="$2" lport="$3" rport="$4"
  echo "[INFO] ${name}: ${ADDRESS}:${lport} -> ${resource}:${rport}"
  "${KUBECTL}" -n "${NAMESPACE}" port-forward "${resource}" "${lport}:${rport}" --address "${ADDRESS}" \
    >"${LOG_DIR}/${name}.log" 2>&1 & # Run port forwarding in background
  pids+=("$!")  # Capture the process ID of port forwarding
}

wait_port() {
  local name="$1" port="$2"
  echo "[INFO] Waiting for ${name} on ${ADDRESS}:${port}..."
  for i in {1..60}; do
    if nc -z 127.0.0.1 "${port}" 2>/dev/null; then
      echo "[INFO] ${name} ready."
      return 0
    fi
    sleep 0.5
  done
  echo "[ERROR] Timeout waiting for ${name} on ${ADDRESS}:${port}"
  sed -n '1,200p' "${LOG_DIR}/${name}.log" || true
  return 1
}

cleanup() {
  echo "[INFO] Cleaning up port-forwarders..."
  # Kill all port-forwarding processes
  for pid in "${pids[@]}"; do
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# Resolve database pod (more robust than targeting StatefulSet directly)
DB_POD="$("${KUBECTL}" -n "${NAMESPACE}" get pods -l app=database -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${DB_POD}" ]]; then
  echo "[WARN] No database pod found by label app=database; trying statefulset/database directly."
  TARGET_DB="statefulset/database"
else
  TARGET_DB="pod/${DB_POD}"
fi

# Start port forwarding for services and pods
start_pf "backend"  "svc/backend"    5001 5000
start_pf "frontend" "svc/frontend"   4000 3000
start_pf "database" "${TARGET_DB}"   5433 5432

# Wait for readiness
wait_port "backend"  5001
wait_port "frontend" 4000
wait_port "database" 5433

# If NO_BLOCK=1, exit and let Jenkins continue while PF keeps running
if [[ "${NO_BLOCK:-}" = "1" ]]; then
  echo "[INFO] Port-forwarders are up (non-blocking mode)."
  exit 0
fi

echo "[INFO] Port-forwarders active. Blocking until killed..."
wait
