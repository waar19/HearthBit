import 'package:flutter/material.dart';

import '../controllers/transfer_controller.dart';
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
                  label: const Text('Enviar por QR'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReceiveOptical,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Recibir por QR'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: records.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_shared_outlined, size: 64),
                        SizedBox(height: 16),
                        Text(
                          'Sin transferencias',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Toca el clip junto a un dispositivo cercano para '
                          'ofrecerle un archivo. La oferta viaja cifrada por '
                          'la malla y el contenido usa el transporte más '
                          'rápido disponible. El modo QR funciona incluso sin '
                          'ninguna radio.',
                          textAlign: TextAlign.center,
                        ),
                      ],
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
    return Card(
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
                        '${incoming ? "De" : "Para"} ${record.peerNickname} · '
                        '${_formatBytes(record.fileSize)}'
                        '${record.transport != null ? " · ${_transportLabel(record.transport!)}" : ""}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _StateChip(state: record.state),
              ],
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
                '${_formatBytes(record.bytesDone)} de ${_formatBytes(record.fileSize)}'
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
                'Guardado en ${record.filePath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _actions(context),
            ),
          ],
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
          child: const Text('RECHAZAR'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => transfers.acceptOffer(record.id),
          child: const Text('ACEPTAR'),
        ),
      ];
    }
    if (record.isActive) {
      return [
        TextButton(
          onPressed: () => transfers.cancel(record.id),
          child: const Text('CANCELAR'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => transfers.remove(record.id),
        child: const Text('ELIMINAR'),
      ),
    ];
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final TransferState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (state) {
      TransferState.offered => ('Oferta', scheme.secondaryContainer),
      TransferState.connecting => ('Conectando', scheme.secondaryContainer),
      TransferState.transferring => ('Enviando', scheme.primaryContainer),
      TransferState.completed => ('Completa', scheme.primaryContainer),
      TransferState.rejected => ('Rechazada', scheme.surfaceContainerHighest),
      TransferState.cancelled => ('Cancelada', scheme.surfaceContainerHighest),
      TransferState.failed => ('Falló', scheme.errorContainer),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

String _transportLabel(TransferTransport transport) => switch (transport) {
  TransferTransport.ble => 'Bluetooth',
  TransferTransport.lan => 'Wi-Fi local',
  TransferTransport.nearby => 'Nearby',
  TransferTransport.wifiAware => 'Wi-Fi Aware',
  TransferTransport.optical => 'QR óptico',
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
}
