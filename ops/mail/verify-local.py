#!/usr/bin/env python3
"""Root-only local acceptance test. Never prints authentication data."""
import email.message
import imaplib
import json
import pathlib
import smtplib
import socket
import ssl
import time
import uuid

HOST = 'mail.vprod.nl'
credentials = json.loads(pathlib.Path('/etc/vprod-mail/client.json').read_text())
context = ssl.create_default_context()
original_connection = socket.create_connection


def local_connection(address, *args, **kwargs):
    # Preserve HOST for verified certificate identity while connecting locally.
    if address[0] == HOST:
        address = ('127.0.0.1', address[1])
    return original_connection(address, *args, **kwargs)


socket.create_connection = local_connection

# Exercise port 25 separately: authenticated submission intentionally bypasses
# its inbound Milter. All recipients stay on this server; no test is relayed.
with smtplib.SMTP('127.0.0.1', 25, timeout=30) as smtp:
    smtp.ehlo(HOST)
    code, _ = smtp.mail('info@vprod.nl')
    assert code == 250, 'Inbound test envelope sender refused'
    missing_recipient = f'setup-missing-{uuid.uuid4().hex}@vprod.nl'
    code, _ = smtp.rcpt(missing_recipient)
    assert code in (550, 553, 554), 'Unknown virtual recipient was not refused at RCPT'
    smtp.rset()

    # Official reject-only GTUBE pattern; do not enable the other test patterns.
    # https://docs.rspamd.com/other/gtube_patterns/
    # Rspamd 3.8.1 checks this during MIME processing even for loopback clients.
    spam_test = email.message.EmailMessage()
    spam_test['From'] = 'info@vprod.nl'
    spam_test['To'] = 'info@vprod.nl'
    spam_test['Subject'] = 'V Production lokale spamfiltercontrole'
    spam_test['X-Vprod-Setup-Test'] = str(uuid.uuid4())
    spam_test.set_content(
        'Lokale synthetische spamfiltercontrole.\n\n'
        'XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X\n'
    )
    try:
        smtp.send_message(spam_test)
    except smtplib.SMTPDataError as error:
        assert error.smtp_code in (550, 554), 'GTUBE must receive a permanent spam rejection, not a temporary scanner error'
        response = error.smtp_error.lower()
        assert b'spam' in response or b'gtube' in response, 'GTUBE DATA rejection did not identify the spam filter'
    else:
        raise AssertionError('Inbound GTUBE was not rejected: verify the port 25 Milter path')
print('Inkomende SMTP: onbekende ontvanger geweigerd en GTUBE door spamfilter tegengehouden.')

with smtplib.SMTP(HOST, 587, timeout=15) as smtp:
    smtp.ehlo()
    assert not smtp.has_extn('auth'), 'AUTH must not be offered before TLS'
    smtp.starttls(context=context)
    smtp.ehlo()
    assert smtp.has_extn('auth'), 'AUTH unavailable after TLS'
    smtp.mail('info@vprod.nl')
    code, _ = smtp.rcpt('relay-test@example.net')
    assert code >= 500, 'Unauthenticated submission was not refused'
    smtp.rset()
    smtp.login(credentials['username'], credentials['password'])
    smtp.mail('unauthorized@example.net')
    code, _ = smtp.rcpt('info@vprod.nl')
    assert code >= 500, 'Authenticated sender spoofing was not refused'
    smtp.rset()
    token = str(uuid.uuid4())
    message = email.message.EmailMessage()
    message['From'] = 'info@vprod.nl'
    message['To'] = 'info@vprod.nl'
    message['Subject'] = 'V Production mailboxcontrole'
    message['X-Vprod-Setup-Test'] = token
    message.set_content('Deze automatische lokale controle test SMTP, LMTP en IMAP. Externe ontvangst en bezorging worden apart gecontroleerd.')
    assert not smtp.send_message(message), 'Local test delivery refused'

with imaplib.IMAP4_SSL(HOST, 993, ssl_context=context, timeout=15) as imap:
    assert imap.login(credentials['username'], credentials['password'])[0] == 'OK'
    found = False
    for _ in range(10):
        assert imap.select('INBOX', readonly=True)[0] == 'OK'
        status, data = imap.uid('SEARCH', None, 'HEADER', 'X-Vprod-Setup-Test', token)
        if status == 'OK' and data and data[0]:
            found = True
            break
        time.sleep(1)
    assert found, 'Submitted local test message did not arrive through LMTP/IMAP'
print('TLS, SMTP-authenticatie, afzendercontrole, LMTP en IMAP: geslaagd.')
