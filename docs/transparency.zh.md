# 透明度与隐私

HearthBit 公开代码，以便审查身份、加密、位置处理、后台运行和互操作性。
本项目是 source-available，并非 OSI 认可的开源项目。

## 数据与网络

本地网状通信不需要中央账户。身份和密钥在设备上生成；消息、传输记录和待发送
内容可以保存在本地。核心应用不要求分析服务，但在线地图、可选的
MQTT/Matrix/LAN 网关、外部链接和 Google Play Services 可能向其他运营方
传输数据。

附近设备可以观察到 BLE 无线活动。公共消息不属于机密信息。私密消息使用
Noise XX，但无线存在、时间和部分路由元数据仍可能被观察。

## 位置与距离

GPS、BLE RSSI、Android Ranging 和声学声纳具有不同误差。BLE 扫描在
90 秒后或移动 15 米后失效。声纳只在内存中处理短 PCM 录音，并发出高频声音；
附近的人、动物或其他麦克风可能感知这些声音。测量结果未经安全认证。

雷达、位置和声学测量需要限时同意。Android 在网状网络启用时显示持久通知；
iOS 由系统控制后台 BLE。

## 限制

HearthBit 不保证消息送达、匿名性、抗干扰能力、昵称对应的现实身份，也无法
保护已被攻破的设备。本应用不能替代官方紧急服务。安全报告不得公开真实设备
标识、位置、录音或紧急消息。

## 许可证

HearthBit 原创代码采用 PolyForm Noncommercial 1.0.0；商业使用需要单独协议。
已经以 MIT 发布的版本继续适用 MIT。第三方代码和子模块保留各自许可证。
请参阅 [`LICENSE`](../LICENSE)、[`NOTICE.md`](../NOTICE.md) 和
[`COMMERCIAL-LICENSE.md`](../COMMERCIAL-LICENSE.md)。
