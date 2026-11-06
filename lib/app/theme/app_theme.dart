import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:strasse/core/core.dart';
import 'package:strasse/features/settings/settings_model.dart';

/// Couleurs sémantiques propres à Strasse, en plus du ColorScheme Material.
@immutable
class StrasseColors extends ThemeExtension<StrasseColors> {
  const StrasseColors({
    required this.route,
    required this.marker,
    required this.success,
    required this.warning,
    required this.danger,
    required this.sea,
    required this.land,
    required this.panel,
  });

  final Color route;
  final Color marker;
  final Color success;
  final Color warning;
  final Color danger;
  final Color sea;
  final Color land;
  final Color panel;

  @override
  StrasseColors copyWith({Color? route, Color? marker, Color? success, Color? warning, Color? danger, Color? sea, Color? land, Color? panel}) => StrasseColors(
        route: route ?? this.route,
        marker: marker ?? this.marker,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        sea: sea ?? this.sea,
        land: land ?? this.land,
        panel: panel ?? this.panel,
      );

  @override
  StrasseColors lerp(ThemeExtension<StrasseColors>? other, double t) {
    if (other is! StrasseColors) return this;
    return StrasseColors(
      route: Color.lerp(route, other.route, t)!,
      marker: Color.lerp(marker, other.marker, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      sea: Color.lerp(sea, other.sea, t)!,
      land: Color.lerp(land, other.land, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
    );
  }
}

extension StrasseThemeX on BuildContext {
  StrasseColors get sc => Theme.of(this).extension<StrasseColors>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}

class AppTheme {
  const AppTheme._();

  /// [dynamicScheme] : palette Material You fournie par le système (Android 12+), sinon null.
  /// Quand elle est présente et que l'option est active, elle remplace la palette de marque ;
  /// sur iOS et sur les Android plus anciens, la palette est générée à partir du vert Strasse.
  static ThemeData build(AppSettings s, Brightness brightness, {ColorScheme? dynamicScheme}) {
    final dark = brightness == Brightness.dark;
    final seed = s.primary;
    final useDynamic = s.useDynamicColor && dynamicScheme != null;
    late final ColorScheme scheme;
    late final Color bg;
    if (useDynamic) {
      scheme = dynamicScheme;
      bg = scheme.surface;
    } else {
      var brand = ColorScheme.fromSeed(seedColor: seed, brightness: brightness, secondary: s.secondary);
      // Garantit un contraste suffisant pour la couleur principale choisie par l'utilisateur.
      bg = dark ? const Color(0xFF111416) : Colors.white;
      brand = brand.copyWith(
        primary: ensureContrast(seed, dark ? const Color(0xFF1C2026) : Colors.white, minRatio: 3.0),
        surface: dark ? const Color(0xFF1A1E21) : Colors.white,
        surfaceContainerHighest: dark ? const Color(0xFF262B2F) : const Color(0xFFF1F3F2),
      );
      scheme = brand;
    }

    final duration = s.reduceAnimations ? Duration.zero : const Duration(milliseconds: 220);
    final density = s.compactUi ? VisualDensity.compact : VisualDensity.standard;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      visualDensity: density,
      splashFactory: s.reduceAnimations ? NoSplash.splashFactory : InkRipple.splashFactory,
    );

    // Transitions natives : glissement latéral avec retour par geste sur iOS, transition Material sur Android.
    const PageTransitionsBuilder noAnim = _NoTransitions();
    final androidBuilder = s.reduceAnimations ? noAnim : const ZoomPageTransitionsBuilder();
    final iosBuilder = s.reduceAnimations ? noAnim : const CupertinoPageTransitionsBuilder();

    return base.copyWith(
      extensions: [
        StrasseColors(
          route: Color(s.routeColor),
          marker: Color(s.markerColor),
          success: dark ? const Color(0xFF6FCF83) : const Color(0xFF2E7D32),
          warning: dark ? const Color(0xFFFFC857) : const Color(0xFFB26A00),
          danger: dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
          sea: const Color(0xFF3E8FD6),
          land: const Color(0xFF5FAE5A),
          panel: useDynamic ? scheme.surfaceContainerLow : (dark ? const Color(0xFF1F2428) : Colors.white),
        ),
      ],
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        TargetPlatform.android: androidBuilder,
        TargetPlatform.iOS: iosBuilder,
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: scheme.outlineVariant.withOpacity(0.5))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 52), shape: const StadiumBorder(), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), shape: const StadiumBorder()),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withOpacity(0.5), space: 1),
      chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder(), side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6))),
    );
  }
}

class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}
