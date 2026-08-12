import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';
import '../models/mesh_models.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, super.key});

  final MeshController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  int _tab = 0;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('EmergencyCom'),
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
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum),
                label: 'Canal',
              ),
              NavigationDestination(
                icon: Icon(Icons.hub_outlined),
                selectedIcon: Icon(Icons.hub),
                label: 'Cercanos',
              ),
              NavigationDestination(
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
          enabled: controller.status == MeshConnectionStatus.active,
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
            'Mantén Bluetooth activo y acerca otro teléfono con EmergencyCom o BitChat.',
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
          trailing: Icon(peer.secure ? Icons.lock : Icons.lock_open),
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
                      onPressed:
                          controller.status == MeshConnectionStatus.active
                          ? () => controller.sendSos('Necesito ayuda médica')
                          : null,
                      child: const Text('AYUDA MÉDICA'),
                    ),
                    FilledButton.tonal(
                      onPressed:
                          controller.status == MeshConnectionStatus.active
                          ? () => controller.sendSos('Estoy atrapado')
                          : null,
                      child: const Text('ESTOY ATRAPADO'),
                    ),
                    FilledButton.tonal(
                      onPressed:
                          controller.status == MeshConnectionStatus.active
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
                subtitle: Text(message.content.replaceFirst('SOS|', '')),
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
    if (confirmed == true) await controller.panicWipe();
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
    final active = controller.status == MeshConnectionStatus.active;
    return ColoredBox(
      color: active
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(active ? Icons.bluetooth_connected : Icons.bluetooth_disabled),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                active
                    ? '${controller.nickname} · ${controller.peers.length} cercanos'
                    : 'Malla detenida',
              ),
            ),
            if (controller.status == MeshConnectionStatus.starting)
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              FilledButton.tonal(
                onPressed: active ? controller.stop : controller.start,
                child: Text(active ? 'DETENER' : 'ACTIVAR'),
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
