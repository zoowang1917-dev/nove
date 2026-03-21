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
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化数据库
  await AppDatabase.instance.db;

  // Fix1: 检测系统杀后台留下的中断任务
  final hasInterrupted = await NovelPipeline.instance.recoverOnStartup();
  if (hasInterrupted) {
    container.read(interruptedTaskProvider.notifier).state = 'recovered';
  }

  // 通知服务
  await NotificationService.instance.init();

  // 系统 UI
  await platform.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:          Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    navigationBarColor:      Color(0xFF111214),
  ));

  if (platform.isMobile) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // 把同一个 container 传给 ProviderScope，确保状态共享
  runApp(UncontrolledProviderScope(
    container: container,
    child: const NovelAIApp(),
  ));
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
