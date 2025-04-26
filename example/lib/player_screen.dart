import 'package:tha_player/tha_player.dart';
import 'package:flutter/material.dart';

class PlayerScreen extends StatefulWidget {
  final String url;
  const PlayerScreen({super.key, required this.url});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late ThaPlayerController thaPlayerController;
  final ValueNotifier<BoxFit> boxFitNotifier = ValueNotifier(BoxFit.contain);

  void initializePlayer() {
    thaPlayerController = ThaPlayerController.network(widget.url);
    thaPlayerController.initialize();
    thaPlayerController.play();
  }

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }

  @override
  void dispose() {
    thaPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Player Screen')),
      body: Container(
        alignment: Alignment.topCenter,
        child: ThaPlayerView(
          thaController: thaPlayerController,
          boxFitNotifier: boxFitNotifier,
          overlay: Row(
            children: [
              const Icon(Icons.play_circle_fill, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                "THA Player",
                style: const TextStyle(
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
    );
  }
}
