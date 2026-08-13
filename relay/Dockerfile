FROM ghcr.io/home-assistant/base:latest

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HEARTHBIT_CONFIG=/config/config.json

WORKDIR /opt/hearthbit-relay
COPY pyproject.toml README.md ./
COPY src ./src
COPY run.sh /run.sh
RUN apk add --no-cache python3 \
    && python3 -m venv /opt/hearthbit-relay/venv \
    && /opt/hearthbit-relay/venv/bin/pip install --no-cache-dir ".[mqtt]" \
    && chmod 0755 /run.sh

RUN mkdir -p /config /var/lib/hearthbit-relay
VOLUME ["/config", "/var/lib/hearthbit-relay"]

CMD ["/run.sh"]
