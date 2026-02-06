import Flutter
import AVFoundation
import AVKit
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
  private var lastUrl: URL?
  private var lastHeaders: [String: String]?
  private var manualVideoBitrate: Double?
  @available(iOS 9.0, *)
  private var pipController: AVPictureInPictureController?
  private var manualAudioId: String?
  private var manualSubtitleId: String?
  private var playbackOptions = PlaybackOptions()
  private var retryAttempts = 0
  private var retryWorkItem: DispatchWorkItem?
  private var isLooping: Bool = false

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
        if let dict = call.arguments as? [String: Any], let loop = dict["loop"] as? Bool {
          self.isLooping = loop
        }
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
      case "retry":
        if self.executeRetry() {
          result(nil)
        } else {
          result(FlutterError(code: "NO_URL", message: "No previous URL to retry", details: nil))
        }
      case "getVideoTracks":
        result(self.videoTracksPayload())
      case "setVideoTrack":
        let args = call.arguments as? [String: Any]
        let identifier = args?["id"] as? String
        self.setVideoTrack(id: identifier)
        result(nil)
      case "getAudioTracks":
        result(self.audioTracksPayload())
      case "setAudioTrack":
        let args = call.arguments as? [String: Any]
        let identifier = args?["id"] as? String
        self.setAudioTrack(id: identifier)
        result(nil)
      case "getSubtitleTracks":
        result(self.subtitleTracksPayload())
      case "setSubtitleTrack":
        let args = call.arguments as? [String: Any]
        let identifier = args?["id"] as? String
        self.setSubtitleTrack(id: identifier)
        result(nil)
      case "enterPip":
        if #available(iOS 9.0, *) {
          result(self.startPictureInPicture())
        } else {
          result(false)
        }
      case "setDataSaver":
        if let dict = call.arguments as? [String: Any], let enable = dict["enable"] as? Bool {
          if let item = self.player.currentItem {
            item.preferredPeakBitRate = enable ? 800_000 : 0
            if enable {
              self.manualVideoBitrate = nil
            }
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
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(playerItemFailed(_:)),
                                           name: .AVPlayerItemFailedToPlayToEndTime,
                                           object: nil)

    eventChannel.setStreamHandler(self)
  }

  func view() -> UIView { container }

  func dispose() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    timer?.invalidate()
    timer = nil
    retryWorkItem?.cancel()
    retryWorkItem = nil
    UIApplication.shared.isIdleTimerDisabled = false
    if #available(iOS 9.0, *) {
      if pipController?.isPictureInPictureActive == true {
        pipController?.stopPictureInPicture()
      }
      pipController = nil
    }
    NotificationCenter.default.removeObserver(self)
  }

  private func setupFromArgs(_ args: [String: Any]) {
    let autoPlay = (args["autoPlay"] as? Bool) ?? true
    let loop = (args["loop"] as? Bool) ?? false
    self.isLooping = loop
    let startMs = (args["startPositionMs"] as? Int) ?? 0
    let startAutoPlay = (args["startAutoPlay"] as? Bool) ?? autoPlay
    let dataSaver = (args["dataSaver"] as? Bool) ?? false
    if let optionMap = args["playbackOptions"] as? [String: Any] {
      playbackOptions = PlaybackOptions.fromMap(optionMap)
    } else {
      playbackOptions = PlaybackOptions()
    }
    if let playlist = args["playlist"] as? [[String: Any]],
       let first = playlist.first,
       let urlStr = first["url"] as? String,
       let url = URL(string: urlStr) {
      // Extract headers if any
      var headers: [String: String]? = nil
      if let h = first["headers"] as? [String: Any] {
        var map: [String: String] = [:]
        for (k, v) in h { if let ks = k as? String, let vs = v as? String { map[ks] = vs } }
        if !map.isEmpty { headers = map }
      }
      let options: [String: Any]? = (headers != nil) ? [AVURLAssetHTTPHeaderFieldsKey: headers!] : nil
      let asset = AVURLAsset(url: url, options: options)
      let item = AVPlayerItem(asset: asset)
      self.lastUrl = url
      self.lastHeaders = headers
      self.player.replaceCurrentItem(with: item)
      if let manual = manualVideoBitrate {
        item.preferredPeakBitRate = manual
      }
      manualAudioId = nil
      manualSubtitleId = nil
      retryAttempts = 0
      retryWorkItem?.cancel()
      retryWorkItem = nil
      // Live tuning if requested
      let isLive = (first["isLive"] as? Bool) ?? false
      if isLive {
        self.player.automaticallyWaitsToMinimizeStalling = true
        if #available(iOS 10.0, *) {
          item.preferredForwardBufferDuration = 0
        }
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
      }
      // Data saver initial cap
      if dataSaver {
        item.preferredPeakBitRate = 800_000
      }
      if startMs > 0 {
        let t = CMTimeMake(value: Int64(startMs), timescale: 1000)
        self.player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
      }
      if startAutoPlay { self.player.play() } else { self.player.pause() }
    }
  }

  @objc private func playerItemDidReachEnd(notification: Notification) {
    guard isLooping else { return }
    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    player.play()
  }

  @objc private func playerItemFailed(_ notification: Notification) {
    var message = "Playback error"
    var code = "AVPlayerItemFailed"
    var details: [String: Any] = [:]
    if let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError {
      message = err.localizedDescription
      code = "\(err.domain):\(err.code)"
      details = [
        "domain": err.domain,
        "code": err.code,
      ]
    }
    let recoverable = canAutoRetry()
    // Emit error to Dart
    eventSink?([
      "positionMs": Int(CMTimeGetSeconds(player.currentTime()) * 1000),
      "durationMs": 0,
      "isBuffering": false,
      "isPlaying": false,
      "error": message,
      "errorCode": code,
      "errorMessage": message,
      "errorRecoverable": recoverable,
      "errorDetails": details,
    ])
  }

  @available(iOS 9.0, *)
  private func ensurePictureInPictureController() {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    if pipController == nil {
      pipController = AVPictureInPictureController(playerLayer: playerLayer)
      pipController?.delegate = self
      if #available(iOS 14.2, *) {
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
      }
    }
  }

  @available(iOS 9.0, *)
  private func startPictureInPicture() -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return false }
    ensurePictureInPictureController()
    guard let controller = pipController else { return false }
    guard controller.isPictureInPicturePossible else { return false }
    if !controller.isPictureInPictureActive {
      controller.startPictureInPicture()
    }
    return true
  }

  private func videoTracksPayload() -> [[String: Any]] {
    guard let item = player.currentItem else { return [] }

    var results: [[String: Any]] = []
    var seen = Set<Double>()
    let activeBitrate = manualVideoBitrate ?? item.accessLog()?.events.last?.indicatedBitrate ?? 0

    if let events = item.accessLog()?.events {
      for event in events {
        let bitrate = event.indicatedBitrate
        if bitrate <= 0 || seen.contains(bitrate) { continue }
        seen.insert(bitrate)
        results.append([
          "id": String(Int(bitrate)),
          "bitrate": bitrate,
          "width": NSNull(),
          "height": NSNull(),
          "label": bitrateLabel(bitrate: bitrate),
          "selected": nearlyEqual(bitrate, activeBitrate),
        ])
      }
    }

    if let manual = manualVideoBitrate, manual > 0, !seen.contains(manual) {
      results.append([
        "id": String(Int(manual)),
        "bitrate": manual,
        "width": NSNull(),
        "height": NSNull(),
        "label": bitrateLabel(bitrate: manual),
        "selected": true,
      ])
    }

    results.sort { lhs, rhs in
      let l = lhs["bitrate"] as? Double ?? 0
      let r = rhs["bitrate"] as? Double ?? 0
      return l > r
    }
    return results
  }

  private func setVideoTrack(id: String?) {
    guard let item = player.currentItem else { return }
    guard let id = id, !id.isEmpty, let bitrate = Double(id) else {
      manualVideoBitrate = nil
      item.preferredPeakBitRate = 0
      return
    }
    manualVideoBitrate = bitrate
    item.preferredPeakBitRate = bitrate
  }

  private func executeRetry() -> Bool {
    guard let url = lastUrl else { return false }
    let options: [String: Any]? = (lastHeaders != nil) ? [AVURLAssetHTTPHeaderFieldsKey: lastHeaders!] : nil
    let asset = AVURLAsset(url: url, options: options)
    let item = AVPlayerItem(asset: asset)
    player.replaceCurrentItem(with: item)
    if let manual = manualVideoBitrate {
      item.preferredPeakBitRate = manual
    }
    if let audioId = manualAudioId,
       let group = asset.mediaSelectionGroup(for: .audible),
       let option = mediaOption(for: audioId, in: group) {
      item.select(option, in: group)
    }
    if let subtitleId = manualSubtitleId,
       let group = asset.mediaSelectionGroup(for: .legible),
       let option = mediaOption(for: subtitleId, in: group) {
      item.select(option, in: group)
    }
    player.play()
    retryAttempts = 0
    retryWorkItem = nil
    return true
  }

  private func audioTracksPayload() -> [[String: Any]] {
    guard let item = player.currentItem else { return [] }
    guard let asset = item.asset as? AVURLAsset else { return [] }
    guard let group = asset.mediaSelectionGroup(for: .audible) else { return [] }
    let selected = item.currentMediaSelection.selectedMediaOption(in: group)
    var payload: [[String: Any]] = []
    for (index, option) in group.options.enumerated() {
      payload.append([
        "id": "audible:\(index)",
        "label": option.displayName,
        "language": option.extendedLanguageTag ?? option.locale?.identifier ?? option.locale?.languageCode,
        "selected": option == selected,
      ])
    }
    return payload
  }

  private func setAudioTrack(id: String?) {
    guard let item = player.currentItem else { return }
    guard let asset = item.asset as? AVURLAsset else { return }
    guard let group = asset.mediaSelectionGroup(for: .audible) else { return }
    if let id = id, let option = mediaOption(for: id, in: group) {
      manualAudioId = id
      item.select(option, in: group)
    } else {
      manualAudioId = nil
      if let defaultOption = group.defaultOption {
        item.select(defaultOption, in: group)
      }
    }
  }

  private func subtitleTracksPayload() -> [[String: Any]] {
    guard let item = player.currentItem else { return [] }
    guard let asset = item.asset as? AVURLAsset else { return [] }
    guard let group = asset.mediaSelectionGroup(for: .legible) else { return [] }
    let selected = item.currentMediaSelection.selectedMediaOption(in: group)
    var payload: [[String: Any]] = []
    for (index, option) in group.options.enumerated() {
      payload.append([
        "id": "legible:\(index)",
        "label": option.displayName,
        "language": option.extendedLanguageTag ?? option.locale?.identifier ?? option.locale?.languageCode,
        "selected": option == selected,
        "forced": option.hasMediaCharacteristic(.containsOnlyForcedSubtitles),
      ])
    }
    return payload
  }

  private func setSubtitleTrack(id: String?) {
    guard let item = player.currentItem else { return }
    guard let asset = item.asset as? AVURLAsset else { return }
    guard let group = asset.mediaSelectionGroup(for: .legible) else { return }
    if let id = id, let option = mediaOption(for: id, in: group) {
      manualSubtitleId = id
      item.select(option, in: group)
    } else {
      manualSubtitleId = nil
      item.select(nil, in: group)
    }
  }

  private func mediaOption(for identifier: String, in group: AVMediaSelectionGroup) -> AVMediaSelectionOption? {
    let parts = identifier.split(separator: ":")
    guard parts.count == 2, let index = Int(parts[1]) else { return nil }
    if index < 0 || index >= group.options.count { return nil }
    return group.options[index]
  }

  private func bitrateLabel(bitrate: Double) -> String {
    if bitrate <= 0 { return "Stream" }
    let mbps = bitrate / 1_000_000.0
    if mbps >= 1 {
      if mbps >= 10 {
        return String(format: "%.0f Mbps", mbps)
      }
      return String(format: "%.1f Mbps", mbps)
    }
    let kbps = bitrate / 1_000.0
    return String(format: "%.0f Kbps", kbps)
  }

  private func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    if lhs == rhs { return true }
    if lhs == 0 || rhs == 0 { return abs(lhs - rhs) < 50_000 }
    return abs(lhs - rhs) / max(lhs, rhs) < 0.05
  }

  private func scheduleAutoRetry() {
    guard playbackOptions.autoRetry else { return }
    if playbackOptions.maxRetryCount >= 0 && retryAttempts >= playbackOptions.maxRetryCount { return }
    retryAttempts += 1
    let delay = min(
      playbackOptions.initialRetryDelay * Double(retryAttempts),
      playbackOptions.maxRetryDelay
    )
    retryWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      _ = self.executeRetry()
    }
    retryWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func canAutoRetry() -> Bool {
    guard playbackOptions.autoRetry else { return false }
    if playbackOptions.maxRetryCount >= 0 && retryAttempts >= playbackOptions.maxRetryCount {
      return false
    }
    return true
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

@available(iOS 9.0, *)
extension NativePlayerView: AVPictureInPictureControllerDelegate {}

private struct PlaybackOptions {
  let maxRetryCount: Int
  let initialRetryDelay: Double
  let maxRetryDelay: Double
  let autoRetry: Bool
  let rebufferTimeout: Double?

  static func fromMap(_ map: [String: Any]) -> PlaybackOptions {
    let maxRetry = (map["maxRetryCount"] as? NSNumber)?.intValue ?? 3
    let initial = ((map["initialRetryDelayMs"] as? NSNumber)?.doubleValue ?? 1000) / 1000.0
    let maxDelay = ((map["maxRetryDelayMs"] as? NSNumber)?.doubleValue ?? 10000) / 1000.0
    let autoRetry = map["autoRetry"] as? Bool ?? true
    let rebufferMs = (map["rebufferTimeoutMs"] as? NSNumber)?.doubleValue
    let rebuffer = rebufferMs != nil ? rebufferMs! / 1000.0 : nil
    return PlaybackOptions(
      maxRetryCount: maxRetry,
      initialRetryDelay: initial,
      maxRetryDelay: maxDelay,
      autoRetry: autoRetry,
      rebufferTimeout: rebuffer
    )
  }

  init(maxRetryCount: Int = 3,
       initialRetryDelay: Double = 1.0,
       maxRetryDelay: Double = 10.0,
       autoRetry: Bool = true,
       rebufferTimeout: Double? = nil) {
    self.maxRetryCount = maxRetryCount
    self.initialRetryDelay = initialRetryDelay
    self.maxRetryDelay = maxRetryDelay
    self.autoRetry = autoRetry
    self.rebufferTimeout = rebufferTimeout
  }
}
