#!/usr/bin/env bash
# Einrichtung der Firewall-VM (Debian 12) für den Übungsplatz. STATUS: nicht getestet (Machbarkeitstest 1.0).
# Aufruf als root im Repo-Ordner: sudo bash setup.sh
# Erwartet: eth0 = Uplink (DHCP), eth1 = 192.168.10.1/24 (statisch, siehe README). Prüfen mit: ip -br a
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte als root ausführen (sudo bash setup.sh)"; exit 1; }
cd "$(dirname "$0")"

echo "== Schnittstellen prüfen"
ip -br addr show eth1 | grep -q '192.168.10.1/24' || { echo "FEHLER: eth1 hat nicht 192.168.10.1/24 (ip -br a). Zuordnung eth0/eth1 zu den Hyper-V-Adaptern prüfen."; exit 1; }

echo "== Pakete"
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg nftables chrony git openssl

echo "== Docker (offizielles Repository)"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

echo "== Kernel: Weiterleitung an, IPv6 aus, kein Bridge-Filter (Verkehr innerhalb einer Zone läuft ohne Regel)"
cat > /etc/sysctl.d/90-lab.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
# br_netfilter nur setzen, wenn das Modul geladen ist (sonst kennt sysctl den Schlüssel nicht)
if modprobe br_netfilter 2>/dev/null; then
  echo "net.bridge.bridge-nf-call-iptables = 0" >> /etc/sysctl.d/90-lab.conf
  echo "br_netfilter" > /etc/modules-load.d/lab.conf
fi
sysctl --system >/dev/null

echo "== Docker: keine eigenen iptables-Regeln (Firewall steuert nftables), feste Adresspools, Logrotation"
install -d /etc/docker
# bip und Pools liegen bewusst außerhalb von 172.16.0.0/12 (Hyper-V Default Switch) und 10.20.0.0/16
cat > /etc/docker/daemon.json <<'EOF'
{
  "iptables": false,
  "ip6tables": false,
  "bip": "10.99.0.1/24",
  "default-address-pools": [{ "base": "10.98.0.0/16", "size": 24 }],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF

echo "== nftables: Syntax prüfen, Regeln laden, beim Start aktivieren (vor Docker)"
nft -c -f nftables/lab.nft || { echo "FEHLER: nftables/lab.nft hat einen Syntaxfehler, nichts wurde geladen."; exit 1; }
install -d /etc/nftables.d
install -m 0644 nftables/lab.nft /etc/nftables.d/lab.nft
grep -q 'nftables.d/lab.nft' /etc/nftables.conf || echo 'include "/etc/nftables.d/lab.nft"' >> /etc/nftables.conf
install -d /etc/systemd/system/docker.service.d
# Requires statt Wants: ohne geladene Firewall startet Docker nicht (sonst wäre bei ip_forward=1 keine Trennung aktiv)
cat > /etc/systemd/system/docker.service.d/after-nftables.conf <<'EOF'
[Unit]
After=nftables.service
Requires=nftables.service
EOF
systemctl daemon-reload
systemctl enable --now nftables
systemctl restart docker

echo "== Zeit (chrony)"
systemctl enable --now chrony

echo "== Konfiguration (.env)"
if [ ! -f .env ]; then
  # Zufallskennwörter statt Vorlagenwerte: jedes Konto bekommt ein eigenes
  while IFS= read -r line; do
    case "$line" in
      *=CHANGE_ME) printf '%s=%s\n' "${line%%=*}" "$(openssl rand -hex 12)" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < .env.example > .env
  chmod 600 .env
  # Besitzer ist der Benutzer, der sudo aufgerufen hat. Sonst kann er die Datei nicht lesen, und
  # 'docker compose' sowie 'tests/run-tests.sh' scheitern beim ersten Lauf (Rollenprüfung 2026-11-03, SA-17).
  if [ -n "${SUDO_USER:-}" ]; then
    chown "${SUDO_USER}" .env
  fi
  echo ".env mit Zufallskennwörtern erzeugt (chmod 600). Nicht ins Repo, nicht in Notizen."
fi
if grep -q 'CHANGE_ME' .env; then
  echo "FEHLER: .env enthält noch CHANGE_ME. Werte ersetzen, dann erneut starten."
  exit 1
fi

echo
echo "Fertig. Nächste Schritte: 'docker compose up -d --build', danach 'bash tests/run-tests.sh'."
echo "Der Test startet den Test-Client (Profil test) selbst. Ohne Mitgliedschaft in der Gruppe docker beide Befehle mit 'sudo' aufrufen."
