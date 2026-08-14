import json
from pathlib import Path

import generate_firmware_header as generator


ROOT = Path(__file__).resolve().parent


def test_generated_header_is_current_and_covers_firmware_features() -> None:
    output = generator.OUTPUT.read_text(encoding="utf-8")
    assert output == generator.render()

    manifest = json.loads(
        (ROOT / "fixtures.v1.json").read_text(encoding="utf-8")
    )
    applicable = {
        entry["id"]
        for entry in manifest["fixtures"]
        if entry["operation"]
        in {
            "packet.decode",
            "packet.fingerprint",
            "fragment.decode",
            "fragment.packet",
            "gcs.decode",
            "courier.decode",
        }
    }
    covered = (
        set(generator.PACKET_IDS)
        | set(generator.FINGERPRINT_IDS)
        | set(generator.AUXILIARY_IDS)
    )
    assert covered == applicable
    assert all(f'"{fixture_id}"' in output for fixture_id in covered)
