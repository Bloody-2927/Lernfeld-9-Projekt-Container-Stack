#!/usr/bin/env bash
# Lokaler Test der Pflicht- und Wahldienste (Pflichtenheft Kapitel 11, Tests T-01 bis T-06, T-12, T-15, T-16 bis T-19).
# Voraussetzung: docker compose up -d --build ; .env vorhanden. Der Test startet den Test-Client (Profil test) selbst.
# Der Test-Client hängt in allen Zonen; Firewall und Routing werden erst in der Firewall-VM getestet.
# Zeilen mit [OFFEN] sind manuelle Schritte (Erstkonten), sie zählen nicht als Fehler und stehen am Ende in der Summe.
set -uo pipefail
# Git Bash unter Windows würde Pfade wie /tmp/x.txt in Windows-Pfade umschreiben
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

# Ohne diese Zeile bricht der Ablauf aus dem How-To ab: 'docker compose up -d --build' startet den Client wegen
# seines Profils nicht, alle Tests laufen aber über 'docker compose exec client' (Rollenprüfung 2026-11-03, DO-12).
docker compose --profile test up -d client >/dev/null 2>&1 || { echo "FEHLER: Test-Client (Profil test) konnte nicht gestartet werden."; exit 1; }

PASS=0; FAIL=0; OFFEN=0
c() { docker compose exec -T client "$@"; }
ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
fail() { echo "  [FEHLER] $1"; [ -n "${2:-}" ] && echo "           $2" | head -3; FAIL=$((FAIL+1)); }
offen() { echo "  [OFFEN]  $1"; OFFEN=$((OFFEN+1)); }
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
c curl -s --max-time 8 -T /tmp/up.txt ftp://ftp.kopernikus-lab.lokal/up.txt >/dev/null 2>&1; rc=$?
# curl-Exitcode 25 = Upload vom Server abgelehnt (550), 7/28 wären Verbindungsfehler und zählen nicht als Verweigerung
expect_eq "anonym: Upload verweigert (Server lehnt ab)" "$rc" "25"

echo "== T-04 FTP user1 / user2"
if c curl -s --max-time 8 -u "user1:${FTP_USER1_PASSWORD}" -T /tmp/up.txt ftp://ftp.kopernikus-lab.lokal/t1.txt >/dev/null 2>&1; then ok "user1: Upload im eigenen Bereich"; else fail "user1: Upload im eigenen Bereich"; fi
expect_has "user1: Datei wieder abrufbar" "$(c curl -s --max-time 8 -u "user1:${FTP_USER1_PASSWORD}" ftp://ftp.kopernikus-lab.lokal/t1.txt)" "test"
if c curl -s --max-time 8 -u "user2:${FTP_USER2_PASSWORD}" -T /tmp/up.txt ftp://ftp.kopernikus-lab.lokal/t2.txt >/dev/null 2>&1; then ok "user2: Upload im eigenen Bereich"; else fail "user2: Upload im eigenen Bereich"; fi
c curl -s --max-time 8 -u "user1:falsch" ftp://ftp.kopernikus-lab.lokal/ >/dev/null 2>&1; rc=$?
# curl-Exitcode 67 = Anmeldung vom Server abgelehnt (530). 7 und 28 wären Verbindungsfehler und zählen nicht als Ablehnung
expect_eq "user1: falsches Passwort abgelehnt (530, curl-Exitcode 67)" "$rc" "67"
# Erst die Anmeldung und den eigenen Bereich prüfen, sonst würde jeder Verbindungsfehler als "VERWEIGERT" gelten
out=$(c lftp -u "user1,${FTP_USER1_PASSWORD}" -e "ls; cd ../user2 && echo ERREICHT || echo VERWEIGERT; bye" ftp.kopernikus-lab.lokal 2>&1 | tr -d '\r')
expect_has "user1: Anmeldung ok, eigener Bereich zeigt t1.txt" "$out" "t1.txt"
expect_has "user1 erreicht Verzeichnis von user2 nicht (Server meldet 550)" "$out" "550"
if echo "$out" | grep -q "ERREICHT"; then fail "user1 darf nicht in das Verzeichnis von user2 wechseln" "$out"; else ok "user1: kein Wechsel zu user2"; fi

