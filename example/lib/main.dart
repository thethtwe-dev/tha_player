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
  TextEditingController controller = TextEditingController();

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
              controller: controller,
              decoration: InputDecoration(hintText: 'Insert Playable Url'),
            ),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (c) => PlayerScreen(url: controller.text),
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
