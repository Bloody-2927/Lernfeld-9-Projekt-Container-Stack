# lf9-lab – Übungslabor Kopernikus Hochschule (LF 9, 11IT2B)

Docker-Stack und Skripte für den Laborübungsplatz der Heiner-IT Systems GmbH.
Projektleitung: Team Heiner-IT Systems. Abgabe: 07.12.2026.
Grundlage: Pflichtenheft V1.2 (Zonenmodell, Adressplan 10.20.x, Regelwerk) und logischer Netzwerkplan V1.2.

## Aufbau

| Zone | Netz | Dienste |
|---|---|---|
| 10 Clients | 192.168.10.0/24 | Windows-PC .10, Test-Client-VM .11, Firewall-VM .1 |
| 20 Web | 10.20.20.0/24 | nginx .4 (Caddy .2, Pi-hole .3, Nextcloud .5 folgen) |
| 30 Infrastruktur | 10.20.30.0/24 | bind9 .2, Uptime Kuma .3 (Loki/Grafana .4 folgt) |
| 40 Fileserver | 10.20.40.0/24 | vsftpd .2, Samba .3 |
| 50 Datenbank | 10.20.50.0/24 | MariaDB .2 |
| 60 VoIP | 10.20.60.0/24 | Asterisk/coturn .2 (optional, folgt) |

## Stand

| Teil | Stand |
|---|---|
| bind9, nginx, vsftpd, Samba, MariaDB, Uptime Kuma (`compose.yml`) | gebaut und mit `tests/run-tests.sh` auf Docker Desktop getestet (31 von 31 Prüfungen bestanden am 02.11.2026; Uptime Kuma antwortet auf Port 3001, Monitore noch nicht eingerichtet) |
| Zonenübergreifendes Routing, nftables, Reject/Drop | **nicht getestet** – erst in der Firewall-VM möglich (`nftables/lab.nft` ist ein Entwurf) |
| `setup.sh`, `scripts/windows/01-hyperv-setup.ps1`, `scripts/backup.sh`, `scripts/windows/map-shares.cmd` | **nicht getestet** (Machbarkeitstest 1.0 steht aus) |
| Caddy, Pi-hole, Nextcloud, Loki/Grafana, VoIP | noch nicht umgesetzt (Aufgaben 4.4 bis 4.6) |

## Lokaler Test (Docker Desktop, ohne VM)

```bash
cp .env.example .env        # Passwörter ersetzen (CHANGE_ME), .env wird nicht committet
docker compose --profile test up -d --build
bash tests/run-tests.sh     # Tests T-01 bis T-06, T-12 (Pflichtenheft Kapitel 11)
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
- `scripts/` – Backup, Hyper-V-Einrichtung, Mapping-Skript für Windows
- `tests/run-tests.sh` – automatisierte Tests

Keine Passwörter im Repository: `.env` ist in `.gitignore`, Vorlage ist `.env.example`.
