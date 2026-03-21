// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/db/database.dart';
import '../../screens/splash/splash_screen.dart';
import '../../screens/splash/onboarding_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/writing/writing_screen.dart';
import '../../screens/kanban/kanban_screen.dart';
import '../../screens/world/world_screen.dart';
import '../../screens/hooks/hooks_screen.dart';
import '../../screens/characters/characters_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/style/style_screen.dart';
import '../../screens/export/export_screen.dart';
import '../../screens/reader/reader_screen.dart';
import '../../screens/chat/chat_screen.dart';
import '../../screens/detection/detection_screen.dart';

final routerProvider = Provider<GoRouter>((ref) => GoRouter(
  initialLocation: '/splash',
  redirect: (ctx, state) async {
    if (state.uri.path == '/') {
      final done = await AppDatabase.instance.getSetting('onboarding_done');
      if (done == null) return '/onboarding';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/splash',     builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),

    // ── 主 Shell（底部6Tab）──
    ShellRoute(
      builder: (_, __, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/',         builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/chat',     builder: (_, __) => const ChatScreen()),
        GoRoute(path: '/kanban',   builder: (_, __) => const KanbanScreen()),
        GoRoute(path: '/hooks',
          builder: (_, s) => HooksScreen(bookId: s.uri.queryParameters['bookId'] ?? '')),
        GoRoute(path: '/world',
          builder: (_, s) => WorldScreen(bookId: s.uri.queryParameters['bookId'] ?? '')),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    ),

    // ── 全屏页 ──
    GoRoute(path: '/writing/:bookId',
      builder: (_, s) => WritingScreen(bookId: s.pathParameters['bookId']!)),
    GoRoute(path: '/reader/:bookId',
      builder: (_, s) => ReaderScreen(
        bookId:         s.pathParameters['bookId']!,
        initialChapter: int.tryParse(s.uri.queryParameters['chapter'] ?? '1') ?? 1)),
    GoRoute(path: '/characters/:bookId',
      builder: (_, s) => CharactersScreen(bookId: s.pathParameters['bookId']!)),
    GoRoute(path: '/style',  builder: (_, __) => const StyleScreen()),
    GoRoute(path: '/export/:bookId',
      builder: (_, s) => ExportScreen(bookId: s.pathParameters['bookId']!)),
    GoRoute(path: '/detect',
      builder: (_, s) => DetectionScreen(bookId: s.uri.queryParameters['bookId'])),
    GoRoute(path: '/detect/:bookId',
      builder: (_, s) => DetectionScreen(bookId: s.pathParameters['bookId'])),
  ],
  errorBuilder: (_, state) => Scaffold(
    backgroundColor: AppColors.bg0,
    body: Center(child: Text('404: ${state.uri}',
      style: const TextStyle(color: AppColors.text3)))),
));

// ════════════════════════════════════════════
// MainShell — 底部6Tab 导航
// ════════════════════════════════════════════
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    (Icons.library_books_outlined,   Icons.library_books,    '书库',    '/'),
    (Icons.chat_bubble_outline,      Icons.chat_bubble,      'AI助手',  '/chat'),
    (Icons.account_balance_outlined, Icons.account_balance,  '看板',    '/kanban'),
    (Icons.link_outlined,            Icons.link,             '伏笔',    '/hooks'),
    (Icons.map_outlined,             Icons.map,              '世界观',  '/world'),
    (Icons.settings_outlined,        Icons.settings,         '设置',    '/settings'),
  ];

  int _idx(String loc) {
    for (int i = _tabs.length - 1; i >= 0; i--) {
      final r = _tabs[i].$4;
      if (r == '/' ? loc == '/' : loc.startsWith(r)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc    = GoRouterState.of(context).uri.toString();
    final bookId = ref.watch(currentBookIdProvider);
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line1))),
        child: NavigationBar(
          selectedIndex: _idx(loc),
          destinations: _tabs.map((t) => NavigationDestination(
            icon:         Icon(t.$1),
            selectedIcon: Icon(t.$2),
            label:        t.$3,
          )).toList(),
          onDestinationSelected: (i) {
            final r = _tabs[i].$4;
            final q = bookId != null && (r == '/hooks' || r == '/world')
              ? '?bookId=$bookId' : '';
            context.go('$r$q');
          },
        ),
      ),
    );
  }
}
