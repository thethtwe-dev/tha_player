// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tha_player_example/main.dart';

void main() {
  testWidgets('renders home screen controls', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('tha_player'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Play Now'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://example.com/video.mp4',
    );
    await tester.tap(find.text('Play Now'));
    await tester.pump();

    expect(find.text('Player Screen'), findsOneWidget);
  });
}
