#!/bin/bash
set -u

URL="http://localhost:8080/"
SCENARIO="${1:-web}"

check_http() {
    curl -s -o /dev/null -m 2 -w "%{http_code}" "$URL"
}

mesure_rto() {
    local debut fin
    debut=$(date +%s.%N)
    while [ "$(check_http)" != "200" ]; do
        sleep 0.2
    done
    fin=$(date +%s.%N)
    awk -v d="$debut" -v f="$fin" 'BEGIN { printf "RTO : %.2f secondes\n", f - d }'
}

case "$SCENARIO" in

  web)
    echo "--- Scénario : panne du serveur web1 ---"
    echo "Service avant panne : HTTP $(check_http)"
    docker stop web1
    echo "web1 arrêté, mesure du temps de rétablissement via le load balancer..."
    mesure_rto
    echo "Contenu servi pendant la panne :"
    curl -s "$URL" | grep -o "Serveur Web [12]"
    echo "--- Redémarrage de web1 ---"
    docker start web1
    ;;

  db)
    echo "--- Scénario : panne de la base de données ---"
    docker stop db
    echo "Base arrêtée. Vérification depuis web1 :"
    docker exec web1 pg_isready -h db && echo "OK" || echo "Base injoignable (attendu)"
    echo "--- Redémarrage et mesure du RTO de la base ---"
    debut=$(date +%s.%N)
    docker start db
    until docker exec web1 pg_isready -h db -q 2>/dev/null; do sleep 0.2; done
    fin=$(date +%s.%N)
    awk -v d="$debut" -v f="$fin" 'BEGIN { printf "RTO base : %.2f secondes\n", f - d }'
    ;;

  rpo)
    echo "--- Mesure du RPO : ancienneté de la dernière sauvegarde ---"
    DERNIERE=$(docker exec backup-runner restic snapshots --latest 1 --json \
        | grep -o '"time":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -z "$DERNIERE" ]; then
        echo "Aucune sauvegarde trouvée."
        exit 1
    fi
    echo "Dernière sauvegarde : $DERNIERE"
    AGE=$(( $(date +%s) - $(date -d "$DERNIERE" +%s) ))
    echo "RPO actuel : $AGE secondes de données potentiellement perdues."
    ;;

  *)
    echo "Usage : $0 [web|db|rpo]"
    exit 1
    ;;
esac
