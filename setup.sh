#!/bin/bash
# À lancer UNE FOIS avant le premier "docker compose up".
# Génère la paire de clés SSH utilisée entre backup-runner et backup-server.
set -e
cd "$(dirname "$0")"

if [ ! -f backup/keys/id_ed25519 ]; then
    mkdir -p backup/keys
    ssh-keygen -t ed25519 -N "" -C "backup-tp" -f backup/keys/id_ed25519
    chmod 600 backup/keys/id_ed25519
    echo "Clés SSH générées dans backup/keys/"
else
    echo "Les clés existent déjà, rien à faire."
fi

echo "Vous pouvez maintenant lancer : docker compose up -d --build"
