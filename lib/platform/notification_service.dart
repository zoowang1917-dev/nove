// lib/platform/notification_service.dart
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // ── 通知渠道（Android 8+）───────────────────
  static const _chWriting = 'novel_writing';     // 写作进度
  static const _chAlert   = 'novel_alert';       // 伏笔/角色告警
  static const _chBg      = 'novel_background';  // 后台任务完成

  // ── 初始化 ─────────────────────────────────
  Future<void> init() async {
    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission:  true,
      requestBadgePermission:  true,
      requestSoundPermission:  false, // 写作 App 默认静音
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Android 创建通知渠道
    if (Platform.isAndroid) {
      await _createChannels();
    }

    _ready = true;
  }

  Future<void> _createChannels() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await impl?.createNotificationChannel(const AndroidNotificationChannel(
      _chWriting, '写作进度',
      description: '显示 AI 写作任务的实时状态',
      importance:  Importance.low,
      playSound:   false,
      enableVibration: false,
    ));
    await impl?.createNotificationChannel(const AndroidNotificationChannel(
      _chAlert, '伏笔与人物告警',
      description: '伏笔账龄超限、遗忘角色等提醒',
      importance:  Importance.defaultImportance,
    ));
    await impl?.createNotificationChannel(const AndroidNotificationChannel(
      _chBg, '后台任务',
      description: '自动续写任务完成通知',
      importance:  Importance.defaultImportance,
    ));
  }

  // ── 写作进行中通知（前台进度条）─────────────
  Future<void> showWritingProgress({
    required String bookTitle,
    required String agentName,
    int progress = 0, // 0-100
  }) async {
    if (!_ready) return;
    await _plugin.show(
      1001,
      '⚔️ 写作中：$bookTitle',
      '$agentName 正在处理...',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _chWriting, '写作进度',
          ongoing:         true,
          showProgress:    true,
          maxProgress:     100,
          progress:        progress,
          indeterminate:   progress == 0,
          styleInformation: const BigTextStyleInformation(''),
          icon:            '@drawable/ic_writing',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      ),
    );
  }

  /// 清除写作进度通知
  Future<void> clearWritingProgress() => _plugin.cancel(1001);

  // ── 任务完成通知 ────────────────────────────
  Future<void> notifyChapterDone({
    required String bookTitle,
    required int chapterNo,
    required int wordCount,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      2000 + chapterNo,
      '✅ 第${chapterNo}章完成',
      '$bookTitle · 本章 $wordCount 字，等待审核',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _chBg, '后台任务',
          styleInformation: BigTextStyleInformation(
            '$bookTitle\n第${chapterNo}章已生成（${wordCount}字），请打开 App 审核',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
        ),
      ),
    );
  }

  // ── 伏笔告警通知 ────────────────────────────
  Future<void> notifyHookAlert({
    required int criticalCount,
    required String bookTitle,
  }) async {
    if (!_ready || criticalCount == 0) return;
    await _plugin.show(
      3001,
      '🔗 $criticalCount 条伏笔需要回收',
      '$bookTitle · 有伏笔账龄超过 20 章，建议尽快安排',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _chAlert, '伏笔与人物告警',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false,
        ),
      ),
    );
  }

  // ── 遗忘角色告警 ────────────────────────────
  Future<void> notifyForgottenChar({
    required String charName,
    required int missedChapters,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      4000,
      '👥 角色长期未出场',
      '"$charName" 已 $missedChapters 章未出场，吏部建议安排戏份',
      NotificationDetails(
        android: AndroidNotificationDetails(_chAlert, '伏笔与人物告警'),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: false),
      ),
    );
  }

  // ── 门下省封驳通知 ──────────────────────────
  Future<void> notifyMenxiaBlocked({
    required String bookTitle,
    required String reason,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      5001,
      '🔍 门下省三次封驳，需要您介入',
      '$bookTitle · $reason',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _chAlert, '伏笔与人物告警',
          importance: Importance.high,
          priority:   Priority.high,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  void _onNotificationTap(NotificationResponse resp) {
    // TODO: 根据 payload 跳转到对应页面
    // 可通过 GoRouter 全局 key 导航
  }
}
