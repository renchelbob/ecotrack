import 'package:ecotrack_mobile/features/home_mascot/domain/home_models.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/widgets/mascot_vector_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoxMascotWidget Tests', () {
    testWidgets('Renders properly for all moods without error', (tester) async {
      for (final mood in MascotMood.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: FoxMascotWidget(mood: mood, size: const Size(150, 150)),
              ),
            ),
          ),
        );

        expect(find.byType(FoxMascotWidget), findsOneWidget);
        expect(find.byType(CustomPaint), findsWidgets);
        await tester.pump(const Duration(milliseconds: 100));
      }
    });

    testWidgets('Triggers onTap callback when tapped', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FoxMascotWidget(
                mood: MascotMood.happy,
                size: const Size(180, 180),
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(tapped, isFalse);
      await tester.tap(find.byType(FoxMascotWidget));
      expect(tapped, isTrue);

      // Drain the temporary squinting timer (600ms)
      await tester.pump(const Duration(milliseconds: 700));
    });
  });
}
