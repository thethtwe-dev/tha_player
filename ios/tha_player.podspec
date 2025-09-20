#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tha_player.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tha_player'
  s.version          = '0.2.0'
  s.summary          = 'Powerful network-only player for Flutter (ExoPlayer on Android, AVPlayer on iOS).'
  s.description      = <<-DESC
Unified network player with M3U playlists, MKV/HLS/DASH, 4K.
Uses ExoPlayer on Android and AVPlayer on iOS.
                       DESC
  s.homepage         = 'https://github.com/thethtwe-dev/tha_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.frameworks = 'MediaPlayer', 'AVFoundation'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'tha_player_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
