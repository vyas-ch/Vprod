#!/usr/bin/env bash
# Read-only identity check. The provider's display name is not the OS hostname.
set -Eeuo pipefail
expected_ipv4='37.97.129.7'
expected_fingerprint='SHA256:GXSblWUtyrwErcHomD8a704S/6OZVRSgg+0aB+8QxAA'

if ! actual_fingerprint=$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256 | awk '{print $2}'); then
    printf 'VPS-identiteit kon niet worden gecontroleerd; installatie gestopt.\n' >&2
    exit 1
fi
if [[ $actual_fingerprint != "$expected_fingerprint" ]]; then
    printf 'SSH-serveridentiteit wijkt af van de V Production VPS; installatie gestopt.\n' >&2
    exit 1
fi
if ! ip -4 -o address show scope global | awk -v expected="$expected_ipv4" '
    { split($4, address, "/"); if (address[1] == expected) found = 1 }
    END { exit !found }
'; then
    printf 'Het verwachte V Production IP-adres ontbreekt; installatie gestopt.\n' >&2
    exit 1
fi
printf 'V Production VPS-identiteit gecontroleerd (%s).\n' "$expected_ipv4"
