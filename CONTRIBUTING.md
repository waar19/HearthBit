# Contributing to HearthBit

Thank you for helping improve emergency communication. Contributions must
preserve privacy, interoperability, safety warnings and licensing clarity.

## Issues, tests and documentation

You may open issues, report device-test results, suggest translations and
propose documentation corrections. Never publish real emergency messages,
precise locations, persistent device identifiers, recordings, private keys or
other people's personal data.

Security vulnerabilities should be reported privately through the repository's
GitHub Security Advisory channel rather than a public issue.

## Code contributions

HearthBit uses a dual source-available/commercial licensing model. A normal
pull request license alone does not necessarily give the project owner the
rights needed to offer commercial licenses that include third-party code.

For that reason:

1. Discuss substantial work in an issue before implementing it.
2. Identify all third-party code, protocol material and generated assets.
3. Do not copy code from BitChat or another project merely because its source
   is public. Confirm that its license is compatible and preserve notices.
4. A code contribution will not be merged until the contributor and copyright
   holder have completed a separate Contributor License Agreement (CLA).
5. The CLA must preserve the contributor's copyright while granting the rights
   required to distribute the contribution under HearthBit's noncommercial and
   commercial licenses.

Submitting a pull request by itself does **not** assign copyright and does not
silently accept a CLA. Until a reviewed CLA process is available, maintainers
may use an issue as a specification and independently implement the change.

## Translation requirements

User-visible changes must cover English, Spanish, German, French, Simplified
Chinese and Japanese. Security, privacy, limitation and license documentation
must be updated in all six core documentation languages. The official English
text in [`LICENSE`](LICENSE) controls over translated summaries.

## Verification

- Run `flutter analyze` and the relevant Flutter tests.
- Run Android native tests for Android changes.
- Build and test iOS-native changes on macOS.
- Mark hardware-dependent claims as pending until physical devices pass.
- Do not claim guaranteed delivery, precise direction or certified rescue use.

See [`NOTICE.md`](NOTICE.md), [`docs/transparency.md`](docs/transparency.md) and
[`docs/localization.md`](docs/localization.md) before contributing.
