#!/usr/bin/env bash
# Wiederherstellung aus einer Sicherung von scripts/backup.sh. STATUS: nicht getestet (Test T-14 steht aus).
# Aufruf im Repo-Ordner: bash scripts/restore.sh backups/backup-JJJJMMTT-HHMMSS
# Achtung: überschreibt die Daten der Volumes und der Datenbank. Der Stack wird dafür gestoppt.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:?Aufruf: bash scripts/restore.sh <Sicherungsordner>}"
[ -f "$SRC/db.sql" ] || { echo "FEHLER: $SRC/db.sql fehlt."; exit 1; }
set -a; . ./.env; set +a

read -r -p "Daten in den Volumes und der Datenbank werden überschrieben. Fortfahren? (ja/nein) " a
[ "$a" = "ja" ] || { echo "Abgebrochen."; exit 1; }

docker compose stop
for v in ftp-data smb-data kuma-data nextcloud-data grafana-data portainer-data pihole-data caddy-data; do
  [ -f "$SRC/${v}.tar.gz" ] || { echo "Übersprungen (fehlt): ${v}"; continue; }
  docker run --rm -v "lf9-lab_${v}:/data" -v "$(cd "$SRC" && pwd):/backup:ro" debian:bookworm-slim \
    sh -c "rm -rf /data/* /data/.[!.]* 2>/dev/null; tar xzf /backup/${v}.tar.gz -C /data"
done

docker compose up -d db
until docker compose exec -T db healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; do sleep 2; done
docker compose exec -T -e MYSQL_PWD="${MARIADB_ROOT_PASSWORD}" db mariadb -uroot < "$SRC/db.sql"
docker compose up -d
echo "Wiederherstellung abgeschlossen. Danach: bash tests/run-tests.sh"
