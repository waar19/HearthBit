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
      'HearthBit はオープンソースの緊急通信プロジェクトです。ご支援は実機テストと堅牢な中継ハードウェアの開発に役立ちます。';

  @override
  String aboutVersion(String version) {
    return 'バージョン $version';
  }

  @override
  String get aboutSourceCode => 'ソースコード';

  @override
  String get supportButton => 'コーヒーで支援';

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
}
