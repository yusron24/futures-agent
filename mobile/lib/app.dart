import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import 'config/theme.dart';
import 'services/foreground_service.dart';
import 'state/app_state.dart';
import 'ui/dashboard/dashboard_page.dart';
import 'ui/history/history_page.dart';
import 'ui/settings/settings_page.dart';

/// Root aplikasi: tema gelap + navigasi bawah (Dashboard / Riwayat / Pengaturan).
class ScalpSignalsApp extends StatelessWidget {
  const ScalpSignalsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scalp Signals',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();
  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  final _pages = const [
    DashboardPage(),
    HistoryPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final app = context.read<AppState>();
    switch (state) {
      case AppLifecycleState.resumed:
        // Kembali ke depan: hentikan service latar & sambung ulang WS live.
        ForegroundService.stop();
        app.onResume();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Ke latar belakang: mulai foreground service agar sinyal tetap jalan.
        app.onPause();
        if (app.settings.backgroundLive) {
          ForegroundService.start(symbolCount: app.symbols.length);
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // WithForegroundTask menjaga interaksi UI dengan foreground service
    // (mis. saat notifikasi service ditekan) tetap benar.
    return WithForegroundTask(
      child: Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
            BottomNavigationBarItem(
                icon: Icon(Icons.history), label: 'Riwayat'),
            BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined), label: 'Pengaturan'),
          ],
        ),
      ),
    );
  }
}