echo "== T-05 SMB"
expect_has "pub: anonym lesen" "$(c smbclient //files.kopernikus-lab.lokal/pub -N -m SMB3 -c ls 2>&1)" "README.txt"
expect_has "pub: Schreiben verweigert" "$(c smbclient //files.kopernikus-lab.lokal/pub -N -m SMB3 -c 'put /tmp/up.txt x.txt' 2>&1)" "NT_STATUS_ACCESS_DENIED"
expect_has "Benutzer1: eigener Share schreibbar" "$(c smbclient //files.kopernikus-lab.lokal/Benutzer1 -U "benutzer1%${SMB_USER1_PASSWORD}" -m SMB3 -c 'put /tmp/up.txt a.txt; ls' 2>&1)" "a.txt"
expect_has "benutzer2 auf Benutzer1-Share verweigert" "$(c smbclient //files.kopernikus-lab.lokal/Benutzer1 -U "benutzer2%${SMB_USER2_PASSWORD}" -m SMB3 -c ls 2>&1)" "NT_STATUS_ACCESS_DENIED"
expect_has "anonym auf Benutzer1-Share verweigert" "$(c smbclient //files.kopernikus-lab.lokal/Benutzer1 -N -m SMB3 -c ls 2>&1)" "NT_STATUS_\(ACCESS_DENIED\|LOGON_FAILURE\)"
expect_has "SMB1 abgelehnt (Mindestprotokoll SMB2)" "$(c smbclient //files.kopernikus-lab.lokal/pub -N -m NT1 -c ls 2>&1)" "NT_STATUS_\(INVALID_NETWORK_RESPONSE\|CONNECTION_DISCONNECTED\)\|protocol negotiation failed"

echo "== T-06 Datenbank (Rechte)"
expect_has "web-Benutzer von fremder Adresse abgewiesen (1130)" "$(c mariadb -h10.20.50.2 -uweb -p"${DB_WEB_PASSWORD}" -e 'select 1' 2>&1)" "1130 - Host '10.20.50.250' is not allowed"
expect_has "root von fremder Adresse abgewiesen (1130)" "$(c mariadb -h10.20.50.2 -uroot -p"${MARIADB_ROOT_PASSWORD}" -e 'select 1' 2>&1)" "1130 - Host '10.20.50.250' is not allowed"
grants=$(docker compose exec -T db mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -N -e "SHOW GRANTS FOR 'web'@'10.20.20.4'" 2>&1)
# Die Init-Skripte laufen nur bei leerem Datenvolume: Ein altes Volume mit ALL-Recht würde nur an dieser genauen Prüfung auffallen
expect_has "web: nur SELECT, INSERT, UPDATE, DELETE auf webapp.*" "$grants" 'SELECT, INSERT, UPDATE, DELETE ON `webapp`'
if echo "$grants" | grep -q "ALL PRIVILEGES"; then fail "web: darf kein ALL PRIVILEGES haben" "$grants"; else ok "web: kein ALL PRIVILEGES"; fi
roots=$(docker compose exec -T db mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -N -e "SELECT host FROM mysql.user WHERE user='root'" 2>&1 | sort -u | tr '\n' ' ')
expect_eq "root nur auf localhost" "$(echo $roots)" "localhost"

echo "== T-15 VoIP (Asterisk, SIP)"
expect_has "SIP erreichbar (OPTIONS wird beantwortet)" "$(c sipsak -s sip:1001@10.20.60.2 -vv 2>&1)" "SIP/2.0 401"
expect_has "Nebenstellen 1001 und 1002 konfiguriert" "$(docker compose exec -T voip asterisk -rx 'pjsip show endpoints' 2>&1)" "1002"
expect_has "Wählplan: Nebenstellen und Echotest 600" "$(docker compose exec -T voip asterisk -rx 'dialplan show intern' 2>&1)" "'600'"
docker compose exec -T voip asterisk -rx "database deltree registrar/contact" >/dev/null 2>&1
docker compose cp tests/sip/register.py client:/tmp/register.py >/dev/null 2>&1
expect_eq "falsches SIP-Kennwort abgelehnt (401)" "$(c python3 /tmp/register.py 1002 falsch | tr -d '\r')" "401"
if docker compose exec -T voip asterisk -rx 'pjsip show contacts' | grep -q "1002/sip"; then fail "falsches Kennwort hat registriert"; else ok "falsches Kennwort: keine Registrierung"; fi
expect_eq "richtiges Kennwort: Nebenstelle 1001 angemeldet (200)" "$(c python3 /tmp/register.py 1001 "${SIP_1001_PASSWORD}" | tr -d '\r')" "200"
expect_has "1001 steht in der Kontaktliste" "$(docker compose exec -T voip asterisk -rx 'pjsip show contacts' 2>&1)" "1001/sip"

