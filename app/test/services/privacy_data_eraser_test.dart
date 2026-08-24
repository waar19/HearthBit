// Spec Hueco 8 (HearthBit panic wipe) — PrivacyDataEraser.clearResidualFiles.
//
// Verifica que el sub-wipe de archivos residuales cumple tres propiedades:
//   1. Solo elimina archivos cuyos nombres empiezan por los cinco prefijos
//      conocidos (hearthbit_voice_, hb_, hearthbit-rescue-,
//      hearthbit-diagnostics-, hearthbit_plain_).
//   2. Archivos con cualquier otro prefijo quedan intactos.
//   3. El método es idempotente: dos llamadas seguidas dejan el mismo estado
//      final (cubre doble pulsación de la UI y reintento tras crash mid-wipe).
//
// Stubs de plataforma:
//   - PathProviderPlatform: clearResidualFiles invoca getTemporaryDirectory()
//     y, a través de OfflineTileCache.clearAll(), getApplicationSupportDirectory().
//     Sin un fake, path_provider lanza MissingPluginException en tests.
//   - FlutterSecureStoragePlatform: AtRestFileCipher.destroyKey() delega en
//     FlutterSecureStorage.delete() que a su vez invoca el platform. Sin un
//     fake, el method channel devuelve MissingPluginException. Sólo se necesita
//     implementar delete; el resto se incluye para que la subclase sea
//     concreta y verificable por el PlatformInterface token.

import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/privacy_data_eraser.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider({
    required this.temporaryPath,
    required this.applicationSupportPath,
  });

  final String temporaryPath;
  final String applicationSupportPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;
}

class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _store = {};

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _store.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _store.containsKey(key);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _store[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map<String, String>.of(_store);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _store.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory supportRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('hb_eraser_test_');
    supportRoot = await Directory.systemTemp.createTemp('hb_eraser_support_');

    PathProviderPlatform.instance = _FakePathProvider(
      temporaryPath: tempRoot.path,
      applicationSupportPath: supportRoot.path,
    );
    FlutterSecureStoragePlatform.instance = _InMemorySecureStorage();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
    if (await supportRoot.exists()) {
      await supportRoot.delete(recursive: true);
    }
  });

  // Caso principal del task: el filtro de prefijos debe dejar intacto todo
  // archivo cuyo nombre no comience por uno de los cinco prefijos conocidos.
  test(
    'clearResidualFiles borra solo archivos con prefijos conocidos',
    () async {
      // Nombres que DEBEN eliminarse (los cinco prefijos del implementation).
      const debenDesaparecer = <String>[
        'hearthbit_voice_123.aac',
        'hb_capture.bin',
        'hearthbit-rescue-archive-001.tmp',
        'hearthbit-diagnostics-2025-08-24.txt',
        'hearthbit_plain_msg_42',
      ];
      // Nombres que NO deben tocarse: prefijo ajeno, sin prefijo hearthbit,
      // o hearthbit con un sufijo que no coincide con ningún prefijo.
      const debenPermanecer = <String>[
        'random.txt',
        'user-upload.jpg',
        'image_cache_001.png',
        'hearthbit_export.csv', // sin '_' al final: no matchea
        'hearthbit.bin', // guion bajo ausente, no matchea
        'respaldo.db',
      ];
      for (final nombre in debenDesaparecer) {
        await File(p.join(tempRoot.path, nombre)).writeAsString('residuo');
      }
      for (final nombre in debenPermanecer) {
        await File(p.join(tempRoot.path, nombre)).writeAsString('no-tocar');
      }

      await PrivacyDataEraser.clearResidualFiles();

      for (final nombre in debenDesaparecer) {
        expect(
          await File(p.join(tempRoot.path, nombre)).exists(),
          isFalse,
          reason: '$nombre debería haber sido eliminado por '
              'clearResidualFiles()',
        );
      }
      for (final nombre in debenPermanecer) {
        expect(
          await File(p.join(tempRoot.path, nombre)).exists(),
          isTrue,
          reason: '$nombre NO debería haber sido eliminado por '
              'clearResidualFiles() (prefijo no reconocido)',
        );
      }
    },
  );

  // Idempotencia (Hueco 7): llamar clearResidualFiles() dos veces seguidas
  // sobre el mismo directorio no debe lanzar y debe dejar el mismo estado
  // final. Cubre doble pulsación de la UI y reintento tras crash mid-wipe.
  test('clearResidualFiles es idempotente', () async {
    const debenDesaparecer = <String>[
      'hearthbit_voice_a.aac',
      'hb_b.bin',
      'hearthbit-rescue-001.tmp',
      'hearthbit-diagnostics-buf.txt',
      'hearthbit_plain_c',
    ];
    const debenPermanecer = <String>['keep.txt', 'unrelated.bin'];
    for (final nombre in debenDesaparecer) {
      await File(p.join(tempRoot.path, nombre)).writeAsString('x');
    }
    for (final nombre in debenPermanecer) {
      await File(p.join(tempRoot.path, nombre)).writeAsString('y');
    }

    await PrivacyDataEraser.clearResidualFiles();

    for (final nombre in debenDesaparecer) {
      expect(
        await File(p.join(tempRoot.path, nombre)).exists(),
        isFalse,
        reason: 'Tras la primera llamada, $nombre ya no debe existir',
      );
    }
    for (final nombre in debenPermanecer) {
      expect(
        await File(p.join(tempRoot.path, nombre)).exists(),
        isTrue,
        reason: 'Tras la primera llamada, $nombre debe seguir existiendo',
      );
    }

    // Segunda llamada sobre el mismo directorio: no debe lanzar, y el
    // estado final debe ser idéntico (los dos archivos que quedan son los
    // que no matchearon ningún prefijo).
    await PrivacyDataEraser.clearResidualFiles();

    final supervivientes = tempRoot
        .listSync()
        .whereType<File>()
        .map((entity) => p.basename(entity.path))
        .toSet();
    expect(
      supervivientes,
      debenPermanecer.toSet(),
      reason: 'La segunda llamada no debe alterar qué archivos quedan',
    );
  });

  // Sanity: clearResidualFiles() sobre un temporal vacío es un no-op seguro
  // (cubre el caso de un wipe cuando no hay archivos residuales que limpiar).
  test('clearResidualFiles sobre directorio vacío no lanza', () async {
    expect(tempRoot.listSync(), isEmpty);

    await PrivacyDataEraser.clearResidualFiles();

    expect(tempRoot.listSync(), isEmpty);
  });
}
