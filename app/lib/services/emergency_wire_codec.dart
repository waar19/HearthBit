import 'dart:convert';
import 'dart:typed_data';

final class EmergencyWireFrame {
  const EmergencyWireFrame({
    required this.version,
    required this.type,
    required this.isDrill,
    required this.senderId,
    required this.payload,
  });

  final int version;
  final int type;
  final bool isDrill;
  final Uint8List senderId;
  final Uint8List payload;
}

final class EmergencyWireBundle {
  const EmergencyWireBundle({required this.isDrill});

  final bool isDrill;
}

abstract final class EmergencyWireCodec {
  static const int announceType = 0x01;
  static const int messageType = 0x02;
  static const int signatureFlag = 0x02;
  static const int compressionFlag = 0x04;
  static const int routeFlag = 0x08;
  static const int drillFlag = 0x20;
  static const String drillMarker = '[HB-DRILL|1|CHECKIN|';

  static EmergencyWireBundle? decodeBundle(
    Uint8List announcementBytes,
    Uint8List messageBytes,
  ) {
    final announcement = decode(announcementBytes);
    final message = decode(messageBytes);
    if (announcement == null ||
        message == null ||
        announcement.type != announceType ||
        message.type != messageType ||
        announcement.isDrill != message.isDrill ||
        !_sameBytes(announcement.senderId, message.senderId) ||
        !_hasEmergencyPreannounce(announcement.payload)) {
      return null;
    }
    if (!message.isDrill) {
      return const EmergencyWireBundle(isDrill: false);
    }
    final content = _utf8(message.payload);
    return content != null && _isDrillPayload(content)
        ? const EmergencyWireBundle(isDrill: true)
        : null;
  }

  static EmergencyWireFrame? decode(Uint8List input) {
    if (input.length < 22) return null;
    final version = input[0];
    if (version != 1 && version != 2) return null;
    if (input.length < (version == 1 ? 22 : 24)) return null;
    final type = input[1];
    final flags = input[11];
    final isDrill = flags & drillFlag != 0;
    if (!isDrill) return _decodeOrdinary(input, version, type, flags);
    if (version != 1 ||
        type != announceType && type != messageType ||
        flags & signatureFlag == 0 ||
        flags & (0x01 | compressionFlag | routeFlag) != 0) {
      return null;
    }
    return _decodeOrdinary(input, version, type, flags);
  }

  static EmergencyWireFrame? _decodeOrdinary(
    Uint8List input,
    int version,
    int type,
    int flags,
  ) {
    final data = ByteData.sublistView(input);
    final headerLength = version == 1 ? 22 : 24;
    final payloadLength = version == 1
        ? data.getUint16(12)
        : data.getUint32(12);
    var offset = headerLength;
    if (flags & 0x01 != 0) offset += 8;
    if (version == 2 && flags & routeFlag != 0) {
      if (offset >= input.length) return null;
      offset += 1 + input[offset] * 8;
    }
    final signatureLength = flags & signatureFlag != 0 ? 64 : 0;
    final end = offset + payloadLength;
    if (offset > input.length ||
        end > input.length ||
        end + signatureLength != input.length) {
      return null;
    }
    final payload = Uint8List.fromList(input.sublist(offset, end));
    final senderOffset = version == 1 ? 14 : 16;
    final senderId = Uint8List.fromList(
      input.sublist(senderOffset, senderOffset + 8),
    );
    final content = type == messageType ? _utf8(payload) : null;
    final isDrill = flags & drillFlag != 0;
    if (content != null &&
        (isDrill
            ? !_isDrillPayload(content)
            : content.contains('[HB-DRILL|'))) {
      return null;
    }
    return EmergencyWireFrame(
      version: version,
      type: type,
      isDrill: isDrill,
      senderId: senderId,
      payload: payload,
    );
  }

  static bool _hasEmergencyPreannounce(Uint8List payload) {
    var offset = 0;
    while (offset < payload.length) {
      if (offset + 2 > payload.length) return false;
      final type = payload[offset++];
      final length = payload[offset++];
      if (offset + length > payload.length) return false;
      if (type == 0xf1) {
        return length == 1 && payload[offset] == 0x01;
      }
      offset += length;
    }
    return false;
  }

  static bool _isDrillPayload(String content) {
    if (_isRealEmergencyPayload(content) || !content.endsWith(']')) {
      return false;
    }
    final marker = content.lastIndexOf(drillMarker);
    if (marker <= 0) return false;
    final fields = content
        .substring(marker + drillMarker.length, content.length - 1)
        .split('|');
    final timestamp = fields.length == 2 ? int.tryParse(fields[1]) : null;
    return fields.length == 2 &&
        const {'OK', 'HELP', 'INJURED'}.contains(fields[0]) &&
        timestamp != null &&
        timestamp > 0;
  }

  static bool _isRealEmergencyPayload(String content) =>
      content.startsWith('SOS|') || content.contains('[HB-CHECKIN|');

  static String? _utf8(Uint8List payload) {
    try {
      return utf8.decode(payload);
    } on FormatException {
      return null;
    }
  }

  static bool _sameBytes(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
