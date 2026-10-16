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
      return MaterialApp(
        title: 'Posey',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: colors.$2,
            surface: colors.$3,
          ),
          scaffoldBackgroundColor: colors.$3,
          appBarTheme: AppBarTheme(
            backgroundColor: colors.$3,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white.withValues(alpha: .8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        home: PoseyShell(dependencies: dependencies),
      );
    },
  );
}
