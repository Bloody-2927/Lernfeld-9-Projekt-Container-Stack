FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends vsftpd \
 && rm -rf /var/lib/apt/lists/* \
 && echo "/usr/sbin/nologin" >> /etc/shells \
 && mkdir -p /var/run/vsftpd/empty

COPY vsftpd.conf /etc/vsftpd.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 21 21100-21110
ENTRYPOINT ["/entrypoint.sh"]
