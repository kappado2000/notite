import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Paleta „Salvie & crem”: verde salvie ca accent, miere ca secundar,
/// fundal crem cald. Variante separate pentru luminos și întunecat.
class AppColors {
  static const sage = Color(0xFF3F8F6B);
  static const honey = Color(0xFFD9A441);

  static const light = ColorScheme(
    brightness: Brightness.light,
    primary: sage,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFD3EBDD),
    onPrimaryContainer: Color(0xFF0F3B27),
    secondary: Color(0xFFB27D24),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF6E6C6),
    onSecondaryContainer: Color(0xFF4A3410),
    tertiary: Color(0xFF5B8A9A),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFD5E8EE),
    onTertiaryContainer: Color(0xFF15343E),
    error: Color(0xFFBA3B2E),
    onError: Colors.white,
    errorContainer: Color(0xFFFBDDD7),
    onErrorContainer: Color(0xFF5A130B),
    surface: Color(0xFFF4F1EA),
    onSurface: Color(0xFF22261F),
    onSurfaceVariant: Color(0xFF5E6559),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFEFEBE3),
    surfaceContainer: Color(0xFFEAE6DC),
    surfaceContainerHigh: Color(0xFFE4E0D5),
    surfaceContainerHighest: Color(0xFFDED9CD),
    outline: Color(0xFF8E968A),
    outlineVariant: Color(0xFFDFDBD1),
    inverseSurface: Color(0xFF2F332C),
    onInverseSurface: Color(0xFFF1EFE8),
    inversePrimary: Color(0xFF8FCFAE),
    shadow: Colors.black,
    scrim: Colors.black,
  );

  static const dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8FCFAE),
    onPrimary: Color(0xFF0B3322),
    primaryContainer: Color(0xFF235740),
    onPrimaryContainer: Color(0xFFD3EBDD),
    secondary: Color(0xFFE9B872),
    onSecondary: Color(0xFF3D2A06),
    secondaryContainer: Color(0xFF574117),
    onSecondaryContainer: Color(0xFFF6E6C6),
    tertiary: Color(0xFF9CC7D6),
    onTertiary: Color(0xFF0E2F39),
    tertiaryContainer: Color(0xFF2B4B56),
    onTertiaryContainer: Color(0xFFD5E8EE),
    error: Color(0xFFF2A598),
    onError: Color(0xFF5A130B),
    errorContainer: Color(0xFF7A2A1F),
    onErrorContainer: Color(0xFFFBDDD7),
    surface: Color(0xFF141712),
    onSurface: Color(0xFFE6E8E1),
    onSurfaceVariant: Color(0xFFB4BBAE),
    surfaceContainerLowest: Color(0xFF0F120E),
    surfaceContainerLow: Color(0xFF1A1E18),
    surfaceContainer: Color(0xFF1E221C),
    surfaceContainerHigh: Color(0xFF262B24),
    surfaceContainerHighest: Color(0xFF30362D),
    outline: Color(0xFF7F8879),
    outlineVariant: Color(0xFF363D33),
    inverseSurface: Color(0xFFE6E8E1),
    onInverseSurface: Color(0xFF2F332C),
    inversePrimary: sage,
    shadow: Colors.black,
    scrim: Colors.black,
  );
}

/// Culoarea scrisului pe un grup colorat.
enum TintText {
  auto('Automat'),
  dark('Închis'),
  light('Deschis');

  const TintText(this.label);
  final String label;
}

/// Nuanțele grupurilor: fiecare carnet și fiecare tip de parolă are una.
/// Din culoarea de bază, [level] (intensitatea, 0…5) și [text] rezultă
/// fundalul cardului, fundalul iconiței și culoarea scrisului, pe luminos
/// și întunecat.
class GroupTint {
  const GroupTint._(
    this.name,
    this.base, {
    this.level = 1,
    this.text = TintText.auto,
  });
  final String name;
  final Color base;
  final int level;
  final TintText text;

  // Ordinea contează: carnetele noi le primesc pe rând, deci culorile
  // vecine sunt cât mai diferite.
  static const all = [
    GroupTint._('Salvie', Color(0xFF3F8F6B)),
    GroupTint._('Coral', Color(0xFFD56A3C)),
    GroupTint._('Albastru', Color(0xFF3F78C2)),
    GroupTint._('Miere', Color(0xFFC4922A)),
    GroupTint._('Mov', Color(0xFF8460B8)),
    GroupTint._('Turcoaz', Color(0xFF0E9FBF)),
    GroupTint._('Roz', Color(0xFFC2507A)),
    GroupTint._('Cafeniu', Color(0xFF8E6A4E)),
  ];

  /// Numele treptelor de intensitate (1 = implicit).
  static const levelNames = [
    'Foarte pal',
    'Pal',
    'Mediu',
    'Puternic',
    'Intens',
    'Plin',
  ];
  static const _lightMix = [0.04, 0.09, 0.18, 0.32, 0.5, 0.74];
  static const _darkMix = [0.08, 0.16, 0.26, 0.38, 0.52, 0.7];

  static GroupTint at(int i) => all[i % all.length];

  /// Aceeași culoare, cu altă intensitate / alt scris.
  GroupTint styled({int? level, TintText? text}) => GroupTint._(
    name,
    base,
    level: (level ?? this.level).clamp(0, levelNames.length - 1),
    text: text ?? this.text,
  );

  bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  /// Fundalul cardului / rândului.
  Color surface(BuildContext c) {
    final s = Theme.of(c).colorScheme;
    final dark = _dark(c);
    final bg = dark ? s.surfaceContainerLow : s.surfaceContainerLowest;
    return Color.lerp(bg, base, (dark ? _darkMix : _lightMix)[level])!;
  }

  /// Fundalul iconiței / etichetei — puțin mai colorat decât cardul.
  Color container(BuildContext c) =>
      Color.lerp(surface(c), base, _dark(c) ? 0.35 : 0.17)!;

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static const _darkText = Color(0xFF22261F);
  static const _lightTextColor = Color(0xFFF5F6F2);

  /// Fundal închis → scris deschis (la „Automat”: varianta cu contrast
  /// mai mare față de fundal).
  bool _lightText(BuildContext c) => switch (text) {
    TintText.light => true,
    TintText.dark => false,
    TintText.auto =>
      _contrast(_lightTextColor, surface(c)) > _contrast(_darkText, surface(c)),
  };

  /// Titlurile, iconițele și marginile grupului: în nuanța grupului, dar
  /// destul de închise (sau deschise) ca să se citească pe fundal.
  Color onContainer(BuildContext c) {
    final bg = surface(c);
    final light = _lightText(c);
    final end = light ? Colors.white : Colors.black;
    // de la mult colorat spre alb/negru, până se citește bine
    for (var f = light ? 0.25 : 0.62; f > 0; f -= 0.06) {
      final col = Color.lerp(end, base, f)!;
      if (_contrast(col, bg) >= 4.5) return col;
    }
    return end;
  }

  /// Scrisul obișnuit (titluri de notițe, text, date).
  Color textColor(BuildContext c) =>
      _lightText(c) ? _lightTextColor : _darkText;

  /// Tema din interiorul grupului: scrisul și iconițele în culoarea aleasă.
  ColorScheme scheme(BuildContext c) {
    final fg = textColor(c);
    return Theme.of(c).colorScheme.copyWith(
      onSurface: fg,
      onSurfaceVariant: fg.withValues(alpha: 0.72),
      primary: onContainer(c),
    );
  }

  Widget themed(BuildContext c, Widget child) {
    final t = Theme.of(c);
    final s = scheme(c);
    return Theme(
      data: t.copyWith(
        colorScheme: s,
        listTileTheme: t.listTileTheme.copyWith(
          iconColor: s.onSurfaceVariant,
          textColor: s.onSurface,
        ),
        iconTheme: t.iconTheme.copyWith(color: s.onSurfaceVariant),
        dividerColor: onContainer(c).withValues(alpha: 0.18),
      ),
      child: child,
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final s = brightness == Brightness.light ? AppColors.light : AppColors.dark;
  final light = brightness == Brightness.light;
  final cardColor = light ? s.surfaceContainerLowest : s.surfaceContainerLow;
  const radius = 18.0;

  final base = ThemeData(
    useMaterial3: true,
    // Pe iPhone: fontul Apple pentru text (SF Pro Text), ca aplicațiile
    // native — varianta implicită „Display” e mai largă și pare mai groasă.
    fontFamily: defaultTargetPlatform == TargetPlatform.iOS
        ? 'CupertinoSystemText'
        : null,
    colorScheme: s,
    scaffoldBackgroundColor: s.surface,
    visualDensity: VisualDensity.standard,
  );
  final text = base.textTheme;

  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      foregroundColor: s.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // Mărime explicită: stilurile din bara de sus nu primesc automat
      // dimensiunile tipografiei.
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: s.onSurface,
        letterSpacing: -0.3,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? s.primaryContainer
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? s.onPrimaryContainer
              : s.onSurface,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: s.outlineVariant)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: s.outlineVariant.withValues(alpha: 0.7)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? s.surfaceContainerLowest : s.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: s.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: s.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: s.primary, width: 1.6),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        light ? s.surfaceContainerLowest : s.surfaceContainer,
      ),
      side: WidgetStatePropertyAll(BorderSide(color: s.outlineVariant)),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      hintStyle: WidgetStatePropertyAll(
        TextStyle(color: s.onSurfaceVariant.withValues(alpha: 0.8)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      elevation: 0,
      backgroundColor: light ? s.surfaceContainerLowest : s.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: s.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (st) => TextStyle(
          fontSize: 12,
          fontWeight: st.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: st.contains(WidgetState.selected)
              ? s.onSurface
              : s.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: light ? s.surfaceContainerLowest : s.surfaceContainerLow,
      indicatorColor: s.primaryContainer,
      labelType: NavigationRailLabelType.all,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.primary,
      foregroundColor: s.onPrimary,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: BorderSide(color: s.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: light ? s.surfaceContainerLowest : s.surfaceContainer,
      selectedColor: s.primaryContainer,
      side: BorderSide(color: s.outlineVariant),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: s.onSurface, fontWeight: FontWeight.w500),
      showCheckmark: false,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      iconColor: s.onSurfaceVariant,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surface,
      iconColor: s.primary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: light ? s.surfaceContainerLowest : s.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: s.outlineVariant, space: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? s.onPrimary : null,
      ),
    ),
  );
}
