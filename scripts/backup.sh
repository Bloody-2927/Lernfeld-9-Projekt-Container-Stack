#!/usr/bin/env bash
# Sicherung der Datenbanken und Volumes (Pflichtenheft Kap. 7.3). STATUS: nicht in der Firewall-VM getestet.
# Aufruf im Repo-Ordner: bash scripts/backup.sh [Zielordner]
# Das Ziel soll AUSSERHALB der VM liegen (z. B. per scp auf den Windows-PC kopieren); hier wird lokal gesichert.
# Wiederherstellung: scripts/restore.sh
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

BASE="${1:-./backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
TMP="$BASE/.tmp-$STAMP"
DEST="$BASE/backup-$STAMP"
KEEP=7
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

# Datenbanken konsistent per Dump, inklusive Benutzer und Rechte (mysql-Systemdatenbank), nicht per Dateikopie.
# Das Kennwort geht über die Umgebung des Containers, nicht über die Kommandozeile.
docker compose exec -T -e MYSQL_PWD="${MARIADB_ROOT_PASSWORD}" db mariadb-dump -uroot --single-transaction --all-databases --routines --events > "$TMP/db.sql"
[ -s "$TMP/db.sql" ] || { echo "FEHLER: Datenbank-Dump ist leer, Sicherung abgebrochen."; exit 1; }

# Volumes als tar. Die Projektnamen-Vorsilbe stammt aus "name:" in compose.yml.
# Hinweis: kuma-data enthält SQLite; für einen sicher konsistenten Stand vorher "docker compose stop kuma" ausführen.
for v in ftp-data smb-data kuma-data nextcloud-data grafana-data portainer-data pihole-data caddy-data; do
  docker run --rm -v "lf9-lab_${v}:/data:ro" -v "$(cd "$TMP" && pwd):/backup" debian:bookworm-slim \
    tar czf "/backup/${v}.tar.gz" -C /data .
done

# Konfiguration ohne Kennwörter mitsichern, die .env getrennt und nur für den Besitzer lesbar
cp .env "$TMP/env.backup"

mv "$TMP" "$DEST"
trap - EXIT
# nur die letzten $KEEP Stände behalten, nur Ordner mit dem eigenen Namensmuster
ls -1dt "$BASE"/backup-*/ 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -rf
echo "Sicherung abgelegt in $DEST"
