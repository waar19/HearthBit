String emergencyQrFallbackText({
  required String content,
  required String peerId,
  required String defaultMessage,
}) {
  final fields = content.split('|');
  final description = fields.length > 1 && fields[1].trim().isNotEmpty
      ? fields[1].trim()
      : defaultMessage;
  final coordinates =
      fields.length > 3 &&
          fields[2].trim().isNotEmpty &&
          fields[3].trim().isNotEmpty
      ? '\nGPS: ${fields[2].trim()}, ${fields[3].trim()}'
      : '';
  return 'HEARTHBIT SOS\n$description$coordinates\nID: $peerId';
}
