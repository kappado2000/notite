import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'account_tab.dart';
import 'home_tab.dart';
import 'notes_tab.dart';
import 'secrets/secrets_screen.dart';

/// Navigarea între file. Permite unei file să deschidă alta
/// (ex. „Acasă” → un carnet anume în „Notițe”).
class ShellController extends ChangeNotifier {
  int index = 0;

  /// Vederea cerută pentru fila Notițe (consumată de NotesTab).
  NoteView? pendingView;

  void go(int i) {
    if (i == index) return;
    index = i;
    notifyListeners();
  }

  void openNotes([NoteView view = const AllNotesView()]) {
    pendingView = view;
    index = 1;
    notifyListeners();
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _controller = ShellController();

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Acasă'),
    (Icons.sticky_note_2_outlined, Icons.sticky_note_2, 'Notițe'),
    (Icons.key_outlined, Icons.key, 'Parole'),
    (Icons.person_outline, Icons.person, 'Cont'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _tab(int i) => switch (i) {
    0 => const HomeTab(),
    1 => const NotesTab(),
    // Parole se reconstruiește la fiecare intrare → cere din nou deblocarea.
    2 => const SecretsScreen(),
    _ => const AccountTab(),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<ShellController>(
        builder: (context, shell, _) {
          // Acasă și Notițe își păstrează starea (derulare, filtre).
          final body = shell.index <= 1
              ? IndexedStack(index: shell.index, children: [_tab(0), _tab(1)])
              : KeyedSubtree(
                  key: ValueKey(shell.index),
                  child: _tab(shell.index),
                );

          if (wide) {
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: shell.index,
                    onDestinationSelected: shell.go,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: _Logo(),
                    ),
                    destinations: [
                      for (final (icon, selected, label) in _destinations)
                        NavigationRailDestination(
                          icon: Icon(icon),
                          selectedIcon: Icon(selected),
                          label: Text(label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              ),
            );
          }

          // Înălțimea ocupată de bara plutitoare (bară + margine + sistem).
          final inset =
              _FloatingNavBar.height +
              MediaQuery.paddingOf(context).bottom
                  .clamp(_FloatingNavBar.gap, double.infinity);
          final theme = Theme.of(context);
          return Scaffold(
            // Conținutul derulează pe sub bara plutitoare.
            extendBody: true,
            body: NavInset(
              inset: inset,
              // Notificările de jos apar deasupra barei, nu sub ea.
              child: Theme(
                data: theme.copyWith(
                  snackBarTheme: theme.snackBarTheme.copyWith(
                    insetPadding: EdgeInsets.fromLTRB(16, 0, 16, inset + 8),
                  ),
                ),
                child: body,
              ),
            ),
            bottomNavigationBar: _FloatingNavBar(
              index: shell.index,
              onSelect: shell.go,
              destinations: _destinations,
            ),
          );
        },
      ),
    );
  }
}

/// Bară de navigare plutitoare, desprinsă de margini, 80% opacă,
/// cu blur peste conținutul de dedesubt.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.index,
    required this.onSelect,
    required this.destinations,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<(IconData, IconData, String)> destinations;

  static const height = 66.0;
  static const gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLowest;
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: gap),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.4 : 0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: NavigationBar(
                  height: height,
                  backgroundColor: Colors.transparent,
                  selectedIndex: index,
                  onDestinationSelected: onSelect,
                  destinations: [
                    for (final (icon, selected, label) in destinations)
                      NavigationDestination(
                        icon: Icon(icon),
                        selectedIcon: Icon(selected),
                        label: label,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.edit_note, color: scheme.onPrimary),
    );
  }
}

/// Cât spațiu ocupă jos bara plutitoare (0 pe ecrane late, cu bară laterală).
class NavInset extends InheritedWidget {
  const NavInset({super.key, required this.inset, required super.child});

  final double inset;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavInset>()?.inset ??
      MediaQuery.paddingOf(context).bottom;

  @override
  bool updateShouldNotify(NavInset old) => old.inset != inset;
}

/// Spațiul de lăsat jos în liste, ca ultimul element să nu stea sub bara
/// plutitoare sau sub butonul „+”.
double bottomSpace(BuildContext context, {bool fab = true}) =>
    NavInset.of(context) + (fab ? 88 : 16);

/// Ridică butonul „+” al unei file deasupra barei plutitoare.
Widget? aboveNavBar(BuildContext context, Widget? fab) => fab == null
    ? null
    : Padding(
        padding: EdgeInsets.only(bottom: NavInset.of(context)),
        child: fab,
      );
