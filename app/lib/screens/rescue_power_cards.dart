import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/mesh_controller.dart';

/// Tarjeta del modo rescate: reenvía el SOS con GPS fresco periódicamente
/// para que los rescatistas puedan seguir la posición de la persona.
class RescueModeCard extends StatelessWidget {
  const RescueModeCard({required this.controller, super.key});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final minutes = MeshController.rescueInterval.inMinutes;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.my_location),
            title: const Text(
              'Modo rescate',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              controller.rescueMode
                  ? 'Reenviando tu SOS con ubicación cada $minutes min.'
                        '${controller.lastRescuePing != null ? " Último envío: ${_hourLabel(controller.lastRescuePing!)}." : ""}'
                  : 'Reenvía tu SOS con GPS actualizado cada $minutes minutos, '
                        'incluso con la pantalla apagada.',
            ),
            value: controller.rescueMode,
            onChanged: controller.canSend
                ? (value) => controller.setRescueMode(value)
                : null,
          ),
          if (controller.rescueMode && !controller.backgroundLocationGranted)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Sin ubicación permanente, el GPS solo se actualiza con '
                      'la app abierta.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: controller.ensureAlwaysLocation,
                    child: const Text('PERMITIR'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _hourLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Lista de verificación de energía: qué desactivar o conceder para que la
/// malla y el GPS sobrevivan en segundo plano sin agotar la batería.
class PowerSavingCard extends StatelessWidget {
  const PowerSavingCard({required this.controller, super.key});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              leading: Icon(Icons.battery_saver),
              title: Text(
                'Batería y ubicación',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Ajustes para que la malla siga latiendo y los rescatistas '
                'puedan ubicarte.',
              ),
            ),
            if (isAndroid)
              _StatusRow(
                ok: controller.ignoringBatteryOptimizations,
                label: 'Optimización de batería desactivada para HearthBit',
                actionLabel: 'DESACTIVAR',
                onAction: controller.requestDisableBatteryOptimizations,
              ),
            _StatusRow(
              ok: controller.backgroundLocationGranted,
              label: isAndroid
                  ? 'Ubicación permitida «todo el tiempo»'
                  : 'Ubicación permitida «siempre»',
              actionLabel: 'PERMITIR',
              onAction: controller.ensureAlwaysLocation,
            ),
            if (controller.lowPowerMode)
              _StatusRow(
                ok: false,
                label: isAndroid
                    ? 'El ahorro de batería del sistema está activo y puede '
                          'apagar la malla'
                    : 'El Modo de bajo consumo está activo y reduce el '
                          'Bluetooth en segundo plano',
              ),
            ExpansionTile(
              leading: const Icon(Icons.tips_and_updates_outlined),
              title: const Text('Consejos para ahorrar batería'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final tip in _tips(isAndroid))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• $tip',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _tips(bool isAndroid) => [
    'Baja el brillo de la pantalla al mínimo y reduce el tiempo de bloqueo.',
    'Si no hay internet, desactiva los datos móviles y el 5G: la malla no '
        'los usa y la búsqueda de señal gasta mucha batería.',
    'Cierra las apps que no necesites; deja Bluetooth y ubicación activos.',
    if (isAndroid) ...[
      'No cierres HearthBit desde «recientes»: el sistema mataría la malla.',
      'Algunos fabricantes (Xiaomi, Huawei, Samsung) tienen su propio '
          'ahorro de energía: excluye a HearthBit también allí.',
      'Desactiva la sincronización automática de cuentas mientras dure la '
          'emergencia.',
    ] else ...[
      'No fuerces el cierre de HearthBit: iOS no la relanza sola.',
      'Desactiva «Actualización en segundo plano» de otras apps en Ajustes.',
      'Evita el Modo de bajo consumo salvo que HearthBit esté en pantalla: '
          'reduce el Bluetooth en segundo plano.',
    ],
    'Comparte batería externa entre vecinos: un solo teléfono encendido '
        'mantiene el enlace de toda la manzana.',
  ];
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.ok,
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  final bool ok;
  final String label;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? scheme.primary : scheme.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          if (!ok && onAction != null)
            TextButton(
              onPressed: () => onAction!(),
              child: Text(actionLabel ?? 'AJUSTAR'),
            ),
        ],
      ),
    );
  }
}
