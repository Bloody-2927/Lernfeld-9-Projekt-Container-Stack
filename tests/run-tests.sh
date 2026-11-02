#!/usr/bin/env bash
# Lokaler Test der Pflicht- und Wahldienste (Pflichtenheft Kapitel 11, Tests T-01 bis T-06, T-12, T-15, T-16 bis T-19).
# Voraussetzung: docker compose --profile test up -d --build ; .env vorhanden.
# Der Test-Client hängt in allen Zonen; Firewall und Routing werden erst in der Firewall-VM getestet.
set -uo pipefail
# Git Bash unter Windows würde Pfade wie /tmp/x.txt in Windows-Pfade umschreiben
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

PASS=0; FAIL=0
c() { docker compose exec -T client "$@"; }
ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
fail() { echo "  [FEHLER] $1"; [ -n "${2:-}" ] && echo "           $2" | head -3; FAIL=$((FAIL+1)); }
expect_eq() { [ "$2" = "$3" ] && ok "$1" || fail "$1" "erwartet '$3', erhalten '$2'"; }
expect_has() { echo "$2" | grep -q -- "$3" && ok "$1" || fail "$1" "erwartet Teilstring '$3' in: $2"; }

echo "== Container-Gesundheit"
for n in lf9-dns lf9-web lf9-ftp lf9-smb lf9-db lf9-voip lf9-caddy lf9-pihole lf9-nextcloud lf9-grafana lf9-homepage; do
  for _ in $(seq 1 30); do
    s=$(docker inspect -f '{{.State.Health.Status}}' "$n" 2>/dev/null || echo "fehlt")
    [ "$s" = "healthy" ] && break
    sleep 2
  done
  expect_eq "$n gesund" "$s" "healthy"
done
for n in lf9-kuma lf9-loki lf9-promtail lf9-portainer lf9-adminer; do
  [ "$(docker inspect -f '{{.State.Running}}' $n 2>/dev/null)" = "true" ] && ok "$n läuft" || fail "$n läuft"
done

echo "== T-01 / T-12 DNS (direkt bind9)"
expect_eq "T-01 www.kopernikus-lab.lokal" "$(c dig +short @10.20.30.2 www.kopernikus-lab.lokal | tr -d '\r')" "10.20.20.4"
expect_eq "T-01 web2.kopernikus-lab.lokal" "$(c dig +short @10.20.30.2 web2.kopernikus-lab.lokal | tr -d '\r')" "10.20.20.4"
expect_eq "T-01 files.kopernikus-lab.lokal" "$(c dig +short @10.20.30.2 files.kopernikus-lab.lokal | tr -d '\r')" "10.20.40.3"
expect_eq "T-12 Rückwärts 10.20.40.2" "$(c dig +short -x 10.20.40.2 @10.20.30.2 | tr -d '\r')" "ftp.kopernikus-lab.lokal."
expect_eq "T-12 Rückwärts 192.168.10.1" "$(c dig +short -x 192.168.10.1 @10.20.30.2 | tr -d '\r')" "fw.kopernikus-lab.lokal."
expect_has "bind9 verweigert Rekursion (REFUSED)" "$(c dig @10.20.30.2 example.com | tr -d '\r')" "REFUSED"

echo "== T-02 Web (zwei virtuelle Hosts, per Name)"
expect_has "www liefert Website 1" "$(c curl -s --max-time 5 http://www.kopernikus-lab.lokal/)" "Website 1"
expect_has "web2 liefert Website 2" "$(c curl -s --max-time 5 http://web2.kopernikus-lab.lokal/)" "Website 2"

echo "== T-03 FTP anonym"
expect_has "anonym: Download aus /pub" "$(c curl -s --max-time 8 ftp://ftp.kopernikus-lab.lokal/README.txt)" "Freier"
c sh -c 'echo test > /tmp/up.txt'
if c curl -s --max-time 8 -T /tmp/up.txt ftp://ftp.kopernikus-lab.lokal/up.txt >/dev/null 2>&1; then fail "anonym: Upload muss verweigert werden"; else ok "anonym: Upload verweigert"; fi

