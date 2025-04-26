import 'package:flutter_test/flutter_test.dart';
import 'package:tha_player/tha_player.dart';
import 'package:tha_player/tha_player_platform_interface.dart';
import 'package:tha_player/tha_player_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockThaPlayerPlatform
    with MockPlatformInterfaceMixin
    implements ThaPlayerPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ThaPlayerPlatform initialPlatform = ThaPlayerPlatform.instance;

  test('$MethodChannelThaPlayer is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelThaPlayer>());
  });

  test('getPlatformVersion', () async {
    ThaPlayer thaPlayerPlugin = ThaPlayer();
    MockThaPlayerPlatform fakePlatform = MockThaPlayerPlatform();
    ThaPlayerPlatform.instance = fakePlatform;

    expect(await thaPlayerPlugin.getPlatformVersion(), '42');
  });
}
