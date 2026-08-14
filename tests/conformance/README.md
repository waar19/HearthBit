# Binary conformance suite

[Español](README.es.md)

This suite pins the
[`docs/bitchat-core-profile.md`](../../docs/bitchat-core-profile.md) profile
against
`vendor/bitchat-android@5156f7de89ec9f6a3429630d90f709b68f6fd7fd`.
`fixtures.v1.json` contains language-neutral metadata and `blobs/*.hex`
contains the exact bytes. Runners ignore whitespace in blobs, but not trailing
bytes.

The vectors are not invented examples:

- v1, canonical signatures, GCS, Courier, and HBT come from existing golden
  tests and production codecs.
- v2/routes were produced by the production encoder with deterministic fields.
- Raw DEFLATE and zlib represent the same deterministic payload and follow the
  profile's write/read policy.
- Truncated or malformed cases are minimal mutations of positive frames:
  version, length, signature, route, padding, stream, or limit.
- Extension payloads reproduce
  [`docs/extension-registry.md`](../../docs/extension-registry.md) literally.

## Running the suite

From PowerShell at the repository root:

```powershell
.\tests\conformance\run-conformance.ps1
```

Limit execution with `-Target kotlin`, `dart`, `python`, `swift`, or
`firmware`. Swift runs only on macOS. Firmware requires ESP-IDF to compile; its
C self-test runs at boot and aborts if a vector differs. On Windows without
ESP-IDF, the script checks that the generated C header remains identical to
the neutral blobs.

Regenerate the C adapter after changing fixtures:

```powershell
python .\tests\conformance\generate_firmware_header.py
python .\tests\conformance\generate_firmware_header.py --check
```

Direct commands:

- Kotlin: `cd app/android; .\gradlew.bat :app:testDebugUnitTest --tests com.hearthbit.app.mesh.ConformanceFixtureTest`
- Dart: `cd app; flutter test test/conformance_fixtures_test.dart`
- Python: `cd relay; python -m pytest tests/test_conformance_fixtures.py`
- Swift: `cd app/ios; xcodebuild test -workspace Runner.xcworkspace -scheme Runner -sdk iphonesimulator -destination "platform=iOS Simulator,OS=latest,name=iPhone 16" CODE_SIGNING_ALLOWED=NO`
- Firmware: `cd firmware/anchor-node; idf.py build`; then `idf.py flash monitor`

## Exact runner matrix

Kotlin JUnit and Swift XCTest cover:

- `packet.v1.message`, `packet.v2.route_signed`
- `packet.v1.raw_deflate`, `packet.v1.zlib_read`
- all `packet.invalid.*`
- `signature.canonical.v1_announce`
- `fragment.payload.valid`, all `fragment.invalid.*`, and both
  `fragment.reassemble.out_of_order.*`
- both `gcs.*` and both `courier.*`
- `extension.hbt_capability.v1`, `extension.node_capability.anchor`,
  `extension.radar_grant`, and both `extension.envelope.*`
- all `hbt.*`

Python pytest covers:

- `packet.v1.message`, `packet.v2.route_signed`
- `packet.v1.raw_deflate`, `packet.v1.zlib_read`
- all `packet.invalid.*`
- `signature.canonical.v1_announce`
- `fragment.payload.valid`, all `fragment.invalid.*`, and both
  `fragment.reassemble.out_of_order.*`
- both `gcs.*`, both `courier.*`, and both `extension.envelope.*`

Dart `flutter_test` covers all `hbt.*` through the production `TransferFrame`.
It does not duplicate the Android/iOS native mesh codec.

The firmware C self-test covers:

- `packet.v1.message`
- `packet.v1.raw_deflate`, `packet.v1.zlib_read`
- `packet.invalid.version`, `packet.invalid.header_truncated`,
  `packet.invalid.payload_truncated`, `packet.invalid.signature_truncated`,
  `packet.invalid.padding`, `packet.invalid.deflate_truncated`,
  `packet.invalid.deflate_trailing`, and `packet.invalid.expanded_size`

Firmware does not declare v2/routes because its production packet structure is
v1. Kotlin, Swift, and Python provide v2 coverage; the matrix avoids presenting
another language's test as a firmware capability.

## Continuous integration

The mobile workflow already runs every Dart and Kotlin test. The added
`conformance` job runs pytest. The C header check remains in the local script
because firmware is a submodule and its change must be published in its own
commit before updating the parent repository pointer. XCTest is ready for
macOS, but is not part of the iOS build workflow to avoid a fragile dependency
on one simulator model.
