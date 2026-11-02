# Asterisk 20 (LTS) aus dem offiziellen Quelltext: Debian 12 liefert kein Asterisk-Paket mehr.
FROM debian:bookworm-slim

ARG AST_VERSION=20.21.0
ARG AST_SHA256=13fd6e8f1fbb19a3174af82a388dd72c87eb2c92d32fca83c4d51bfab03f686a

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates wget build-essential pkg-config \
        libssl-dev libxml2-dev libsqlite3-dev uuid-dev libedit-dev libjansson-dev libncurses-dev \
        libssl3 libxml2 libsqlite3-0 libuuid1 libedit2 libjansson4 libncurses6; \
    cd /usr/src; \
    wget -q "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${AST_VERSION}.tar.gz"; \
    echo "${AST_SHA256}  asterisk-${AST_VERSION}.tar.gz" | sha256sum -c -; \
    tar xzf "asterisk-${AST_VERSION}.tar.gz"; \
    cd "asterisk-${AST_VERSION}"; \
    ./configure --without-pjproject-bundled=no >/dev/null 2>&1 || ./configure >/dev/null; \
    make -j"$(nproc)" >/dev/null; \
    make install >/dev/null; \
    make samples >/dev/null; \
    ldconfig; \
    cd /; rm -rf /usr/src/asterisk-*; \
    apt-get purge -y --auto-remove build-essential wget pkg-config libssl-dev libxml2-dev libsqlite3-dev uuid-dev libedit-dev libjansson-dev libncurses-dev; \
    rm -rf /var/lib/apt/lists/*; \
    groupadd -r asterisk; useradd -r -g asterisk -d /var/lib/asterisk -s /usr/sbin/nologin asterisk; \
    mkdir -p /var/run/asterisk /var/log/asterisk /var/spool/asterisk /opt/asterisk-conf

COPY conf/ /opt/asterisk-conf/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# SIP (UDP) und Medienstrom (RTP, Bereich siehe rtp.conf)
EXPOSE 5060/udp 10000-10100/udp
ENTRYPOINT ["/entrypoint.sh"]
