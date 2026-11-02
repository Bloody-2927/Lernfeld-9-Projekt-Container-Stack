#!/bin/sh
# Konfiguration aus der Vorlage erzeugen: Kennwörter kommen aus der Umgebung (.env), nie aus dem Repo.
set -eu
: "${SIP_1001_PASSWORD:?nicht gesetzt}" "${SIP_1002_PASSWORD:?nicht gesetzt}"
cp /opt/asterisk-conf/*.conf /etc/asterisk/
sed -i "s/@SIP_1001_PASSWORD@/${SIP_1001_PASSWORD}/; s/@SIP_1002_PASSWORD@/${SIP_1002_PASSWORD}/" /etc/asterisk/pjsip.conf
chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk /var/run/asterisk 2>/dev/null || true
exec asterisk -f -U asterisk -G asterisk
