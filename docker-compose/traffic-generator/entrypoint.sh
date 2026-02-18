#!/bin/bash
# Enqueue-only traffic producer. Waits for queues to exist, then runs
# generate_traffic.sql in a loop (50 rounds per session).

set -euo pipefail

DB_CONN="pdbadmin/Welcome12345@free23ai:1521/freepdb1"
SQL_FILE="/traffic/generate_traffic.sql"

echo "[traffic-generator] Waiting for database and queues to be ready..."

until sqlplus -s /nolog <<EOF 2>/dev/null | grep -q "QUEUES_READY"
CONNECT ${DB_CONN}
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT 'QUEUES_READY' FROM user_queues WHERE name = 'HEALTHY_Q' AND ROWNUM = 1;
EXIT;
EOF
do
    echo "[traffic-generator] Queues not ready, retrying in 15s..."
    sleep 15
done

echo "[traffic-generator] Queues are ready. Starting enqueue loop."

while true; do
    echo "[traffic-generator] Starting new sqlplus session (50 rounds)..."
    sqlplus -s "${DB_CONN}" @"${SQL_FILE}" || {
        echo "[traffic-generator] sqlplus exited with error, retrying in 15s..."
        sleep 15
        continue
    }
    echo "[traffic-generator] Session completed, restarting..."
    sleep 2
done
