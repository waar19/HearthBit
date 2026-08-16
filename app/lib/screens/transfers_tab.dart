import 'package:flutter/material.dart';

import '../controllers/transfer_controller.dart';
import '../l10n/l10n.dart';
import '../models/transfer_models.dart';

class TransfersTab extends StatelessWidget {
  const TransfersTab({
    required this.transfers,
    required this.onSendOptical,
    required this.onReceiveOptical,
    super.key,
  });

  final TransferController transfers;
  final VoidCallback onSendOptical;
  final VoidCallback onReceiveOptical;

  @override
  Widget build(BuildContext context) {
    final records = transfers.transfers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSendOptical,
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(context.l10n.sendByQr),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReceiveOptical,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(context.l10n.receiveByQr),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: records.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.folder_shared_outlined,
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.l10n.emptyTransfersTitle,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                context.l10n.emptyTransfersBody,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: records.length,
                  itemBuilder: (context, index) => _TransferCard(
                    record: records[index],
                    transfers: transfers,
                  ),
                ),
        ),
      ],
    );
  }
}

class _TransferCard extends StatefulWidget {
  const _TransferCard({required this.record, required this.transfers});

  final TransferRecord record;
  final TransferController transfers;

  @override
  State<_TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends State<_TransferCard> {
  int _lastBytes = 0;
  DateTime _lastAt = DateTime.now();
  double _speedBps = 0;

  TransferRecord get record => widget.record;

  TransferController get transfers => widget.transfers;

  @override
  void didUpdateWidget(covariant _TransferCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (record.state != TransferState.transferring) {
      _speedBps = 0;
      _lastBytes = record.bytesDone;
      _lastAt = DateTime.now();
      return;
    }
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastAt).inMilliseconds;
    if (elapsedMs >= 500 && record.bytesDone > _lastBytes) {
      _speedBps = (record.bytesDone - _lastBytes) * 1000 / elapsedMs;
      _lastBytes = record.bytesDone;
      _lastAt = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final incoming = record.direction == TransferDirection.incoming;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Semantics(
      container: true,
      liveRegion: record.isActive,
      label:
          '${record.fileName}, ${_stateLabel(context, record.state)}, '
          '${_formatBytes(record.bytesDone)} ${_formatBytes(record.fileSize)}',
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    incoming
                        ? Icons.file_download_outlined
                        : Icons.file_upload_outlined,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.fileName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${incoming ? context.l10n.transferFrom(record.peerNickname) : context.l10n.transferTo(record.peerNickname)} · '
                          '${_formatBytes(record.fileSize)}'
                          '${record.transport != null ? " · ${_transportLabel(context, record.transport!)}" : ""}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!largeText) _StateChip(state: record.state),
                ],
              ),
              if (largeText)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _StateChip(state: record.state),
                ),
              if (record.state == TransferState.connecting ||
                  record.state == TransferState.transferring) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: record.state == TransferState.transferring
                      ? record.progress
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  '${context.l10n.transferProgress(_formatBytes(record.bytesDone), _formatBytes(record.fileSize))}'
                  '${_speedBps > 0 ? " · ${_formatBytes(_speedBps.round())}/s" : ""}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (record.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  record.error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ],
              if (record.state == TransferState.completed &&
                  incoming &&
                  record.filePath != null) ...[
                const SizedBox(height: 6),
                Text(
                  context.l10n.transferSavedAt(record.filePath!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 4,
                children: _actions(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final incoming = record.direction == TransferDirection.incoming;
    if (record.state == TransferState.offered && incoming) {
      return [
        TextButton(
          onPressed: () => transfers.rejectOffer(record.id),
          child: Text(context.l10n.actionReject),
        ),
        const SizedBox(width: 8),
        if (transfers.canAcceptExternal(record.id)) ...[
          OutlinedButton.icon(
            onPressed: () => transfers.acceptOffer(
              record.id,
              preferredTransport: TransferTransport.external,
            ),
            icon: const Icon(Icons.ios_share),
            label: Text(context.l10n.transportShare),
          ),
          const SizedBox(width: 8),
        ],
        FilledButton(
          onPressed: () => transfers.acceptOffer(record.id),
          child: Text(context.l10n.actionAccept),
        ),
      ];
    }
    if (record.isActive) {
      return [
        if (transfers.canShareExternal(record.id))
          FilledButton.icon(
            onPressed: () {
              final box = context.findRenderObject() as RenderBox?;
              final origin = box == null || !box.hasSize
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size;
              transfers.shareExternalPackage(record.id, origin: origin);
            },
            icon: const Icon(Icons.share),
            label: Text(context.l10n.transferExport),
          ),
        TextButton(
          onPressed: () => transfers.cancel(record.id),
          child: Text(context.l10n.actionCancel),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => transfers.remove(record.id),
        child: Text(context.l10n.actionDelete),
      ),
    ];
  }
}

String _stateLabel(BuildContext context, TransferState state) {
  final l10n = context.l10n;
  return switch (state) {
    TransferState.offered => l10n.stateOffered,
    TransferState.connecting => l10n.stateConnecting,
    TransferState.transferring => l10n.stateTransferring,
    TransferState.completed => l10n.stateCompleted,
    TransferState.rejected => l10n.stateRejected,
    TransferState.cancelled => l10n.stateCancelled,
    TransferState.failed => l10n.stateFailed,
  };
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final TransferState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final (label, color) = switch (state) {
      TransferState.offered => (l10n.stateOffered, scheme.secondaryContainer),
      TransferState.connecting => (
        l10n.stateConnecting,
        scheme.secondaryContainer,
      ),
      TransferState.transferring => (
        l10n.stateTransferring,
        scheme.primaryContainer,
      ),
      TransferState.completed => (l10n.stateCompleted, scheme.primaryContainer),
      TransferState.rejected => (
        l10n.stateRejected,
        scheme.surfaceContainerHighest,
      ),
      TransferState.cancelled => (
        l10n.stateCancelled,
        scheme.surfaceContainerHighest,
      ),
      TransferState.failed => (l10n.stateFailed, scheme.errorContainer),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

String _transportLabel(BuildContext context, TransferTransport transport) =>
    switch (transport) {
      TransferTransport.ble => context.l10n.transportBle,
      TransferTransport.lan => context.l10n.transportLan,
      TransferTransport.nearby => context.l10n.transportNearby,
      TransferTransport.wifiAware => context.l10n.transportWifiAware,
      TransferTransport.optical => context.l10n.transportOptical,
      TransferTransport.wifiDirect => context.l10n.transportWifiDirect,
      TransferTransport.multipeer => context.l10n.transportMultipeer,
      TransferTransport.external => context.l10n.transportShare,
    };

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
}
