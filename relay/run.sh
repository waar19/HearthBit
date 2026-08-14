#!/usr/bin/with-contenv sh
set -eu

if [ -f /data/options.json ]; then
    chmod 0600 /data/options.json
    export HEARTHBIT_CONFIG=/data/options.json
fi

for secret in /data/identity.json /data/trusted-peers.json /data/mqtt-secrets.json /data/matrix-access-token; do
    if [ -e "${secret}" ]; then
        if [ -L "${secret}" ]; then
            echo "Refusing symbolic-link secret: ${secret}" >&2
            exit 1
        fi
        chmod 0600 "${secret}"
    fi
done

if [ ! -f "${HEARTHBIT_CONFIG}" ]; then
    echo "HearthBit configuration not found: ${HEARTHBIT_CONFIG}" >&2
    exit 1
fi

exec /opt/hearthbit-relay/venv/bin/hearthbit-relay
