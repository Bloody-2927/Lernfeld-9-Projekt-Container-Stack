#!/bin/sh
# Legt je Anwendung eine eigene Datenbank und einen eigenen Benutzer an (Pflichtenheft 6.4).
# Zugriff nur von der festen Adresse der Anwendung; root bleibt auf localhost beschränkt.
set -eu

mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS webapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'web'@'10.20.20.4'       IDENTIFIED BY '${DB_WEB_PASSWORD}';
CREATE USER IF NOT EXISTS 'nextcloud'@'10.20.20.5' IDENTIFIED BY '${DB_NEXTCLOUD_PASSWORD}';

GRANT ALL PRIVILEGES ON webapp.*    TO 'web'@'10.20.20.4';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'10.20.20.5';
FLUSH PRIVILEGES;
SQL
