import '../services/sealed_transfer_package.dart';

class PendingSealedImport {
  const PendingSealedImport({
    required this.packagePath,
    required this.metadata,
  });

  final String packagePath;
  final SealedPackageMetadata metadata;
}
