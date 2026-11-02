FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends samba smbclient \
 && rm -rf /var/lib/apt/lists/*

COPY smb.conf /etc/samba/smb.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && testparm -s /etc/samba/smb.conf >/dev/null

EXPOSE 445
ENTRYPOINT ["/entrypoint.sh"]
