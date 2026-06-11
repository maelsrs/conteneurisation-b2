#!/bin/bash
set -e
echo "=== Sauvegarde du $(date) ==="

if ! restic snapshots > /dev/null 2>&1; then
    echo "Initialisation du dépôt restic..."
    restic init
fi

mkdir -p /sauvegardes
pg_dump > /sauvegardes/dump.sql
echo "Dump PostgreSQL OK ($(wc -l < /sauvegardes/dump.sql) lignes)"

restic backup /sauvegardes/dump.sql /data/web1 /data/web2
restic forget --keep-last 10 --prune

echo "=== Sauvegarde terminée ==="
