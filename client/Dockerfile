# Test-Client für den lokalen Test (nicht Teil des Laborplatzes)
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends dnsutils curl lftp smbclient iputils-ping netcat-openbsd mariadb-client tcpdump ca-certificates \
 && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
