import CoreGraphics
import Foundation

public struct OneEuroFilterSettings: Codable, Equatable {
  public var minCutoff: Double
  public var beta: Double
  public var dCutoff: Double

  public init(minCutoff: Double = 1.0, beta: Double = 0.0, dCutoff: Double = 1.0) {
    self.minCutoff = minCutoff
    self.beta = beta
    self.dCutoff = dCutoff
  }
}

public struct OneEuroFilter {
  private var settings: OneEuroFilterSettings
  private var xFilter: OneEuroFilter1D
  private var yFilter: OneEuroFilter1D

  public init(settings: OneEuroFilterSettings = OneEuroFilterSettings()) {
    self.settings = settings
    self.xFilter = OneEuroFilter1D(settings: settings)
    self.yFilter = OneEuroFilter1D(settings: settings)
  }

  public mutating func update(settings: OneEuroFilterSettings) {
    guard settings != self.settings else { return }
    self.settings = settings
    self.xFilter = OneEuroFilter1D(settings: settings)
    self.yFilter = OneEuroFilter1D(settings: settings)
  }

  public mutating func reset(position: CGPoint, time: Double) {
    xFilter.reset(value: position.x, time: time)
    yFilter.reset(value: position.y, time: time)
  }

  public mutating func filter(position: CGPoint, time: Double) -> CGPoint {
    let x = xFilter.filter(value: position.x, time: time)
    let y = yFilter.filter(value: position.y, time: time)
    return CGPoint(x: x, y: y)
  }
}

private struct OneEuroFilter1D {
  private var settings: OneEuroFilterSettings
  private var lowPass = LowPassFilter()
  private var derivativeLowPass = LowPassFilter()
  private var lastTime: Double?
  private var lastRawValue: Double?

  init(settings: OneEuroFilterSettings) {
    self.settings = settings
  }

  mutating func reset(value: Double, time: Double) {
    lastTime = time
    lastRawValue = value
    lowPass.reset(value)
    derivativeLowPass.reset(0)
  }

  mutating func filter(value: Double, time: Double) -> Double {
    guard let lastTime, let lastRawValue else {
      reset(value: value, time: time)
      return value
    }

    let dt = time - lastTime
    guard dt > 0 else {
      reset(value: value, time: time)
      return value
    }

    let dx = (value - lastRawValue) / dt
    let edx = derivativeLowPass.filter(value: dx, alpha: alpha(cutoff: settings.dCutoff, dt: dt))
    let cutoff = max(0.0, settings.minCutoff + settings.beta * abs(edx))
    let filtered = lowPass.filter(value: value, alpha: alpha(cutoff: cutoff, dt: dt))

    self.lastTime = time
    self.lastRawValue = value
    return filtered
  }

  private func alpha(cutoff: Double, dt: Double) -> Double {
    guard cutoff > 0, dt > 0 else { return 1.0 }
    let tau = 1.0 / (2.0 * Double.pi * cutoff)
    let a = 1.0 / (1.0 + tau / dt)
    return min(max(a, 0.0), 1.0)
  }
}

private struct LowPassFilter {
  private var y: Double = 0
  private var initialized = false

  mutating func reset(_ value: Double) {
    initialized = true
    y = value
  }

  mutating func filter(value: Double, alpha: Double) -> Double {
    let a = min(max(alpha, 0.0), 1.0)
    guard initialized else {
      initialized = true
      y = value
      return value
    }
    y = a * value + (1.0 - a) * y
    return y
  }
}
