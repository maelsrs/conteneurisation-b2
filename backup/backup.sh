#!/bin/bash
# Sauvegarde chiffrée (restic) envoyée en SFTP vers backup-server.
# Sauvegarde : dump PostgreSQL + contenu des deux serveurs web.
set -e

echo "=== Sauvegarde du $(date) ==="

# 1. Initialise le dépôt restic au premier passage (chiffré avec RESTIC_PASSWORD)
if ! restic snapshots > /dev/null 2>&1; then
    echo "Initialisation du dépôt restic..."
    restic init
fi

# 2. Dump de la base de données
mkdir -p /sauvegardes
pg_dump > /sauvegardes/dump.sql
echo "Dump PostgreSQL OK ($(wc -l < /sauvegardes/dump.sql) lignes)"

# 3. Sauvegarde restic : dump SQL + fichiers web
restic backup /sauvegardes/dump.sql /data/web1 /data/web2

# 4. Rotation : on garde les 10 dernières sauvegardes
restic forget --keep-last 10 --prune

echo "=== Sauvegarde terminée ==="
