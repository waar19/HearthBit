import AVFoundation
import AudioToolbox
import Foundation
import UIKit

final class IOSBeaconActuator {
  private struct PulseStep {
    let on: Bool
    let duration: TimeInterval
  }

  private static let sosPattern = [
    PulseStep(on: true, duration: 0.2), PulseStep(on: false, duration: 0.2),
    PulseStep(on: true, duration: 0.2), PulseStep(on: false, duration: 0.2),
    PulseStep(on: true, duration: 0.2), PulseStep(on: false, duration: 0.6),
    PulseStep(on: true, duration: 0.6), PulseStep(on: false, duration: 0.2),
    PulseStep(on: true, duration: 0.6), PulseStep(on: false, duration: 0.2),
    PulseStep(on: true, duration: 0.6), PulseStep(on: false, duration: 0.6),
    PulseStep(on: true, duration: 0.2), PulseStep(on: false, duration: 0.2),
    PulseStep(on: true, duration: 0.2), PulseStep(on: false, duration: 0.2),
    PulseStep(on: true, duration: 0.2), PulseStep(on: false, duration: 1.4),
  ]

  private var pulseTimer: Timer?
  private var expiryTimer: Timer?
  private var pulseIndex = 0
  private(set) var flags: UInt8 = 0
  private(set) var expiresAt: UInt64 = 0
  private var expiration: (() -> Void)?

  var isActive: Bool {
    expiresAt > UInt64(Date().timeIntervalSince1970 * 1000)
  }

  @discardableResult
  func start(flags: UInt8, expiresAt: UInt64, onExpired: @escaping () -> Void) -> Bool {
    precondition(Thread.isMainThread)
    let now = UInt64(Date().timeIntervalSince1970 * 1000)
    guard
      UIApplication.shared.applicationState == .active,
      flags != 0,
      flags & ~IOSBeaconControlProtocol.allowedFlags == 0,
      expiresAt > now,
      expiresAt <= now + IOSBeaconControlProtocol.maximumDurationMilliseconds
    else { return false }
    let hasTorch = flags & IOSBeaconControlProtocol.flashFlag != 0 &&
      AVCaptureDevice.default(for: .video)?.hasTorch == true
    let hasSound = flags & IOSBeaconControlProtocol.soundFlag != 0
    let hasHaptics = flags & IOSBeaconControlProtocol.vibrateFlag != 0
    guard hasTorch || hasSound || hasHaptics else { return false }

    stop()
    self.flags = flags
    self.expiresAt = expiresAt
    expiration = onExpired
    pulseIndex = 0
    scheduleNextPulse()
    expiryTimer = Timer.scheduledTimer(
      withTimeInterval: TimeInterval(expiresAt - now) / 1000,
      repeats: false
    ) { [weak self] _ in self?.expire() }
    return true
  }

  func stop() {
    precondition(Thread.isMainThread)
    pulseTimer?.invalidate()
    expiryTimer?.invalidate()
    pulseTimer = nil
    expiryTimer = nil
    setTorch(false)
    flags = 0
    expiresAt = 0
    expiration = nil
  }

  private func scheduleNextPulse() {
    guard isActive, UIApplication.shared.applicationState == .active else {
      expire()
      return
    }
    let step = Self.sosPattern[pulseIndex]
    pulseIndex = (pulseIndex + 1) % Self.sosPattern.count
    apply(step)
    pulseTimer = Timer.scheduledTimer(
      withTimeInterval: step.duration,
      repeats: false
    ) { [weak self] _ in self?.scheduleNextPulse() }
  }

  private func apply(_ step: PulseStep) {
    if flags & IOSBeaconControlProtocol.flashFlag != 0 {
      setTorch(step.on)
    }
    guard step.on else { return }
    if flags & IOSBeaconControlProtocol.soundFlag != 0 {
      AudioServicesPlaySystemSound(1005)
    }
    if flags & IOSBeaconControlProtocol.vibrateFlag != 0 {
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      let feedback = UINotificationFeedbackGenerator()
      feedback.prepare()
      feedback.notificationOccurred(.warning)
    }
  }

  private func setTorch(_ enabled: Bool) {
    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      if enabled {
        try device.setTorchModeOn(level: 1)
      } else {
        device.torchMode = .off
      }
    } catch {
      // La baliza sigue con los actuadores disponibles.
    }
  }

  private func expire() {
    guard isActive || expiration != nil else { return }
    let callback = expiration
    stop()
    callback?()
  }
}
