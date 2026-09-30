#!/bin/sh
set -eu
case "${RENEWED_LINEAGE:-}" in
  /etc/letsencrypt/live/mail.vprod.nl)
    /usr/sbin/postfix check
    /usr/bin/doveconf -n >/dev/null
    systemctl reload dovecot
    /usr/sbin/postfix reload
    ;;
esac
