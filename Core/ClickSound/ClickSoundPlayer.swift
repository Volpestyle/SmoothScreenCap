import AVFoundation
import Foundation

public enum ClickSoundAsset {
  public static func bundledURL() -> URL? {
    Bundle.module.url(forResource: "click", withExtension: "wav")
  }
}

public final class ClickSoundPlayer {
  public var isEnabled: Bool {
    didSet { if !isEnabled { stopAll() } }
  }
  public var volume: Float {
    didSet { updateVolumes() }
  }

  private var players: [AVAudioPlayer] = []
  private var nextIndex = 0

  public init(soundURL: URL?, volume: Float = 1.0, isEnabled: Bool = true, polyphony: Int = 4) {
    self.isEnabled = isEnabled
    self.volume = volume
    loadPlayers(url: soundURL, polyphony: polyphony)
  }

  public func updateSound(url: URL?, polyphony: Int = 4) {
    loadPlayers(url: url, polyphony: polyphony)
  }

  public func play() {
    guard isEnabled, !players.isEmpty else { return }
    let player = players[nextIndex]
    player.currentTime = 0
    player.volume = volume
    player.play()
    nextIndex = (nextIndex + 1) % players.count
  }

  private func loadPlayers(url: URL?, polyphony: Int) {
    players.removeAll()
    nextIndex = 0
    guard let url, polyphony > 0 else { return }

    for _ in 0..<polyphony {
      guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
      player.prepareToPlay()
      player.volume = volume
      players.append(player)
    }
  }

  private func stopAll() {
    for player in players {
      player.stop()
    }
  }

  private func updateVolumes() {
    for player in players {
      player.volume = volume
    }
  }
}
