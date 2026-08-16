# HearthBit

<img src="app/assets/icon/hearthbit.png" alt="HearthBit 应用图标" width="160">

[English](README.md) · [Español](README.es.md) · [Deutsch](README.de.md) ·
[Français](README.fr.md) · **简体中文** · [日本語](README.ja.md)

HearthBit（“持续跳动的网络”）是一款无需互联网即可工作的移动应急通信应用。
手机通过低功耗蓝牙组成网状网络并转发消息。ESP32 节点、Android TV/Automotive、
Linux 和 Raspberry Pi 中继可以扩展网络覆盖范围。

## 主要功能

- 与 BitChat 兼容的公共和私密通信。
- 签名 SOS 警报、救援模式和定期 GPS 更新。
- 通过 Nearby Connections、局域网/热点、Wi-Fi Aware、BLE 或光学二维码传输文件。
- 专业搜索雷达：BLE 接近度与趋势、指南针、GPS 融合、Android 16 Ranging，
  以及可选的短距离声学测距。
- 离线紧急联系电话、家庭群组和物理信标。
- 支持英语、西班牙语、德语、法语、简体中文和日语。

具体能力取决于硬件和操作系统。BLE RSSI 不能提供真实方向；Android Ranging
需要兼容设备。声学声纳适用于约 1–25 米，并且在视线无遮挡时效果最佳。
HearthBit 不能替代官方紧急服务。

## 透明度与隐私

项目公开源代码，以便审查身份机制、加密、位置处理、后台运行和协议互操作性。
请参阅 [NOTICE.md](NOTICE.md)、[透明度说明](docs/transparency.zh.md) 和
[架构文档](docs/architecture.md)。

公共消息对频道参与者可见。私密消息使用 Noise XX 会话。雷达、位置和声学测量
需要限时同意。项目不保证消息送达、距离测量或后台运行始终成功。

## 许可证

HearthBit 是**源代码可见（source-available）**项目，并非 OSI 认可的开源项目。
HearthBit 原创代码采用
[PolyForm Noncommercial License 1.0.0](LICENSE)。在该许可证允许的
非商业范围内，可以审查、使用、修改和再分发。商业使用需要单独的书面许可：
[COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md)。

已经以 MIT 许可证发布的版本继续适用 MIT。
`vendor/bitchat-android/`、固件子模块和依赖项保留各自的许可证。
详情参阅 [NOTICE.md](NOTICE.md)。

## 快速开始

```powershell
git submodule update --init --recursive
cd app
flutter pub get
flutter run
```

真实网状网络测试需要启用蓝牙的物理设备。

## 支持项目

捐赠将用于设备测试、实地测试和中继硬件：
[Buy Me a Coffee](https://buymeacoffee.com/wilmeralzal)。
