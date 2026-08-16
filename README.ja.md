# HearthBit

<img src="app/assets/icon/hearthbit.png" alt="HearthBitアプリアイコン" width="160">

[English](README.md) · [Español](README.es.md) · [Deutsch](README.de.md) ·
[Français](README.fr.md) · [简体中文](README.zh.md) · **日本語**

HearthBit（「鼓動し続けるネットワーク」）は、インターネットなしで動作する
モバイル緊急通信アプリです。スマートフォンがBluetooth Low Energyの
メッシュを構成してメッセージを中継します。ESP32ノード、Android
TV/Automotive、Linux、Raspberry Piのリレーで到達範囲を拡張できます。

## 主な機能

- BitChatと互換性のある公開・非公開通信。
- 署名付きSOS、救助モード、定期的なGPS更新。
- Nearby Connections、LAN/ホットスポット、Wi-Fi Aware、BLE、光学QRによる
  ファイル転送。
- BLE近接度と傾向、コンパス、GPS融合、Android 16 Ranging、任意の短距離
  音響測距を備えた捜索レーダー。
- オフライン緊急連絡先、家族グループ、物理ビーコン。
- 英語、スペイン語、ドイツ語、フランス語、簡体字中国語、日本語のUI。

利用できる機能はハードウェアとOSに依存します。BLE RSSIは実際の方向を
示しません。Android Rangingには対応端末が必要です。音響ソナーの目安は
約1〜25 mで、見通しのよい環境に適しています。HearthBitは公的な緊急通報を
代替するものではありません。

## 透明性とプライバシー

本人確認、暗号化、位置情報、バックグラウンド動作、相互運用性を監査できる
よう、ソースコードを公開しています。[NOTICE.md](NOTICE.md)、
[透明性レポート](docs/transparency.ja.md)、
[アーキテクチャ](docs/architecture.md)を参照してください。

公開メッセージはチャンネル参加者に見えます。非公開メッセージはNoise XX
セッションを使用します。レーダー、位置情報、音響測定には期限付きの同意が
必要です。配信、測距、バックグラウンド動作は保証されません。

## ライセンス

HearthBitは**source-available**ですが、OSI承認のオープンソースでは
ありません。HearthBit独自コードは
[PolyForm Noncommercial License 1.0.0](LICENSE)で提供されます。
同ライセンスが認める非商用目的で、閲覧、使用、変更、再配布できます。
商用利用には別途書面によるライセンスが必要です：
[COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md)。

すでにMITで公開されたバージョンは引き続きMITです。
`vendor/bitchat-android/`、ファームウェアのサブモジュール、依存関係には
それぞれのライセンスが適用されます。詳細は[NOTICE.md](NOTICE.md)を
参照してください。

## クイックスタート

```powershell
git submodule update --init --recursive
cd app
flutter pub get
flutter run
```

実際のメッシュ試験には、Bluetoothを有効にした実機が必要です。

## プロジェクトを支援

寄付は実機試験、フィールド試験、リレーハードウェアに使用されます：
[Buy Me a Coffee](https://buymeacoffee.com/wilmeralzal)。
