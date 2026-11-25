#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
env_file="${NOOKFLOW_ENV_FILE:-/etc/nookflow/license.env}"
if [[ ! -f "$env_file" ]]; then
  env_file="$script_dir/.env"
fi

set -a
source "$env_file"
set +a

note="${1:-manual}"
curl --fail-with-body --silent --show-error \
  -X POST http://127.0.0.1:8787/api/admin/licenses \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "$(printf '{\"note\":\"%s\"}' "${note//\"/\\\"}")"
printf '\n'
