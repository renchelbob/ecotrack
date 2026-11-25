import 'package:ecotrack_mobile/features/home_mascot/presentation/widgets/fox_mascot_widget.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Mascot breathing animation renders within frame budget', (
    tester,
  ) async {
    await binding.traceAction(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: FoxMascotWidget(
                mood: MascotMoodState.thriving,
                equippedAccessoryCode: 'firefly_aura',
              ),
            ),
          ),
        ),
      );

      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(FoxMascotWidget), findsOneWidget);
    }, reportKey: 'mascot_breathing_timeline');
  });
}
