#!/usr/bin/with-contenv sh
set -eu

if [ -f /data/options.json ]; then
    export HEARTHBIT_CONFIG=/data/options.json
fi

if [ ! -f "${HEARTHBIT_CONFIG}" ]; then
    echo "HearthBit configuration not found: ${HEARTHBIT_CONFIG}" >&2
    exit 1
fi

exec /opt/hearthbit-relay/venv/bin/hearthbit-relay
