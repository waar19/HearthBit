# Security policy

## Report privately

Do not open a public issue for an unpatched vulnerability. Use a
[private GitHub Security Advisory](https://github.com/waar19/HearthBit/security/advisories/new).

Include the affected revision, platform and device, reproduction steps, impact,
logs with personal data removed, and whether the issue affects compatibility
with BitChat. Do not include real peer identifiers, precise locations, private
keys, voice recordings or emergency messages.

If the private advisory channel is unavailable, contact the repository owner
through a verified profile channel and share only enough information to
establish a secure reporting method.

## Scope

Relevant reports include:

- bypasses of identity, signature, Noise-session or replay checks;
- private-message, location, family-group or file-transfer disclosure;
- unauthorized radar, acoustic ranging or physical-beacon activation;
- denial of service caused by malformed mesh traffic;
- unsafe gateway defaults or exposed credentials;
- dependency vulnerabilities reachable in a supported HearthBit build.

BLE observability, radio interference, RSSI inaccuracy and operating-system
background limits are documented constraints rather than vulnerabilities by
themselves. A practical exploit that worsens one of these constraints is still
in scope.

## Handling

HearthBit is maintained without a guaranteed response or remediation SLA.
Reports will be acknowledged when maintainer capacity permits, validated on
available hardware, and disclosed after a fix or coordinated mitigation is
ready. Emergency-service operators should not rely on an unpatched build while
a relevant vulnerability is under investigation.

Supported versions and physical test coverage may change. Security claims tied
to iOS require macOS/iPhone validation; claims tied to Android Ranging require
compatible physical devices.

For privacy boundaries and known limitations, see the transparency documents
in [English](docs/transparency.md), [Español](docs/transparency.es.md),
[Deutsch](docs/transparency.de.md), [Français](docs/transparency.fr.md),
[简体中文](docs/transparency.zh.md) and [日本語](docs/transparency.ja.md).
