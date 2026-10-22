import 'package:biomass_iot_app/app/app_icons.dart';
import 'package:biomass_iot_app/app/app_theme.dart';
import 'package:biomass_iot_app/core/widgets/icon_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'support/mock_app_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockAppFonts);

  for (final brightness in Brightness.values) {
    testWidgets('default icons stay readable in ${brightness.name} mode', (
      tester,
    ) async {
      final theme = brightness == Brightness.dark
          ? AppTheme.getDarkTheme()
          : AppTheme.getLightTheme();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Column(
              children: [
                Icon(AppIcons.safety),
                IconLabel(icon: AppIcons.trends, label: 'Trends'),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(GoogleFonts.pendingFonts);
      for (final icon in [AppIcons.safety, AppIcons.trends]) {
        final glyph = tester.widget<RichText>(
          find.descendant(
            of: find.byIcon(icon),
            matching: find.byType(RichText),
          ),
        );
        final foreground = glyph.text.style!.color!;
        final contrast = brightness == Brightness.dark
            ? (foreground.computeLuminance() + 0.05) /
                  (theme.scaffoldBackgroundColor.computeLuminance() + 0.05)
            : (theme.scaffoldBackgroundColor.computeLuminance() + 0.05) /
                  (foreground.computeLuminance() + 0.05);
        expect(contrast, greaterThanOrEqualTo(3));
      }
    });
  }
}
