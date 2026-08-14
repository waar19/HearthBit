FROM ghcr.io/home-assistant/base:latest

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HEARTHBIT_CONFIG=/config/config.json

WORKDIR /opt/hearthbit-relay
COPY pyproject.toml constraints.txt README.md ./
COPY src ./src
COPY run.sh /run.sh
RUN apk add --no-cache python3 \
    && apk add --no-cache --virtual .build-deps build-base python3-dev \
    && python3 -m venv /opt/hearthbit-relay/venv \
    && /opt/hearthbit-relay/venv/bin/pip install --no-cache-dir \
        -c constraints.txt ".[mqtt]" \
    && apk del .build-deps \
    && chmod 0755 /run.sh

RUN mkdir -p /config /var/lib/hearthbit-relay
VOLUME ["/config", "/var/lib/hearthbit-relay"]

CMD ["/run.sh"]
