import 'package:flutter/material.dart';
import '../../services/app_navigation.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import '../calling/incoming_call_overlay.dart';
import '../main/main_menu_page.dart';
import '../schedule/schedule_page.dart';
import '../messaging/messaging_page.dart';
import '../map/map_page.dart';
import '../finances/payment_tracker_page.dart';

/// The main app shell — port of `AppShell.xaml`'s 5-tab TabBar
/// (Home / Schedule / Messager / Payments / Map). Tab bodies are swapped in as
/// each screen is ported; until then they show a labelled placeholder.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Let the notification layer switch tabs (mirrors MAUI's Shell.GoToAsync).
    AppNavigation.goToTab = (i) {
      if (mounted && i >= 0 && i < _tabs.length) setState(() => _index = i);
    };
  }

  @override
  void dispose() {
    AppNavigation.goToTab = null;
    super.dispose();
  }

  static const _tabs = [
    _TabDef('icon_home', 'Home'),
    _TabDef('icon_calendar', 'Schedule'),
    _TabDef('icon_chat', 'Messager'),
    _TabDef('icon_money', 'Payments'),
    _TabDef('icon_map', 'Map'),
  ];

  // Replaced with real ported screens as they land.
  List<Widget> get _pages => const [
        MainMenuPage(),
        SchedulePage(),
        MessagingPage(),
        PaymentTrackerPage(),
        MapPage(),
      ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IncomingCallOverlay(child: Scaffold(
      backgroundColor: palette.background,
      body: AppShellScope(
        goToTab: (i) {
          if (i >= 0 && i < _tabs.length) setState(() => _index = i);
        },
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: palette.surface,
          indicatorColor: AppColors.iconBgBlue,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppColors.primaryBlue : palette.textSecondary,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (int i = 0; i < _tabs.length; i++)
              NavigationDestination(
                icon: AppIcon(_tabs[i].icon, size: 24, color: palette.textSecondary),
                selectedIcon: AppIcon(_tabs[i].icon, size: 24, color: AppColors.primaryBlue),
                label: _tabs[i].label,
              ),
          ],
        ),
      ),
    ));
  }
}

class _TabDef {
  final String icon;
  final String label;
  const _TabDef(this.icon, this.label);
}

/// Exposes the shell's tab switcher to descendant pages (the MAUI dashboard used
/// `Shell.GoToAsync("//Schedule")`; here a page calls
/// `AppShellScope.of(context)?.goToTab(1)`). Tab indices: 0 Home, 1 Schedule,
/// 2 Messager, 3 Payments, 4 Map.
class AppShellScope extends InheritedWidget {
  const AppShellScope({super.key, required this.goToTab, required super.child});

  final void Function(int index) goToTab;

  static AppShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellScope>();

  @override
  bool updateShouldNotify(AppShellScope oldWidget) => false;
}
