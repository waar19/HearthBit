# 雷达与距离测量验证

[English](radar-ranging-validation.en.md) ·
[Español](radar-ranging-validation.md) ·
[Deutsch](radar-ranging-validation.de.md) ·
[Français](radar-ranging-validation.fr.md) · **简体中文** ·
[日本語](radar-ranging-validation.ja.md)

## 范围与安全

- GPS 用于远距离引导。
- BLE RSSI 仅表示接近度和趋势，不能测量物理方向。
- 实验性 BLE 扫描在 90 秒后或移动 15 米后失效。
- Android Ranging 在 Android 16+ 上根据硬件使用 Channel Sounding、
  Wi-Fi NAN RTT 或 BLE RSSI。
- 声学声纳使用三轮类似 BeepBeep 的双向测量估算短距离。

声纳最适合 1–25 米且无遮挡的环境。请勿贴近耳朵使用；儿童和动物可能听到
高频声音。任何测量结果都不能替代救援人员的判断。

## 界面验证

1. 在窄屏设备上打开雷达。
2. 将手机靠近金属以降低指南针校准质量。
3. 确认只出现一个提示，并且雷达圆不移动。
4. 远离金属并做“8”字运动，确认提示消失且布局不跳动。
5. 开始扫描，确认引导动画覆盖在雷达圆上。
6. 等待 90 秒或移动超过 15 米，确认系统要求重新扫描。

## Android Ranging

需要两台 Android 16+ 设备和 `RANGING` 权限：

1. 在目标设备上启用网状网络并同意雷达测量。
2. 在第二台手机上打开雷达并启动无线测量。
3. 确认界面显示测量距离和误差范围。
4. 分别在 1、3、5、10 米处测试无遮挡和隔墙情况。

## Android–iPhone 声纳

1. 保持两台设备上的应用打开，并授予雷达和麦克风权限。
2. 断开蓝牙耳机，不要遮挡扬声器和麦克风。
3. 将设备间距设为 1–3 米并开始声学测量。
4. 三轮测量期间保持静止，并与卷尺结果比较。
5. 在 5、10、20 米及有背景噪声时重复。

如果每轮未检测到两个 chirp，HearthBit 必须丢弃结果。

## Android 持久通知

启用网状网络，在 Android 14+ 上划掉通知，确认通知会重新出现。停止网状网络
后，通知应消失且不再出现。
