import 'package:flutter/material.dart';
import 'package:tha_player/tha_player.dart';

class PlayerScreen extends StatefulWidget {
  final String url;
  const PlayerScreen({super.key, required this.url});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late ThaNativePlayerController controller;
  final ValueNotifier<BoxFit> boxFitNotifier = ValueNotifier(BoxFit.contain);

  @override
  void initState() {
    super.initState();
    controller = ThaNativePlayerController.single(
      ThaMediaSource(widget.url),
      autoPlay: true,
      loop: false,
    );
  }

  @override
  void dispose() {
    boxFitNotifier.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Player Screen')),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ThaModernPlayer(
            controller: controller,
            overlay: Row(
              children: const [
                Icon(Icons.play_circle_fill, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  'THA Player',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
