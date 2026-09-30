#!/usr/bin/env python3
"""Check the chosen relay credential from stdin without sending mail or logging it."""
import smtplib
import ssl
import sys

if len(sys.argv) != 2:
    raise SystemExit(2)
password = sys.stdin.read().rstrip('\n')
if not password:
    raise SystemExit('SMTP-wachtwoord ontbreekt.')
try:
    with smtplib.SMTP('vps.transip.email', 587, timeout=20) as smtp:
        smtp.ehlo()
        smtp.starttls(context=ssl.create_default_context())
        smtp.ehlo()
        smtp.login(sys.argv[1], password)
except Exception:
    raise SystemExit('TransIP SMTP/TLS-aanmelding niet geslaagd; er zijn nog geen mailpakketten geïnstalleerd.') from None
finally:
    password = None
print('TransIP SMTP/TLS-aanmelding geslaagd; geen bericht verstuurd.')