echo "== T-04 FTP user1 / user2"
if c curl -s --max-time 8 -u "user1:${FTP_USER1_PASSWORD}" -T /tmp/up.txt ftp://ftp.kopernikus-lab.lokal/t1.txt >/dev/null 2>&1; then ok "user1: Upload im eigenen Bereich"; else fail "user1: Upload im eigenen Bereich"; fi
expect_has "user1: Datei wieder abrufbar" "$(c curl -s --max-time 8 -u "user1:${FTP_USER1_PASSWORD}" ftp://ftp.kopernikus-lab.lokal/t1.txt)" "test"
if c curl -s --max-time 8 -u "user2:${FTP_USER2_PASSWORD}" -T /tmp/up.txt ftp://ftp.kopernikus-lab.lokal/t2.txt >/dev/null 2>&1; then ok "user2: Upload im eigenen Bereich"; else fail "user2: Upload im eigenen Bereich"; fi
if c curl -s --max-time 8 -u "user1:falsch" ftp://ftp.kopernikus-lab.lokal/ >/dev/null 2>&1; then fail "user1: falsches Passwort muss scheitern (530)"; else ok "user1: falsches Passwort abgelehnt"; fi
out=$(c lftp -u "user1,${FTP_USER1_PASSWORD}" -e "cd ../user2 && echo ERREICHT || echo VERWEIGERT; bye" ftp.kopernikus-lab.lokal 2>&1 | tr -d '\r')
expect_has "user1 erreicht Verzeichnis von user2 nicht" "$out" "VERWEIGERT"

echo "== T-05 SMB"
expect_has "pub: anonym lesen" "$(c smbclient //files.kopernikus-lab.lokal/pub -N -m SMB3 -c ls 2>&1)" "README.txt"
expect_has "pub: Schreiben verweigert" "$(c smbclient //files.kopernikus-lab.lokal/pub -N -m SMB3 -c 'put /tmp/up.txt x.txt' 2>&1)" "NT_STATUS_ACCESS_DENIED"
expect_has "Benutzer1: eigener Share schreibbar" "$(c smbclient //files.kopernikus-lab.lokal/Benutzer1 -U "benutzer1%${SMB_USER1_PASSWORD}" -m SMB3 -c 'put /tmp/up.txt a.txt; ls' 2>&1)" "a.txt"
expect_has "benutzer2 auf Benutzer1-Share verweigert" "$(c smbclient //files.kopernikus-lab.lokal/Benutzer1 -U "benutzer2%${SMB_USER2_PASSWORD}" -m SMB3 -c ls 2>&1)" "NT_STATUS"
expect_has "anonym auf Benutzer1-Share verweigert" "$(c smbclient //files.kopernikus-lab.lokal/Benutzer1 -N -m SMB3 -c ls 2>&1)" "NT_STATUS"
expect_has "SMB1 abgelehnt (Mindestprotokoll SMB2)" "$(c smbclient //files.kopernikus-lab.lokal/pub -N -m NT1 -c ls 2>&1)" "NT_STATUS\|protocol negotiation failed\|Connection"

echo "== T-06 Datenbank (Rechte)"
expect_has "web-Benutzer von fremder Adresse abgewiesen (1130)" "$(c mariadb -h10.20.50.2 -uweb -p"${DB_WEB_PASSWORD}" -e 'select 1' 2>&1)" "1130 - Host '10.20.50.250' is not allowed"
expect_has "root von fremder Adresse abgewiesen (1130)" "$(c mariadb -h10.20.50.2 -uroot -p"${MARIADB_ROOT_PASSWORD}" -e 'select 1' 2>&1)" "1130 - Host '10.20.50.250' is not allowed"
grants=$(docker compose exec -T db mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -N -e "SHOW GRANTS FOR 'web'@'10.20.20.4'" 2>&1)
expect_has "web: ALL nur auf webapp.*" "$grants" "webapp"
roots=$(docker compose exec -T db mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -N -e "SELECT host FROM mysql.user WHERE user='root'" 2>&1 | sort -u | tr '\n' ' ')
expect_eq "root nur auf localhost" "$(echo $roots)" "localhost"

