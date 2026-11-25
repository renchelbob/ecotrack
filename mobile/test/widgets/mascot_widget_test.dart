import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/widgets/fox_mascot_widget.dart';
import 'package:ecotrack_mobile/features/home_mascot/presentation/widgets/mascot_vector_painter.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('FoxMascotWidget & MascotVectorPainter Tests', () {
    testWidgets('Renders all 5 MascotMoodState values cleanly', (tester) async {
      for (final mood in MascotMoodState.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: EcoTheme.lightTheme,
            home: Scaffold(
              body: Center(child: FoxMascotWidget(mood: mood)),
            ),
          ),
        );

        expect(find.byType(FoxMascotWidget), findsOneWidget);
        final paints = tester.widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(FoxMascotWidget),
            matching: find.byType(CustomPaint),
          ),
        );
        final mascotPaints = paints
            .map((w) => w.painter)
            .whereType<MascotVectorPainter>()
            .toList();
        expect(mascotPaints, hasLength(1));
        expect(mascotPaints.first.mood, equals(mood));
        await tester.pump(const Duration(milliseconds: 1600));
      }
    });

    testWidgets(
      'Pressing (onTapDown) triggers squinting and speech bubble, release restores',
      (tester) async {
        final squintingEvents = <bool>[];
        var tapCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: EcoTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: FoxMascotWidget(
                  mood: MascotMoodState.happy,
                  onSquintingChanged: squintingEvents.add,
                  onTap: () => tapCount++,
                ),
              ),
            ),
          ),
        );

        expect(find.text('Щекотно! Пойдём гулять?'), findsNothing);

        final center = tester.getCenter(find.byType(FoxMascotWidget));
        final gesture = await tester.startGesture(center);
        await tester.pump(const Duration(milliseconds: 120));

        expect(find.text('Щекотно! Пойдём гулять?'), findsOneWidget);
        expect(squintingEvents, contains(true));

        final painterDuringPress = tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byType(FoxMascotWidget),
                matching: find.byType(CustomPaint),
              ),
            )
            .map((w) => w.painter)
            .whereType<MascotVectorPainter>()
            .first;
        expect(painterDuringPress.isPointerSquinting, isTrue);

        await gesture.up();
        await tester.pump();

        expect(find.text('Щекотно! Пойдём гулять?'), findsNothing);
        expect(squintingEvents.last, isFalse);
        expect(tapCount, equals(1));
      },
    );

    testWidgets('Renders all 5 equipped vector accessories without errors', (
      tester,
    ) async {
      const accessories = <String>[
        'leaf_sprout_hat',
        'knit_green_scarf',
        'solar_shades',
        'moss_crown',
        'firefly_aura',
      ];

      for (final code in accessories) {
        await tester.pumpWidget(
          MaterialApp(
            theme: EcoTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: FoxMascotWidget(
                  mood: MascotMoodState.thriving,
                  equippedAccessoryCode: code,
                ),
              ),
            ),
          ),
        );

        final painter = tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byType(FoxMascotWidget),
                matching: find.byType(CustomPaint),
              ),
            )
            .map((w) => w.painter)
            .whereType<MascotVectorPainter>()
            .first;
        expect(painter.equippedAccessoryCode, equals(code));
        await tester.pump(const Duration(milliseconds: 200));
      }
    });

    test('MascotVectorPainter shouldRepaint responds to visual deltas', () {
      const base = MascotVectorPainter(
        mood: MascotMoodState.neutral,
        breathingPhase: 0.25,
        equippedAccessoryCode: 'solar_shades',
      );
      expect(base.shouldRepaint(base), isFalse);
      expect(
        base.shouldRepaint(
          const MascotVectorPainter(
            mood: MascotMoodState.thriving,
            breathingPhase: 0.25,
            equippedAccessoryCode: 'solar_shades',
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const MascotVectorPainter(
            mood: MascotMoodState.neutral,
            breathingPhase: 0.75,
            equippedAccessoryCode: 'solar_shades',
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const MascotVectorPainter(
            mood: MascotMoodState.neutral,
            breathingPhase: 0.25,
            equippedAccessoryCode: 'moss_crown',
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const MascotVectorPainter(
            mood: MascotMoodState.neutral,
            breathingPhase: 0.25,
            equippedAccessoryCode: 'solar_shades',
            isPointerSquinting: true,
          ),
        ),
        isTrue,
      );
    });
  });
}
