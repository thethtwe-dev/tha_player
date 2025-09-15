import Flutter
import AVFoundation
import UIKit

class PlayerContainerView: UIView {
  weak var playerLayerRef: AVPlayerLayer?
  override func layoutSubviews() {
    super.layoutSubviews()
    playerLayerRef?.frame = bounds
  }
}

class NativePlayerView: NSObject, FlutterPlatformView {
  private let container: PlayerContainerView
  private let player = AVPlayer()
  private let playerLayer = AVPlayerLayer()
  private let channel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private var timer: Timer?

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, params: [String: Any]?) {
    container = PlayerContainerView(frame: frame)
    channel = FlutterMethodChannel(name: "thaplayer/view_\(viewId)", binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: "thaplayer/events_\(viewId)", binaryMessenger: messenger)
    super.init()

    playerLayer.player = player
    playerLayer.videoGravity = .resizeAspect
    player.actionAtItemEnd = .pause
    container.layer.addSublayer(playerLayer)
    playerLayer.frame = container.bounds
    container.playerLayerRef = playerLayer
    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    // Keep device awake during playback session for this view
    UIApplication.shared.isIdleTimerDisabled = true

    if let params = params {
      setupFromArgs(params)
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "play":
        self.player.play(); result(nil)
      case "pause":
        self.player.pause(); result(nil)
      case "seekTo":
        if let dict = call.arguments as? [String: Any], let ms = dict["millis"] as? Int {
          let time = CMTimeMake(value: Int64(ms), timescale: 1000)
          self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        result(nil)
      case "setSpeed":
        if let dict = call.arguments as? [String: Any], let speed = dict["speed"] as? Double {
          self.player.rate = Float(speed)
        }
        result(nil)
      case "setLooping":
        // For single item, observe end and seek to zero if looping is true.
        result(nil)
      case "setBoxFit":
        if let dict = call.arguments as? [String: Any], let fit = dict["fit"] as? String {
          switch fit {
          case "cover": self.playerLayer.videoGravity = .resizeAspectFill
          case "fill": self.playerLayer.videoGravity = .resize
          case "fitWidth": self.playerLayer.videoGravity = .resizeAspect
          case "fitHeight": self.playerLayer.videoGravity = .resizeAspect
          default: self.playerLayer.videoGravity = .resizeAspect
          }
        }
        result(nil)
      case "dispose":
        self.dispose(); result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NotificationCenter.default.addObserver(self,
                                           selector: #selector(playerItemDidReachEnd),
                                           name: .AVPlayerItemDidPlayToEndTime,
                                           object: nil)

    eventChannel.setStreamHandler(self)
  }

  func view() -> UIView { container }

  func dispose() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    timer?.invalidate()
    timer = nil
    UIApplication.shared.isIdleTimerDisabled = false
  }

  private func setupFromArgs(_ args: [String: Any]) {
    let autoPlay = (args["autoPlay"] as? Bool) ?? true
    let loop = (args["loop"] as? Bool) ?? false
    let startMs = (args["startPositionMs"] as? Int) ?? 0
    let startAutoPlay = (args["startAutoPlay"] as? Bool) ?? autoPlay
    if let playlist = args["playlist"] as? [[String: Any]], let first = playlist.first, let urlStr = first["url"] as? String, let url = URL(string: urlStr) {
      let item = AVPlayerItem(url: url)
      self.player.replaceCurrentItem(with: item)
      if startMs > 0 {
        let t = CMTimeMake(value: Int64(startMs), timescale: 1000)
        self.player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
      }
      if startAutoPlay { self.player.play() } else { self.player.pause() }
      // Simple loop for single item.
      if loop {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
          self?.player.seek(to: .zero)
          self?.player.play()
        }
      }
    }
  }

  @objc private func playerItemDidReachEnd(notification: Notification) {
    // Placeholder for potential playlist handling.
  }
}

extension NativePlayerView: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.sendEvent()
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    timer?.invalidate()
    timer = nil
    eventSink = nil
    return nil
  }

  private func sendEvent() {
    guard let item = player.currentItem else { return }
    let pos = CMTimeGetSeconds(player.currentTime())
    let dur = CMTimeGetSeconds(item.duration)
    let isBuffering = item.isPlaybackBufferEmpty && !item.isPlaybackLikelyToKeepUp
    let isPlaying = player.rate > 0.0
    eventSink?([
      "positionMs": Int(pos * 1000),
      "durationMs": dur.isFinite ? Int(dur * 1000) : 0,
      "isBuffering": isBuffering,
      "isPlaying": isPlaying,
    ])
  }
}
