import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../controllers/mesh_controller.dart';
import '../../controllers/transfer_controller.dart';
import '../../l10n/l10n.dart';
import '../../models/mesh_models.dart';
import '../../models/voice_note.dart';
import '../../services/transfer_storage.dart';
import '../../services/voice_note_audio_controller.dart';
import '../../utils/message_timeline.dart';
import '../../utils/scroll_to_bottom.dart';
import '../../utils/voice_formatting.dart';
import '../../widgets/message_composer.dart';
import '../../widgets/sensitive_screen.dart';
import '../../widgets/voice_waveform.dart';
import 'message_timeline.dart' as timeline;

class PrivateChatSheet extends StatefulWidget {
  const PrivateChatSheet({
    required this.controller,
    required this.transfers,
    required this.peer,
    required this.onOpenRadar,
    super.key,
  });

  final MeshController controller;
  final TransferController transfers;
  final MeshPeer peer;
  final Future<void> Function(MeshPeer peer) onOpenRadar;

  @override
  State<PrivateChatSheet> createState() => _PrivateChatSheetState();
}

class _PrivateChatSheetState extends State<PrivateChatSheet> {
  late final TextEditingController _textController;
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final VoiceNoteAudioController _voiceAudio = VoiceNoteAudioController();
  final List<double> _recordingWaveform = [];
  var _privateMessageCount = 0;
  var _scrollScheduled = false;
  var _recording = false;
  var _sending = false;
  String? _sendError;
  DateTime? _recordingStarted;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingLimitTimer;
  Timer? _recordingUiTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _privateMessageCount = _countPrivateMessages();
    widget.controller.addListener(_handleControllerUpdate);
    widget.transfers.addListener(_handleTransferUpdate);
    _scrollToBottom(animate: false);
  }

  @override
  void didUpdateWidget(covariant PrivateChatSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerUpdate);
      widget.controller.addListener(_handleControllerUpdate);
      _privateMessageCount = _countPrivateMessages();
      _scrollToBottom(animate: false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerUpdate);
    widget.transfers.removeListener(_handleTransferUpdate);
    _recordingLimitTimer?.cancel();
    _recordingUiTimer?.cancel();
    unawaited(_amplitudeSubscription?.cancel());
    _audioRecorder.dispose();
    _voiceAudio.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int _countPrivateMessages() => widget.controller.messages
      .where(
        (message) =>
            message.isPrivate && message.senderPeerId == widget.peer.id,
      )
      .length;

  void _handleControllerUpdate() {
    final count = _countPrivateMessages();
    if (!mounted) return;
    final hasNewMessage = count > _privateMessageCount;
    setState(() => _privateMessageCount = count);
    if (hasNewMessage) _scrollToBottom();
  }

  void _handleTransferUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoiceRecording(MeshPeer peer) async {
    if (_recording) {
      await _stopVoiceRecording();
      return;
    }
    if (!peer.supportsTransfers) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.voiceUnsupported)));
      return;
    }
    if (!await _audioRecorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.voiceMicrophoneRequired),
          action: SnackBarAction(
            label: context.l10n.actionOpenSettings,
            onPressed: Geolocator.openAppSettings,
          ),
        ),
      );
      return;
    }
    await _voiceAudio.stop();
    final directory = await TransferStorage.cacheDirectory();
    final path = p.join(
      directory.path,
      'hearthbit_voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 20000,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
        audioInterruption: AudioInterruptionMode.pauseResume,
      ),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordingStarted = DateTime.now();
      _recordingElapsed = Duration.zero;
      _recordingWaveform.clear();
      _sendError = null;
    });
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen(_recordAmplitude);
    _recordingUiTimer?.cancel();
    _recordingUiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_recording || _recordingStarted == null) return;
      setState(() {
        _recordingElapsed = DateTime.now().difference(_recordingStarted!);
      });
    });
    _recordingLimitTimer?.cancel();
    _recordingLimitTimer = Timer(
      const Duration(seconds: 20),
      _stopVoiceRecording,
    );
  }

  void _recordAmplitude(Amplitude amplitude) {
    if (!mounted || !_recording) return;
    final decibels = amplitude.current.clamp(-60.0, 0.0);
    final linear = ((decibels + 60) / 60).clamp(0.0, 1.0);
    final normalized = math.sqrt(linear).clamp(0.08, 1.0);
    setState(() {
      _recordingWaveform.add(normalized);
    });
  }

  Future<void> _stopVoiceRecording() async {
    if (!_recording) return;
    _recordingLimitTimer?.cancel();
    _recordingUiTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final elapsed = DateTime.now().difference(
      _recordingStarted ?? DateTime.now(),
    );
    final duration = (elapsed.inMilliseconds / 1000).ceil().clamp(1, 20);
    final waveform = VoiceNoteEnvelope.resample(_recordingWaveform);
    final path = await _audioRecorder.stop();
    await _voiceAudio.resetPlaybackSession();
    if (mounted) {
      setState(() {
        _recording = false;
        _recordingStarted = null;
        _recordingElapsed = Duration.zero;
      });
    }
    if (path == null || !mounted) return;
    final peer =
        widget.controller.peerById(widget.peer.id) ??
        widget.controller.knownPeerById(widget.peer.id) ??
        widget.peer;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    String? transferId;
    try {
      transferId = await widget.transfers.sendFile(
        peer: peer,
        filePath: path,
        fileName: p.basename(path),
        mimeType: TransferController.voiceNoteMimeType,
      );
      final result = await widget.controller.sendPrivate(
        peer,
        VoiceNoteEnvelope(
          transferId: transferId,
          durationSeconds: duration,
          waveform: waveform,
        ).encode(),
      );
      if (!result.accepted) {
        throw StateError(result.error ?? currentL10n.errorUnknown);
      }
      _scrollToBottom();
    } catch (error) {
      if (transferId != null) {
        await widget.transfers.cancel(transferId);
      }
      if (mounted) {
        setState(() => _sendError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_recording) return;
    _recordingLimitTimer?.cancel();
    _recordingUiTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    await _audioRecorder.cancel();
    await _voiceAudio.resetPlaybackSession();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingStarted = null;
      _recordingElapsed = Duration.zero;
      _recordingWaveform.clear();
    });
  }

  Future<void> _sendMessage(MeshPeer peer) async {
    if (_sending) return;
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    PrivateMessageSendResult result;
    try {
      result = await widget.controller.sendPrivate(peer, text);
    } catch (error) {
      result = PrivateMessageSendResult.failed(error.toString());
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.accepted) {
        _textController.clear();
      } else {
        _sendError = result.error ?? context.l10n.errorUnknown;
      }
    });
    if (result.accepted) _scrollToBottom();
  }

  void _scrollToBottom({bool animate = true}) {
    scheduleScrollToBottom(
      _scrollController,
      animate: animate,
      isMounted: () => mounted,
      markScheduled: () => _scrollScheduled,
      setScheduled: (value) => _scrollScheduled = value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final peer =
        widget.controller.peerById(widget.peer.id) ??
        widget.controller.knownPeerById(widget.peer.id) ??
        widget.peer;
    final isOnline = widget.controller.isPeerOnline(peer.id);
    final secure = isOnline && peer.secure;
    final canUseLivePrivateChannel =
        isOnline && secure && widget.controller.canSend && !_sending;
    final canQueueText =
        peer.role.canChat && widget.controller.canSend && !_sending;
    final privateMessages = widget.controller.messages
        .where(
          (message) =>
              message.isPrivate && message.senderPeerId == widget.peer.id,
        )
        .toList(growable: false);
    final entries = messageTimelineEntries(privateMessages);
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom - 32;
    final sheetHeight = math.min(
      mediaQuery.size.height * .65,
      math.max(160, availableHeight),
    );
    return SensitiveScreen(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: mediaQuery.viewInsets.bottom + 16,
        ),
        child: SizedBox(
          height: sheetHeight.toDouble(),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(secure ? Icons.lock : Icons.lock_open),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      peer.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: peer.radarAllowed
                        ? context.l10n.tooltipRadar
                        : context.l10n.radarConsentRequired,
                    onPressed: isOnline && peer.radarAllowed
                        ? () => widget.onOpenRadar(peer)
                        : null,
                    icon: const Icon(Icons.radar),
                  ),
                ],
              ),
              const Divider(),
              if (!isOnline || !secure)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        isOnline
                            ? Icons.lock_clock_outlined
                            : Icons.cloud_off_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isOnline
                              ? context.l10n.secureChatUnavailableHint
                              : context.l10n.offlineChatHint,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: privateMessages.isEmpty
                    ? Center(
                        child: Text(
                          context.l10n.privateChatIntro,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: entries.length,
                        itemBuilder: (context, index) =>
                            timeline.buildMessageTimelineEntry(
                              context,
                              entries[index],
                              transfers: widget.transfers,
                              voiceAudio: _voiceAudio,
                            ),
                      ),
              ),
              if (_sendError case final error?)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.privateMessageSendError(error),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_recording)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: context.l10n.actionCancel,
                        onPressed: _cancelVoiceRecording,
                        icon: const Icon(Icons.delete_outline),
                      ),
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatVoiceDuration(_recordingElapsed),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: VoiceWaveform(
                          samples: VoiceNoteEnvelope.resample(
                            _recordingWaveform,
                            bars: 40,
                          ),
                          progress: 1,
                          activeColor: Theme.of(context).colorScheme.error,
                          inactiveColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      IconButton.filled(
                        tooltip: context.l10n.voiceStop,
                        onPressed: _stopVoiceRecording,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: context.l10n.voiceRecord,
                      onPressed:
                          canUseLivePrivateChannel && peer.supportsTransfers
                          ? () => _toggleVoiceRecording(peer)
                          : null,
                      icon: const Icon(Icons.mic),
                    ),
                    Expanded(
                      child: MessageComposer(
                        controller: _textController,
                        enabled: canQueueText,
                        hint: context.l10n.composerPrivateHint,
                        onSend: () => _sendMessage(peer),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
