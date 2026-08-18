import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controllers/transfer_controller.dart';
import '../../l10n/l10n.dart';
import '../../models/mesh_models.dart';
import '../../models/transfer_models.dart';
import '../../services/voice_note_audio_controller.dart';
import '../../utils/noop_listenable.dart';
import '../../utils/voice_formatting.dart';
import '../../widgets/voice_waveform.dart';

class VoiceNoteContent extends StatelessWidget {
  const VoiceNoteContent({
    required this.message,
    required this.transfers,
    required this.voiceAudio,
    super.key,
  });

  final MeshMessage message;
  final TransferController? transfers;
  final VoiceNoteAudioController? voiceAudio;

  @override
  Widget build(BuildContext context) {
    TransferRecord? record;
    final transferId = message.voiceTransferId;
    if (transferId != null && transfers != null) {
      for (final item in transfers!.transfers) {
        if (item.id == transferId) {
          record = item;
          break;
        }
      }
    }
    final playbackPath = record?.filePath;
    final localFileAvailable =
        playbackPath != null && File(playbackPath).existsSync();
    final ready =
        localFileAvailable &&
        (record?.direction == TransferDirection.outgoing ||
            record?.state == TransferState.completed);
    final failed =
        record?.state == TransferState.failed ||
        record?.state == TransferState.rejected ||
        record?.state == TransferState.cancelled;
    final transferKey = transferId ?? message.id;
    final fallbackDuration = Duration(
      seconds: message.voiceDurationSeconds ?? 0,
    );
    final samples = message.voiceWaveform.isEmpty
        ? fallbackVoiceWaveform()
        : message.voiceWaveform;
    final controller = voiceAudio;
    final contentWidth = math.min(
      240.0,
      MediaQuery.sizeOf(context).width * .66,
    );
    return AnimatedBuilder(
      animation: controller ?? const NoopListenable(),
      builder: (context, _) {
        final active = controller?.isActive(transferKey) ?? false;
        final playing = controller?.isPlaying(transferKey) ?? false;
        final progress =
            controller?.progressFor(transferKey, fallbackDuration) ?? 0;
        final position = active
            ? controller?.position ?? Duration.zero
            : Duration.zero;
        final playbackError = active ? controller?.error : null;
        final tooltip = failed && !ready
            ? (record?.error ?? context.l10n.errorUnknown)
            : playbackError ??
                  (playing ? context.l10n.voicePause : context.l10n.voicePlay);
        return SizedBox(
          width: contentWidth,
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: tooltip,
                onPressed: ready && controller != null
                    ? () => controller.toggle(
                        transferId: transferKey,
                        filePath: playbackPath,
                      )
                    : null,
                icon: ready
                    ? Icon(playing ? Icons.pause : Icons.play_arrow)
                    : failed
                    ? Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      )
                    : const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: VoiceWaveform(
                  samples: samples,
                  progress: progress,
                  onSeek: ready && active && controller != null
                      ? (value) => controller.seek(
                          transferId: transferKey,
                          progress: value,
                          fallbackDuration: fallbackDuration,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatVoiceDuration(
                  active && position > Duration.zero
                      ? position
                      : fallbackDuration,
                ),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              if (playbackError != null || (failed && ready)) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message:
                      playbackError ??
                      record?.error ??
                      context.l10n.errorUnknown,
                  child: Icon(
                    Icons.error_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
