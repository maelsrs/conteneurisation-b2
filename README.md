# TP Conteneurisation — Infrastructure résiliente avec sauvegardes

## 1. Architecture

```
                        ┌─────────────┐
   http://localhost:8080│     lb      │  Nginx load balancer (étape 4)
            ───────────►│   (nginx)   │
                        └──────┬──────┘
                     ┌─────────┴─────────┐
                ┌────▼────┐         ┌────▼────┐
                │  web1   │         │  web2   │   Nginx (étape 1)
                └────┬────┘         └────┬────┘
                     └─────────┬─────────┘
                          ┌────▼────┐
                          │   db    │   PostgreSQL 16 (étape 1)
                          └────┬────┘
                               │ pg_dump
                      ┌────────▼────────┐      SSH/SFTP       ┌───────────────┐
                      │  backup-runner  │────────────────────►│ backup-server │
                      │ (restic + cron) │   dépôt chiffré     │    (sshd)     │
                      └─────────────────┘    (étapes 2-3)     └───────────────┘
```

- **lb** : Nginx en reverse proxy, seul point d'entrée exposé (port 8080),
  répartition round-robin entre les deux serveurs web.
- **web1 / web2** : deux serveurs Nginx servant chacun une page distincte. Le
  client PostgreSQL y est installé pour démontrer l'interaction web => bdd.
- **db** : PostgreSQL 16 avec une base `boutique` et une table `produits`
  initialisée automatiquement (`db/init.sql`), données persistées dans le
  volume `db-data`.
- **backup-server** : serveur SSH/SFTP minimaliste (Alpine + OpenSSH) qui
  héberge le dépôt de sauvegarde dans le volume `backup-data`.
- **backup-runner** : machine de sauvegarde équipée de restic, pg_dump et cron.

## 2. Démarrage

```bash
cp .env.example .env
./setup.sh                      # génère les clés SSH
docker compose up -d --build
```

## 3. Étape 1 — Serveurs web + base de données

```bash
curl http://localhost:8080/                          # page web1 ou web2
docker exec web1 psql -c "SELECT * FROM produits;"   # requête DB depuis web1
docker exec web2 psql -c "SELECT * FROM produits;"   # idem depuis web2
```

## 4. Étapes 2-3 — Stratégie de sauvegarde et sécurité

- **Outil** : restic (open source).
- **Quoi** : un dump complet PostgreSQL (`pg_dump`) + le contenu des deux
  serveurs web.
- **Quand** : tâche cron toutes les 5 minutes → **RPO théorique ≤ 5 minutes**.
- **Où** : dépôt restic sur le serveur de sauvegarde, transféré en **SFTP (SSH)**.
- **Sécurité** :
  - dépôt **chiffré de bout en bout** par restic (AES-256, clé `RESTIC_PASSWORD`
    dans `.env`) ;
  - authentification SSH **par clé uniquement** (`PasswordAuthentication no`) ;
  - accès restreint au seul utilisateur `backup` (`AllowUsers backup`,
    `PermitRootLogin no`) ;
  - rotation automatique (`restic forget --keep-last 10 --prune`).

Commandes utiles :
```bash
docker exec backup-runner /usr/local/bin/backup.sh   # lancer manuellement
docker exec backup-runner restic snapshots           # lister les sauvegardes
docker exec backup-runner cat /var/log/backup.log    # journal du cron
```

## 5. Étape 4 — Résilience : load balancer Nginx

Mécanisme choisi : **reverse proxy Nginx** devant web1 et web2. L'upstream est
configuré avec `max_fails=1 fail_timeout=10s`, un `proxy_connect_timeout` de 1 s
et `proxy_next_upstream` pour rejouer la requête sur l'autre serveur en cas
d'erreur : la panne d'un serveur web est **transparente** pour l'utilisateur.
De plus, `restart: unless-stopped` fait redémarrer automatiquement tout
conteneur qui crashe.

```bash
docker stop web1 && curl http://localhost:8080/      # web2 répond toujours
docker start web1
```

## 6. Étape 5 — Tests de panne et restauration

```bash
./scripts/simulate-failure.sh web    # panne web1 → mesure du RTO
./scripts/simulate-failure.sh db     # panne base → mesure du RTO
./scripts/simulate-failure.sh rpo    # âge de la dernière sauvegarde (RPO)
./scripts/restore.sh                 # restauration complète depuis backup-server
```

Résultats mesurés :

| Scénario | Commande | RTO mesuré | Observation |
|---|---|---|---|
| Panne web1 | `./scripts/simulate-failure.sh web` | 1,01 s | Le LB bascule sur web2, le service reste disponible pendant toute la panne |
| Panne base | `./scripts/simulate-failure.sh db` | 1,39 s après `docker start` | Le web reste servi (pages statiques) pendant la panne |
| RPO | `./scripts/simulate-failure.sh rpo` | 35 s au moment du test (≤ 300 s garanti) | Sauvegarde cron toutes les 5 minutes |
| Restauration complète | `./scripts/restore.sh` | < 5 s | Après un `DELETE` de toutes les lignes, la table `produits` a été restaurée à l'identique depuis le dépôt restic |

## 7. Propositions d'amélioration

- **Supervision / monitoring** : ajouter Prometheus + Grafana (ou Uptime Kuma)
  pour surveiller la disponibilité HTTP, l'état des conteneurs et l'âge de la
  dernière sauvegarde, avec alertes (mail/Discord).
- **Haute disponibilité de la base** : la base reste un point de défaillance
  unique → réplication PostgreSQL primaire/réplica (streaming replication)
  avec bascule automatique (Patroni).
- **Load balancer redondant** : le LB est lui-même un SPOF → en doubler
  l'instance avec une IP virtuelle (keepalived/VRRP).
- **Sauvegardes hors site** : répliquer le dépôt restic vers un second site ou
  un stockage objet (S3) — règle 3-2-1.
- **Tests de restauration automatisés** : vérifier régulièrement que les
  sauvegardes sont restaurables (un backup non testé n'est pas un backup).
- **Automatisation / IaC** : provisionner l'ensemble avec Ansible ou Terraform,
  et gérer les secrets avec Vault plutôt qu'un fichier `.env`.

## 8. Fichiers

| Fichier | Rôle |
|---|---|
| `docker-compose.yml` | Définition des 6 conteneurs |
| `.env` | Mots de passe (PostgreSQL, chiffrement restic) |
| `web/` | Image nginx + pages web1/web2 |
| `db/init.sql` | Création de la table `produits` |
| `lb/nginx.conf` | Configuration du load balancer |
| `backup/` | Serveur SSH, client restic, script de sauvegarde |
| `scripts/` | Simulation de pannes et restauration |
