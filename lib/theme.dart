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
