# lf9-lab – Übungslabor Kopernikus Hochschule (LF 9, 11IT2B)

Docker-Stack und Skripte für den Laborübungsplatz der Heiner-IT Systems GmbH.
Projektleitung: Team Heiner-IT Systems. Abgabe: 07.12.2026.
Grundlage: Pflichtenheft V1.2 (Zonenmodell, Adressplan 10.20.x, Regelwerk) und logischer Netzwerkplan V1.2.

## Aufbau

| Zone | Netz | Dienste |
|---|---|---|
| 10 Clients | 192.168.10.0/24 | Windows-PC .10, lf9-client1 .11, lf9-client2 .12, lf9-client-gui .13 (Desktop mit Browser), Firewall-VM .1 |
| 20 Web | 10.20.20.0/24 | Caddy .2, Pi-hole .3, nginx .4 (www, web2, intern, Minispiel), Nextcloud .5, Adminer .6 |
| 30 Infrastruktur | 10.20.30.0/24 | bind9 .2, Uptime Kuma .3, Grafana .4, Loki .5, Promtail .6, Homepage .8, Portainer .9 |
| 40 Fileserver | 10.20.40.0/24 | vsftpd .2, Samba .3 |
| 50 Datenbank | 10.20.50.0/24 | MariaDB .2 |
| 60 VoIP | 10.20.60.0/24 | Asterisk 20 .2 (Nebenstellen 1001 und 1002, Echotest 600) |

## Stand

| Teil | Stand |
|---|---|
| alle 16 Dienste in `compose.yml` (bind9, nginx, vsftpd, Samba, MariaDB, Uptime Kuma, Asterisk, Caddy, Pi-hole, Nextcloud, Adminer, Grafana, Loki, Promtail, Homepage, Portainer) | gebaut und mit `tests/run-tests.sh` auf Docker Desktop getestet (61 von 61 Prüfungen am 02.11.2026). **Noch zu konfigurieren:** Kuma (Konto, Monitore), Nextcloud (Installationsassistent, Datenbank 10.20.50.2), Portainer (Admin-Konto), Pi-hole (Blocklisten, DNS-Weitergabe), Grafana (Dashboards) |
| Zonenübergreifendes Routing, nftables, Reject/Drop | **nicht getestet** – erst in der Firewall-VM möglich (`nftables/lab.nft` ist ein Entwurf) |
| `setup.sh`, `scripts/windows/01-hyperv-setup.ps1`, `scripts/backup.sh`, `scripts/windows/map-shares.cmd` | **nicht getestet** (Machbarkeitstest 1.0 steht aus) |
| Zonenübergreifende Wege der neuen Dienste (Caddy zu Kuma, Grafana, Portainer; Pi-hole zu bind9; Nextcloud zu MariaDB) | **nicht getestet**, lokal gibt es kein Routing zwischen den Zonen |

## Lokaler Test (Docker Desktop, ohne VM)

```bash
cp .env.example .env        # Passwörter ersetzen (CHANGE_ME), .env wird nicht committet
docker compose --profile test up -d --build
bash tests/run-tests.sh     # Tests T-01 bis T-06, T-12 und T-15 bis T-19, Pflichtenheft Kapitel 11
                            # startet den Test-Client (Profil test) selbst; [OFFEN] = manuelles Erstkonto, kein Fehler
docker compose --profile test down       # Container stoppen (Daten bleiben in den Volumes)
docker compose --profile test down -v    # zusätzlich Volumes löschen
```

Der Test-Client (`--profile test`) hängt in allen Zonen. Firewall und Routing zwischen den Zonen gibt es lokal nicht.

## Aufbau der Firewall-VM (Hyper-V)

1. Debian-12-Netinst-ISO herunterladen (amd64).
2. PowerShell **als Administrator**: `scripts\windows\01-hyperv-setup.ps1 -IsoPath <ISO> [-WithClients]` (Switch `labnet-intern`, Route 10.20.0.0/16, VM `lf9-fw`).
3. Debian installieren (nur SSH-Server und Systemwerkzeuge). `eth0` = DHCP (Default Switch), `eth1` = 192.168.10.1/24 statisch.
4. In der VM: Repo klonen, `.env` anlegen, `sudo ./setup.sh`, dann `docker compose up -d --build`.
5. Machbarkeitstest 1.0: vom PC `ping 192.168.10.1` und TCP-Zugriff auf einen Container (z. B. `curl http://10.20.20.4`).

## Dateien

- `compose.yml` – Netze (Zonen), Dienste, Volumes
- `bind9/`, `web/`, `ftp/`, `smb/`, `db/`, `client/` – Konfiguration je Dienst
- `nftables/lab.nft` – Firewall-Entwurf
- `voip/` – Asterisk (Image aus dem Quelltext, Konfiguration)
- `scripts/` – Backup und Wiederherstellung (backup.sh, restore.sh, ungetestet), Hyper-V-Einrichtung, Mapping-Skript für Windows
- Netzwerkdokumentation: Vault, `02 Projekt/LF9 Übungslabor/05P Dokumentation/Netzwerkdokumentation LF9.md`
- `tests/run-tests.sh` – automatisierte Tests

Keine Passwörter im Repository: `.env` ist in `.gitignore`, Vorlage ist `.env.example`.