echo "== T-15 VoIP (Asterisk, SIP)"
expect_has "SIP erreichbar (OPTIONS wird beantwortet)" "$(c sipsak -s sip:1001@10.20.60.2 -vv 2>&1)" "SIP/2.0 401"
expect_has "Nebenstellen 1001 und 1002 konfiguriert" "$(docker compose exec -T voip asterisk -rx 'pjsip show endpoints' 2>&1)" "1002"
expect_has "Wählplan: Nebenstellen und Echotest 600" "$(docker compose exec -T voip asterisk -rx 'dialplan show intern' 2>&1)" "'600'"
docker compose exec -T voip asterisk -rx "database deltree registrar/contact" >/dev/null 2>&1
docker compose cp tests/sip/register.py client:/tmp/register.py >/dev/null 2>&1
expect_eq "falsches SIP-Kennwort abgelehnt (401)" "$(c python3 /tmp/register.py 1002 falsch | tr -d '')" "401"
if docker compose exec -T voip asterisk -rx 'pjsip show contacts' | grep -q "1002/sip"; then fail "falsches Kennwort hat registriert"; else ok "falsches Kennwort: keine Registrierung"; fi
expect_eq "richtiges Kennwort: Nebenstelle 1001 angemeldet (200)" "$(c python3 /tmp/register.py 1001 "${SIP_1001_PASSWORD}" | tr -d '')" "200"
expect_has "1001 steht in der Kontaktliste" "$(docker compose exec -T voip asterisk -rx 'pjsip show contacts' 2>&1)" "1001/sip"

echo "== T-16 Caddy und Nextcloud (Reverse Proxy)"
expect_has "Nextcloud läuft (status.php direkt)" "$(c curl -s --max-time 8 http://10.20.20.5/status.php)" "installed"
expect_has "Caddy leitet cloud.kopernikus-lab.lokal an Nextcloud" "$(c curl -s --max-time 8 -H 'Host: cloud.kopernikus-lab.lokal' http://10.20.20.2/status.php)" "installed"
expect_has "Caddy leitet dbadmin an Adminer" "$(c curl -s --max-time 8 -H 'Host: dbadmin.kopernikus-lab.lokal' http://10.20.20.2/)" "Adminer"
expect_has "Caddy: unbekannter Name liefert Kennung" "$(c curl -s --max-time 8 http://10.20.20.2/)" "Caddy"

echo "== T-17 Pi-hole (DNS-Filter)"
expect_has "Pi-hole beantwortet DNS (pi.hole)" "$(c dig +short +time=3 +tries=2 @10.20.20.3 pi.hole | tr -d '\r')" "10.20.20"
expect_has "Pi-hole Weboberfläche erreichbar" "$(c curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://10.20.20.3/admin/login)" "200"

echo "== T-18 Logs (Loki, Promtail, Grafana)"
expect_has "Loki bereit" "$(c curl -s --max-time 8 http://10.20.30.5:3100/ready)" "ready"
expect_has "Grafana gesund" "$(c curl -s --max-time 8 http://10.20.30.4:3000/api/health)" "ok"
expect_has "Grafana kennt die Loki-Datenquelle" "$(c curl -s --max-time 8 -u "admin:${GRAFANA_ADMIN_PASSWORD}" http://10.20.30.4:3000/api/datasources)" "Loki"
for _ in $(seq 1 12); do labels=$(c curl -s --max-time 8 http://10.20.30.5:3100/loki/api/v1/label/container/values); echo "$labels" | grep -q "lf9-web" && break; sleep 5; done
expect_has "Loki hat Logs von lf9-web (über Promtail)" "$labels" "lf9-web"

echo "== T-19 Portal und Docker-Oberfläche"
expect_has "Homepage zeigt das Portal" "$(c curl -s --max-time 8 -H 'Host: portal.kopernikus-lab.lokal' http://10.20.30.8:3000/)" "Heiner"
expect_has "Portainer antwortet" "$(c curl -s --max-time 8 http://10.20.30.9:9000/api/system/status)" "Version"

echo
echo "Ergebnis: $PASS bestanden, $FAIL fehlgeschlagen"
[ "$FAIL" -eq 0 ]
