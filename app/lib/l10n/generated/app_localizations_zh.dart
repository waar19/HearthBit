// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'HearthBit';

  @override
  String storageOpenError(String error) {
    return '无法打开本地存储：\n$error';
  }

  @override
  String statusActiveLabel(String nickname, int count) {
    return '$nickname · 附近 $count 台设备';
  }

  @override
  String statusDegradedLabel(String nickname) {
    return '$nickname · 仅接收（无 BLE 广播）';
  }

  @override
  String get statusStarting => '正在启动网状网络…';

  @override
  String get statusError => '网状网络出错';

  @override
  String get statusStopped => '网状网络已停止';

  @override
  String get actionStop => '停止';

  @override
  String get actionRestart => '重新启动';

  @override
  String get actionActivate => '开启';

  @override
  String get actionRetry => '重试';

  @override
  String get tooltipChangeName => '修改名称';

  @override
  String get tooltipPanicWipe => '紧急抹除';

  @override
  String get tabChannel => '频道';

  @override
  String get tabNearby => '附近';

  @override
  String get tabFiles => '文件';

  @override
  String get tabSos => 'SOS';

  @override
  String get emptyChatTitle => '还没有消息';

  @override
  String get emptyChatBody => '开启网状网络。消息将在附近的手机之间接力传递，无需互联网。';

  @override
  String get composerPublicHint => '发给附近所有人的消息';

  @override
  String get composerPrivateHint => '加密消息';

  @override
  String get privateChatIntro => '第一条消息将发起 Noise XX 握手。';

  @override
  String get emptyPeersTitle => '附近没有设备';

  @override
  String get emptyPeersBody => '保持蓝牙开启，并让另一台装有 HearthBit 或 BitChat 的手机靠近。';

  @override
  String get peerSecure => '加密通道已就绪';

  @override
  String get peerTapToEncrypt => '点按以加密';

  @override
  String get tooltipRadar => '近距离雷达';

  @override
  String get tooltipSendFile => '发送文件';

  @override
  String get peerDoesNotSupportTransfers =>
      '对方使用 BitChat；文件传输需要 HearthBit。请改用二维码传输。';

  @override
  String get sosCardTitle => '发送优先求救警报';

  @override
  String get sosCardBody => '如有可能将附上您的 GPS 位置。警报是公开的，并将通过网状网络转发。';

  @override
  String get sosMedical => '我需要医疗救助';

  @override
  String get sosTrapped => '我被困住了';

  @override
  String get sosImOk => '我没事';

  @override
  String get sosDefaultMessage => '我需要帮助';

  @override
  String get sosReceivedTitle => '收到的警报';

  @override
  String get sosNoneReceived => '尚未收到 SOS 警报。';

  @override
  String get actionTrack => '追踪';

  @override
  String get rescueModeTitle => '救援模式';

  @override
  String rescueModeActive(int minutes) {
    return '每 $minutes 分钟重新发送带位置的 SOS。';
  }

  @override
  String rescueModeLastPing(String time) {
    return '上次发送：$time。';
  }

  @override
  String rescueModeInactive(int minutes) {
    return '每 $minutes 分钟用最新 GPS 重新发送您的 SOS，即使屏幕已关闭。';
  }

  @override
  String get rescueModeNoBackgroundLocation => '没有始终允许的定位权限，GPS 只会在应用打开时更新。';

  @override
  String get actionAllow => '允许';

  @override
  String get powerCardTitle => '电池与定位';

  @override
  String get powerCardSubtitle => '这些设置能让网状网络持续运行，并帮助救援人员找到您。';

  @override
  String get powerBatteryOptimization => '已为 HearthBit 关闭电池优化';

  @override
  String get actionDisable => '关闭';

  @override
  String get powerLocationAndroid => '定位权限已设为“始终允许”';

  @override
  String get powerLocationIos => '定位权限已设为“始终”';

  @override
  String get powerSaverAndroid => '系统省电模式已开启，可能会关闭网状网络';

  @override
  String get powerSaverIos => '低电量模式已开启，会降低后台蓝牙性能';

  @override
  String get powerTipsTitle => '省电建议';

  @override
  String get actionAdjust => '调整';

  @override
  String get powerTipBrightness => '将屏幕亮度调到最低，并缩短锁屏时间。';

  @override
  String get powerTipMobileData => '如果没有互联网，请关闭移动数据和 5G：网状网络不使用它们，而搜索信号非常耗电。';

  @override
  String get powerTipCloseApps => '关闭不需要的应用；保持蓝牙和定位开启。';

  @override
  String get powerTipAndroidRecents => '不要从最近任务中划掉 HearthBit：系统会杀死网状网络。';

  @override
  String get powerTipAndroidVendor =>
      '部分厂商（小米、华为、三星）有自己的省电机制：也要在那里为 HearthBit 设置例外。';

  @override
  String get powerTipAndroidSync => '紧急期间请关闭账号自动同步。';

  @override
  String get powerTipIosForceClose => '不要强制退出 HearthBit：iOS 不会自动重新启动它。';

  @override
  String get powerTipIosBackgroundRefresh => '在设置中关闭其他应用的后台刷新。';

  @override
  String get powerTipIosLowPower => '除非 HearthBit 在前台显示，否则请避免低电量模式：它会降低后台蓝牙性能。';

  @override
  String get powerTipShareBattery => '邻里之间共享充电宝：只要有一部手机保持开机，就能维持整个街区的连接。';

  @override
  String get nicknameDialogTitle => '显示名称';

  @override
  String get nicknameDialogHint => '例如：12 号楼或小安';

  @override
  String get actionCancel => '取消';

  @override
  String get actionSave => '保存';

  @override
  String get wipeDialogTitle => '抹除全部身份信息？';

  @override
  String get wipeDialogBody => '将删除密钥、历史记录和待发送的消息。此操作无法撤销。';

  @override
  String get actionWipe => '全部抹除';

  @override
  String get photoProfileTitle => '应急配置';

  @override
  String photoProfileBody(String size) {
    return '这张照片有 $size MiB。压缩后可加快传输并节省网状网络的电量。';
  }

  @override
  String get actionSendOriginal => '发送原图';

  @override
  String get actionCompress => '压缩';

  @override
  String offerFileError(String error) {
    return '无法发起文件传输：$error';
  }

  @override
  String get terrPeerDoesNotSupportTransfers =>
      '接收方不支持 HearthBit 文件传输。请改用二维码传输。';

  @override
  String get terrOfferExpiredNoHbt => '传输请求已过期，因为接收方不支持 HearthBit 文件传输。';

  @override
  String get sendByQr => '通过二维码发送';

  @override
  String get receiveByQr => '通过二维码接收';

  @override
  String get emptyTransfersTitle => '暂无传输';

  @override
  String get emptyTransfersBody =>
      '点按附近设备旁的回形针，即可向其发送文件。传输请求通过网状网络加密传递，内容则使用当前最快的可用通道。二维码模式甚至无需任何无线电。';

  @override
  String transferFrom(String nickname) {
    return '来自 $nickname';
  }

  @override
  String transferTo(String nickname) {
    return '发给 $nickname';
  }

  @override
  String transferProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String transferSavedAt(String path) {
    return '已保存到 $path';
  }

  @override
  String get stateOffered => '待确认';

  @override
  String get stateConnecting => '连接中';

  @override
  String get stateTransferring => '传输中';

  @override
  String get stateCompleted => '已完成';

  @override
  String get stateRejected => '已拒绝';

  @override
  String get stateCancelled => '已取消';

  @override
  String get stateFailed => '失败';

  @override
  String get transportBle => '蓝牙';

  @override
  String get transportLan => '本地 Wi-Fi';

  @override
  String get transportNearby => 'Nearby';

  @override
  String get transportWifiAware => 'Wi-Fi Aware';

  @override
  String get transportOptical => '光学二维码';

  @override
  String get actionReject => '拒绝';

  @override
  String get actionAccept => '接受';

  @override
  String get actionDelete => '删除';

  @override
  String get opticalFileEmpty => '文件为空';

  @override
  String opticalSendStats(String fileName, int chunks, int symbol) {
    return '$fileName · $chunks 个数据块 · 符号 $symbol';
  }

  @override
  String get opticalConfirmed => '接收方已通过 BLE 确认接收';

  @override
  String get opticalSpeedLabel => '速度';

  @override
  String opticalFps(int fps) {
    return '$fps 个二维码/秒';
  }

  @override
  String get densityCompact => '紧凑';

  @override
  String get densityMedium => '中等';

  @override
  String get densityHigh => '高';

  @override
  String get opticalSendHint => '如果接收方相机丢帧较多，请降低速度或密度。编码是无码率的：重复符号绝不会损坏传输。';

  @override
  String get opticalShaFailed => 'SHA-256 校验失败；请重新开始发送';

  @override
  String opticalSavedTitle(String fileName) {
    return '$fileName 已校验并保存';
  }

  @override
  String get genericFile => '文件';

  @override
  String get actionDone => '完成';

  @override
  String get opticalScanHint => '将相机对准发送方的二维码。文件头每隔几帧就会重复一次。';

  @override
  String opticalReceiveStats(
    String fileName,
    int decoded,
    int total,
    int symbols,
  ) {
    return '$fileName · $decoded / $total 个数据块 · $symbols 个符号';
  }

  @override
  String radarTitle(String nickname) {
    return '雷达 · $nickname';
  }

  @override
  String get radarSignalLost => '信号丢失';

  @override
  String get radarSignalLostHint => '沿原路慢慢往回走，直到重新收到信号。';

  @override
  String get radarSearching => '正在搜索信号…';

  @override
  String get radarSearchingHint => '慢慢地绕大圈行走。雷达接收的是直接的蓝牙信号（数十米范围）。';

  @override
  String get proximityVeryClose => '非常近';

  @override
  String get proximityClose => '较近';

  @override
  String get proximityInRange => '在范围内';

  @override
  String get proximityFar => '较远';

  @override
  String get trendApproaching => '您正在接近';

  @override
  String get trendReceding => '信号正在减弱';

  @override
  String get trendSteady => '信号稳定';

  @override
  String get trendUnknown => '正在测量信号…';

  @override
  String get distanceVeryNear => '距离不到 2 米';

  @override
  String distanceApprox(int meters) {
    return '约 $meters 米';
  }

  @override
  String get distanceFar => '距离超过 15 米';

  @override
  String radarDbm(int dbm) {
    return '信号 $dbm dBm';
  }

  @override
  String radarGpsDistance(String distance) {
    return '最后上报的 GPS：直线距离 $distance';
  }

  @override
  String get errorPermissions => '创建网状网络需要蓝牙和通知权限。';

  @override
  String get errorLocationOff => '请开启系统定位以使用救援模式';

  @override
  String get errorUnknown => '未知错误';

  @override
  String get tooltipSupport => '支持 HearthBit';

  @override
  String get aboutTitle => '关于 HearthBit';

  @override
  String get aboutBody => 'HearthBit 是一个开源应急通信项目。您的支持将帮助我们进行真机测试并开发可靠的中继硬件。';

  @override
  String aboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String get aboutSourceCode => '源代码';

  @override
  String get supportButton => '请我喝杯咖啡';

  @override
  String get shareInviteButton => '分享 HearthBit';

  @override
  String shareInviteMessage(String url) {
    return '加入 HearthBit：一个无需互联网即可工作的开源应急网状网络。下载或参与贡献：$url';
  }

  @override
  String get tooltipShare => '邀请他人使用 HearthBit';

  @override
  String get shareInviteError => '无法打开分享选项';

  @override
  String get openLinkError => '无法打开链接';

  @override
  String get actionClose => '关闭';

  @override
  String get terrInterrupted => '应用关闭时中断';

  @override
  String get terrFileSize => '文件大小必须在 1 字节到 512 MiB 之间';

  @override
  String get terrOfferExpired => '传输请求已超时，无人响应';

  @override
  String get terrNoTransport => '没有与发送方兼容的传输通道';

  @override
  String get terrInvalidSignature => '已丢弃一个签名无效的传输请求';

  @override
  String get terrUnsupportedTransport => '此版本不支持该传输通道';

  @override
  String get terrLanIncomplete => 'LAN 连接未完成就已结束';

  @override
  String terrLanFailed(String error) {
    return 'LAN 失败：$error';
  }

  @override
  String terrBleChunk(String error) {
    return 'BLE 数据块无效：$error';
  }

  @override
  String get terrTransport => '传输错误';

  @override
  String terrNearbyStart(String error) {
    return '无法启动 Nearby：$error';
  }

  @override
  String terrWifiAwareStart(String error) {
    return '无法启动 Wi-Fi Aware：$error';
  }

  @override
  String terrBleInterrupted(String error) {
    return 'BLE 发送中断：$error';
  }

  @override
  String get terrReceiverSilent => '接收方不再确认数据块';

  @override
  String terrNearbyUnavailable(String error) {
    return 'Nearby 不可用：$error';
  }

  @override
  String terrWifiAwareUnavailable(String error) {
    return 'Wi-Fi Aware 不可用：$error';
  }

  @override
  String get terrContainerIncomplete => '容器到达时不完整';

  @override
  String terrContainerDecrypt(String error) {
    return '无法解密容器：$error';
  }

  @override
  String get terrShaMismatch => 'SHA-256 校验失败；文件已丢弃';

  @override
  String terrNoMeshSession(String error) {
    return '与对方没有网状网络连接：$error';
  }

  @override
  String get terrTransportTimeout => '传输通道无响应';

  @override
  String get recentChatsTitle => '最近对话';

  @override
  String get nearbyPeopleTitle => '附近的人';

  @override
  String get peerOnline => '在线';

  @override
  String get peerOffline => '离线';

  @override
  String get offlineChatHint => '对方当前离线。你可以查看历史记录，并在对方重新连接后发送消息。';

  @override
  String get radarConsentTitle => '雷达隐私';

  @override
  String get radarConsentOff => '默认禁止雷达定位';

  @override
  String radarConsentActive(int minutes) {
    return '他人还可使用雷达 $minutes 分钟';
  }

  @override
  String get radarConsentAllow => '允许雷达定位 15 分钟';

  @override
  String get radarConsentRevoke => '立即撤销';

  @override
  String get radarPrivacyWarning => '此设置仅限制 HearthBit。其他软件仍可能测量手机发出的蓝牙信号。';

  @override
  String get rescueRadarWarning =>
      '救援模式会共享最新 SOS 位置，并允许附近的 HearthBit 救援人员在 SOS 激活期间测量你的信号。';

  @override
  String get radarConsentRequired => '需要对方同意';

  @override
  String get radarConsentSos => '因近期 SOS 而可用';

  @override
  String get radarConsentTemporary => '对方已临时授权';

  @override
  String radarConsentExpires(String time) {
    return '权限于 $time 到期';
  }

  @override
  String get radarNotDirection => '圆点表示距离而非方向。请缓慢移动并比较信号是否增强。';

  @override
  String get radarPermissionExpired => '雷达权限已到期或被撤销。';

  @override
  String get radarTentativeSignal => '暂定信号：正在确认此 iPhone 是否属于所选人员。';

  @override
  String get radarSweepStart => '搜索方向';

  @override
  String get radarSweepRestart => '重新扫描';

  @override
  String get radarSweepInstruction => '将手机贴在胸前，缓慢转动一整圈。';

  @override
  String radarSweepProgress(int percent) {
    return '扫描进度：$percent%';
  }

  @override
  String radarSweepResult(int heading) {
    return '估计信号方位：$heading°';
  }

  @override
  String radarSweepConfidence(int percent) {
    return '置信度：$percent%';
  }

  @override
  String get radarSweepEstimateWarning => '这是 RSSI 估计值，并非精确方向。请移动位置并重新扫描以验证。';

  @override
  String get radarCompassUnavailable => '此手机没有可用的指南针传感器。距离雷达仍可使用。';

  @override
  String get dateToday => '今天';

  @override
  String get dateYesterday => '昨天';

  @override
  String get genericPresenceSectionTitle => '其他蓝牙信号';

  @override
  String get genericPresenceNoChat => '检测到附近设备，无法聊天';

  @override
  String genericPresenceSignal(int rssi) {
    return '通用蓝牙信号 · $rssi dBm';
  }

  @override
  String get nodeModeTooltip => '节点模式';

  @override
  String get nodeModeTitle => '此手机应如何参与网络？';

  @override
  String get nodeModeRelayTitle => '网状网络中继';

  @override
  String get nodeModeRelayBody => '正常聊天，并为附近的人转发消息。';

  @override
  String get nodeModeBeaconTitle => '仅在线状态';

  @override
  String get nodeModeBeaconBody =>
      '不聊天、不转发消息，仅广播在线状态以节省电量。在 Android 上还会禁用数据连接。';

  @override
  String get tabEmergency => '紧急';

  @override
  String get emergencyHeadline => '紧急模式';

  @override
  String get emergencyInstructions => '长按 SOS 2 秒。HearthBit 将启动网状网络、共享位置并重复警报。';

  @override
  String get emergencyHoldSos => '长按发送 SOS';

  @override
  String get emergencySosActive => 'SOS 已启动';

  @override
  String get emergencyStopRescue => '停止救援模式';

  @override
  String get errorEmergencyMeshUnavailable => '无法启动蓝牙网状网络。请检查权限后重试。';

  @override
  String get checkInTitle => '报告你的状态';

  @override
  String get checkInBody => '状态将通过网状网络转发，并附带时间和可用的位置。';

  @override
  String get checkInOk => '我很安全';

  @override
  String get checkInNeedsHelp => '我需要帮助';

  @override
  String get checkInInjured => '我受伤了';

  @override
  String get checkInRecentTitle => '最新状态';

  @override
  String get checkInNone => '尚未有人报告状态。';

  @override
  String get onboardingWelcomeTitle => '网络中断时保持通信';

  @override
  String get onboardingWelcomeBody => 'HearthBit 无需移动网络或互联网，通过蓝牙在附近手机间转发紧急消息。';

  @override
  String get onboardingMeshTitle => '保持紧急网状网络运行';

  @override
  String get onboardingMeshBody => '蓝牙、附近设备和通知权限用于发现人员并转发消息。';

  @override
  String get onboardingReadyTitle => '在紧急情况前做好准备';

  @override
  String get onboardingReadyBody => '允许后台位置并解除电池限制，以保持 SOS 位置最新。';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingBack => '返回';

  @override
  String get onboardingAllowMesh => '允许并启动网络';

  @override
  String get onboardingAllowLocation => '允许紧急位置';

  @override
  String get onboardingFinish => '完成设置';

  @override
  String get appearanceTitle => '显示与无障碍';

  @override
  String get appearanceAmoled => 'AMOLED 纯黑主题';

  @override
  String get appearanceAmoledBody => '在 OLED 屏幕上使用纯黑以节省电量。';

  @override
  String get appearanceHighContrast => '高对比度和更大控件';

  @override
  String get appearanceHighContrastBody => '提高可读性并放大关键操作。';

  @override
  String get tooltipAppearance => '显示与无障碍';

  @override
  String get meshHealthTitle => '网状网络状态';

  @override
  String meshHealthDirect(int count) {
    return '$count 个直接节点';
  }

  @override
  String meshHealthRelays(int count) {
    return '$count 个中继';
  }

  @override
  String meshHealthAnchors(int count) {
    return '$count 个数据锚点';
  }

  @override
  String meshHealthSignals(int count) {
    return '$count 个其他蓝牙信号';
  }

  @override
  String get meshHealthAnchorReady => '附近有持久数据锚点。';

  @override
  String get meshHealthNoAnchor => '当前未发现持久数据锚点。';

  @override
  String get adaptivePowerTitle => '自适应省电';

  @override
  String get adaptivePowerNormal => '完整网状网络性能';

  @override
  String get adaptivePowerSaving => '省电：短时扫描';

  @override
  String get survivalModeTitle => '生存模式';

  @override
  String get survivalModeBody => '仅保留 SOS 信标以延长续航，聊天和中继将停止。';

  @override
  String get survivalModeEnable => '启用生存模式';

  @override
  String get survivalModeDisable => '返回网状网络模式';

  @override
  String get survivalModeSuggestion => '电量严重不足。启用生存模式可延长可被发现的时间。';

  @override
  String get gatewayTitle => '紧急互联网网关';

  @override
  String get gatewayBody => '互联网恢复后，此手机可发布排队的 SOS 和状态。';

  @override
  String get gatewayOptIn => '允许此手机提供互联网出口';

  @override
  String get gatewayAvailable => '已检测到互联网连接';

  @override
  String get gatewayUnavailable => '未检测到互联网连接';

  @override
  String get gatewayPrivacy => '仅处理 SOS 和状态。未配置可信网关前不会上传。';

  @override
  String gatewayPending(int count) {
    return '$count 个紧急项目待发送';
  }

  @override
  String get gatewayConfigure => '配置可信网关';

  @override
  String get gatewayKindMatrix => 'Matrix';

  @override
  String get gatewayKindMqtt => 'MQTT';

  @override
  String get gatewayHomeserver => 'Matrix 服务器 URL';

  @override
  String get gatewayBroker => 'MQTT 服务器';

  @override
  String get gatewayRoom => 'Matrix 房间 ID';

  @override
  String get gatewayTopic => 'MQTT 主题';

  @override
  String get gatewayUsername => '用户名';

  @override
  String get gatewayAccessToken => '访问令牌';

  @override
  String get gatewayPassword => '密码';

  @override
  String get gatewayPort => '端口';

  @override
  String get gatewayTls => '使用加密 TLS 连接';

  @override
  String get voiceRecord => '录制语音消息';

  @override
  String get voiceStop => '停止录音';

  @override
  String get voiceTooLong => '语音消息最长 20 秒。';

  @override
  String get voiceUnsupported => '接收设备需要安装 HearthBit。';

  @override
  String get voicePlay => '播放语音消息';

  @override
  String get voicePause => '暂停语音消息';
}
