#!/usr/bin/env bash
# Sicherung der Datenbanken und Volumes (Pflichtenheft Kap. 7.3). STATUS: nicht in der Firewall-VM getestet.
# Aufruf im Repo-Ordner: ./scripts/backup.sh [Zielordner]
# Das Ziel soll AUSSERHALB der VM liegen (z. B. per SMB/scp auf den Windows-PC kopieren); hier wird lokal gesichert.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

DEST="${1:-./backups}/$(date +%Y%m%d-%H%M%S)"
KEEP=7
mkdir -p "$DEST"

# Datenbanken konsistent per Dump (nicht per Dateikopie des laufenden Servers)
docker compose exec -T db mariadb-dump -uroot -p"${MARIADB_ROOT_PASSWORD}" --single-transaction --databases webapp nextcloud > "$DEST/db.sql"

# Volumes als tar
for v in ftp-data smb-data kuma-data; do
  docker run --rm -v "lf9-lab_${v}:/data:ro" -v "$(cd "$DEST" && pwd):/backup" debian:bookworm-slim \
    tar czf "/backup/${v}.tar.gz" -C /data .
done

# nur die letzten $KEEP Stände behalten
ls -1dt "$(dirname "$DEST")"/*/ 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -rf
echo "Sicherung abgelegt in $DEST"
