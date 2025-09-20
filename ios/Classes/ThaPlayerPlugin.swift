import Flutter
import UIKit
import MediaPlayer

public class ThaPlayerPlugin: NSObject, FlutterPlugin {
  private var utilChannel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let versionChannel = FlutterMethodChannel(name: "tha_player", binaryMessenger: registrar.messenger())
    let instance = ThaPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: versionChannel)

    // Extra utility channel to match Android bridge for brightness/volume
    let util = FlutterMethodChannel(name: "thaplayer/channel", binaryMessenger: registrar.messenger())
    instance.utilChannel = util
    registrar.addMethodCallDelegate(instance, channel: util)

    // Register platform view
    registrar.register(NativePlayerFactory(messenger: registrar.messenger()), withId: "thaplayer/native_view")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "setBrightness":
      guard let args = call.arguments as? [String: Any], let delta = args["value"] as? Double else {
        result(FlutterError(code: "ARG_ERROR", message: "Missing value for setBrightness", details: nil))
        return
      }
      let current = UIScreen.main.brightness
      var newValue = CGFloat(current) + CGFloat(delta)
      if newValue < 0.01 { newValue = 0.01 }
      if newValue > 1.0 { newValue = 1.0 }
      UIScreen.main.brightness = newValue
      result(Double(newValue))
    case "setVolume":
      guard let args = call.arguments as? [String: Any], let delta = args["value"] as? Double else {
        result(FlutterError(code: "ARG_ERROR", message: "Missing value for setVolume", details: nil))
        return
      }
      // Adjust system volume with MPVolumeView slider hack
      let volumeView = MPVolumeView(frame: .zero)
      if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
        let current = slider.value
        var newVal = current + Float(delta)
        if newVal < 0.0 { newVal = 0.0 }
        if newVal > 1.0 { newVal = 1.0 }
        DispatchQueue.main.async {
          slider.value = newVal
          result(Double(slider.value))
        }
      } else {
        result(FlutterError(code: "NO_SLIDER", message: "Failed to access volume slider", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
