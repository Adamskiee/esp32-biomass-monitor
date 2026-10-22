import 'package:biomass_iot_app/app/app_state_provider.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/features/settings/settings_controller.dart';
import 'package:biomass_iot_app/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mock_app_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockAppFonts);

  for (final brightness in Brightness.values) {
    testWidgets('Settings icons share styling in ${brightness.name} mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final state = AppStateProvider(preferences);
      final settings = SettingsController(preferences);
      addTearDown(state.dispose);
      addTearDown(settings.dispose);
      final theme = brightness == Brightness.dark
          ? AppTheme.getDarkTheme()
          : AppTheme.getLightTheme();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: MaterialApp(theme: theme, home: const SettingsScreen()),
        ),
      );
      await tester.runAsync(GoogleFonts.pendingFonts);
      final icons = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Icon),
      );
      expect(icons, findsWidgets);
      for (final icon in icons.evaluate()) {
        final glyph = tester.widget<RichText>(
          find
              .descendant(
                of: find.byWidget(icon.widget),
                matching: find.byType(RichText),
              )
              .first,
        );
        expect(glyph.text.style!.color, theme.colorScheme.onSurfaceVariant);
        expect(glyph.text.style!.fontSize, 20);
      }
      expect(
        tester.getTopLeft(find.text('Dark Mode Theme')).dx,
        tester.getTopLeft(find.text('About / Documentation')).dx,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
