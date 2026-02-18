#!/bin/bash
# Dequeue worker. Waits for queues to exist, then runs dequeue_messages.sql
# in a loop. Stop this container to simulate a consumer outage.

set -euo pipefail

DB_CONN="pdbadmin/Welcome12345@free23ai:1521/freepdb1"
SQL_FILE="/dequeue/dequeue_messages.sql"

echo "[dequeue-worker] Waiting for database and queues to be ready..."

until sqlplus -s /nolog <<EOF 2>/dev/null | grep -q "QUEUES_READY"
CONNECT ${DB_CONN}
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT 'QUEUES_READY' FROM user_queues WHERE name = 'HEALTHY_Q' AND ROWNUM = 1;
EXIT;
EOF
do
    echo "[dequeue-worker] Queues not ready, retrying in 15s..."
    sleep 15
done

echo "[dequeue-worker] Queues are ready. Starting dequeue loop."

while true; do
    echo "[dequeue-worker] Starting new sqlplus session (50 rounds)..."
    sqlplus -s "${DB_CONN}" @"${SQL_FILE}" || {
        echo "[dequeue-worker] sqlplus exited with error, retrying in 15s..."
        sleep 15
        continue
    }
    echo "[dequeue-worker] Session completed, restarting..."
    sleep 2
done
