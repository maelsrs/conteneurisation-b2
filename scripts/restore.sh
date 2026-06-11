#!/bin/bash
set -e

echo "--- 1. Récupération de la dernière sauvegarde restic ---"
docker exec backup-runner sh -c "rm -rf /tmp/restore && restic restore latest --target /tmp/restore"

echo "--- 2. Restauration de la base de données ---"
docker exec backup-runner psql -c "DROP TABLE IF EXISTS produits;"
docker exec backup-runner sh -c "psql -v ON_ERROR_STOP=0 < /tmp/restore/sauvegardes/dump.sql"

echo "--- 3. Vérification : contenu de la table produits ---"
docker exec backup-runner psql -c "SELECT * FROM produits;"

echo "Restauration terminée."
echo "(Les fichiers web restaurés sont dans /tmp/restore/data/ du conteneur backup-runner.)"
