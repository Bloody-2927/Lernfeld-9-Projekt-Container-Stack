#!/usr/bin/env bash
# Einrichtung der Firewall-VM (Debian 12) für den Übungsplatz. STATUS: nicht getestet (Machbarkeitstest 1.0).
# Aufruf als root im Repo-Ordner: sudo ./setup.sh
# Erwartet: eth0 = Uplink (DHCP), eth1 = 192.168.10.1/24 (statisch, siehe README).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte als root ausführen (sudo ./setup.sh)"; exit 1; }
cd "$(dirname "$0")"

echo "== Pakete"
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg nftables chrony git

echo "== Docker (offizielles Repository)"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

echo "== Kernel: Weiterleitung an, IPv6 aus"
cat > /etc/sysctl.d/90-lab.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl --system >/dev/null

echo "== Docker: keine eigenen iptables-Regeln (Firewall steuert nftables), Logrotation"
install -d /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "iptables": false,
  "ip6tables": false,
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF

echo "== nftables: Regeln laden und beim Start aktivieren (vor Docker)"
install -d /etc/nftables.d
install -m 0644 nftables/lab.nft /etc/nftables.d/lab.nft
grep -q 'nftables.d/lab.nft' /etc/nftables.conf || echo 'include "/etc/nftables.d/lab.nft"' >> /etc/nftables.conf
install -d /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/after-nftables.conf <<'EOF'
[Unit]
After=nftables.service
Wants=nftables.service
EOF
systemctl daemon-reload
systemctl enable --now nftables
systemctl restart docker

echo "== Zeit (chrony)"
systemctl enable --now chrony

echo "== Konfiguration"
[ -f .env ] || { cp .env.example .env; chmod 600 .env; echo "HINWEIS: .env aus Vorlage erzeugt. Passwörter VOR dem Start ersetzen (CHANGE_ME)."; }

echo
echo "Fertig. Nächste Schritte: .env prüfen, dann 'docker compose up -d --build', danach tests/run-tests.sh."
