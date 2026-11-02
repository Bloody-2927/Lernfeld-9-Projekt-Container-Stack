#!/usr/bin/env python3
"""SIP-REGISTER mit Digest-Anmeldung (qop=auth), Asterisk verlangt diese Form.
Aufruf: register.py <Benutzer> <Kennwort> [Server]. Ausgabe: Statuscode der zweiten Antwort (200 = angemeldet)."""
import hashlib, random, re, socket, sys

user, pwd = sys.argv[1], sys.argv[2]
srv = sys.argv[3] if len(sys.argv) > 3 else "10.20.60.2"
uri = f"sip:{srv}"
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2)
s.connect((srv, 5060))
me, port = s.getsockname()
cid = f"{random.randrange(10**9)}@{me}"
tag = str(random.randrange(10**6))

def register(cseq, auth=""):
    msg = (f"REGISTER {uri} SIP/2.0\r\nVia: SIP/2.0/UDP {me}:{port};branch=z9hG4bK{cseq}{tag};rport\r\n"
           f"From: <sip:{user}@{srv}>;tag={tag}\r\nTo: <sip:{user}@{srv}>\r\nCall-ID: {cid}\r\n"
           f"CSeq: {cseq} REGISTER\r\nContact: <sip:{user}@{me}:{port}>\r\nMax-Forwards: 70\r\nExpires: 120\r\n"
           f"{auth}Content-Length: 0\r\n\r\n")
    s.send(msg.encode())
    return s.recv(4096).decode(errors="replace")

md5 = lambda x: hashlib.md5(x.encode()).hexdigest()
try:
    r1 = register(1)
    f = lambda k: re.search(k + r'="([^"]*)"', r1).group(1)
    nonce, realm, opaque = f("nonce"), f("realm"), f("opaque")
    cn, nc = md5(str(random.random()))[:16], "00000001"
    resp = md5(f"{md5(f'{user}:{realm}:{pwd}')}:{nonce}:{nc}:{cn}:auth:{md5(f'REGISTER:{uri}')}")
    auth = (f'Authorization: Digest username="{user}", realm="{realm}", nonce="{nonce}", uri="{uri}", '
            f'response="{resp}", algorithm=MD5, cnonce="{cn}", qop=auth, nc={nc}, opaque="{opaque}"\r\n')
    r2 = register(2, auth)
    print(r2.split("\r\n")[0].split()[1])
except (socket.timeout, AttributeError):
    print("keine Antwort")
    sys.exit(2)
