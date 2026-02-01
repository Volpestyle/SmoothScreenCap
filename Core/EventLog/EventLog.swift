import Foundation

public struct EventLogEntry: Codable, Equatable {
  public enum EventType: String, Codable {
    case mouse
    case scroll
    case key
  }

  public struct Point: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  public struct MouseEvent: Codable, Equatable {
    public enum Action: String, Codable {
      case move
      case down
      case up
    }

    public enum Button: String, Codable {
      case left
      case right
      case other
    }

    public var action: Action
    public var button: Button?
    public var location: Point
    public var globalLocation: Point?

    public init(
      action: Action,
      button: Button? = nil,
      location: Point,
      globalLocation: Point? = nil
    ) {
      self.action = action
      self.button = button
      self.location = location
      self.globalLocation = globalLocation
    }
  }

  public struct ScrollEvent: Codable, Equatable {
    public var deltaX: Double
    public var deltaY: Double

    public init(deltaX: Double, deltaY: Double) {
      self.deltaX = deltaX
      self.deltaY = deltaY
    }
  }

  public struct KeyEvent: Codable, Equatable {
    public enum Action: String, Codable {
      case down
    }

    public var action: Action
    public var keyCode: Int?
    public var isRepeat: Bool?
    public var modifiers: [String]?

    public init(
      action: Action = .down,
      keyCode: Int? = nil,
      isRepeat: Bool? = nil,
      modifiers: [String]? = nil
    ) {
      self.action = action
      self.keyCode = keyCode
      self.isRepeat = isRepeat
      self.modifiers = modifiers
    }
  }

  public var time: Double
  public var type: EventType
  public var mouse: MouseEvent?
  public var scroll: ScrollEvent?
  public var key: KeyEvent?

  public init(time: Double, mouse: MouseEvent) {
    self.time = time
    self.type = .mouse
    self.mouse = mouse
    self.scroll = nil
    self.key = nil
  }

  public init(time: Double, scroll: ScrollEvent) {
    self.time = time
    self.type = .scroll
    self.mouse = nil
    self.scroll = scroll
    self.key = nil
  }

  public init(time: Double, key: KeyEvent) {
    self.time = time
    self.type = .key
    self.mouse = nil
    self.scroll = nil
    self.key = key
  }
}

public enum EventLogJSONL {
  public static func encode(_ entries: [EventLogEntry]) throws -> Data {
    var lines: [String] = []
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    for entry in entries {
      let data = try encoder.encode(entry)
      lines.append(String(decoding: data, as: UTF8.self))
    }
    let payload = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    return Data(payload.utf8)
  }

  public static func decode(_ data: Data) throws -> [EventLogEntry] {
    let decoder = JSONDecoder()
    let text = String(decoding: data, as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    var entries: [EventLogEntry] = []
    entries.reserveCapacity(lines.count)
    for line in lines {
      let entry = try decoder.decode(EventLogEntry.self, from: Data(line.utf8))
      entries.append(entry)
    }
    return entries
  }
}

public final class EventLogWriter {
  private let handle: FileHandle

  public init(url: URL, createIfNeeded: Bool = true) throws {
    if createIfNeeded {
      FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
    }
    self.handle = try FileHandle(forWritingTo: url)
    try self.handle.seekToEnd()
  }

  public func append(_ entry: EventLogEntry) throws {
    let data = try EventLogJSONL.encode([entry])
    try handle.write(contentsOf: data)
  }

  public func close() throws {
    try handle.close()
  }
}

public enum EventLogReader {
  public static func read(from url: URL) throws -> [EventLogEntry] {
    let data = try Data(contentsOf: url)
    return try EventLogJSONL.decode(data)
  }
}
