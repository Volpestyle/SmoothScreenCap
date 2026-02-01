import CoreGraphics
import Darwin
import EventLog
import Foundation

final class EventTapMonitor {
  private let writer: EventLogWriter
  private let captureRect: CGRect?
  private let timeConverter: MachTimeConverter
  private let startTime: UInt64
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var thread: Thread?
  private var runLoop: CFRunLoop?
  private var isRunning = false

  init(writer: EventLogWriter, captureRect: CGRect?, startTime: UInt64) {
    self.writer = writer
    self.captureRect = captureRect
    self.startTime = startTime
    self.timeConverter = MachTimeConverter()
  }

  func start() throws {
    guard !isRunning else { return }
    let eventMask = eventMaskForCapture()
    let callback: CGEventTapCallBack = { proxy, type, event, refcon in
      guard let refcon else { return Unmanaged.passUnretained(event) }
      let monitor = Unmanaged<EventTapMonitor>.fromOpaque(refcon).takeUnretainedValue()
      return monitor.handleEvent(proxy: proxy, type: type, event: event)
    }

    guard let tap = CGEvent.tapCreate(
      tap: .cghidEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: callback,
      userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    ) else {
      throw EventTapError.failedToCreate
    }

    eventTap = tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    let thread = Thread { [weak self] in
      guard let self else { return }
      let runLoop = RunLoop.current
      self.runLoop = runLoop.getCFRunLoop()
      if let source = self.runLoopSource {
        CFRunLoopAddSource(runLoop.getCFRunLoop(), source, .commonModes)
      }
      CGEvent.tapEnable(tap: tap, enable: true)
      self.isRunning = true
      runLoop.run()
    }
    self.thread = thread
    thread.start()
  }

  func stop() {
    guard isRunning else { return }
    isRunning = false
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
    if let source = runLoopSource {
      CFRunLoopSourceInvalidate(source)
    }
    if let runLoop = runLoop {
      CFRunLoopStop(runLoop)
    }
    thread?.cancel()
    thread = nil
    runLoop = nil
    runLoopSource = nil
    eventTap = nil
  }

  private func handleEvent(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    let eventTime = timeConverter.seconds(fromMachAbsolute: event.timestamp)
    let startSeconds = timeConverter.seconds(fromMachAbsolute: startTime)
    let time = max(0, eventTime - startSeconds)

    switch type {
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      appendMouse(
        time: time,
        action: .move,
        button: nil,
        event: event
      )
    case .leftMouseDown:
      appendMouse(time: time, action: .down, button: .left, event: event)
    case .leftMouseUp:
      appendMouse(time: time, action: .up, button: .left, event: event)
    case .rightMouseDown:
      appendMouse(time: time, action: .down, button: .right, event: event)
    case .rightMouseUp:
      appendMouse(time: time, action: .up, button: .right, event: event)
    case .otherMouseDown:
      appendMouse(time: time, action: .down, button: .other, event: event)
    case .otherMouseUp:
      appendMouse(time: time, action: .up, button: .other, event: event)
    case .scrollWheel:
      let deltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
      let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
      let entry = EventLogEntry(time: time, scroll: .init(deltaX: deltaX, deltaY: deltaY))
      try? writer.append(entry)
    case .keyDown:
      let modifiers = modifiersList(from: event.flags)
      let entry = EventLogEntry(
        time: time,
        key: .init(action: .down, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, modifiers: modifiers)
      )
      try? writer.append(entry)
    default:
      break
    }

    return Unmanaged.passUnretained(event)
  }

  private func appendMouse(
    time: Double,
    action: EventLogEntry.MouseEvent.Action,
    button: EventLogEntry.MouseEvent.Button?,
    event: CGEvent
  ) {
    let globalPoint = event.location
    let global = EventLogEntry.Point(x: Double(globalPoint.x), y: Double(globalPoint.y))
    let localPoint: EventLogEntry.Point
    if let rect = captureRect {
      localPoint = EventLogEntry.Point(
        x: Double(globalPoint.x - rect.origin.x),
        y: Double(globalPoint.y - rect.origin.y)
      )
    } else {
      localPoint = global
    }
    let entry = EventLogEntry(
      time: time,
      mouse: .init(
        action: action,
        button: button,
        location: localPoint,
        globalLocation: global
      )
    )
    try? writer.append(entry)
  }

  private func eventMaskForCapture() -> CGEventMask {
    let types: [CGEventType] = [
      .mouseMoved,
      .leftMouseDown,
      .leftMouseUp,
      .rightMouseDown,
      .rightMouseUp,
      .otherMouseDown,
      .otherMouseUp,
      .leftMouseDragged,
      .rightMouseDragged,
      .otherMouseDragged,
      .scrollWheel,
      .keyDown
    ]
    return types.reduce(CGEventMask(0)) { mask, type in
      mask | CGEventMask(1 << type.rawValue)
    }
  }

  private func modifiersList(from flags: CGEventFlags) -> [String] {
    var modifiers: [String] = []
    if flags.contains(.maskShift) { modifiers.append("shift") }
    if flags.contains(.maskControl) { modifiers.append("control") }
    if flags.contains(.maskAlternate) { modifiers.append("option") }
    if flags.contains(.maskCommand) { modifiers.append("command") }
    if flags.contains(.maskAlphaShift) { modifiers.append("capsLock") }
    if flags.contains(.maskSecondaryFn) { modifiers.append("fn") }
    return modifiers
  }

  enum EventTapError: Error {
    case failedToCreate
  }
}

private struct MachTimeConverter {
  let numer: UInt32
  let denom: UInt32

  init() {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    self.numer = info.numer
    self.denom = info.denom
  }

  func seconds(fromMachAbsolute value: UInt64) -> Double {
    let nanos = Double(value) * Double(numer) / Double(denom)
    return nanos / 1_000_000_000.0
  }
}
