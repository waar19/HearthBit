import 'dart:math' as math;

import '../models/mesh_models.dart';
import '../models/rescue_case_models.dart';

enum RescuePriority { low, medium, high, critical }

class RescueCaseCluster {
  const RescueCaseCluster({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.cases,
    required this.maximumPriority,
  });

  final String id;
  final double latitude;
  final double longitude;
  final List<RescueCase> cases;
  final RescuePriority maximumPriority;

  bool get isCluster => cases.length > 1;
}

abstract final class RescueCaseClusterer {
  static List<RescueCaseCluster> cluster(
    Iterable<RescueCase> cases, {
    required double zoom,
  }) {
    final normalizedZoom = zoom.clamp(2, 20);
    final cellSize = 360 / math.pow(2, normalizedZoom + 4);
    final buckets = <String, List<RescueCase>>{};
    for (final rescueCase in cases) {
      final latitude = rescueCase.latitude;
      final longitude = rescueCase.longitude;
      if (latitude == null ||
          longitude == null ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        continue;
      }
      final row = ((latitude + 90) / cellSize).floor();
      final column = ((longitude + 180) / cellSize).floor();
      final key = '$row:$column';
      (buckets[key] ??= []).add(rescueCase);
    }

    final keys = buckets.keys.toList()..sort();
    return keys
        .map((key) {
          final members = buckets[key]!
            ..sort(
              (first, second) => first.caseHash.compareTo(second.caseHash),
            );
          var latitude = 0.0;
          var longitude = 0.0;
          var maximumPriority = RescuePriority.low;
          for (final member in members) {
            latitude += member.latitude!;
            longitude += member.longitude!;
            final priority = priorityForTriage(member.triage);
            if (priority.index > maximumPriority.index) {
              maximumPriority = priority;
            }
          }
          return RescueCaseCluster(
            id: key,
            latitude: latitude / members.length,
            longitude: longitude / members.length,
            cases: List.unmodifiable(members),
            maximumPriority: maximumPriority,
          );
        })
        .toList(growable: false);
  }

  static RescuePriority priorityForTriage(SosTriage? triage) {
    if (triage == null) return RescuePriority.low;
    var score = 0;
    if (triage.injuryStatus == SosInjuryStatus.injured) score += 4;
    if (triage.trappedStatus == SosTrappedStatus.yes) score += 3;
    score += switch (triage.primaryNeed) {
      SosPrimaryNeed.medical => 3,
      SosPrimaryNeed.extraction => 2,
      SosPrimaryNeed.water || SosPrimaryNeed.shelter => 1,
      SosPrimaryNeed.other => 0,
    };
    if (score >= 8) return RescuePriority.critical;
    if (score >= 5) return RescuePriority.high;
    if (score >= 2) return RescuePriority.medium;
    return RescuePriority.low;
  }
}
