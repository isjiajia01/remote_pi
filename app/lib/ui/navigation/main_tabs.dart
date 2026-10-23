import 'package:app/config/features.dart';
import 'package:app/ui/core/interaction_feedback.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/timeline/viewmodels/timeline_viewmodel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

/// The existing Agents master/detail navigator remains inside the Agents tab.
class MainTabs extends StatefulWidget {
  const MainTabs({super.key, required this.location, required this.child});
  final String location;
  final Widget child;
  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> with WidgetsBindingObserver {
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateActivity();
  }

  void _updateActivity() {
    if (!perchFullFeatures) return;
    context.read<TimelineViewModel>().setActive(
      _foreground && widget.location == '/timeline',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateActivity();
    });
    final index = switch (widget.location) {
      '/timeline' => 1,
      '/settings' => perchFullFeatures ? 2 : 1,
      _ => 0,
    };
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: widget.child,
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: index,
        backgroundColor: context.colors.surface,
        activeColor: context.colors.accent,
        inactiveColor: context.colors.ink2,
        border: Border(top: BorderSide(color: context.colors.hairline)),
        onTap: (next) {
          if (next == index) return;
          InteractionFeedback.selection();
          context.go(
            (perchFullFeatures
                ? ['/home', '/timeline', '/settings']
                : ['/home', '/settings'])[next],
          );
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.bot, size: 22),
            label: 'Agents',
          ),
          if (perchFullFeatures)
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.activity, size: 22),
              label: 'Timeline',
            ),
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.settings, size: 22),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
