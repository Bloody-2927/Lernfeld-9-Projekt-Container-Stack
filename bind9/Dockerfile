FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends bind9 bind9-utils dnsutils \
 && rm -rf /var/lib/apt/lists/*

COPY named.conf named.conf.options named.conf.local /etc/bind/
COPY zones/ /etc/bind/zones/

# Konfiguration und Zonendateien beim Bauen prüfen
RUN named-checkconf /etc/bind/named.conf \
 && named-checkzone kopernikus-lab.lokal /etc/bind/zones/db.kopernikus-lab.lokal \
 && named-checkzone 20.20.10.in-addr.arpa /etc/bind/zones/db.10.20.20 \
 && named-checkzone 30.20.10.in-addr.arpa /etc/bind/zones/db.10.20.30 \
 && named-checkzone 40.20.10.in-addr.arpa /etc/bind/zones/db.10.20.40 \
 && named-checkzone 50.20.10.in-addr.arpa /etc/bind/zones/db.10.20.50 \
 && named-checkzone 60.20.10.in-addr.arpa /etc/bind/zones/db.10.20.60 \
 && named-checkzone 10.168.192.in-addr.arpa /etc/bind/zones/db.192.168.10

EXPOSE 53/udp 53/tcp
CMD ["named", "-g", "-u", "bind"]
