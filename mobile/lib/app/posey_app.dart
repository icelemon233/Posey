import 'package:flutter/material.dart';
import 'package:posey/core/ui/posey_theme.dart';
import 'package:posey/app/posey_dependencies.dart';
import 'package:posey/app/posey_shell.dart';

class PoseyApp extends StatelessWidget {
  const PoseyApp({super.key, required this.dependencies});
  final PoseyDependencies dependencies;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: dependencies.settings,
    builder: (context, _) {
      final colors =
          homeThemes[dependencies.settings.theme] ?? homeThemes['sunny-cream']!;
      ThemeData appTheme(Brightness brightness) {
        final scheme = ColorScheme.fromSeed(
          seedColor: colors.$2,
          brightness: brightness,
          surface: brightness == Brightness.light
              ? colors.$3
              : const Color(0xFF211F1D),
        );
        return ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: scheme.surface,
          appBarTheme: AppBarTheme(
            backgroundColor: scheme.surface,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: brightness == Brightness.light
                ? Colors.white.withValues(alpha: .8)
                : scheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }

      return MaterialApp(
        title: 'Posey',
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: ThemeMode.values.byName(dependencies.settings.themeMode),
        home: PoseyShell(dependencies: dependencies),
      );
    },
  );
}
