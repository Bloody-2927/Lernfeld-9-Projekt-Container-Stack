#!/bin/sh
# Legt je Anwendung eine eigene Datenbank und einen eigenen Benutzer an (Pflichtenheft 6.4).
# Zugriff nur von der festen Adresse der Anwendung; root bleibt auf localhost beschränkt.
# Läuft nur bei leerem Datenvolume. Kennwörter nur aus Buchstaben und Ziffern (setup.sh erzeugt hex), sonst bricht das SQL.
set -eu

mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS webapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'web'@'10.20.20.4'       IDENTIFIED BY '${DB_WEB_PASSWORD}';
CREATE USER IF NOT EXISTS 'nextcloud'@'10.20.20.5' IDENTIFIED BY '${DB_NEXTCLOUD_PASSWORD}';
CREATE USER IF NOT EXISTS 'adminer'@'10.20.20.6'   IDENTIFIED BY '${DB_ADMINER_PASSWORD}';

-- web: nur Datenänderung, kein Schema (die statischen Seiten brauchen keine Datenbank, das Konto ist für Tests und spätere Anwendungen)
GRANT SELECT, INSERT, UPDATE, DELETE ON webapp.* TO 'web'@'10.20.20.4';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'10.20.20.5';
-- adminer: Weboberfläche für die Vorführung, nur auf die Anwendungsdatenbank webapp
GRANT SELECT, INSERT, UPDATE, DELETE ON webapp.* TO 'adminer'@'10.20.20.6';
FLUSH PRIVILEGES;
SQL