echo "== T-16 Caddy und Nextcloud (Reverse Proxy)"
# Mit dem Namen als Host-Header: Direkt über die IP meldet Nextcloud nach einem Neustart "Trusted domain error" (cloud.kopernikus-lab.lokal ist die vertraute Domain)
nc=$(c curl -s --max-time 8 -H 'Host: cloud.kopernikus-lab.lokal' http://10.20.20.5/status.php)
expect_has "Nextcloud antwortet (status.php direkt, mit Namen)" "$nc" "\"version\""
# status.php liefert "version" auch vor der Einrichtung ("installed":false): das Erstkonto ist ein eigener, manueller Punkt (Rollenprüfung 2026-11-03, BA-18)
if echo "$nc" | grep -q '"installed":true'; then ok "Nextcloud: eingerichtet (Erstkonto angelegt)"; else offen "Nextcloud: Erstkonto noch nicht angelegt (Nick, sofort nach dem ersten Start, bevor Clients im Netz sind)"; fi
expect_has "Caddy leitet cloud.kopernikus-lab.lokal an Nextcloud" "$(c curl -s --max-time 8 -H 'Host: cloud.kopernikus-lab.lokal' http://10.20.20.2/status.php)" "\"version\""
expect_has "Caddy leitet dbadmin an Adminer" "$(c curl -s --max-time 8 -H 'Host: dbadmin.kopernikus-lab.lokal' http://10.20.20.2/)" "Adminer"
expect_has "Caddy: unbekannter Name liefert Kennung" "$(c curl -s --max-time 8 http://10.20.20.2/)" "Heiner-IT Systems"
agrants=$(docker compose exec -T db mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -N -e "SHOW GRANTS FOR 'adminer'@'10.20.20.6'" 2>&1)
expect_has "Adminer-Konto: nur Datenänderung auf webapp, Quelle 10.20.20.6" "$agrants" 'SELECT, INSERT, UPDATE, DELETE ON `webapp`'
if echo "$agrants" | grep -q "ALL PRIVILEGES"; then fail "Adminer-Konto: darf kein ALL PRIVILEGES haben" "$agrants"; else ok "Adminer-Konto: kein ALL PRIVILEGES"; fi

echo "== T-17 Pi-hole (DNS-Filter)"
expect_has "Pi-hole beantwortet DNS (pi.hole)" "$(c dig +short +time=3 +tries=2 @10.20.20.3 pi.hole | tr -d '\r')" "10.20.20"
expect_has "Pi-hole Weboberfläche erreichbar" "$(c curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://10.20.20.3/admin/login)" "200"

echo "== T-18 Logs (Loki, Promtail, Grafana)"
# Loki meldet nach dem Start noch etwa 15 s "Ingester not ready": bis zu 60 s warten, damit der Test direkt nach 'docker compose up' nicht fälschlich scheitert
for _ in $(seq 1 12); do lokiready=$(c curl -s --max-time 8 http://10.20.30.5:3100/ready | tr -d '\r\n '); [ "$lokiready" = "ready" ] && break; sleep 5; done
expect_eq "Loki bereit" "$lokiready" "ready"
expect_has "Grafana gesund" "$(c curl -s --max-time 8 http://10.20.30.4:3000/api/health)" "\"database\": \"ok\""
expect_has "Grafana kennt die Loki-Datenquelle" "$(c curl -s --max-time 8 -u "admin:${GRAFANA_ADMIN_PASSWORD}" http://10.20.30.4:3000/api/datasources)" "Loki"
for _ in $(seq 1 12); do labels=$(c curl -s --max-time 8 http://10.20.30.5:3100/loki/api/v1/label/container/values); echo "$labels" | grep -q "lf9-web" && break; sleep 5; done
expect_has "Loki hat Logs von lf9-web (über Promtail)" "$labels" "lf9-web"

echo "== T-19 Portal und Docker-Oberfläche"
expect_has "Homepage zeigt das Portal" "$(c curl -s --max-time 8 -H 'Host: portal.kopernikus-lab.lokal' http://10.20.30.8:3000/)" "Heiner"
expect_has "Portainer antwortet (Version oder Hinweis auf die Ersteinrichtung)" "$(c curl -s --max-time 8 http://10.20.30.9:9000/api/system/status)" "Version\|initialization"
# 204 = Admin-Konto existiert, 404 = noch keines (Erstkonto sofort anlegen, Portainer sperrt sich sonst nach wenigen Minuten)
pa=$(c curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://10.20.30.9:9000/api/users/admin/check)
if [ "$pa" = "204" ]; then ok "Portainer: Admin-Konto angelegt"; else offen "Portainer: Admin-Konto noch nicht angelegt (HTTP $pa)"; fi

echo
echo "Ergebnis: $PASS bestanden, $FAIL fehlgeschlagen, $OFFEN offen (manuelle Erstkonten, zählen nicht als Fehler)"
[ "$FAIL" -eq 0 ]
