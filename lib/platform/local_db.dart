// lib/platform/local_db.dart
// 轻量 KV 缓存：阅读进度 + 草稿暂存
// 复用 AppDatabase 的 app_settings 表，无需额外表
import '../core/db/database.dart';

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  // ── 阅读进度 ─────────────────────────────────
  Future<void> saveReadingProgress(
      String bookId, int chapterNo, double scrollPos) async {
    await AppDatabase.instance.setSetting(
      'reading_${bookId}',
      '$chapterNo:$scrollPos',
    );
  }

  Future<({int chapterNo, double scrollPos})?> getReadingProgress(
      String bookId) async {
    final raw = await AppDatabase.instance.getSetting('reading_$bookId');
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    return (
      chapterNo: int.tryParse(parts[0]) ?? 1,
      scrollPos: double.tryParse(parts[1]) ?? 0.0,
    );
  }

  // ── 草稿暂存（写作中断恢复）──────────────────
  Future<void> saveDraft(String bookId, String content) async {
    await AppDatabase.instance.setSetting('draft_$bookId', content);
  }

  Future<String?> getDraft(String bookId) async {
    return AppDatabase.instance.getSetting('draft_$bookId');
  }

  Future<void> clearDraft(String bookId) async {
    await AppDatabase.instance.setSetting('draft_$bookId', '');
  }

  // ── 通用设置 ──────────────────────────────────
  Future<String?> getSetting(String key) =>
      AppDatabase.instance.getSetting(key);

  Future<void> setSetting(String key, String value) =>
      AppDatabase.instance.setSetting(key, value);
}
