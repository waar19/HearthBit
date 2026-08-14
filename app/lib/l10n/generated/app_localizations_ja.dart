// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'HearthBit';

  @override
  String storageOpenError(String error) {
    return 'ローカルストレージを開けませんでした：\n$error';
  }

  @override
  String statusActiveLabel(String nickname, int count) {
    return '$nickname · 近くに $count 台';
  }

  @override
  String statusDegradedLabel(String nickname) {
    return '$nickname · 受信のみ（BLE アドバタイズなし）';
  }

  @override
  String get statusBannerYou => 'あなた';

  @override
  String get statusStarting => 'メッシュを起動中…';

  @override
  String get statusError => 'メッシュのエラー';

  @override
  String get statusStopped => 'メッシュ停止中';

  @override
  String get actionStop => '停止';

  @override
  String get actionRestart => '再起動';

  @override
  String get actionActivate => 'オンにする';

  @override
  String get actionRetry => '再試行';

  @override
  String get tooltipChangeName => '名前を変更';

  @override
  String get tooltipPanicWipe => '緊急消去';

  @override
  String get tabChannel => 'チャンネル';

  @override
  String get tabNearby => '近くの端末';

  @override
  String get tabFiles => 'ファイル';

  @override
  String get tabSos => 'SOS';

  @override
  String get emptyChatTitle => 'まだメッセージはありません';

  @override
  String get emptyChatBody =>
      'メッシュをオンにしてください。メッセージはインターネットなしで近くのスマホ同士を伝わっていきます。';

  @override
  String get composerPublicHint => '近くの全員へのメッセージ';

  @override
  String get composerPrivateHint => '暗号化メッセージ';

  @override
  String get privateChatIntro => '最初のメッセージで Noise XX ハンドシェイクが始まります。';

  @override
  String get secureChatUnavailableHint => '暗号化チャネルが利用可能になるのを待っています。';

  @override
  String get privateMessagePending => '送信待ち';

  @override
  String privateMessageSendError(String error) {
    return 'メッセージを送信できませんでした：$error';
  }

  @override
  String get emptyPeersTitle => '近くに端末がありません';

  @override
  String get emptyPeersBody =>
      'Bluetooth をオンにしたまま、HearthBit か BitChat の入った別のスマホを近づけてください。';

  @override
  String get peerSecure => '暗号化チャネル準備完了';

  @override
  String get peerTapToEncrypt => 'タップして暗号化';

  @override
  String get tooltipRadar => '近接レーダー';

  @override
  String get tooltipSendFile => 'ファイルを送信';

  @override
  String get peerDoesNotSupportTransfers =>
      '相手は BitChat を使用しています。ファイル送信には HearthBit が必要です。代わりに QR 転送を使用してください。';

  @override
  String get sosCardTitle => '優先アラートを送信';

  @override
  String get sosCardBody => '可能であれば GPS 位置情報が添付されます。アラートは公開され、メッシュ全体に中継されます。';

  @override
  String get sosMedical => '医療支援が必要です';

  @override
  String get sosTrapped => '閉じ込められています';

  @override
  String get sosImOk => '無事です';

  @override
  String get sosDefaultMessage => '助けが必要です';

  @override
  String get sosReceivedTitle => '受信したアラート';

  @override
  String get sosNoneReceived => 'SOS アラートは受信していません。';

  @override
  String get actionTrack => '追跡';

  @override
  String get rescueModeTitle => 'レスキューモード';

  @override
  String rescueModeActive(int minutes) {
    return '$minutes 分ごとに位置情報付きの SOS を再送信しています。';
  }

  @override
  String rescueModeLastPing(String time) {
    return '最終送信：$time。';
  }

  @override
  String rescueModeInactive(int minutes) {
    return '画面がオフでも、$minutes 分ごとに最新の GPS 付きで SOS を再送信します。';
  }

  @override
  String get rescueModeNoBackgroundLocation =>
      '「常に許可」の位置情報がないと、GPS はアプリを開いている間しか更新されません。';

  @override
  String get actionAllow => '許可';

  @override
  String get powerCardTitle => 'バッテリーと位置情報';

  @override
  String get powerCardSubtitle => 'メッシュを動かし続け、救助隊があなたを見つけるための設定です。';

  @override
  String get powerBatteryOptimization => 'HearthBit のバッテリー最適化は無効です';

  @override
  String get actionDisable => '無効にする';

  @override
  String get powerLocationAndroid => '位置情報が「常に許可」になっています';

  @override
  String get powerLocationIos => '位置情報が「常に」許可されています';

  @override
  String get powerSaverAndroid => 'システムの省電力モードが有効で、メッシュが停止される可能性があります';

  @override
  String get powerSaverIos => '低電力モードが有効で、バックグラウンドの Bluetooth が制限されます';

  @override
  String get powerTipsTitle => 'バッテリー節約のヒント';

  @override
  String get actionAdjust => '調整';

  @override
  String get powerTipBrightness => '画面の明るさを最小にし、ロックまでの時間を短くしてください。';

  @override
  String get powerTipMobileData =>
      'インターネットがない場合はモバイルデータと 5G をオフに：メッシュは使用せず、電波探索はバッテリーを大きく消耗します。';

  @override
  String get powerTipCloseApps => '不要なアプリは閉じ、Bluetooth と位置情報はオンのままにしてください。';

  @override
  String get powerTipAndroidRecents =>
      '最近のアプリから HearthBit をスワイプで消さないでください：システムがメッシュを終了させます。';

  @override
  String get powerTipAndroidVendor =>
      '一部メーカー（Xiaomi、Huawei、Samsung）は独自の省電力機能があります：そちらでも HearthBit を除外してください。';

  @override
  String get powerTipAndroidSync => '緊急時の間はアカウントの自動同期をオフにしてください。';

  @override
  String get powerTipIosForceClose =>
      'HearthBit を強制終了しないでください：iOS は自動で再起動しません。';

  @override
  String get powerTipIosBackgroundRefresh => '設定で他のアプリのバックグラウンド更新をオフにしてください。';

  @override
  String get powerTipIosLowPower =>
      'HearthBit を画面に表示している時以外は低電力モードを避けてください：バックグラウンドの Bluetooth が制限されます。';

  @override
  String get powerTipShareBattery =>
      'モバイルバッテリーを近所で共有しましょう：1 台のスマホが動いていれば街区全体のリンクが保たれます。';

  @override
  String get nicknameDialogTitle => '表示名';

  @override
  String get nicknameDialogHint => '例：12号棟 または アナ';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get actionSave => '保存';

  @override
  String get wipeDialogTitle => 'すべての ID を消去しますか？';

  @override
  String get wipeDialogBody => '鍵、履歴、送信待ちメッセージが削除されます。この操作は元に戻せません。';

  @override
  String get wipeDialogInstruction => '確認するには BORRAR と入力してください。';

  @override
  String get wipeDialogKeyword => 'BORRAR と入力';

  @override
  String get wipeDialogComplete => 'ID と機密データを消去しました。';

  @override
  String get wipeDialogError => '消去を完了できませんでした。端末を他人に渡す前にもう一度お試しください。';

  @override
  String get actionWipe => 'すべて消去';

  @override
  String get photoProfileTitle => '緊急プロファイル';

  @override
  String photoProfileBody(String size) {
    return 'この写真は $size MiB あります。圧縮すると送信が速くなり、メッシュのバッテリーを節約できます。';
  }

  @override
  String get actionSendOriginal => '元のまま送信';

  @override
  String get actionCompress => '圧縮する';

  @override
  String offerFileError(String error) {
    return 'ファイルを送信できませんでした：$error';
  }

  @override
  String get terrPeerDoesNotSupportTransfers =>
      '受信側は HearthBit のファイル転送に対応していません。代わりに QR 転送を使用してください。';

  @override
  String get terrOfferExpiredNoHbt =>
      '受信側が HearthBit のファイル転送に対応していないため、送信依頼の期限が切れました。';

  @override
  String get sendByQr => 'QR で送信';

  @override
  String get receiveByQr => 'QR で受信';

  @override
  String get emptyTransfersTitle => '転送はありません';

  @override
  String get emptyTransfersBody =>
      '近くの端末の横にあるクリップをタップするとファイルを送れます。送信の申し出はメッシュ経由で暗号化されて届き、内容は利用可能な最速の経路を使います。QR モードは無線が一切なくても機能します。';

  @override
  String transferFrom(String nickname) {
    return '$nickname から';
  }

  @override
  String transferTo(String nickname) {
    return '$nickname へ';
  }

  @override
  String transferProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String transferSavedAt(String path) {
    return '$path に保存しました';
  }

  @override
  String get stateOffered => '申し出';

  @override
  String get stateConnecting => '接続中';

  @override
  String get stateTransferring => '転送中';

  @override
  String get stateCompleted => '完了';

  @override
  String get stateRejected => '拒否';

  @override
  String get stateCancelled => 'キャンセル';

  @override
  String get stateFailed => '失敗';

  @override
  String get transportBle => 'Bluetooth';

  @override
  String get transportLan => 'ローカル Wi-Fi';

  @override
  String get transportNearby => 'Nearby';

  @override
  String get transportWifiAware => 'Wi-Fi Aware';

  @override
  String get transportOptical => '光学 QR';

  @override
  String get actionReject => '拒否';

  @override
  String get actionAccept => '承認';

  @override
  String get actionDelete => '削除';

  @override
  String get opticalFileEmpty => 'ファイルが空です';

  @override
  String opticalSendStats(String fileName, int chunks, int symbol) {
    return '$fileName · $chunks チャンク · シンボル $symbol';
  }

  @override
  String get opticalConfirmed => '受信側が BLE で受信を確認しました';

  @override
  String get opticalSpeedLabel => '速度';

  @override
  String opticalFps(int fps) {
    return '$fps QR/秒';
  }

  @override
  String get densityCompact => 'コンパクト';

  @override
  String get densityMedium => '中';

  @override
  String get densityHigh => '高';

  @override
  String get opticalSendHint =>
      '受信側のカメラが多くのフレームを取りこぼす場合は、速度か密度を下げてください。レートレス符号なので、シンボルの繰り返しで転送が壊れることはありません。';

  @override
  String get opticalShaFailed => 'SHA-256 検証に失敗しました。送信をやり直してください';

  @override
  String opticalSavedTitle(String fileName) {
    return '$fileName を検証して保存しました';
  }

  @override
  String get genericFile => 'ファイル';

  @override
  String get actionDone => '完了';

  @override
  String get opticalScanHint => '送信側の QR にカメラを向けてください。ヘッダーは数フレームごとに繰り返されます。';

  @override
  String opticalReceiveStats(
    String fileName,
    int decoded,
    int total,
    int symbols,
  ) {
    return '$fileName · $decoded / $total チャンク · $symbols シンボル';
  }

  @override
  String radarTitle(String nickname) {
    return 'レーダー · $nickname';
  }

  @override
  String beaconRequestTitle(String nickname) {
    return '$nickname が目印の作動を求めています';
  }

  @override
  String get beaconRequestBody =>
      '同意すると、ライト・警報音・振動を最長5分間使用します。同意なしに作動することはありません。';

  @override
  String get beaconMakeVisible => '自分を見つけやすくする';

  @override
  String get beaconStopVisible => '物理ビーコンを停止';

  @override
  String get beaconRequestRemote => 'ビーコンを依頼';

  @override
  String get beaconStopRemote => 'ビーコンを停止';

  @override
  String get radarSignalLost => '信号ロスト';

  @override
  String get radarSignalLostHint => '信号が戻るまで、来た道をゆっくり引き返してください。';

  @override
  String get radarSearching => '信号を探しています…';

  @override
  String get radarSearchingHint =>
      '大きな円を描くようにゆっくり歩いてください。レーダーは直接の Bluetooth 信号（数十メートル）を検出します。';

  @override
  String get proximityVeryClose => 'すぐ近く';

  @override
  String get proximityClose => '近い';

  @override
  String get proximityInRange => '範囲内';

  @override
  String get proximityFar => '遠い';

  @override
  String get trendApproaching => '近づいています';

  @override
  String get trendReceding => '信号が弱くなっています';

  @override
  String get trendSteady => '信号は安定しています';

  @override
  String get trendUnknown => '信号を測定中…';

  @override
  String get distanceVeryNear => '2 m 以内';

  @override
  String distanceApprox(int meters) {
    return '約 $meters m';
  }

  @override
  String get distanceFar => '15 m 以上';

  @override
  String radarDbm(int dbm) {
    return '信号 $dbm dBm';
  }

  @override
  String radarGpsDistance(String distance) {
    return '最後に報告された GPS：直線距離 $distance';
  }

  @override
  String get errorPermissions => 'メッシュの作成には Bluetooth と通知の権限が必要です。';

  @override
  String get errorLocationOff => 'レスキューモードにはシステムの位置情報をオンにしてください';

  @override
  String get errorUnknown => '不明なエラー';

  @override
  String get tooltipSupport => 'HearthBit を支援';

  @override
  String get aboutTitle => 'HearthBit について';

  @override
  String get aboutBody =>
      'HearthBit は、プライバシーと安全性を監査できる source-available の緊急通信プロジェクトです。非商用利用はライセンスされ、商用利用には許可が必要です。';

  @override
  String aboutVersion(String version) {
    return 'バージョン $version';
  }

  @override
  String get aboutSourceCode => 'ソースコード';

  @override
  String get supportButton => 'コーヒーで支援';

  @override
  String get shareInviteButton => 'HearthBit を共有';

  @override
  String shareInviteMessage(String url) {
    return 'インターネットなしで動作し、公開監査できる緊急メッシュ HearthBit に参加してください。ダウンロードまたは貢献はこちら: $url';
  }

  @override
  String get tooltipShare => 'HearthBit に招待';

  @override
  String get shareInviteError => '共有オプションを開けませんでした';

  @override
  String get diagnosticsExportButton => '診断情報をエクスポート';

  @override
  String get diagnosticsExportSubject => 'HearthBit 診断情報';

  @override
  String get diagnosticsExportError => '診断レポートをエクスポートできませんでした';

  @override
  String get openLinkError => 'リンクを開けませんでした';

  @override
  String get actionClose => '閉じる';

  @override
  String get terrInterrupted => 'アプリ終了時に中断されました';

  @override
  String get terrFileSize => 'ファイルサイズは 1 バイト以上 512 MiB 以下にしてください';

  @override
  String get terrOfferExpired => '申し出は応答がないまま期限切れになりました';

  @override
  String get terrNoTransport => '送信側と互換性のある転送経路がありません';

  @override
  String get terrInvalidSignature => '署名が無効な申し出を破棄しました';

  @override
  String get terrUnsupportedTransport => 'このバージョンでは対応していない転送経路です';

  @override
  String get terrLanIncomplete => 'LAN 接続が完了せずに終了しました';

  @override
  String terrLanFailed(String error) {
    return 'LAN の失敗：$error';
  }

  @override
  String terrBleChunk(String error) {
    return '無効な BLE チャンク：$error';
  }

  @override
  String get terrTransport => '転送エラー';

  @override
  String terrNearbyStart(String error) {
    return 'Nearby を開始できませんでした：$error';
  }

  @override
  String terrWifiAwareStart(String error) {
    return 'Wi-Fi Aware を開始できませんでした：$error';
  }

  @override
  String terrBleInterrupted(String error) {
    return 'BLE 送信が中断されました：$error';
  }

  @override
  String get terrReceiverSilent => '受信側がチャンクの確認応答を停止しました';

  @override
  String terrNearbyUnavailable(String error) {
    return 'Nearby は利用できません：$error';
  }

  @override
  String terrWifiAwareUnavailable(String error) {
    return 'Wi-Fi Aware は利用できません：$error';
  }

  @override
  String get terrContainerIncomplete => 'コンテナが不完全な状態で届きました';

  @override
  String terrContainerDecrypt(String error) {
    return 'コンテナを復号できませんでした：$error';
  }

  @override
  String get terrShaMismatch => 'SHA-256 検証に失敗しました。ファイルを破棄しました';

  @override
  String terrNoMeshSession(String error) {
    return '相手とのメッシュ接続がありません：$error';
  }

  @override
  String get terrTransportTimeout => '転送経路が応答しませんでした';

  @override
  String get recentChatsTitle => '最近の会話';

  @override
  String get nearbyPeopleTitle => '近くの人';

  @override
  String get peerRoleInfraRelay => 'インフラ中継';

  @override
  String get peerRoleStorageAnchor => 'メッセージ保存アンカー';

  @override
  String get peerLongRangeTrunkActive => '長距離トランク稼働中';

  @override
  String get peerOnline => 'オンライン';

  @override
  String get peerOffline => 'オフライン';

  @override
  String get offlineChatHint => '相手はオフラインです。履歴を確認し、再接続後にメッセージを送信できます。';

  @override
  String get radarConsentTitle => 'レーダーのプライバシー';

  @override
  String get radarConsentOff => 'レーダーによる位置確認は初期状態で無効です';

  @override
  String radarConsentActive(int minutes) {
    return '他の人はあと $minutes 分レーダーを使用できます';
  }

  @override
  String get radarConsentAllow => 'レーダーを15分間許可';

  @override
  String get radarConsentRevoke => '今すぐ取り消す';

  @override
  String get radarPrivacyWarning =>
      'この設定で制限できるのは HearthBit のみです。他のソフトウェアが端末のBluetooth信号を測定する可能性は残ります。';

  @override
  String get rescueRadarWarning =>
      '救助モードは最新のSOS位置を共有し、SOSが有効な間は近くのHearthBit救助者による信号測定を許可します。';

  @override
  String get radarConsentRequired => '相手の同意が必要です';

  @override
  String get radarConsentSos => '最近のSOSにより利用できます';

  @override
  String get radarConsentTemporary => '相手が一時的に許可しています';

  @override
  String radarConsentExpires(String time) {
    return '許可は $time に期限切れになります';
  }

  @override
  String get radarNotDirection => '点は方向ではなく近さを示します。ゆっくり移動し、信号が強くなるか比較してください。';

  @override
  String get radarPermissionExpired => 'レーダーの許可が期限切れ、または取り消されました。';

  @override
  String get radarTentativeSignal => '暫定的な信号です。この iPhone が選択した相手か確認しています。';

  @override
  String get radarSweepStart => '方向を探す';

  @override
  String get radarSweepRestart => 'スイープをやり直す';

  @override
  String get radarSweepHoldTitle => 'スマートフォンの持ち方';

  @override
  String get radarSweepInstruction =>
      '画面を上にして胸の前で水平に持ち、上端を正面に向けます。体全体をゆっくり回してください。';

  @override
  String radarSweepProgress(int percent) {
    return 'スイープ進捗：$percent%';
  }

  @override
  String radarSweepResult(int heading) {
    return '信号がある可能性の高い範囲：$heading°（±30°）';
  }

  @override
  String radarSweepConfidence(int percent) {
    return '信頼度：$percent%';
  }

  @override
  String get radarSweepInconclusive =>
      '信頼できる範囲を特定できませんでした。よりゆっくり回り、金属や電子機器から離れてください。';

  @override
  String get radarSweepExpired => '方向が変化したか期限切れです。現在地からもう一度スイープしてください。';

  @override
  String radarMeasuredDistance(String distance) {
    return '実測：$distance';
  }

  @override
  String get radarActionRadio => '無線';

  @override
  String get radarActionSonar => 'ソナー';

  @override
  String get radarActionBeacon => 'ビーコン';

  @override
  String get radarActionDirection => '方向';

  @override
  String get radarActionSweeping => '探索中';

  @override
  String get radarActionWaiting => '待機中';

  @override
  String get radarRadioStart => '無線で距離を測定';

  @override
  String get radarRadioStop => '無線測距を停止';

  @override
  String get radarSonarStart => '音響ソナーで測定';

  @override
  String get radarSonarStop => '音響ソナーを停止';

  @override
  String get radarSonarMicrophoneRequired => '音響ソナーにはマイクの許可が必要です。';

  @override
  String get radarSonarTooNoisy =>
      'チャープ音を測定できませんでした。周囲の騒音を減らし、両方の端末を覆わずに再試行してください。';

  @override
  String get radarSweepEstimateWarning =>
      'BLE で推定できるのは広い範囲だけで、正確な方向ではありません。移動して再度スイープし、確認してください。';

  @override
  String get radarCompassUnavailable =>
      'このスマートフォンではコンパスを利用できません。近接レーダーは引き続き使用できます。';

  @override
  String get radarCompassCalibration =>
      '金属や電子機器から離れ、スマートフォンを8の字に動かしてコンパスを調整してください。';

  @override
  String get radarDirectionGps => 'GPSによる方角 · 青いひし形に従ってください';

  @override
  String get radarDirectionBle => 'BLEスイープで推定した範囲';

  @override
  String get radarDirectionVeryClose =>
      'すぐ近くです。BLEの方向は信頼できないため非表示にしています。向きを変えながら振動を頼りに進んでください。';

  @override
  String get radarSourcesDisagree => 'GPSとBLEが一致しないため、再測定するまで方向を表示しません。';

  @override
  String get dateToday => '今日';

  @override
  String get dateYesterday => '昨日';

  @override
  String get genericPresenceSectionTitle => 'その他の Bluetooth 信号';

  @override
  String get genericPresenceNoChat => '存在を検出、チャット不可';

  @override
  String genericPresenceSignal(int rssi) {
    return '一般 Bluetooth 信号 · $rssi dBm';
  }

  @override
  String genericPresenceSummary(int count, int rssi) {
    return '近くの Bluetooth 信号 $count 件 · 最強 $rssi dBm';
  }

  @override
  String get genericPresenceExpand => '信号の詳細を表示';

  @override
  String get nodeModeTooltip => 'ノードモード';

  @override
  String get nodeModeTitle => 'このスマートフォンをどのように参加させますか？';

  @override
  String get nodeModeRelayTitle => 'メッシュ中継';

  @override
  String get nodeModeRelayBody => '通常どおりチャットし、近くの人のメッセージを中継します。';

  @override
  String get nodeModeBeaconTitle => 'プレゼンスのみ';

  @override
  String get nodeModeBeaconBody =>
      'チャットや中継をせず、存在だけを通知して電力を節約します。Android ではデータ接続も無効になります。';

  @override
  String get tabEmergency => '緊急';

  @override
  String get emergencyHeadline => '緊急モード';

  @override
  String get emergencyInstructions =>
      'SOSを2秒間長押ししてください。メッシュを起動し、位置情報を共有して警報を繰り返します。';

  @override
  String get emergencyHoldSos => 'SOSを長押し';

  @override
  String get emergencySosActive => 'SOS発信中';

  @override
  String get emergencyStopRescue => '救助モードを停止';

  @override
  String get emergencyDeliveryTitle => '送信した警報の状態';

  @override
  String get deliveryPending => '送信待ち';

  @override
  String get deliveryRelayed => 'メッシュへ送信済み';

  @override
  String get deliveryAcknowledged => 'HearthBit が確認';

  @override
  String get deliveryExpired => '確認なしで期限切れ';

  @override
  String get deliveryAttemptsLabel => '試行回数';

  @override
  String get deliveryConfirmationsLabel => '確認数';

  @override
  String get deliveryLastAttemptLabel => '最終試行';

  @override
  String get deliveryExpiresLabel => '期限';

  @override
  String get deliveryNoHearthBitConfirmation =>
      '別の HearthBit からの確認はありませんが、BitChat ノードが受信した可能性はあります。';

  @override
  String get deliveryRetry => '警報を再送';

  @override
  String get errorEmergencyMeshUnavailable =>
      'Bluetoothメッシュを起動できません。権限を確認してください。';

  @override
  String get checkInTitle => '安否を知らせる';

  @override
  String get checkInBody => '時刻と利用可能な位置情報を添えて、安否をメッシュで中継します。';

  @override
  String get checkInOk => '無事です';

  @override
  String get checkInNeedsHelp => '助けが必要です';

  @override
  String get checkInInjured => 'けがをしています';

  @override
  String get checkInRecentTitle => '最新の安否情報';

  @override
  String get checkInNone => 'まだ安否情報はありません。';

  @override
  String get onboardingWelcomeTitle => '通信網が止まってもつながる';

  @override
  String get onboardingWelcomeBody =>
      'HearthBitは携帯回線やインターネットなしで、Bluetoothにより緊急メッセージを中継します。';

  @override
  String get onboardingMeshTitle => '緊急メッシュを維持';

  @override
  String get onboardingMeshBody => 'Bluetooth、付近のデバイス、通知の権限が探索と中継に必要です。';

  @override
  String get onboardingReadyTitle => '災害前に準備';

  @override
  String get onboardingReadyBody => 'バックグラウンド位置情報を許可し、バッテリー制限から除外してください。';

  @override
  String get onboardingNicknameLabel => '表示名（任意）';

  @override
  String get onboardingNext => '次へ';

  @override
  String get onboardingBack => '戻る';

  @override
  String get onboardingAllowMesh => '許可してメッシュを起動';

  @override
  String get onboardingAllowLocation => '緊急位置情報を許可';

  @override
  String get onboardingFinish => '設定を完了';

  @override
  String get appearanceTitle => '表示とアクセシビリティ';

  @override
  String get appearanceAmoled => 'AMOLED黒テーマ';

  @override
  String get appearanceAmoledBody => 'OLED画面で完全な黒を使い、電力を節約します。';

  @override
  String get appearanceHighContrast => '高コントラストと大きな操作';

  @override
  String get appearanceHighContrastBody => '読みやすさを高め、重要な操作を大きくします。';

  @override
  String get tooltipAppearance => '表示とアクセシビリティ';

  @override
  String get meshHealthTitle => 'メッシュの状態';

  @override
  String meshHealthDirect(int count) {
    return '直接接続 $count 台';
  }

  @override
  String meshHealthRelays(int count) {
    return 'メッセージを中継する端末 $count 台';
  }

  @override
  String meshHealthAnchors(int count) {
    return 'メッセージ保存地点 $count 台';
  }

  @override
  String meshHealthTrunks(int count) {
    return '稼働中の長距離トランク $count 本';
  }

  @override
  String meshHealthSignals(int count) {
    return 'その他のBluetooth信号 $count 件';
  }

  @override
  String get meshHealthAnchorReady => 'メッセージ保存地点が近くにあります。';

  @override
  String get meshHealthNoAnchor => '近くにメッセージ保存地点はありません。';

  @override
  String get adaptivePowerTitle => '適応バッテリーモード';

  @override
  String get adaptivePowerNormal => 'メッシュ性能：最大';

  @override
  String get adaptivePowerSaving => '省電力：短い間隔でスキャン';

  @override
  String get powerProfilePerformance => '高性能：高速検出';

  @override
  String get powerProfileBalanced => 'バランス：メッシュ全体を維持';

  @override
  String get powerProfilePowerSaver => '省電力：間隔を空けてスキャン';

  @override
  String get powerProfileCritical => '危険：接続とスキャンを最小化';

  @override
  String get powerProfileSurvival => 'サバイバル：SOS ビーコンのみ';

  @override
  String get survivalModeTitle => 'サバイバルモード';

  @override
  String get survivalModeBody => 'SOSビーコンのみを維持します。チャットと中継は停止します。';

  @override
  String get survivalModeEnable => 'サバイバルモードを有効化';

  @override
  String get survivalModeDisable => 'メッシュモードに戻る';

  @override
  String get survivalModeSuggestion => 'バッテリー残量が危険です。検出可能時間を延ばしてください。';

  @override
  String get gatewayTitle => '緊急インターネットゲートウェイ';

  @override
  String get gatewayBody => 'インターネット復旧時に、保留中のSOSと安否情報を公開できます。';

  @override
  String get gatewayOptIn => 'この端末からインターネット出口を提供';

  @override
  String get gatewayAvailable => 'インターネット接続を検出';

  @override
  String get gatewayUnavailable => 'インターネット接続なし';

  @override
  String get gatewayPrivacy => '対象はSOSと安否情報のみです。信頼できる設定なしでは送信しません。';

  @override
  String gatewayPending(int count) {
    return '保留中の緊急項目 $count 件';
  }

  @override
  String get gatewayConfigure => '信頼済みゲートウェイを設定';

  @override
  String get gatewayKindMatrix => 'Matrix';

  @override
  String get gatewayKindMqtt => 'MQTT';

  @override
  String get gatewayHomeserver => 'MatrixサーバーURL';

  @override
  String get gatewayBroker => 'MQTTブローカー';

  @override
  String get gatewayRoom => 'MatrixルームID';

  @override
  String get gatewayTopic => 'MQTTトピック';

  @override
  String get gatewayUsername => 'ユーザー名';

  @override
  String get gatewayAccessToken => 'アクセストークン';

  @override
  String get gatewayPassword => 'パスワード';

  @override
  String get gatewayPort => 'ポート';

  @override
  String get gatewayTls => '暗号化TLS接続を使用';

  @override
  String get mapOpen => 'オフライン地図を開く';

  @override
  String get mapOpenRescue => '救助マップを開く';

  @override
  String get mapTitle => 'オフライン救助マップ';

  @override
  String get mapMyLocation => '現在地を中央に表示';

  @override
  String get mapPassiveCacheInfo =>
      '表示した地図タイルは、オフラインで再利用できるよう自動保存されます。地域のダウンロードには、許可されたプロバイダーまたは独自サーバーが必要です。';

  @override
  String get mapTilePolicyAction => 'OSMポリシー';

  @override
  String get mapDownloadVisible => '表示範囲をダウンロード';

  @override
  String mapDownloadComplete(int count) {
    return '$count枚の地図タイルをオフライン用に保存しました。';
  }

  @override
  String mapDownloadTooLarge(int maximum) {
    return '範囲が広すぎます。拡大してください。安全な上限は$maximum枚です。';
  }

  @override
  String mapDownloadError(String error) {
    return '地図範囲をダウンロードできませんでした：$error';
  }

  @override
  String mapDownloading(int completed, int total) {
    return '地図を保存中：$completed/$total';
  }

  @override
  String mapCacheError(String error) {
    return 'オフライン地図キャッシュを開けませんでした：$error';
  }

  @override
  String get mapYouAreHere => '現在地';

  @override
  String get mapOfflineHint => 'ネットワークがありません。保存済みの地図タイルは表示できます。';

  @override
  String get mapTileBlockedHint =>
      'プロバイダーが地図タイルを一時的にブロックしました。救助マーカーは引き続き利用できます。オフライン地図には許可された配信元または独自サーバーを使用してください。';

  @override
  String get mapShowOnMap => '地図に表示';

  @override
  String get rescueListTitle => '救助リスト・近い順';

  @override
  String get rescueListEmpty => '救助情報を含むSOSまたは安否確認はありません。';

  @override
  String get rescueExportCsv => '救助CSVを共有';

  @override
  String get rescueExportSubject => 'HearthBit救助リスト';

  @override
  String rescueExportError(String error) {
    return '救助リストを共有できませんでした：$error';
  }

  @override
  String get rescueDistanceUnknown => '距離不明';

  @override
  String rescueDistanceMeters(int meters) {
    return '$meters m先';
  }

  @override
  String rescueDistanceKilometers(String kilometers) {
    return '$kilometers km先';
  }

  @override
  String get voiceRecord => '音声メモを録音';

  @override
  String get voiceStop => '録音を停止';

  @override
  String get voiceTooLong => '音声メモは20秒までです。';

  @override
  String get voiceUnsupported => '受信側にもHearthBitが必要です。';

  @override
  String get voicePlay => '音声メモを再生';

  @override
  String get voicePause => '音声メモを一時停止';

  @override
  String get shareApkButton => 'インストール済みAPKを共有';

  @override
  String get sendApkToPeer => 'HearthBit APKを送信';

  @override
  String get apkSafetyTitle => 'Androidインストーラーを共有しますか？';

  @override
  String apkSendToPeerWarning(String peer) {
    return '$peer にHearthBitのAndroidインストーラーを送信します。';
  }

  @override
  String get apkInstallWarning =>
      '受信者はAndroid設定で、受信に使用した提供元からのアプリのインストールを許可する必要があります。HearthBitが自動的にインストールすることはありません。';

  @override
  String get apkSignatureWarning =>
      '異なる鍵で署名されたAPKは、インストール済みアプリを更新できません。インストール前に提供元と署名を確認してください。';

  @override
  String get apkTransportWarning =>
      'APK転送にBLEは使用しません。ローカルWi-Fi、Nearby、またはWi-Fi Awareが必要です。利用できない場合は転送エラーが表示されます。';

  @override
  String get apkConfirmShare => '続行';

  @override
  String get apkPreparing => '安全なAPKコピーを準備しています…';

  @override
  String get apkSplitUnavailable =>
      'このインストールは分割APKを使用しています。ベースAPKだけでは不完全なため、HearthBitは共有しません。代わりにGitHubリンクを案内してください。';

  @override
  String get apkUnsupported => 'インストール済みAPKの共有はAndroidでのみ利用できます。';

  @override
  String apkShareError(String error) {
    return 'APKを準備または共有できませんでした：$error';
  }

  @override
  String get apkShareMessage =>
      'HearthBit Androidインストーラーです。Androidでは、この提供元からのインストール許可が必要です。署名が異なるAPKは既存のインストールを更新できないため、先に提供元と署名を確認してください。';

  @override
  String apkOfferSent(String peer) {
    return '$peer にAPKを提案しました。適切な高速転送経路がない場合はエラーが表示されます。';
  }

  @override
  String get firstAidOpen => 'オフライン応急手当を開く';

  @override
  String get firstAidTitle => 'オフライン応急手当';

  @override
  String get firstAidDisclaimer =>
      '地域の救急へ通報してください。この案内は専門家の救助や講習に代わりません。地域で手順が異なるため、通信指令員と当局に従ってください。';

  @override
  String get firstAidChooseTopic => '起きていることを選ぶ';

  @override
  String get firstAidEnglishFallback => 'この翻訳を検証できないため、検証済みの英語版を表示しています。';

  @override
  String get firstAidSteps => '今すぐ行う';

  @override
  String get firstAidWarnings => '避けること';

  @override
  String get firstAidSources => '出典と確認情報';

  @override
  String firstAidReviewed(String date) {
    return '内容確認日：$date';
  }

  @override
  String get firstAidLoadError =>
      '検証済みのオフライン案内を読み込めませんでした。不完全な情報に頼らず、地域の救急へ通報してください。';

  @override
  String get familyTitle => '家族グループ';

  @override
  String get familySecurityBody =>
      '署名付きQRを対面で確認してメンバーを登録します。名前や古い端末IDだけを信頼することはありません。';

  @override
  String get familyCreateGroup => 'グループを作成';

  @override
  String get familyRenameGroup => 'グループ名を変更';

  @override
  String get familyGroupHint => '例：家族';

  @override
  String get familyGroupLabel => 'グループ';

  @override
  String get familyConfirmTitle => '家族を確認';

  @override
  String familyFingerprint(String fingerprint) {
    return 'セキュリティコード：$fingerprint';
  }

  @override
  String get familyConfirmBody => '保存前に両方の端末でこのセキュリティコードを比較してください。';

  @override
  String get familyAddMember => 'メンバーを追加';

  @override
  String get familyRemoveTitle => '家族を削除しますか？';

  @override
  String familyRemoveBody(String nickname) {
    return '$nickname の家族表示と通知が無効になります。';
  }

  @override
  String get familyRemoveAction => '削除';

  @override
  String familySaveError(String error) {
    return '家族グループを保存できませんでした：$error';
  }

  @override
  String get familyMembersTitle => '確認済みメンバー';

  @override
  String get familyScanAction => '家族のQRをスキャン';

  @override
  String get familyCreateFirst => 'メンバーを追加する前にグループを作成してください。';

  @override
  String get familyNoMembers => '確認済みメンバーはいません。';

  @override
  String get familyMyQr => '自分の確認用QR';

  @override
  String get familyMyQrBody => 'このQRを対面で見せてください。公開署名鍵のみを含み、秘密鍵は含みません。';

  @override
  String get familyQrUnavailable => '署名付き確認QRを表示するにはメッシュを有効にしてください。';

  @override
  String get familyScanTitle => '家族QRをスキャン';

  @override
  String get familyQrInvalid => 'このQRは無効か、署名を確認できませんでした。';

  @override
  String get familyScanHint => '家族の端末に表示されたQRをスキャンしてください。';

  @override
  String get familyAlertBadge => '確認済みの家族';

  @override
  String get drillSafetyBanner => '訓練 - 救助を要請しません';

  @override
  String get drillModeTitle => '訓練モード';

  @override
  String get drillModeBody =>
      '明確に訓練と表示されたメッセージだけを送信します。SOS、救助位置、物理ビーコン、インターネットゲートウェイは使用しません。';

  @override
  String get drillConfirmTitle => '訓練モードを有効にしますか？';

  @override
  String get drillConfirmBody =>
      '救助モードとサバイバルモードは停止します。訓練メッセージは公開されますが、実際の緊急警報にはなりません。';

  @override
  String get drillEnableAction => '訓練を有効化';

  @override
  String get drillHoldToSend => '長押しして訓練を送信';

  @override
  String get drillPracticeMessage => '助けを求める訓練';

  @override
  String get drillReceivedTitle => '訓練メッセージ';

  @override
  String get drillNoneReceived => '訓練メッセージはありません。';

  @override
  String get drillBadge => '訓練 — 緊急事態ではありません';

  @override
  String get drillInvalidMessage => '認識できない訓練メッセージは緊急システムから隔離されました。';

  @override
  String get drillCheckInTitle => '状況報告を練習';

  @override
  String get drillCheckInBody => 'この報告は訓練チャンネル内に留まり、救助警報、地図、エクスポートには表示されません。';

  @override
  String get drillExitForRealTitle => '本物のSOSを送信しますか？';

  @override
  String get drillExitForRealBody => '訓練を終了し、位置共有と繰り返しSOSを伴う実際の救助要請を開始します。';

  @override
  String get drillSendRealSos => '訓練を終了してSOSを送信';

  @override
  String get drillDisableTitle => '訓練モードを終了しますか？';

  @override
  String get drillDisableBody => '訓練メッセージを停止し、HearthBitを実際の緊急時の動作に戻します。';

  @override
  String get drillDisableAction => '訓練を終了';

  @override
  String get mapNoLocationTitle => '位置情報がありません';

  @override
  String get mapNoLocationBody =>
      '位置情報を有効にするか、ノードが有効な救助位置を共有するまで待ってください。地図は(0,0)を代替位置として使用しません。';

  @override
  String get voiceMicrophoneRequired => '音声メモの録音にはマイクへのアクセスが必要です。';

  @override
  String get actionOpenSettings => '設定を開く';

  @override
  String get opticalUnverifiedTitle => '未確認の送信元';

  @override
  String get opticalUnverifiedBody =>
      'この転送を以前に認証したIDと照合できません。受け入れる前に送信者とフィンガープリントを確認してください。';

  @override
  String get opticalLegacyWarning => 'この送信者は署名のない旧式の光学形式を使用しています。';

  @override
  String opticalFingerprint(String fingerprint) {
    return 'フィンガープリント: $fingerprint';
  }

  @override
  String get opticalAcceptUnverified => '未確認のまま受け入れる';

  @override
  String get opticalSignatureInvalid =>
      '光学マニフェストの署名が既知の送信者と一致しません。ファイルを拒否しました。';

  @override
  String get opticalVerifiedSource => '確認済みの送信者';

  @override
  String get gatewayPrivacyConfirm =>
      '緊急メッセージ、送信者情報、含まれる救助位置を設定したインターネットサービスへ送信します。関係者の同意がある場合のみ有効にしてください。';

  @override
  String get gatewayEnableAction => 'ゲートウェイを有効化';

  @override
  String get gatewayTlsRequired => '緊急データには必須です。安全でない接続は拒否されます。';

  @override
  String get locationExportConfirmTitle => '救助位置をエクスポートしますか？';

  @override
  String get locationExportConfirmBody =>
      'CSVには正確な位置と緊急情報が含まれる場合があります。信頼できる救助者とのみ共有し、ファイルを保護してください。';

  @override
  String get locationExportConfirmAction => '位置をエクスポート';

  @override
  String get lanGatewayConnected => 'LANリレー接続済み';

  @override
  String get lanGatewaySearching => 'LANリレー有効・ローカル検索中';

  @override
  String get lanGatewayDisabled => 'LANリレー無効';

  @override
  String get lanGatewayConfigure => 'LANリレーを設定';

  @override
  String get lanGatewayDisable => 'LANリレーを無効化';

  @override
  String get lanGatewayPrivacy =>
      '明示的に有効化した場合のみ動作します。共有鍵は信頼できるHearthBit Raspberry Piリレーと一致させてください。メッシュフレームはローカルネットワーク上で認証・暗号化されます。';

  @override
  String get lanGatewayPsk => '32バイトのペアリング鍵（base64）';

  @override
  String get lanGatewayGeneratePsk => '鍵を生成';

  @override
  String get lanGatewayInvalidPsk => '有効な32バイトのbase64鍵を入力してください。';

  @override
  String get emergencyContactsOpen => '緊急番号と公式リンク';

  @override
  String get emergencyContactsTitle => '緊急連絡先';

  @override
  String get emergencyContactsSafetyNotice =>
      '緊急番号はモバイルデータなしでも利用できる場合がありますが、携帯電話の音声回線が必要です。公式サイトにはインターネットが必要です。';

  @override
  String get emergencyContactsCountry => '国または地域';

  @override
  String emergencyContactsAutomatic(String country) {
    return '自動（$country）';
  }

  @override
  String get emergencyContactsNumbers => '緊急電話番号';

  @override
  String get emergencyContactsOrganizations => '公式機関';

  @override
  String get emergencyContactsCall => '電話する';

  @override
  String get emergencyContactsWebsite => 'ウェブサイト';

  @override
  String get emergencyContactsSources => '情報源と確認';

  @override
  String emergencyContactsReviewed(String date) {
    return '確認日：$date';
  }

  @override
  String get emergencyContactsFallback => 'この翻訳を利用できないため、確認済みの英語版を表示しています。';

  @override
  String get emergencyContactsLoadError => 'オフライン緊急連絡先を読み込めませんでした。';

  @override
  String get emergencyContactsOpenError => 'この端末では番号またはリンクを開けませんでした。';

  @override
  String get emergencyContactsRetry => '再試行';
}
