#!/usr/bin/env bash
set -euo pipefail

deploy_dir="/etc/nookflow"
backup_dir="/var/backups/nookflow"
mkdir -p "$backup_dir"

set -a
source "$deploy_dir/license.env"
set +a

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
destination="$backup_dir/nookflow-${timestamp}.sql.gz"
temporary="${destination}.tmp"
trap 'rm -f "$temporary"' EXIT

MYSQL_PWD="$DATABASE_PASSWORD" mysqldump \
  -h 127.0.0.1 -u "$DATABASE_USER" \
  --single-transaction --routines --triggers --no-tablespaces nookflow \
  | gzip -9 > "$temporary"

mv "$temporary" "$destination"
trap - EXIT

find "$backup_dir" -type f -name 'nookflow-*.sql.gz' -mtime +14 -delete
