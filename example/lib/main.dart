import 'package:flutter/material.dart';
import 'package:tha_player_example/player_screen.dart';

//to add
// - current selected boxFit
// - seek Overlays

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tha_player Example',
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _defaultUrl =
      'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
  late final TextEditingController _urlController = TextEditingController(
    text: _defaultUrl,
  );
  bool _isLive = false;
  bool _autoFullscreen = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('tha_player')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 15,
          children: [
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'Insert Playable Url',
                helperText: 'Tip: paste an HTTPS stream or MP4 URL',
              ),
            ),

            SwitchListTile(
              title: const Text('Is Live (HLS)'),
              value: _isLive,
              onChanged: (v) => setState(() => _isLive = v),
            ),

            SwitchListTile(
              title: const Text('Start in Fullscreen'),
              value: _autoFullscreen,
              onChanged: (v) => setState(() => _autoFullscreen = v),
            ),

            ElevatedButton.icon(
              onPressed: () {
                final url = _urlController.text.trim();
                if (!_isValidUrl(url)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid http/https URL.'),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => PlayerScreen(
                      url: url,
                      isLive: _isLive,
                      autoFullscreen: _autoFullscreen,
                    ),
                  ),
                );
              },
              label: Text('Play Now'),
              icon: Icon(Icons.play_circle),
            ),
          ],
        ),
      ),
    );
  }
}
