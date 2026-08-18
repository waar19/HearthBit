import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/authority_announcement_models.dart';
import '../models/mesh_models.dart';
import '../models/rescue_roster_models.dart';
import 'mesh_controller.dart';
import 'rescue_roster_controller.dart';

class AuthorityAnnouncementController extends ChangeNotifier {
  AuthorityAnnouncementController({
    required this.mesh,
    required this.roster,
    Random? secureRandom,
    DateTime Function()? now,
  }) : _random = secureRandom ?? Random.secure(),
       _now = now ?? DateTime.now;

  static const String channel = 'authority';
  static const Duration maximumFutureSkew = Duration(minutes: 5);
  static const int maximumRetainedAnnouncements = 100;
  static const int maximumProcessedMessageIds = 1000;

  final MeshController mesh;
  final RescueRosterController roster;
  final Random _random;
  final DateTime Function() _now;
  final Map<String, AuthorityAnnouncement> _announcementsById = {};
  final Set<String> _processedMessageIds = {};

  bool _disposed = false;
  bool _processing = false;
  bool _processingRequested = false;
  Timer? _expiryTimer;
  String? lastError;

  List<AuthorityAnnouncement> get announcements {
    final result = _announcementsById.values.toList(growable: false)
      ..sort(_compareAnnouncements);
    return List.unmodifiable(result);
  }

  AuthorityAnnouncement? get activeAnnouncement {
    final now = _now().toUtc();
    final active =
        _announcementsById.values
            .where((announcement) => announcement.isActiveAt(now))
            .toList(growable: false)
          ..sort((first, second) {
            final priorityOrder = second.priority.index.compareTo(
              first.priority.index,
            );
            if (priorityOrder != 0) return priorityOrder;
            return _compareAnnouncements(first, second);
          });
    return active.firstOrNull;
  }

  RescueRosterMember? get localMember => roster.verifiedMember(
    peerId: mesh.peerId,
    signingPublicKey: mesh.signingPublicKey,
  );

  bool get canIssue => localMember?.role == RescueRosterRole.authority;

  Future<void> initialize() async {
    mesh.addListener(_handleMeshChanged);
    roster.addListener(_handleRosterChanged);
    await _processMessages();
  }

  Future<AuthorityAnnouncement> issue({
    required AuthorityAnnouncementPriority priority,
    required String body,
    required Duration lifetime,
  }) async {
    final activeRoster = roster.activeRoster;
    final member = localMember;
    if (activeRoster == null ||
        member == null ||
        member.role != RescueRosterRole.authority) {
      throw StateError(
        'Only an authority roster member can issue announcements',
      );
    }
    final issuedAt = _now().toUtc();
    final announcement = AuthorityAnnouncement(
      version: AuthorityAnnouncementCodec.version,
      announcementId: _randomHex(16),
      teamId: activeRoster.teamId,
      actorPeerId: member.peerId,
      priority: priority,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(lifetime),
      body: body.trim(),
      callsign: member.callsign,
    );
    final encoded = AuthorityAnnouncementCodec.encode(announcement);
    final messageId = await mesh.sendPublic(encoded, channel: channel);
    if (messageId == null || messageId.isEmpty) {
      throw StateError('Authority announcement was not transmitted');
    }
    _accept(announcement);
    lastError = null;
    if (!_disposed) notifyListeners();
    return announcement;
  }

  void _handleMeshChanged() {
    unawaited(_processMessages());
  }

  void _handleRosterChanged() {
    _processedMessageIds.clear();
    _announcementsById.clear();
    unawaited(_processMessages());
  }

  Future<void> _processMessages() async {
    if (_processing) {
      _processingRequested = true;
      return;
    }
    _processing = true;
    try {
      do {
        _processingRequested = false;
        final messages = mesh.messages.toList(growable: false)
          ..sort((first, second) {
            final timestampOrder = first.timestamp.compareTo(second.timestamp);
            return timestampOrder != 0
                ? timestampOrder
                : first.id.compareTo(second.id);
          });
        for (final message in messages) {
          if (_processedMessageIds.contains(message.id) ||
              message.isPrivate ||
              message.external ||
              message.channel != channel ||
              !message.content.startsWith(AuthorityAnnouncementCodec.marker)) {
            continue;
          }
          _ingest(message);
          _processedMessageIds.add(message.id);
          if (_processedMessageIds.length > maximumProcessedMessageIds) {
            _processedMessageIds.remove(_processedMessageIds.first);
          }
        }
      } while (_processingRequested);
      lastError = null;
    } catch (error) {
      lastError = error.toString();
    } finally {
      _processing = false;
      _scheduleExpiry();
      if (!_disposed) notifyListeners();
    }
  }

  void _ingest(MeshMessage message) {
    final senderPeerId = message.senderPeerId.trim().toLowerCase();
    final member = _memberByPeerId(senderPeerId);
    if (member == null || member.role != RescueRosterRole.authority) return;
    final announcement = AuthorityAnnouncementCodec.tryDecode(
      message.content,
      callsign: member.callsign,
    );
    final activeRoster = roster.activeRoster;
    final now = _now().toUtc();
    if (announcement == null ||
        activeRoster == null ||
        announcement.actorPeerId != senderPeerId ||
        announcement.teamId != activeRoster.teamId ||
        announcement.issuedAt.isAfter(now.add(maximumFutureSkew)) ||
        !announcement.expiresAt.isAfter(now)) {
      return;
    }
    _accept(announcement);
  }

  void _accept(AuthorityAnnouncement announcement) {
    if (_announcementsById.containsKey(announcement.announcementId)) return;
    _announcementsById[announcement.announcementId] = announcement;
    if (_announcementsById.length > maximumRetainedAnnouncements) {
      final ordered = _announcementsById.values.toList(growable: false)
        ..sort(_compareAnnouncements);
      for (final removed in ordered.skip(maximumRetainedAnnouncements)) {
        _announcementsById.remove(removed.announcementId);
      }
    }
    _scheduleExpiry();
  }

  RescueRosterMember? _memberByPeerId(String peerId) {
    for (final member in roster.members) {
      if (member.peerId == peerId) return member;
    }
    return null;
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final now = _now().toUtc();
    final expirations =
        _announcementsById.values
            .map((announcement) => announcement.expiresAt)
            .where((expiresAt) => expiresAt.isAfter(now))
            .toList(growable: false)
          ..sort();
    if (expirations.isEmpty) return;
    _expiryTimer = Timer(expirations.first.difference(now), () {
      if (!_disposed) notifyListeners();
      _scheduleExpiry();
    });
  }

  String _randomHex(int byteCount) => List<int>.generate(
    byteCount,
    (_) => _random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static int _compareAnnouncements(
    AuthorityAnnouncement first,
    AuthorityAnnouncement second,
  ) {
    final issuedOrder = second.issuedAt.compareTo(first.issuedAt);
    return issuedOrder != 0
        ? issuedOrder
        : first.announcementId.compareTo(second.announcementId);
  }

  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    mesh.removeListener(_handleMeshChanged);
    roster.removeListener(_handleRosterChanged);
    super.dispose();
  }
}
