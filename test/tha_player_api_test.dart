import 'package:flutter_test/flutter_test.dart';
import 'package:tha_player/tha_player.dart';

void main() {
  test('ThaPlayerError.fromEvent parses structured fields', () {
    final error = ThaPlayerError.fromEvent({
      'errorCode': 'IO_NETWORK',
      'errorMessage': 'Network down',
      'errorRecoverable': true,
      'errorDetails': {'status': 500},
    });

    expect(error.code, 'IO_NETWORK');
    expect(error.message, 'Network down');
    expect(error.isRecoverable, true);
    expect(error.details?['status'], 500);
  });

  test('Controller preferences update from setters', () async {
    final controller = ThaNativePlayerController.single(
      const ThaMediaSource('https://example.com/video.mp4'),
      initialPreferences: const ThaPlayerPreferences(
        playbackSpeed: 1.0,
        dataSaver: false,
      ),
    );
    addTearDown(controller.dispose);

    await controller.setSpeed(1.5);
    await controller.setDataSaver(true);
    await controller.selectVideoTrack('v1');
    await controller.selectAudioTrack('a1');
    await controller.selectSubtitleTrack('s1');

    var prefs = controller.preferences.value;
    expect(prefs.playbackSpeed, 1.5);
    expect(prefs.dataSaver, true);
    expect(prefs.manualVideoTrackId, 'v1');
    expect(prefs.manualAudioTrackId, 'a1');
    expect(prefs.manualSubtitleTrackId, 's1');

    await controller.clearVideoTrackSelection();
    expect(controller.preferences.value.manualVideoTrackId, isNull);

    controller.resetPreferences();
    prefs = controller.preferences.value;
    expect(prefs.playbackSpeed, 1.0);
    expect(prefs.dataSaver, false);
    expect(prefs.manualVideoTrackId, isNull);
    expect(prefs.manualAudioTrackId, isNull);
    expect(prefs.manualSubtitleTrackId, isNull);

    await controller.setPlaybackSpeed(2.0, persist: false);
    expect(controller.preferences.value.playbackSpeed, 1.0);
  });
}
