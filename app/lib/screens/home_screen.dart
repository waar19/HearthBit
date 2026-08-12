import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controllers/mesh_controller.dart';
import '../controllers/transfer_controller.dart';
import '../models/mesh_models.dart';
import '../models/transfer_models.dart';
import '../services/photo_profile.dart';
import 'optical_receive_screen.dart';
import 'optical_send_screen.dart';
import 'radar_screen.dart';
import 'rescue_power_cards.dart';
import 'transfers_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.controller,
    required this.transfers,
    super.key,
  });

  final MeshController controller;
  final TransferController transfers;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de Ajustes (batería/ubicación) se refresca el estado real.
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshPowerStatus();
    }
  }

  int get _pendingOffers => widget.transfers.transfers
      .where(
        (record) =>
            record.direction == TransferDirection.incoming &&
            record.state == TransferState.offered,
      )
      .length;

  Future<void> _sendFileTo(MeshPeer peer) async {
    final file = await openFile();
    if (file == null || !mounted) return;
    var path = file.path;
    var name = file.name;
    if (PhotoEmergencyProfile.isPhoto(name)) {
      final size = await File(path).length();
      if (size > PhotoEmergencyProfile.compressThresholdBytes && mounted) {
        final compress = await _askCompressPhoto(size);
        if (compress == null || !mounted) return;
        if (compress) {
          final compressed = await PhotoEmergencyProfile.compress(path);
          if (compressed != null) {
            path = compressed;
            name = p.basename(compressed);
          }
        }
      }
    }
    if (!mounted) return;
    try {
      await widget.transfers.sendFile(
        peer: peer,
        filePath: path,
        fileName: name,
      );
      if (!mounted) return;
      setState(() => _tab = 2);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo ofrecer el archivo: $error')),
      );
    }
  }

  Future<void> _startOpticalSend() async {
    final file = await openFile();
    if (file == null || !mounted) return;
    var path = file.path;
    var name = file.name;
    if (PhotoEmergencyProfile.isPhoto(name)) {
      final size = await File(path).length();
      if (size > PhotoEmergencyProfile.compressThresholdBytes && mounted) {
        final compress = await _askCompressPhoto(size);
        if (compress == null || !mounted) return;
        if (compress) {
          final compressed = await PhotoEmergencyProfile.compress(path);
          if (compressed != null) {
            path = compressed;
            name = p.basename(compressed);
          }
        }
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OpticalSendScreen(
          filePath: path,
          fileName: name,
          senderPeerId: widget.controller.peerId,
        ),
      ),
    );
  }

  Future<void> _startOpticalReceive() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OpticalReceiveScreen(transfers: widget.transfers),
      ),
    );
  }

  Future<void> _openRadar({
    required String peerId,
    required String nickname,
    double? latitude,
    double? longitude,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RadarScreen(
          peerId: peerId,
          nickname: nickname,
          latitude: latitude,
          longitude: longitude,
        ),
      ),
    );
  }

  Future<bool?> _askCompressPhoto(int size) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Perfil de emergencia'),
        content: Text(
          'La foto pesa ${(size / (1024 * 1024)).toStringAsFixed(1)} MiB. '
          'Comprimirla acelera el envío y ahorra batería en la malla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ENVIAR ORIGINAL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('COMPRIMIR'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.transfers]),
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('HearthBit'),
            actions: [
              IconButton(
                tooltip: 'Cambiar nombre',
                onPressed: () => _changeNickname(controller),
                icon: const Icon(Icons.badge_outlined),
              ),
              IconButton(
                tooltip: 'Borrado de emergencia',
                onPressed: () => _confirmWipe(controller),
                icon: const Icon(Icons.delete_forever_outlined),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _StatusBanner(controller: controller),
                if (controller.lastError != null)
                  MaterialBanner(
                    content: Text(controller.lastError!),
                    leading: const Icon(Icons.warning_amber_rounded),
                    actions: [
                      TextButton(
                        onPressed: () => controller.start(),
                        child: const Text('REINTENTAR'),
                      ),
                    ],
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _buildChat(controller),
                      _buildPeers(controller),
                      TransfersTab(
                        transfers: widget.transfers,
                        onSendOptical: _startOpticalSend,
                        onReceiveOptical: _startOpticalReceive,
                      ),
                      _buildSos(controller),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (value) => setState(() => _tab = value),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum),
                label: 'Canal',
              ),
              const NavigationDestination(
                icon: Icon(Icons.hub_outlined),
                selectedIcon: Icon(Icons.hub),
                label: 'Cercanos',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: _pendingOffers > 0,
                  label: Text('$_pendingOffers'),
                  child: const Icon(Icons.folder_shared_outlined),
                ),
                selectedIcon: const Icon(Icons.folder_shared),
                label: 'Archivos',
              ),
              const NavigationDestination(
                icon: Icon(Icons.sos_outlined),
                selectedIcon: Icon(Icons.sos),
                label: 'SOS',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChat(MeshController controller) {
    final publicMessages = controller.messages
        .where((message) => !message.isPrivate)
        .toList(growable: false);
    return Column(
      children: [
        Expanded(
          child: publicMessages.isEmpty
              ? const _EmptyState(
                  icon: Icons.bluetooth_searching,
                  title: 'Aún no hay mensajes',
                  description:
                      'Activa la malla. Los mensajes saltarán entre teléfonos cercanos sin usar internet.',
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: publicMessages.length,
                  itemBuilder: (context, index) =>
                      _MessageBubble(message: publicMessages[index]),
                ),
        ),
        _MessageComposer(
          controller: _messageController,
          enabled: controller.canSend,
          hint: 'Mensaje para todos los cercanos',
          onSend: () async {
            final text = _messageController.text;
            _messageController.clear();
            await controller.sendPublic(text);
            _scrollToBottom();
          },
        ),
      ],
    );
  }

  Widget _buildPeers(MeshController controller) {
    if (controller.peers.isEmpty) {
      return const _EmptyState(
        icon: Icons.portable_wifi_off,
        title: 'No hay dispositivos cercanos',
        description:
            'Mantén Bluetooth activo y acerca otro teléfono con HearthBit o BitChat.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: controller.peers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final peer = controller.peers[index];
        return ListTile(
          leading: CircleAvatar(
            child: Text(peer.nickname.characters.first.toUpperCase()),
          ),
          title: Text(peer.nickname),
          subtitle: Text(
            '${peer.id.substring(0, 8)} · ${peer.secure ? "canal cifrado listo" : "toca para cifrar"}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Radar de proximidad',
                onPressed: () => _openRadar(
                  peerId: peer.id,
                  nickname: peer.nickname,
                ),
                icon: const Icon(Icons.radar),
              ),
              IconButton(
                tooltip: 'Enviar archivo',
                onPressed: () => _sendFileTo(peer),
                icon: const Icon(Icons.attach_file),
              ),
              Icon(peer.secure ? Icons.lock : Icons.lock_open),
            ],
          ),
          onTap: () => _openPrivateChat(controller, peer),
        );
      },
    );
  }

  Widget _buildSos(MeshController controller) {
    final sosMessages = controller.messages
        .where((message) => message.isSos)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.sos,
                  size: 52,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Enviar alerta prioritaria',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Se intentará incluir tu ubicación GPS. La alerta será pública y se retransmitirá por la malla.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: controller.canSend
                          ? () => controller.sendSos('Necesito ayuda médica')
                          : null,
                      child: const Text('AYUDA MÉDICA'),
                    ),
                    FilledButton.tonal(
                      onPressed: controller.canSend
                          ? () => controller.sendSos('Estoy atrapado')
                          : null,
                      child: const Text('ESTOY ATRAPADO'),
                    ),
                    FilledButton.tonal(
                      onPressed: controller.canSend
                          ? () => controller.sendSos('Estoy bien')
                          : null,
                      child: const Text('ESTOY BIEN'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        RescueModeCard(controller: controller),
        const SizedBox(height: 12),
        PowerSavingCard(controller: controller),
        const SizedBox(height: 16),
        Text(
          'Alertas recibidas',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (sosMessages.isEmpty)
          const Text('No se han recibido alertas SOS.')
        else
          ...sosMessages.map(
            (message) => Card(
              child: ListTile(
                leading: const Icon(Icons.crisis_alert),
                title: Text(message.sender),
                subtitle: Text(
                  message.sosLatitude != null
                      ? '${message.sosDescription}\n'
                            'GPS ${message.sosLatitude!.toStringAsFixed(5)}, '
                            '${message.sosLongitude!.toStringAsFixed(5)}'
                      : message.sosDescription,
                ),
                isThreeLine: message.sosLatitude != null,
                trailing: message.isMine
                    ? null
                    : FilledButton.tonalIcon(
                        onPressed: () => _openRadar(
                          peerId: message.senderPeerId,
                          nickname: message.sender,
                          latitude: message.sosLatitude,
                          longitude: message.sosLongitude,
                        ),
                        icon: const Icon(Icons.radar, size: 18),
                        label: const Text('RASTREAR'),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openPrivateChat(
    MeshController controller,
    MeshPeer peer,
  ) async {
    final textController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final privateMessages = controller.messages
            .where(
              (message) => message.isPrivate && message.senderPeerId == peer.id,
            )
            .toList(growable: false);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        peer.nickname,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: privateMessages.isEmpty
                      ? const Center(
                          child: Text(
                            'El primer mensaje iniciará un handshake Noise XX.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView(
                          children: privateMessages
                              .map(
                                (message) => _MessageBubble(message: message),
                              )
                              .toList(growable: false),
                        ),
                ),
                _MessageComposer(
                  controller: textController,
                  enabled: true,
                  hint: 'Mensaje cifrado',
                  onSend: () async {
                    final text = textController.text;
                    textController.clear();
                    await controller.sendPrivate(peer, text);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    textController.dispose();
  }

  Future<void> _changeNickname(MeshController controller) async {
    final textController = TextEditingController(text: controller.nickname);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre visible'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 31,
          decoration: const InputDecoration(hintText: 'Ej. Casa 12 o Ana'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (value != null) await controller.updateNickname(value);
  }

  Future<void> _confirmWipe(MeshController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar toda la identidad?'),
        content: const Text(
          'Se eliminarán claves, historial y mensajes pendientes. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('BORRAR TODO'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.transfers.wipe();
      await controller.panicWipe();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = controller.status;
    final (color, icon, label) = switch (status) {
      MeshConnectionStatus.active => (
        scheme.primaryContainer,
        Icons.bluetooth_connected,
        '${controller.nickname} · ${controller.peers.length} cercanos',
      ),
      MeshConnectionStatus.degraded => (
        scheme.tertiaryContainer,
        Icons.bluetooth_searching,
        '${controller.nickname} · solo recepción (sin anuncio BLE)',
      ),
      MeshConnectionStatus.starting => (
        scheme.surfaceContainerHighest,
        Icons.bluetooth_searching,
        'Iniciando malla…',
      ),
      MeshConnectionStatus.error => (
        scheme.errorContainer,
        Icons.bluetooth_disabled,
        'Error en la malla',
      ),
      MeshConnectionStatus.stopped => (
        scheme.surfaceContainerHighest,
        Icons.bluetooth_disabled,
        'Malla detenida',
      ),
    };
    return ColoredBox(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            if (status == MeshConnectionStatus.starting)
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (status == MeshConnectionStatus.active)
              FilledButton.tonal(
                onPressed: controller.stop,
                child: const Text('DETENER'),
              )
            else if (status == MeshConnectionStatus.degraded)
              FilledButton.tonal(
                onPressed: controller.start,
                child: const Text('REINICIAR'),
              )
            else
              FilledButton.tonal(
                onPressed: controller.start,
                child: const Text('ACTIVAR'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 240,
              decoration: InputDecoration(
                hintText: hint,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final MeshMessage message;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isMine
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final color = message.isSos
        ? Theme.of(context).colorScheme.errorContainer
        : message.isMine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isPrivate) ...[
                  const Icon(Icons.lock, size: 14),
                  const SizedBox(width: 4),
                ],
                Text(
                  message.sender,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(message.content.replaceFirst('SOS|', 'SOS: ')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
