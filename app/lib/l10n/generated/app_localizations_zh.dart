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
  String get statusBannerYou => '你';

  @override
  String get statusStarting => '正在启动网状网络…';

  @override
  String get statusError => '网状网络出错';

  @override
  String get statusStopped => '网状网络已停止';

  @override
  String get statusMeshPermissionsRevoked => '网状网络已暂停：蓝牙或附近设备权限已被撤销。';

  @override
  String get statusMeshBatteryRestricted => '电池限制可能会暂停后台网状网络。';

  @override
  String get statusMeshSuspended => '网状网络已暂停：消息将排队等待可用出口。';

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
  String get privacyTitle => '隐私';

  @override
  String get privacyPrivateDefaultBody =>
      '默认启用隐私模式。HearthBit 会尽量减少固定无线标识符并限制身份广播。';

  @override
  String get privacyBitchatInteropTitle => 'BitChat 兼容性';

  @override
  String get privacyBitchatInteropOffBody =>
      '已关闭。BitChat 公共聊天将被隐藏。外部设备仍会显示但无法聊天，只显示其公共 SOS 警报。';

  @override
  String get privacyBitchatInteropWarning =>
      '已开启。附近观察者可通过固定无线标识符关联此设备，网状网络仍可读取公开消息。';

  @override
  String get meshtasticInteropTitle => 'Meshtastic 远距离无线电';

  @override
  String get meshtasticInteropBody =>
      '默认关闭。启用后，HearthBit 会连接附近的一台 Meshtastic 无线电。私密内容在 LoRa 网状网络中仍保持端到端加密。';

  @override
  String get externalPresenceNoChat => '外部网络设备 · 无法聊天';

  @override
  String get externalNetworkBadge => '外部网络';

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
  String get secureChatUnavailableHint => '正在等待加密通道可用。';

  @override
  String get privateMessagePending => '待发送';

  @override
  String privateMessageSendError(String error) {
    return '无法发送消息：$error';
  }

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
  String get sosPrivacyTitle => '公开 SOS 隐私';

  @override
  String get sosPrivacyPublicWarning => '公开 SOS 会向网状网络参与者透露您的消息和加密身份。请选择位置精度。';

  @override
  String get sosLocationExact => '精确位置';

  @override
  String get sosLocationExactBody => '最适合立即救援；会公开精确坐标。';

  @override
  String get sosLocationApproximate => '大致位置（推荐）';

  @override
  String get sosLocationApproximateBody => '将坐标取整到大约一个街区范围。';

  @override
  String get sosLocationNone => '不含位置';

  @override
  String get sosLocationNoneBody => '仅发送 SOS 消息。';

  @override
  String get sosSendPublic => '发送公开 SOS';

  @override
  String get sosMedical => '我需要医疗救助';

  @override
  String get sosTrapped => '我被困住了';

  @override
  String get sosImOk => '我没事';

  @override
  String get sosDefaultMessage => '我需要帮助';

  @override
  String get sosQrTitle => '二维码 SOS';

  @override
  String get sosQrShowInstructions =>
      '请向他人展示此代码。HearthBit 可以转发 SOS，普通相机也能读取备用文字。';

  @override
  String get sosQrFallbackTitle => '无需应用即可阅读的信息';

  @override
  String get sosQrOpen => '显示 SOS 二维码';

  @override
  String get sosQrScan => '扫描并转发 SOS';

  @override
  String get acousticSosListen => '监听声音 SOS';

  @override
  String get acousticSosStopListening => '停止声音监听';

  @override
  String get sosChannelsTitle => 'SOS 已发送或已准备的渠道';

  @override
  String get sosQrRelayTitle => '发现 SOS';

  @override
  String get sosQrRelayAction => '转发 SOS';

  @override
  String get sosQrInvalid => '二维码不包含有效且已签名的 HearthBit SOS。';

  @override
  String get sosQrRelayed => 'SOS 已验证并加入网状网络';

  @override
  String get sosSentToMesh => 'SOS 已发送到网状网络。';

  @override
  String get sosQueuedWithoutRoute => 'SOS 已排队，但此手机当前没有可用出口。';

  @override
  String get emergencySmsOpen => '通过短信通知可信联系人';

  @override
  String get emergencySmsTitle => '紧急短信';

  @override
  String get emergencySmsBody => '为可信联系人准备一条短信。系统将打开短信应用，供你检查并发送。';

  @override
  String get emergencySmsRecipient => '可信联系人的电话号码';

  @override
  String get emergencySmsMessage => '紧急消息';

  @override
  String get emergencySmsDisclaimer => '短信不会自动发送，也不能替代拨打官方紧急服务电话。';

  @override
  String get emergencySmsCompose => '打开短信应用';

  @override
  String get emergencySmsUnavailable => '没有兼容的短信应用';

  @override
  String get emergencySmsInvalidRecipient => '请输入有效的电话号码';

  @override
  String emergencySmsBodyWithoutLocation(String message) {
    return 'HearthBit 紧急警报：$message。此短信不能替代官方紧急服务。';
  }

  @override
  String emergencySmsBodyWithLocation(
    String message,
    String latitude,
    String longitude,
  ) {
    return 'HearthBit 紧急警报：$message。坐标：$latitude, $longitude。此短信不能替代官方紧急服务。';
  }

  @override
  String get sosReceivedTitle => '收到的警报';

  @override
  String get sosNoneReceived => '尚未收到 SOS 警报。';

  @override
  String get sosTriageTitle => '快速救援信息';

  @override
  String get sosTriageOptional => '可选。选择主要需求或立即发送 SOS。';

  @override
  String get sosTriageNone => '无结构化信息';

  @override
  String get sosTriageMedical => '医疗';

  @override
  String get sosTriageWater => '饮水';

  @override
  String get sosTriageExtraction => '救出';

  @override
  String get sosTriageShelter => '避难所';

  @override
  String get sosTriageOther => '其他';

  @override
  String get sosTriageDetails => '添加详情';

  @override
  String get sosTriagePeople => '人数';

  @override
  String get sosTriageInjuries => '伤员';

  @override
  String get sosTriageTrapped => '受困';

  @override
  String get sosTriageUnknown => '未知';

  @override
  String get sosTriageNo => '否';

  @override
  String get sosTriageYes => '是';

  @override
  String get sosTriageSave => '保存详情';

  @override
  String sosTriageSummary(
    String people,
    String injured,
    String trapped,
    String need,
  ) {
    return '人数：$people · 伤员：$injured · 受困：$trapped · 需求：$need';
  }

  @override
  String get checkInPrivateBody => '仅向已验证的家人发送端到端加密状态。';

  @override
  String get checkInNoCircle => '发送私密签到前，请先添加已验证的家人。';

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
  String get wipeDialogInstruction => '输入 BORRAR 以确认。';

  @override
  String get wipeDialogKeyword => '输入 BORRAR';

  @override
  String get wipeDialogComplete => '身份信息和敏感数据已抹除。';

  @override
  String get wipeDialogError => '抹除未完成。将设备交给他人前请重试。';

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
  String get transportWifiDirect => 'Wi-Fi Direct';

  @override
  String get transportMultipeer => 'Multipeer';

  @override
  String get transportShare => '使用其他应用分享';

  @override
  String get transportOptical => '光学二维码';

  @override
  String get transferExport => '分享';

  @override
  String get transferImport => '打开 HearthBit 文件包';

  @override
  String get sealedTransferSend => '通过其他应用加密发送';

  @override
  String get sealedImportTitle => '已验证的加密文件';

  @override
  String sealedImportBody(String fileName, String sender) {
    return '$fileName 已由可信联系人 $sender 签名。是否保存？';
  }

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
  String beaconRequestTitle(String nickname) {
    return '$nickname 请求你发出可见信号';
  }

  @override
  String get beaconRequestBody => '接受后，闪光灯、警报声和振动最多运行5分钟。未经你的同意不会启动。';

  @override
  String get beaconMakeVisible => '让我更容易被发现';

  @override
  String get beaconStopVisible => '停止实体信标';

  @override
  String get beaconRequestRemote => '请求信标';

  @override
  String get beaconStopRemote => '停止信标';

  @override
  String get radarSignalLost => '信号丢失';

  @override
  String get radarSignalLostHint => '沿原路慢慢往回走，直到重新收到信号。';

  @override
  String get radarSearching => '正在搜索信号…';

  @override
  String get radarSearchingHint => '慢慢地绕大圈行走。雷达接收的是直接的蓝牙信号（数十米范围）。';

  @override
  String get radarNoSignalHint => '尚未读取到直接信号。请在两部手机上保持 HearthBit 打开，并缓慢走动。';

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
  String get aboutBody =>
      'HearthBit 是一个源代码可见的应急通信项目，代码公开用于隐私和安全审查。非商业使用按许可证授权；商业使用需要许可。';

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
    return '加入 HearthBit：一个无需互联网、可公开审查的应急网状网络。下载或参与贡献：$url';
  }

  @override
  String get tooltipShare => '邀请他人使用 HearthBit';

  @override
  String get shareInviteError => '无法打开分享选项';

  @override
  String get diagnosticsExportButton => '导出诊断信息';

  @override
  String get diagnosticsExportSubject => 'HearthBit 诊断信息';

  @override
  String get diagnosticsExportError => '无法导出诊断报告';

  @override
  String get diagnosticsExportRefreshError => '无法刷新诊断信息，因此未导出任何内容。';

  @override
  String get diagnosticsTitle => '诊断';

  @override
  String get diagnosticsRefreshTooltip => '刷新诊断信息';

  @override
  String get diagnosticsMeshSection => '网状网络';

  @override
  String get diagnosticsPlatform => '平台';

  @override
  String get diagnosticsStatus => '状态';

  @override
  String get diagnosticsIdentityRotation => '最近一次身份轮换';

  @override
  String get diagnosticsNearbyDevices => '附近设备';

  @override
  String get diagnosticsAdvertising => 'BLE 广播';

  @override
  String get diagnosticsMeshScan => '网状网络扫描';

  @override
  String get diagnosticsGenericScan => '通用信号扫描';

  @override
  String get diagnosticsEnergySection => '电量';

  @override
  String get diagnosticsBattery => '电池';

  @override
  String get diagnosticsPowerProfile => '电源配置';

  @override
  String get diagnosticsBleDutyCycle => 'BLE 活跃占比';

  @override
  String get diagnosticsScanStarts => '扫描启动次数';

  @override
  String get diagnosticsStoreForward => '存储转发队列';

  @override
  String get diagnosticsOperationalCountersSection => '运行计数器';

  @override
  String get diagnosticsOpenEmergencyLimitedKnown => '已限流的已知紧急帧';

  @override
  String get diagnosticsOpenEmergencyLimitedUnknown => '已限流的未知紧急帧';

  @override
  String get diagnosticsRelaySuppressed => '因抑制而取消的中继';

  @override
  String get diagnosticsRelayScheduled => '已计划的中继';

  @override
  String get diagnosticsRelayExpired => '已完成的中继计时器';

  @override
  String get diagnosticsTrustEvictions => '已逐出的信任固定项';

  @override
  String get diagnosticsTrustConflicts => '信任冲突';

  @override
  String get diagnosticsOperationalCountersLifetime => '计数周期';

  @override
  String get diagnosticsLifetimeProcess => '自本进程启动以来';

  @override
  String get diagnosticsLifetimeUnknown => '未报告周期';

  @override
  String get diagnosticsTransportsSection => '活跃传输方式';

  @override
  String get diagnosticsNoActiveTransports => '未报告活跃传输方式';

  @override
  String get diagnosticsEventsSection => '最近事件';

  @override
  String get diagnosticsNoEvents => '尚无诊断事件';

  @override
  String get diagnosticsEnabled => '活跃';

  @override
  String get diagnosticsDisabled => '未活跃';

  @override
  String get diagnosticsTransportOutcomesSection => '传输结果';

  @override
  String diagnosticsTransportOutcome(int success, int failure) {
    return '成功 $success 次 · 失败 $failure 次';
  }

  @override
  String get diagnosticsTransportAudio => '音频';

  @override
  String get diagnosticsTransportQr => '二维码';

  @override
  String get diagnosticsTransportExternal => '外部分享';

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
  String get peerRoleInfraRelay => '基础设施中继';

  @override
  String get peerRoleStorageAnchor => '消息存储锚点';

  @override
  String get peerLongRangeTrunkActive => '长距离中继干线已启用';

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
  String get radarSweepHoldTitle => '如何握持手机';

  @override
  String get radarSweepInstruction => '将手机水平放在胸前，屏幕朝上、顶部朝前。缓慢转动整个身体。';

  @override
  String radarSweepProgress(int percent) {
    return '扫描进度：$percent%';
  }

  @override
  String radarSweepResult(int heading) {
    return '信号可能所在扇区：$heading°（±30°）';
  }

  @override
  String radarSweepConfidence(int percent) {
    return '置信度：$percent%';
  }

  @override
  String get radarSweepInconclusive => '未找到可靠扇区。请更慢转动，并远离金属或电子设备。';

  @override
  String get radarSweepExpired => '方向已变化或已过期。请从当前位置重新扫描。';

  @override
  String radarMeasuredDistance(String distance) {
    return '实测：$distance';
  }

  @override
  String radarGpsDistanceMargin(String distance, String accuracy) {
    return 'GPS 约$distance ±$accuracy';
  }

  @override
  String get radarActionRadio => '无线';

  @override
  String get radarActionSonar => '声纳';

  @override
  String get radarActionBeacon => '信标';

  @override
  String get radarActionDirection => '方向';

  @override
  String get radarActionSweeping => '扫描中';

  @override
  String get radarActionWaiting => '等待中';

  @override
  String get radarRadioStart => '通过无线电测距';

  @override
  String get radarRadioStop => '停止无线电测距';

  @override
  String get radarSonarStart => '使用声学声纳测距';

  @override
  String get radarSonarStop => '停止声学声纳';

  @override
  String get radarSonarMicrophoneRequired => '声学声纳需要麦克风权限。';

  @override
  String get radarSonarTooNoisy => '无法测量啁啾信号。请降低环境噪声，勿遮挡两部手机，然后重试。';

  @override
  String get radarSonarRemoteMicrophoneRequired => '另一部手机未允许声纳使用麦克风。';

  @override
  String get radarSonarSelfChirpMissing => '此手机未检测到自身信号。请断开蓝牙耳机、勿遮挡扬声器，然后重试。';

  @override
  String get radarSweepEstimateWarning =>
      'BLE 只能估计较宽的扇区，无法提供精确方向。请移动位置并重新扫描确认。';

  @override
  String get radarCompassUnavailable => '此手机没有可用的指南针传感器。距离雷达仍可使用。';

  @override
  String get radarCompassCalibration => '请远离金属或电子设备，并用手机画“8”字以校准指南针。';

  @override
  String get radarDirectionGps => 'GPS 方位引导 · 跟随蓝色菱形';

  @override
  String get radarDirectionBle => '通过 BLE 扫描估计的扇区';

  @override
  String get radarDirectionVeryClose =>
      '你已非常接近：此时 BLE 扇区不再可靠，因此已隐藏。请转动身体并跟随振动。';

  @override
  String get radarSourcesDisagree => 'GPS 与 BLE 方向不一致；重新测量前不会显示方向。';

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
  String genericPresenceSummary(int count, int rssi) {
    return '附近有 $count 个蓝牙信号 · 最强 $rssi dBm';
  }

  @override
  String get genericPresenceExpand => '显示信号详情';

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
  String get emergencyDeliveryTitle => '已广播警报状态';

  @override
  String get deliveryPending => '等待广播';

  @override
  String get deliveryRelayed => '已广播到网状网络';

  @override
  String get deliveryAcknowledged => '已由 HearthBit 确认';

  @override
  String get deliveryExpired => '未确认且已过期';

  @override
  String get deliveryAttemptsLabel => '尝试次数';

  @override
  String get deliveryConfirmationsLabel => '确认数';

  @override
  String get deliveryLastAttemptLabel => '上次尝试';

  @override
  String get deliveryExpiresLabel => '过期时间';

  @override
  String get deliveryNoHearthBitConfirmation =>
      '尚无其他 HearthBit 确认；BitChat 节点仍可能已收到。';

  @override
  String get deliveryRetry => '重试警报';

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
  String get onboardingNicknameLabel => '你的显示名称（可选）';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingBack => '返回';

  @override
  String get onboardingAllowMesh => '允许并启动网络';

  @override
  String get onboardingAllowLocation => '允许紧急位置';

  @override
  String get onboardingAllowMicrophone => '允许麦克风用于救援';

  @override
  String get onboardingMicrophoneReady => '语音留言和声学救援工具已就绪。';

  @override
  String get onboardingMicrophoneRequired => '语音留言和声学救援工具需要此权限。';

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
    return '$count 台手机正在转发消息';
  }

  @override
  String meshHealthAnchors(int count) {
    return '$count 个消息存储点';
  }

  @override
  String meshHealthTrunks(int count) {
    return '$count 条已启用的长距离中继干线';
  }

  @override
  String meshHealthSignals(int count) {
    return '$count 个其他蓝牙信号';
  }

  @override
  String get meshHealthAnchorReady => '附近有消息存储点。';

  @override
  String get meshHealthNoAnchor => '附近没有消息存储点。';

  @override
  String get adaptivePowerTitle => '自适应省电';

  @override
  String get adaptivePowerNormal => '完整网状网络性能';

  @override
  String get adaptivePowerSaving => '省电：短时扫描';

  @override
  String get powerProfilePerformance => '性能：快速发现';

  @override
  String get powerProfileBalanced => '均衡：完整网状网络覆盖';

  @override
  String get powerProfilePowerSaver => '省电：间歇扫描';

  @override
  String get powerProfileCritical => '电量危急：最少连接和扫描';

  @override
  String get powerProfileSurvival => '生存：仅 SOS 信标';

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
  String get gatewayTrustTitle => 'TLS 证书信任方式';

  @override
  String get gatewayTrustSystem => '系统';

  @override
  String get gatewayTrustSystemBody => '使用设备信任的证书颁发机构。兼容公共服务，但不会将网关锁定到某一张证书。';

  @override
  String get gatewayTrustTofu => 'TOFU';

  @override
  String get gatewayTrustTofuBody => '信任此端点首次出现的证书，并拒绝之后的变化。请确认首次连接未被拦截。';

  @override
  String get gatewayTrustPinned => '固定';

  @override
  String get gatewayTrustPinnedBody =>
      '只接受完全匹配的 SHA-256 证书指纹。证书轮换后，更新此值前将无法发送。';

  @override
  String get gatewayFingerprint => '证书 SHA-256 指纹';

  @override
  String get gatewayFingerprintHint => '64 个十六进制字符；允许分隔符';

  @override
  String get gatewayFingerprintInvalid => '请输入有效的 64 字符 SHA-256 证书指纹。';

  @override
  String get gatewayResetTofu => '忘记首次证书';

  @override
  String get gatewayResetTofuDone => '已删除保存的 TOFU 证书。';

  @override
  String get gatewayPrivacyScopeTitle => '与网关共享的数据';

  @override
  String get gatewaySensitiveContentConsent => '共享消息内容和发送者身份';

  @override
  String get gatewaySensitiveContentConsentBody => '包括紧急情况描述、显示名称和节点标识符。默认关闭。';

  @override
  String get gatewayCoordinatesConsent => '共享精确坐标';

  @override
  String get gatewayCoordinatesConsentBody => '在存在时包括纬度和经度。此同意与消息内容相互独立。';

  @override
  String get gatewayPrivacyScopeWarning =>
      '网关会将所选数据发送到本地网状网络之外的互联网服务。仅在获得知情同意后启用相应类别。';

  @override
  String get mapOpen => '打开离线地图';

  @override
  String get mapOpenRescue => '打开救援地图';

  @override
  String get mapTitle => '离线救援地图';

  @override
  String get mapMyLocation => '以我的位置为中心';

  @override
  String get mapPassiveCacheInfo =>
      '此地图会自动保存你查看过的图块，以便离线时再次使用。下载整个区域需要获授权的提供商或自有服务器。';

  @override
  String get mapTilePolicyAction => 'OSM 政策';

  @override
  String get mapDownloadVisible => '下载可见区域';

  @override
  String mapDownloadComplete(int count) {
    return '已保存 $count 个地图图块供离线使用。';
  }

  @override
  String mapDownloadTooLarge(int maximum) {
    return '区域过大。请放大地图；安全上限为 $maximum 个图块。';
  }

  @override
  String mapDownloadError(String error) {
    return '无法下载地图区域：$error';
  }

  @override
  String mapDownloading(int completed, int total) {
    return '正在保存地图：$completed/$total';
  }

  @override
  String mapCacheError(String error) {
    return '无法打开离线地图缓存：$error';
  }

  @override
  String get mapYouAreHere => '你在这里';

  @override
  String get mapOfflineHint => '网络不可用。已保存的地图图块仍可查看。';

  @override
  String get mapTileBlockedHint =>
      '地图服务商暂时阻止了图块访问。救援标记仍可使用；离线地图请使用获授权的数据源或自建服务器。';

  @override
  String get mapShowOnMap => '在地图上显示';

  @override
  String get rescueListTitle => '救援队列 · 最近优先';

  @override
  String get rescueListEmpty => '没有包含救援数据的 SOS 警报或状态报告。';

  @override
  String get rescueExportCsv => '分享救援 CSV';

  @override
  String get rescueExportSubject => 'HearthBit 救援队列';

  @override
  String rescueExportError(String error) {
    return '无法分享救援列表：$error';
  }

  @override
  String get rescueDistanceUnknown => '距离未知';

  @override
  String rescueDistanceMeters(int meters) {
    return '距离 $meters 米';
  }

  @override
  String rescueDistanceKilometers(String kilometers) {
    return '距离 $kilometers 公里';
  }

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

  @override
  String get shareApkButton => '分享已安装的 APK';

  @override
  String get sendApkToPeer => '发送 HearthBit APK';

  @override
  String get apkSafetyTitle => '分享 Android 安装程序？';

  @override
  String apkSendToPeerWarning(String peer) {
    return '$peer 将收到 HearthBit Android 安装程序。';
  }

  @override
  String get apkInstallWarning =>
      '接收方必须在 Android 设置中允许从接收来源安装应用。HearthBit 不会自动安装任何内容。';

  @override
  String get apkSignatureWarning => '使用不同密钥签名的 APK 无法更新已安装的应用。安装前请验证来源和签名。';

  @override
  String get apkTransportWarning =>
      'APK 不通过 BLE 传输。它需要本地 Wi-Fi、Nearby 或 Wi-Fi Aware；如果均不可用，传输将报告错误。';

  @override
  String get apkConfirmShare => '继续';

  @override
  String get apkPreparing => '正在准备安全的 APK 副本…';

  @override
  String get apkSplitUnavailable =>
      '此安装使用拆分 APK。仅分享基础 APK 会产生不完整的安装程序，因此 HearthBit 不会分享它。请改为提供 GitHub 链接。';

  @override
  String get apkUnsupported => '仅 Android 支持分享已安装的 APK。';

  @override
  String apkShareError(String error) {
    return '无法准备或分享 APK：$error';
  }

  @override
  String get apkShareMessage =>
      'HearthBit Android 安装程序。Android 要求允许从此来源安装。签名不同的 APK 无法更新现有安装；请先验证来源和签名。';

  @override
  String apkOfferSent(String peer) {
    return '已向 $peer 提供 APK。如果没有合适的高速传输方式，传输将显示错误。';
  }

  @override
  String get familyTitle => '家庭群组';

  @override
  String get familySecurityBody => '成员须当面使用签名二维码验证。绝不只信任昵称或旧设备标识。';

  @override
  String get familyCreateGroup => '创建群组';

  @override
  String get familyRenameGroup => '重命名群组';

  @override
  String get familyGroupHint => '例如：我的家人';

  @override
  String get familyGroupLabel => '群组';

  @override
  String get familyConfirmTitle => '确认家庭成员';

  @override
  String familyFingerprint(String fingerprint) {
    return '安全码：$fingerprint';
  }

  @override
  String get familyConfirmBody => '保存前请在两部手机上核对该安全码。';

  @override
  String get familyAddMember => '添加成员';

  @override
  String get familyRemoveTitle => '移除家庭成员？';

  @override
  String familyRemoveBody(String nickname) {
    return '$nickname 将不再获得家庭高亮和提醒。';
  }

  @override
  String get familyRemoveAction => '移除';

  @override
  String familySaveError(String error) {
    return '无法保存家庭群组：$error';
  }

  @override
  String get familyMembersTitle => '已验证成员';

  @override
  String get familyScanAction => '扫描成员二维码';

  @override
  String get familyCreateFirst => '添加成员前请先创建群组。';

  @override
  String get familyNoMembers => '暂无已验证成员。';

  @override
  String get familyMyQr => '我的验证二维码';

  @override
  String get familyMyQrBody => '请当面展示此二维码。它只包含公开签名密钥，绝不包含私钥。';

  @override
  String get familyQrUnavailable => '请启用网状网络以生成签名验证二维码。';

  @override
  String get familyScanTitle => '扫描家庭二维码';

  @override
  String get familyQrInvalid => '此二维码无效或无法验证其签名。';

  @override
  String get familyScanHint => '扫描家庭成员手机上显示的二维码。';

  @override
  String get familyAlertBadge => '已验证家人';

  @override
  String get drillSafetyBanner => '演练 - 不会请求救援';

  @override
  String get drillModeTitle => '演练模式';

  @override
  String get drillModeBody => '仅发送明确标记的演练消息。绝不发送 SOS、共享救援位置、启动实体信标或使用互联网网关。';

  @override
  String get drillConfirmTitle => '启用演练模式？';

  @override
  String get drillConfirmBody => '救援模式和生存模式将关闭。演练消息是公开的，但不会变成真实紧急警报。';

  @override
  String get drillEnableAction => '启用演练';

  @override
  String get drillHoldToSend => '长按发送演练';

  @override
  String get drillPracticeMessage => '模拟求助请求';

  @override
  String get drillReceivedTitle => '演练消息';

  @override
  String get drillNoneReceived => '尚未收到演练消息。';

  @override
  String get drillBadge => '演练 — 并非紧急情况';

  @override
  String get drillInvalidMessage => '无法识别的演练消息已与紧急系统隔离。';

  @override
  String get drillCheckInTitle => '演练状态更新';

  @override
  String get drillCheckInBody => '这些更新仅保留在演练频道，不会出现在救援警报、地图或导出中。';

  @override
  String get drillExitForRealTitle => '发送真实 SOS？';

  @override
  String get drillExitForRealBody => '这将结束演练，并启动包含位置共享和重复 SOS 警报的真实救援请求。';

  @override
  String get drillSendRealSos => '结束演练并发送 SOS';

  @override
  String get drillDisableTitle => '结束演练模式？';

  @override
  String get drillDisableBody => '演练消息将停止，HearthBit 将恢复真实紧急情况的运行方式。';

  @override
  String get drillDisableAction => '结束演练';

  @override
  String get mapNoLocationTitle => '没有可用位置';

  @override
  String get mapNoLocationBody => '请开启定位，或等待节点共享有效的救援位置。地图绝不会使用 (0,0) 作为后备位置。';

  @override
  String get voiceMicrophoneRequired => '录制语音消息需要麦克风权限。';

  @override
  String get actionOpenSettings => '打开设置';

  @override
  String get opticalUnverifiedTitle => '来源未验证';

  @override
  String get opticalUnverifiedBody =>
      'HearthBit 无法将此传输与先前验证的身份匹配。接受文件前，请与发送者核对指纹。';

  @override
  String get opticalLegacyWarning => '此发送者使用未签名的旧版光学格式。';

  @override
  String opticalFingerprint(String fingerprint) {
    return '指纹：$fingerprint';
  }

  @override
  String get opticalAcceptUnverified => '接受未验证文件';

  @override
  String get opticalSignatureInvalid => '光学清单签名与已知发送者不匹配。文件已被拒绝。';

  @override
  String get opticalVerifiedSource => '发送者已验证';

  @override
  String get gatewayPrivacyConfirm =>
      '这会将紧急消息、发送者信息以及其中包含的救援位置发送到配置的互联网服务。仅在相关人员同意后启用。';

  @override
  String get gatewayEnableAction => '启用网关';

  @override
  String get gatewayTlsRequired => '紧急数据必须使用；不安全连接将被阻止。';

  @override
  String get locationExportConfirmTitle => '导出救援位置？';

  @override
  String get locationExportConfirmBody =>
      '导出内容可能包含精确位置、身份信息和紧急详情。仅与可信救援人员共享并妥善保护文件。';

  @override
  String get locationExportConfirmAction => '导出位置';

  @override
  String get mapExport => '导出行动数据';

  @override
  String get mapExportFormatTitle => '选择导出格式';

  @override
  String get mapExportCsv => 'CSV · 进行中的救援案件';

  @override
  String get mapExportGeoJson => 'GeoJSON · 进行中的案件和已搜索区域';

  @override
  String get mapExportSubject => 'HearthBit 救援行动';

  @override
  String mapExportError(String error) {
    return '无法导出救援行动：$error';
  }

  @override
  String get lanGatewayConnected => 'LAN 中继已连接';

  @override
  String get lanGatewaySearching => 'LAN 中继已启用 · 正在本地搜索';

  @override
  String get lanGatewayDisabled => 'LAN 中继已禁用';

  @override
  String get lanGatewayConfigure => '配置 LAN 中继';

  @override
  String get lanGatewayDisable => '禁用 LAN 中继';

  @override
  String get lanGatewayPrivacy =>
      '仅在主动选择后启用。共享密钥必须与可信的 HearthBit Raspberry Pi 中继一致。网状帧会在本地网络上进行认证和加密。';

  @override
  String get lanGatewayPsk => '32 字节配对密钥（base64）';

  @override
  String get lanGatewayGeneratePsk => '生成密钥';

  @override
  String get lanGatewayInvalidPsk => '请输入有效的 32 字节 base64 密钥。';

  @override
  String get emergencyContactsOpen => '紧急电话号码与官方链接';

  @override
  String get emergencyContactsTitle => '紧急联系目录';

  @override
  String get emergencyContactsSafetyNotice =>
      '紧急电话可能无需移动数据，但仍需蜂窝语音信号。官方网站需要互联网。';

  @override
  String get emergencyContactsCountry => '国家或地区';

  @override
  String emergencyContactsAutomatic(String country) {
    return '自动（$country）';
  }

  @override
  String get emergencyContactsNumbers => '紧急电话号码';

  @override
  String get emergencyContactsOrganizations => '官方机构';

  @override
  String get emergencyContactsCall => '拨打';

  @override
  String get emergencyContactsWebsite => '网站';

  @override
  String get emergencyContactsSources => '来源与审核';

  @override
  String emergencyContactsReviewed(String date) {
    return '审核日期：$date';
  }

  @override
  String get emergencyContactsFallback => '此翻译不可用，现显示已验证的英文目录。';

  @override
  String get emergencyContactsLoadError => '无法加载离线紧急联系目录。';

  @override
  String get emergencyContactsOpenError => '此手机无法打开该号码或链接。';

  @override
  String get emergencyContactsRetry => '重试';

  @override
  String get rescueRosterTitle => '救援队名册';

  @override
  String get rescueRosterSecurityBody =>
      '名册由队长签名。只有节点 ID 和 Ed25519 签名公钥都匹配时，成员才会显示为已验证救援人员。';

  @override
  String get rescueRosterEmpty => '此手机上没有启用的救援队名册。';

  @override
  String get rescueRosterCreate => '创建名册';

  @override
  String get rescueRosterTeamName => '队伍名称';

  @override
  String get rescueRosterCallsign => '队长呼号';

  @override
  String rescueRosterUtf8TooLarge(int maximum) {
    return '请输入不超过 $maximum 个 UTF-8 字节。';
  }

  @override
  String get rescueRosterAddMember => '添加附近成员';

  @override
  String get rescueRosterNoEligiblePeers => '附近没有可添加且带签名公钥的 HearthBit 身份。';

  @override
  String get rescueRosterNearbyIdentity => '附近身份';

  @override
  String get rescueRosterMemberCallsign => '成员呼号';

  @override
  String get rescueRosterMemberRole => '救援角色';

  @override
  String get rescueRosterRemoveMemberTitle => '从名册中移除成员？';

  @override
  String rescueRosterRemoveMemberBody(String callsign) {
    return '$callsign 将不再是此名册中的已验证救援人员。';
  }

  @override
  String rescueRosterMemberCount(int count) {
    return '$count 名已验证成员';
  }

  @override
  String get rescueRosterImportTitle => '导入签名名册';

  @override
  String get rescueRosterImportText => '粘贴二维码文本';

  @override
  String get rescueRosterPasteHint => 'HBRT1:…';

  @override
  String get rescueRosterImport => '导入';

  @override
  String get rescueRosterImportFile => '打开名册文件';

  @override
  String get rescueRosterScanQr => '扫描名册二维码';

  @override
  String get rescueRosterScanHint => '将相机对准已签名的 HBRT1 救援名册二维码。';

  @override
  String get rescueRosterImported => '签名名册已验证并启用。';

  @override
  String get rescueRosterExported => '救援名册文件已保存。';

  @override
  String get rescueRosterExportQr => '显示二维码和文本';

  @override
  String get rescueRosterQrTooLarge => '此名册过大，无法放入一个二维码。请导出文件或复制签名文本。';

  @override
  String get rescueRosterExportFile => '保存名册文件';

  @override
  String get rescueRosterRemoveTitle => '移除当前救援名册？';

  @override
  String get rescueRosterRemoveBody => '成员将不再显示为已验证救援人员，其受保护的原生固定密钥也会被移除。';

  @override
  String rescueRosterError(String error) {
    return '无法处理救援名册：$error';
  }

  @override
  String get rescueRosterRoleLeader => '队长';

  @override
  String get rescueRosterRoleResponder => '救援人员';

  @override
  String get rescueRosterRoleMedic => '医疗';

  @override
  String get rescueRosterRoleSearch => '搜救';

  @override
  String get rescueRosterRoleLogistics => '后勤';

  @override
  String get rescueRosterRoleCommunications => '通信';

  @override
  String get rescueRosterRoleAuthority => '主管部门';

  @override
  String get authorityTitle => '主管部门公告';

  @override
  String get authorityTrustBody =>
      '只有当前已签名名册中被分配“主管部门”角色的成员才能发布这些已认证的队伍公告。队长不会自动获得该权限。';

  @override
  String get authorityCreate => '创建公告';

  @override
  String get authorityPriority => '优先级';

  @override
  String get authorityPriorityInfo => '信息';

  @override
  String get authorityPriorityWarning => '警告';

  @override
  String get authorityPriorityEvacuate => '撤离';

  @override
  String get authorityBody => '官方指示';

  @override
  String authorityBodyBytes(int current, int maximum) {
    return '$current/$maximum 个 UTF-8 字节';
  }

  @override
  String authorityBodyTooLarge(int maximum) {
    return '指示不得超过 $maximum 个 UTF-8 字节。';
  }

  @override
  String get authorityDuration => '有效时长';

  @override
  String authorityDurationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String authorityDurationHours(int hours) {
    return '$hours 小时';
  }

  @override
  String get authoritySend => '发布公告';

  @override
  String get authoritySent => '已发送签名的主管部门公告。';

  @override
  String authoritySendError(String error) {
    return '无法发送主管部门公告：$error';
  }

  @override
  String get authorityHistory => '公告历史';

  @override
  String get authorityHistoryEmpty => '尚未收到已认证的主管部门公告。';

  @override
  String get authorityActive => '有效';

  @override
  String get authorityExpired => '已过期';

  @override
  String authorityExpires(String date) {
    return '到期时间：$date';
  }

  @override
  String get authorityBannerSemantics => '当前有效的已认证主管部门公告';

  @override
  String get verifiedRescuerBadge => '已验证救援人员';

  @override
  String get rescueRosterFileType => 'HearthBit 救援名册';

  @override
  String get rescueOperationsTitle => '救援行动';

  @override
  String get rescueOperationsEmpty => '尚未收到 SOS 案件。';

  @override
  String rescueOperationsError(String error) {
    return '无法更新救援行动：$error';
  }

  @override
  String get rescueOperationsAssignMe => '分配给我';

  @override
  String get rescueOperationsEnRoute => '前往途中';

  @override
  String get rescueOperationsAttended => '已处置';

  @override
  String get rescueOperationsClose => '关闭';

  @override
  String get rescueOperationsNoActions => '没有获授权的操作';

  @override
  String rescueOperationsAssignee(String callsign) {
    return '已分配给 $callsign';
  }

  @override
  String rescueOperationsReceivedAt(String date) {
    return '接收于 $date';
  }

  @override
  String rescueOperationsTriage(String need, String people) {
    return '优先事项：$need · 人数：$people';
  }

  @override
  String get rescueCaseStateNew => '新案件';

  @override
  String get rescueCaseStateAssigned => '已分配';

  @override
  String get rescueCaseStateEnRoute => '前往途中';

  @override
  String get rescueCaseStateAttended => '已处置';

  @override
  String get rescueCaseStateClosed => '已关闭';

  @override
  String get rescueTriageMedical => '医疗';

  @override
  String get rescueTriageWater => '饮水';

  @override
  String get rescueTriageExtraction => '救出';

  @override
  String get rescueTriageShelter => '庇护';

  @override
  String get rescueTriageOther => '其他';

  @override
  String get mapFilterActive => '进行中';

  @override
  String get mapFilterUnassigned => '未分配';

  @override
  String get mapFilterAssigned => '已分配';

  @override
  String get mapFilterClosed => '已关闭';

  @override
  String mapOperationalCases(int count) {
    return '$count 个行动案件';
  }

  @override
  String get mapCasesEmpty => '没有符合此筛选条件的案件。';

  @override
  String mapClusterTooltip(int count, String priority) {
    return '$count 个 SOS 案件 · 最高优先级：$priority';
  }

  @override
  String get mapPriorityLow => '低优先级';

  @override
  String get mapPriorityMedium => '中优先级';

  @override
  String get mapPriorityHigh => '高优先级';

  @override
  String get mapPriorityCritical => '紧急优先级';

  @override
  String get mapCaseNoCoordinates => '此案件没有坐标';

  @override
  String get mapZoneConsent => '仅在此控件保持可见且启用时记录已搜索路线。';

  @override
  String get mapZoneStart => '记录路线';

  @override
  String mapZoneRecording(int count, int maximum) {
    return '正在记录已搜索区域 · $count/$maximum 个点';
  }

  @override
  String get mapZoneVisibleOnly => '取消、发布或离开此地图时，位置记录会停止。';

  @override
  String get mapZoneFinish => '完成并分享路线';

  @override
  String get mapZonePublished => '已搜索路线已与验证团队共享。';

  @override
  String get mapZoneLocationRequired => '记录路线需要位置权限并开启位置服务。';

  @override
  String get mapZoneRosterChanged => '由于当前名册或您的成员资格发生变化，记录已取消。';

  @override
  String mapZoneError(String error) {
    return '无法记录或分享已搜索路线：$error';
  }
}
