// lib/core/utils/backup_manager.dart
// Fix7: 完整数据库备份与恢复
// 使用 share_plus 导出 .db 文件（用户可存入微信/iCloud/网盘）
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';

class BackupManager {
  BackupManager._();
  static final BackupManager instance = BackupManager._();

  static const _dbName = 'novel_ai.db';

  // ── 导出数据库 ─────────────────────────────
  /// 导出完整 SQLite 数据库文件
  /// 调出系统分享面板，用户可选择存入微信收藏/百度网盘/iCloud/邮件等
  Future<BackupResult> exportDatabase() async {
    try {
      final dbDir  = await getDatabasesPath();
      final dbPath = p.join(dbDir, _dbName);
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        return BackupResult.failure('未找到数据库文件，请先创建一本书再备份');
      }

      // 生成带时间戳的备份文件名
      final now     = DateTime.now();
      final stamp   = '${now.year}${_pad(now.month)}${_pad(now.day)}'
                      '_${_pad(now.hour)}${_pad(now.minute)}';
      final backupName = 'InkOS_Backup_$stamp.db';

      // 复制到 Documents 目录（share_plus 需要稳定路径）
      final docsDir    = await getApplicationDocumentsDirectory();
      final backupFile = File(p.join(docsDir.path, backupName));
      await dbFile.copy(backupFile.path);

      // 文件大小
      final sizeKB = (await backupFile.length() / 1024).toStringAsFixed(1);

      await Share.shareXFiles(
        [XFile(backupFile.path, name: backupName)],
        subject: '三省六部 AI网文 — 数据备份',
        text: '备份文件包含：所有书籍、章节内容、角色圣经、世界观档案、伏笔记录。\n'
              '恢复方法：将此文件替换手机内的同名数据库文件。\n'
              '文件大小：${sizeKB}KB',
      );

      return BackupResult.success(backupFile.path, sizeKB);
    } catch (e) {
      return BackupResult.failure('备份失败：$e');
    }
  }

  // ── 恢复数据库 ─────────────────────────────
  /// 从 .db 文件恢复（需配合 file_picker 使用）
  Future<BackupResult> importDatabase(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return BackupResult.failure('找不到备份文件：$sourcePath');
      }

      // 验证是否为 SQLite 文件（检查文件头魔数）
      final bytes = await sourceFile.openRead(0, 16).first;
      if (bytes.length < 16 ||
          String.fromCharCodes(bytes.sublist(0, 6)) != 'SQLite') {
        return BackupResult.failure('不是有效的 SQLite 数据库文件');
      }

      final dbDir    = await getDatabasesPath();
      final dbPath   = p.join(dbDir, _dbName);
      final dbFile   = File(dbPath);

      // 备份当前数据库（防止恢复失败丢失数据）
      if (await dbFile.exists()) {
        final safetyBackup = File('$dbPath.bak');
        await dbFile.copy(safetyBackup.path);
      }

      // 替换数据库文件
      await sourceFile.copy(dbPath);

      return BackupResult.success(dbPath, null,
        message: '恢复成功！请重启 App 使数据生效。');
    } catch (e) {
      return BackupResult.failure('恢复失败：$e');
    }
  }

  // ── 备份信息查询 ───────────────────────────
  Future<BackupInfo> getDatabaseInfo() async {
    try {
      final dbDir  = await getDatabasesPath();
      final dbPath = p.join(dbDir, _dbName);
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        return BackupInfo(exists: false, sizeKB: 0, lastModified: null);
      }

      final stat = await dbFile.stat();
      final size = stat.size / 1024;
      return BackupInfo(
        exists:       true,
        sizeKB:       size,
        lastModified: stat.modified,
        path:         dbPath,
      );
    } catch (_) {
      return BackupInfo(exists: false, sizeKB: 0, lastModified: null);
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

// ── 结果模型 ──────────────────────────────────
class BackupResult {
  const BackupResult._({
    required this.success,
    this.path,
    this.sizeKB,
    this.message,
    this.error,
  });

  factory BackupResult.success(String path, String? sizeKB, {String? message}) =>
    BackupResult._(success: true, path: path, sizeKB: sizeKB,
      message: message ?? '备份成功！文件大小：${sizeKB ?? "?"}KB');

  factory BackupResult.failure(String error) =>
    BackupResult._(success: false, error: error);

  final bool    success;
  final String? path;
  final String? sizeKB;
  final String? message;
  final String? error;
}

class BackupInfo {
  const BackupInfo({
    required this.exists,
    required this.sizeKB,
    required this.lastModified,
    this.path,
  });
  final bool      exists;
  final double    sizeKB;
  final DateTime? lastModified;
  final String?   path;

  String get sizeLabel => sizeKB < 1024
    ? '${sizeKB.toStringAsFixed(1)} KB'
    : '${(sizeKB / 1024).toStringAsFixed(2)} MB';
}
