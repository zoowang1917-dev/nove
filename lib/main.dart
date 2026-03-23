// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/db/database.dart';
import 'core/pipeline/novel_pipeline.dart';
import 'providers/providers.dart';
import 'platform/notification_service.dart';
import 'platform/platform_service.dart';

// Fix1: 全局 ProviderContainer，允许 main() 在 Widget 树外读写 Provider
final container = ProviderContainer();

void main() async {
  // 必须放在第一行
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 1. 初始化数据库
    await AppDatabase.instance.db;

    // 3. 通知服务
    await NotificationService.instance.init();

    // 4. 系统 UI 和平台
    await platform.init();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF111214),
      ),
    );

    if (platform.isMobile) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }

    // 所有准备工作顺利完成，正常启动 App！
    runApp(UncontrolledProviderScope(
      container: container,
      child: const NovelAIApp(),
    ));

  } catch (e, stackTrace) {
    // 💥 核心破局点：如果上面任何一步报错了，不要白屏，直接把报错信息显示在屏幕上！
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                '❌ 启动失败 (Init Error):\n\n$e\n\n$stackTrace',
                style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class NovelAIApp extends ConsumerWidget {
  const NovelAIApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title:                    '三省六部 × InkOS',
      debugShowCheckedModeBanner: false,
      theme:                    AppTheme.dark,
      routerConfig:             ref.watch(routerProvider),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.noScaling),
        child: child!,
      ),
    );
  }
}
