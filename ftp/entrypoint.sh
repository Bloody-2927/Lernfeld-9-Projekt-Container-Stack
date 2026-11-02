#!/bin/bash
# Legt Verzeichnisse und die Benutzer user1/user2 an. Passwörter kommen aus der Umgebung (.env).
set -euo pipefail

mkdir -p /srv/ftp/pub /srv/ftp/users /var/run/vsftpd/empty
chmod 755 /srv/ftp /srv/ftp/pub
[ -f /srv/ftp/pub/README.txt ] || echo "Freier Downloadbereich des Uebungslabors (nur lesen)." > /srv/ftp/pub/README.txt

for u in user1 user2; do
  var="FTP_${u^^}_PASSWORD"
  pw="${!var:?Passwort $var fehlt}"
  id "$u" >/dev/null 2>&1 || useradd -M -d "/srv/ftp/users/$u" -s /usr/sbin/nologin "$u"
  mkdir -p "/srv/ftp/users/$u"
  chown "$u:$u" "/srv/ftp/users/$u"
  chmod 750 "/srv/ftp/users/$u"
  echo "$u:$pw" | chpasswd
done

# vsftpd kann nicht nach /dev/stdout schreiben: Logdatei im Container auf stdout spiegeln (Docker-Log, später Loki)
touch /var/log/vsftpd.log
tail -n 0 -F /var/log/vsftpd.log &

exec vsftpd /etc/vsftpd.conf
