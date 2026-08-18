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
  static const double _earthRadiusMeters = 6371008.8;

  static List<RescueCaseCluster> cluster(
    Iterable<RescueCase> cases, {
    required double zoom,
  }) {
    final normalizedZoom = zoom.clamp(2, 20).toDouble();
    final angularRadiusDegrees =
        360 / math.pow(2, normalizedZoom + 4).toDouble();
    final angularRadiusRadians = _radians(angularRadiusDegrees);
    final maximumDistanceMeters = _earthRadiusMeters * angularRadiusRadians;
    final maximumChordMeters =
        2 * _earthRadiusMeters * math.sin(angularRadiusRadians / 2);
    final bucketSizeMeters = maximumChordMeters / math.sqrt(3);
    final validCases = <RescueCase>[];
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
      validCases.add(rescueCase);
    }
    validCases.sort(
      (first, second) => first.caseHash.compareTo(second.caseHash),
    );

    final unionFind = _UnionFind(validCases.length);
    final buckets = <_SpatialBucket, List<int>>{};
    for (var index = 0; index < validCases.length; index++) {
      final rescueCase = validCases[index];
      final point = _earthCenteredPoint(
        rescueCase.latitude!,
        rescueCase.longitude!,
      );
      final bucket = _SpatialBucket(
        (point.$1 / bucketSizeMeters).floor(),
        (point.$2 / bucketSizeMeters).floor(),
        (point.$3 / bucketSizeMeters).floor(),
      );
      final sameBucket = buckets[bucket];
      if (sameBucket != null) {
        // A bucket's 3D diagonal is exactly the clustering chord limit.
        unionFind.union(index, sameBucket.first);
      }
      for (var xOffset = -2; xOffset <= 2; xOffset++) {
        for (var yOffset = -2; yOffset <= 2; yOffset++) {
          for (var zOffset = -2; zOffset <= 2; zOffset++) {
            if (xOffset == 0 && yOffset == 0 && zOffset == 0) continue;
            final candidates =
                buckets[_SpatialBucket(
                  bucket.x + xOffset,
                  bucket.y + yOffset,
                  bucket.z + zOffset,
                )];
            if (candidates == null) continue;
            if (unionFind.find(index) == unionFind.find(candidates.first)) {
              continue;
            }
            for (final candidateIndex in candidates) {
              final candidate = validCases[candidateIndex];
              if (_distanceMeters(
                    rescueCase.latitude!,
                    rescueCase.longitude!,
                    candidate.latitude!,
                    candidate.longitude!,
                  ) <=
                  maximumDistanceMeters) {
                unionFind.union(index, candidateIndex);
                // All points in one bucket already share a component.
                break;
              }
            }
          }
        }
      }
      (buckets[bucket] ??= []).add(index);
    }

    final membersByRoot = <int, List<RescueCase>>{};
    for (var index = 0; index < validCases.length; index++) {
      (membersByRoot[unionFind.find(index)] ??= []).add(validCases[index]);
    }
    final clusters = membersByRoot.values.map(_buildCluster).toList()
      ..sort((first, second) => first.id.compareTo(second.id));
    return List.unmodifiable(clusters);
  }

  static RescueCaseCluster _buildCluster(List<RescueCase> members) {
    var latitudeSum = 0.0;
    var longitudeSinSum = 0.0;
    var longitudeCosSum = 0.0;
    var maximumPriority = RescuePriority.low;
    for (final member in members) {
      latitudeSum += member.latitude!;
      final longitudeRadians = _radians(member.longitude!);
      longitudeSinSum += math.sin(longitudeRadians);
      longitudeCosSum += math.cos(longitudeRadians);
      final priority = priorityForTriage(member.triage);
      if (priority.index > maximumPriority.index) {
        maximumPriority = priority;
      }
    }
    final longitude =
        math.atan2(longitudeSinSum, longitudeCosSum) * 180 / math.pi;
    return RescueCaseCluster(
      id: members.first.caseHash,
      latitude: latitudeSum / members.length,
      longitude: longitude,
      cases: List.unmodifiable(members),
      maximumPriority: maximumPriority,
    );
  }

  static (double, double, double) _earthCenteredPoint(
    double latitude,
    double longitude,
  ) {
    final latitudeRadians = _radians(latitude);
    final longitudeRadians = _radians(longitude);
    final latitudeCosine = math.cos(latitudeRadians);
    return (
      _earthRadiusMeters * latitudeCosine * math.cos(longitudeRadians),
      _earthRadiusMeters * latitudeCosine * math.sin(longitudeRadians),
      _earthRadiusMeters * math.sin(latitudeRadians),
    );
  }

  static double _distanceMeters(
    double firstLatitude,
    double firstLongitude,
    double secondLatitude,
    double secondLongitude,
  ) {
    final latitudeDelta = _radians(secondLatitude - firstLatitude);
    final longitudeDelta = _radians(secondLongitude - firstLongitude);
    final firstLatitudeRadians = _radians(firstLatitude);
    final secondLatitudeRadians = _radians(secondLatitude);
    final haversine =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(firstLatitudeRadians) *
            math.cos(secondLatitudeRadians) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    return _earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(math.max(0, 1 - haversine)));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

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

class _SpatialBucket {
  const _SpatialBucket(this.x, this.y, this.z);

  final int x;
  final int y;
  final int z;

  @override
  bool operator ==(Object other) =>
      other is _SpatialBucket && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}

class _UnionFind {
  _UnionFind(int length)
    : _parents = List<int>.generate(length, (index) => index),
      _ranks = List<int>.filled(length, 0);

  final List<int> _parents;
  final List<int> _ranks;

  int find(int value) {
    var root = value;
    while (_parents[root] != root) {
      root = _parents[root];
    }
    while (_parents[value] != value) {
      final parent = _parents[value];
      _parents[value] = root;
      value = parent;
    }
    return root;
  }

  void union(int first, int second) {
    final firstRoot = find(first);
    final secondRoot = find(second);
    if (firstRoot == secondRoot) return;
    if (_ranks[firstRoot] < _ranks[secondRoot]) {
      _parents[firstRoot] = secondRoot;
    } else if (_ranks[firstRoot] > _ranks[secondRoot]) {
      _parents[secondRoot] = firstRoot;
    } else {
      _parents[secondRoot] = firstRoot;
      _ranks[firstRoot] += 1;
    }
  }
}
