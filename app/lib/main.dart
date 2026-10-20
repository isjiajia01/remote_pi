import 'dart:async';
import 'package:app/data/approvals/approval_service.dart';
import 'package:app/data/push/push_service.dart';
import 'package:app/config/dependencies.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plan 31 — open the v2 SSOT boxes + WIPE the volatile runtime box BEFORE
  // anything subscribes (#3 / Risk 2).
  await LocalBoxes.init();
  await setupDependencies();
  // Eagerly construct the SSOT writer so it's consuming the channel from boot
  // (messages can arrive before the chat screen mounts).
  injector.get<SyncService>();
  injector.get<ApprovalService>();
  runApp(const RemotePiApp());
}

class RemotePiApp extends StatefulWidget {
  const RemotePiApp({super.key});

  @override
  State<RemotePiApp> createState() => _RemotePiAppState();
}

class _RemotePiAppState extends State<RemotePiApp> with WidgetsBindingObserver {
  late final _router = buildRouter(
    injector.get<PairingStorage>(),
    injector.get<ConnectionManager>(),
    injector.get<Preferences>(),
    injector.get<OwnerIdentityBridge>(),
    injector.get<MeshSyncService>(),
  );

  StreamSubscription<Map<String, dynamic>>? _pushSub;
  Map<String, dynamic>? _pendingNotification;
  bool get _notificationReady => !{
    '/boot',
    '/sync-required',
  }.contains(_router.routeInformationProvider.value.uri.path);
  void _onRouteChanged() {
    if (!_notificationReady || _pendingNotification == null) return;
    final payload = _pendingNotification!;
    _pendingNotification = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openNotification(payload));
    });
  }

  Future<void> _openNotification(Map<String, dynamic> payload) async {
    if (!_notificationReady) {
      _pendingNotification = payload;
      return;
    }
    final storage = injector.get<PairingStorage>();
    final prefs = injector.get<Preferences>();
    final conn = injector.get<ConnectionManager>();
    final target = injector.get<ApprovalService>().resolveNotification(payload);
    if (target == null || await storage.loadPeer(target.peerEpk) == null) {
      if (mounted) _router.go('/home?notification=unavailable');
      return;
    }
    await prefs.setSelectedRoom(epk: target.peerEpk, roomId: target.roomId);
    if (!mounted) return;
    conn.switchRoom(target.roomId);
    _router.go('/home');
    unawaited(_router.push('/chat'));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router.routeInformationProvider.addListener(_onRouteChanged);
    _pushSub = injector.get<PushService>().taps.listen(
      (payload) => unawaited(_openNotification(payload)),
    );
    // Start after the first frame; native retains taps until ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(injector.get<PushService>().start());
    });
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    _router.routeInformationProvider.removeListener(_onRouteChanged);
    _router.dispose();
    WidgetsBinding.instance.removeObserver(this);
    disposeDependencies();
    super.dispose();
  }

  /// Plan 24 — keep the mesh poll timer aligned with the app's
  /// foreground lifecycle. Polling runs ONLY while resumed; in
  /// inactive/paused/hidden/detached we cancel so we don't drain the
  /// battery (and we'll resync via `pullOnDemand` on the next resume +
  /// boot path).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final meshSync = injector.get<MeshSyncService>();
    switch (state) {
      case AppLifecycleState.resumed:
        meshSync.startPolling();
        unawaited(injector.get<PushService>().start());
        // ignore: unawaited_futures
        meshSync.pullOnDemand();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        meshSync.stopPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Preferences>.value(
          value: injector.get<Preferences>(),
        ),
        ChangeNotifierProvider<SessionSelection>.value(
          value: injector.get<SessionSelection>(),
        ),
        // Shell layout state — lets the adaptive shell collapse the split
        // into a single centered pane on zero-state Home (no Pi / empty).
        ChangeNotifierProvider<ShellLayout>.value(
          value: injector.get<ShellLayout>(),
        ),
      ],
      // Theme is reactive: toggling the mode in Settings notifies
      // [Preferences] → this Consumer rebuilds → MaterialApp swaps theme.
      child: Consumer<Preferences>(
        builder: (context, prefs, _) => MaterialApp.router(
          title: 'Remote Pi',
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: prefs.themeMode,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
          // Issue #114 — user-chosen text size. Applied here rather than by
          // scaling `AppTypography`'s base sizes so the many per-widget
          // `copyWith(fontSize: …)` overrides scale too. `TextScaler.linear`
          // REPLACES the platform scaler, which is deliberate: Flutter can't
          // read iOS's per-app Text Size anyway (it only reads the global
          // accessibility setting), so honoring both would compound them.
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: prefs.fontScale.factor,
            maxScaleFactor: prefs.fontScale.factor,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
