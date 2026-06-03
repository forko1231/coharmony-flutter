import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_icon.dart';
import 'child_main_menu.dart';
import 'child_schedule_page.dart';
import 'child_messaging_page.dart';

/// Port of `Views/Child/ChildAppShell.xaml` — the child-account shell with a
/// 3-tab bottom nav (Home / Schedule / Messages). Separate from the parent
/// [AppShell], which has 5 tabs and parent-only features.
class ChildAppShell extends StatefulWidget {
  const ChildAppShell({super.key});

  @override
  State<ChildAppShell> createState() => _ChildAppShellState();
}

class _ChildAppShellState extends State<ChildAppShell> {
  int _index = 0;

  static const _tabs = [
    ('icon_home', 'Home'),
    ('icon_calendar', 'Schedule'),
    ('icon_chat', 'Messages'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pages = [
      ChildMainMenu(onViewSchedule: () => setState(() => _index = 1)),
      const ChildSchedulePage(),
      const ChildMessagingPage(),
    ];
    return Scaffold(
      backgroundColor: palette.background,
      body: IndexedStack(index: _index, children: pages),
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
            for (final t in _tabs)
              NavigationDestination(
                icon: AppIcon(t.$1, size: 24, color: palette.textSecondary),
                selectedIcon: AppIcon(t.$1, size: 24, color: AppColors.primaryBlue),
                label: t.$2,
              ),
          ],
        ),
      ),
    );
  }
}
