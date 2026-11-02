#!/bin/bash
# Legt Freigabeverzeichnisse und die Konten benutzer1/benutzer2 an. Passwörter aus der Umgebung (.env).
set -euo pipefail

mkdir -p /srv/samba/pub /srv/samba/Benutzer1 /srv/samba/Benutzer2
chmod 755 /srv/samba/pub
[ -f /srv/samba/pub/README.txt ] || echo "Freier Downloadbereich des Uebungslabors (nur lesen)." > /srv/samba/pub/README.txt

for n in 1 2; do
  u="benutzer$n"
  var="SMB_USER${n}_PASSWORD"
  pw="${!var:?Passwort $var fehlt}"
  id "$u" >/dev/null 2>&1 || useradd -M -d "/srv/samba/Benutzer$n" -s /usr/sbin/nologin "$u"
  chown "$u:$u" "/srv/samba/Benutzer$n"
  chmod 700 "/srv/samba/Benutzer$n"
  printf '%s\n%s\n' "$pw" "$pw" | smbpasswd -s -a "$u" >/dev/null
done

exec smbd --foreground --no-process-group --debug-stdout
