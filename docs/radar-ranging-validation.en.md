# Radar and distance-ranging validation

**English** · [Español](radar-ranging-validation.md) ·
[Deutsch](radar-ranging-validation.de.md) ·
[Français](radar-ranging-validation.fr.md) ·
[简体中文](radar-ranging-validation.zh.md) ·
[日本語](radar-ranging-validation.ja.md)

## Scope and safety

HearthBit combines several sources, but none replaces rescue-team judgment:

- GPS: long-range guidance when combined accuracy is sufficiently good.
- BLE RSSI: proximity and trend; it does not measure physical direction.
- BLE sweep: experimental sector that must be repeated after walking 15 m or
  after 90 seconds.
- Android Ranging: Channel Sounding, Wi-Fi NAN RTT or BLE RSSI distance on
  Android 16 or later, depending on both phones.
- Acoustic sonar: short-range Android-to-iPhone distance using three chirp
  rounds and a BeepBeep-style two-way method.

Acoustic sonar works best at 1–25 m, with both phones uncovered and without
obstacles. Do not use it next to the ear; children and animals may hear the
high frequencies.

## Layout test

1. Open the radar on a narrow screen.
2. Degrade compass calibration by moving the phone near metal.
3. Confirm that only one banner appears and the circle does not move.
4. Move away, draw a figure eight and confirm the banner disappears without
   displacing the radar.
5. Start a sweep and verify that its guide overlays the circle.
6. Wait 90 seconds or walk more than 15 m and confirm that a repeat is required.

## Android Ranging test

Two Android 16-or-later devices with `RANGING` permission are required.

1. Enable the mesh and radar consent on the target.
2. Open the radar on the second phone.
3. Press the radio-ranging button.
4. Verify that the UI changes from approximate to measured distance and shows
   an error margin.
5. Repeat at 1, 3, 5 and 10 m, with line of sight and with a wall.

`RangingManager` selects Bluetooth Channel Sounding, Wi-Fi NAN RTT or BLE RSSI
according to reported capabilities.

## Android–iPhone acoustic sonar test

The app must remain open on both phones and the target must grant radar consent.

1. Grant microphone permission on both phones.
2. Disconnect Bluetooth headsets and leave speakers and microphones uncovered.
3. Place phones 1–3 m apart.
4. Press the acoustic-wave button.
5. Keep both phones still for all three rounds.
6. Compare the result with a measuring tape.
7. Repeat at 5, 10 and 20 m and with background noise.

If two chirps are not detected in each round, HearthBit discards the result
instead of displaying a misleading distance.

## Persistent Android notification

1. Enable the mesh.
2. Swipe the notification away on Android 14 or later.
3. Confirm that it is republished while the mesh remains active.
4. Stop the mesh from the app.
5. Confirm that the notification disappears and is not republished.
