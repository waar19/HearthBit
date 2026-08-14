class CompassCalibrationGate {
  CompassCalibrationGate({
    this.enterThresholdDegrees = 25,
    this.exitThresholdDegrees = 15,
    this.holdDuration = const Duration(seconds: 2),
  }) : assert(exitThresholdDegrees < enterThresholdDegrees);

  final double enterThresholdDegrees;
  final double exitThresholdDegrees;
  final Duration holdDuration;

  bool _needsCalibration = false;
  DateTime? _candidateSince;

  bool get needsCalibration => _needsCalibration;

  bool update(double? accuracyDegrees, DateTime at) {
    if (accuracyDegrees == null || !accuracyDegrees.isFinite) {
      _candidateSince = null;
      return _needsCalibration;
    }

    final wantsTransition = _needsCalibration
        ? accuracyDegrees < exitThresholdDegrees
        : accuracyDegrees > enterThresholdDegrees;
    if (!wantsTransition) {
      _candidateSince = null;
      return _needsCalibration;
    }

    final candidateSince = _candidateSince;
    if (candidateSince == null) {
      _candidateSince = at;
      return _needsCalibration;
    }
    if (at.difference(candidateSince) >= holdDuration) {
      _needsCalibration = !_needsCalibration;
      _candidateSince = null;
    }
    return _needsCalibration;
  }

  void reset() {
    _needsCalibration = false;
    _candidateSince = null;
  }
}
