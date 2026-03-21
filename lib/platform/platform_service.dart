// lib/platform/platform_service.dart
// 多端适配核心：统一 Android / iOS 平台差异
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 设备与平台信息缓存
class PlatformService {
  PlatformService._();
  static final PlatformService instance = PlatformService._();

  DeviceInfoPlugin?  _deviceInfo;
  PackageInfo?       _packageInfo;
  AndroidDeviceInfo? _android;
  IosDeviceInfo?     _ios;

  bool get isAndroid => Platform.isAndroid;
  bool get isIOS     => Platform.isIOS;
  bool get isMobile  => isAndroid || isIOS;

  // ── 初始化（main() 中调用）──────────────────
  Future<void> init() async {
    _deviceInfo   = DeviceInfoPlugin();
    _packageInfo  = await PackageInfo.fromPlatform();

    if (isAndroid) {
      _android = await _deviceInfo!.androidInfo;
    } else if (isIOS) {
      _ios = await _deviceInfo!.iosInfo;
    }
  }

  // ── 应用信息 ───────────────────────────────
  String get appVersion   => _packageInfo?.version        ?? '1.0.0';
  String get buildNumber  => _packageInfo?.buildNumber    ?? '1';
  String get packageName  => _packageInfo?.packageName    ?? 'com.novel.ai';

  // ── 设备信息 ───────────────────────────────
  String get deviceModel {
    if (isAndroid) return _android?.model            ?? 'Android';
    if (isIOS)     return _ios?.utsname.machine       ?? 'iPhone';
    return 'Unknown';
  }

  String get osVersion {
    if (isAndroid) return 'Android ${_android?.version.release ?? ''}';
    if (isIOS)     return 'iOS ${_ios?.systemVersion ?? ''}';
    return 'Unknown';
  }

  int get androidSdkInt => _android?.version.sdkInt ?? 0;

  // Android 12+ 有更严格的后台限制
  bool get isAndroid12Plus => isAndroid && androidSdkInt >= 31;
  // Android 13+ 需要 POST_NOTIFICATIONS 权限
  bool get isAndroid13Plus => isAndroid && androidSdkInt >= 33;

  // ── 权限管理 ───────────────────────────────

  /// 申请存储权限（Android < 13 需要；Android 13+ 用 READ_MEDIA_*）
  Future<bool> requestStoragePermission() async {
    if (isIOS) return true; // iOS 不需要显式申请
    if (isAndroid13Plus) {
      // Android 13+ 文件选择器自动处理，不需要 STORAGE
      return true;
    }
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  /// 申请通知权限
  Future<bool> requestNotificationPermission() async {
    if (isAndroid13Plus) {
      final status = await Permission.notification.request();
      return status.isGranted;
    }
    return true;
  }

  /// 检查并申请所有需要的权限
  Future<Map<String, bool>> requestAllPermissions() async {
    final results = <String, bool>{};

    results['notification'] = await requestNotificationPermission();
    results['storage']      = await requestStoragePermission();

    // iOS 不需要额外权限，Android 后台任务自动通知
    return results;
  }

  // ── 文件路径 ───────────────────────────────

  /// 文档目录（用于保存导出文件）
  Future<String> getDocumentsPath() async {
    if (isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    }
    // Android：优先外部存储 Downloads，失败则用应用目录
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return '${ext.path}/Downloads';
    } catch (_) {}
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// 临时目录（用于上传前缓存）
  Future<String> getTempPath() async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  }

  // ── 系统 UI 配置 ───────────────────────────

  /// 写作模式：防息屏 + 沉浸式
  Future<void> enterWritingMode() async {
    await WakelockPlus.enable();
    if (isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    }
  }

  /// 退出写作模式
  Future<void> exitWritingMode() async {
    await WakelockPlus.disable();
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
  }

  /// 阅读模式：亮度降低，状态栏隐藏
  Future<void> enterReadingMode() async {
    await WakelockPlus.enable();
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersive,
    );
  }

  Future<void> exitReadingMode() async {
    await WakelockPlus.disable();
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
  }

  // ── 震动反馈 ───────────────────────────────
  Future<void> hapticLight()  async => HapticFeedback.lightImpact();
  Future<void> hapticMedium() async => HapticFeedback.mediumImpact();
  Future<void> hapticHeavy()  async => HapticFeedback.heavyImpact();
  Future<void> hapticSelect() async => HapticFeedback.selectionClick();

  // ── 平台特有 UI 尺寸 ───────────────────────

  /// iOS 是否有刘海（影响 safe area 计算）
  bool get hasNotch {
    if (!isIOS) return false;
    final model = deviceModel.toLowerCase();
    // iPhone X 及以后
    return model.contains('iphone') &&
        !['iphone8', 'iphone7', 'iphone6'].any(model.contains);
  }

  /// Android 导航栏高度估算
  double get androidNavBarHeight {
    if (!isAndroid) return 0;
    // Android 10+ gesture nav = 0, button nav ≈ 48
    return androidSdkInt >= 29 ? 0 : 48;
  }
}

/// 便捷全局访问
final platform = PlatformService.instance;
