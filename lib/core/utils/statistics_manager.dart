// lib/core/utils/statistics_manager.dart
// 写作统计与成本测算中台
// 真实 Token 累计（从 LLM 响应提取）+ 多模型费率表
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';

class StatisticsManager {
  StatisticsManager._();
  static final StatisticsManager instance = StatisticsManager._();

  // SharedPreferences Keys
  static const _kTotalTokens   = 'stats_total_tokens';
  static const _kInputTokens   = 'stats_input_tokens';
  static const _kOutputTokens  = 'stats_output_tokens';
  static const _kRequestCount  = 'stats_request_count';
  static const _kErrorCount    = 'stats_error_count';
  static const _kSessionStart  = 'stats_session_start';

  // ── 费率表（元/百万 Token，2024年主流费率）─────
  static const _priceTable = {
    // DeepSeek
    'deepseek-chat':      (input: 1.0,   output: 2.0),   // ¥1/¥2 per M
    'deepseek-reasoner':  (input: 4.0,   output: 16.0),
    // 通义千问
    'qwen-plus':          (input: 4.0,   output: 12.0),
    'qwen-turbo':         (input: 2.0,   output: 6.0),
    'qwen-max':           (input: 40.0,  output: 120.0),
    'qwen-long':          (input: 0.5,   output: 1.5),
    // 豆包
    'doubao-pro-128k':    (input: 4.0,   output: 8.0),
    'doubao-lite-128k':   (input: 0.8,   output: 1.6),
    // OpenAI
    'gpt-4o':             (input: 50.0,  output: 150.0),
    'gpt-4o-mini':        (input: 3.0,   output: 10.0),
    // Anthropic
    'claude-3-5-sonnet-20241022': (input: 100.0, output: 300.0),
    'claude-3-5-haiku-20241022':  (input: 10.0,  output: 30.0),
  };

  // ── 累加 Token（在 LLM 调用后立即调用）───────
  Future<void> record({
    required int inputTokens,
    required int outputTokens,
    required String model,
    bool isError = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final total = inputTokens + outputTokens;

    await prefs.setInt(_kTotalTokens,
      (prefs.getInt(_kTotalTokens)  ?? 0) + total);
    await prefs.setInt(_kInputTokens,
      (prefs.getInt(_kInputTokens)  ?? 0) + inputTokens);
    await prefs.setInt(_kOutputTokens,
      (prefs.getInt(_kOutputTokens) ?? 0) + outputTokens);
    await prefs.setInt(_kRequestCount,
      (prefs.getInt(_kRequestCount) ?? 0) + 1);
    if (isError) {
      await prefs.setInt(_kErrorCount,
        (prefs.getInt(_kErrorCount) ?? 0) + 1);
    }
  }

  // ── 全站统计（跨书） ──────────────────────────
  Future<WritingStats> getGlobalStats() async {
    final prefs   = await SharedPreferences.getInstance();
    final db      = AppDatabase.instance;

    // 从数据库取准确字数（不依赖内存）
    final books   = await db.getBooks();
    int totalWords = 0, totalChapters = 0, totalBooks = 0;
    for (final b in books) {
      totalBooks++;
      totalWords    += (b['total_words']    as int? ?? 0);
      totalChapters += (b['total_chapters'] as int? ?? 0);
    }

    // Token 数据
    final inputTokens  = prefs.getInt(_kInputTokens)  ?? 0;
    final outputTokens = prefs.getInt(_kOutputTokens) ?? 0;
    final totalTokens  = prefs.getInt(_kTotalTokens)
                      ?? (totalWords * 3).toInt(); // fallback：中文1字≈3token

    // 从 DB 读取当前使用的模型（bingbu Agent）
    final bingbuCfg = await db.getLlmConfig('bingbu');
    final model     = bingbuCfg?['model'] as String? ?? 'deepseek-chat';
    final price     = _priceTable[model] ?? (input: 1.0, output: 2.0);

    // 精确成本计算（区分输入/输出 Token 费率）
    final costRmb = (inputTokens  / 1000000 * price.input) +
                    (outputTokens / 1000000 * price.output);

    // 每章平均成本
    final costPerChapter = totalChapters > 0 ? costRmb / totalChapters : 0.0;

    // 请求统计
    final requestCount = prefs.getInt(_kRequestCount) ?? 0;
    final errorCount   = prefs.getInt(_kErrorCount)   ?? 0;

    return WritingStats(
      totalBooks:      totalBooks,
      totalChapters:   totalChapters,
      totalWords:      totalWords,
      inputTokens:     inputTokens,
      outputTokens:    outputTokens,
      totalTokens:     totalTokens,
      costRmb:         costRmb,
      costPerChapter:  costPerChapter,
      currentModel:    model,
      requestCount:    requestCount,
      errorCount:      errorCount,
      avgWordsPerChapter: totalChapters > 0
        ? (totalWords / totalChapters).round() : 0,
    );
  }

  // ── 单书统计 ──────────────────────────────────
  Future<BookStats> getBookStats(String bookId) async {
    final db    = AppDatabase.instance;
    final book  = await db.getBook(bookId);
    if (book == null) return BookStats.empty();

    // 从 tasks 统计该书的 Token 消耗
    final tasks = await db.rawQuery(
      'SELECT SUM(tokens_used) as t, COUNT(*) as c FROM tasks WHERE book_id=? AND status=?',
      [bookId, 'DONE'],
    );
    final tokenUsed  = (tasks.isNotEmpty ? tasks.first['t'] as int? : null) ?? 0;
    final chaptersDone = (tasks.isNotEmpty ? tasks.first['c'] as int? : null) ?? 0;

    final model  = (await db.getLlmConfig('bingbu'))?['model'] as String? ?? 'deepseek-chat';
    final price  = _priceTable[model] ?? (input: 1.0, output: 2.0);
    final avgPrice = (price.input + price.output * 2) / 3; // 估算混合费率
    final cost   = tokenUsed / 1000000 * avgPrice;

    return BookStats(
      title:         book['title'] as String,
      totalChapters: book['total_chapters'] as int? ?? 0,
      totalWords:    book['total_words'] as int? ?? 0,
      tokensUsed:    tokenUsed,
      costRmb:       cost,
      chaptersWrittenByAi: chaptersDone,
    );
  }

  // ── 重置统计 ──────────────────────────────────
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTotalTokens);
    await prefs.remove(_kInputTokens);
    await prefs.remove(_kOutputTokens);
    await prefs.remove(_kRequestCount);
    await prefs.remove(_kErrorCount);
  }

  // ── 费率查询 ──────────────────────────────────
  static String estimateChapterCost(String model) {
    final p = _priceTable[model] ?? (input: 1.0, output: 2.0);
    // 一章约 3000 输入 token + 4000 输出 token
    final cost = 3000 / 1000000 * p.input + 4000 / 1000000 * p.output;
    if (cost < 0.001) return '<¥0.001/章';
    if (cost < 0.01)  return '≈¥${cost.toStringAsFixed(4)}/章';
    return '≈¥${cost.toStringAsFixed(3)}/章';
  }
}

// ── 数据模型 ──────────────────────────────────────
class WritingStats {
  const WritingStats({
    required this.totalBooks,
    required this.totalChapters,
    required this.totalWords,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.costRmb,
    required this.costPerChapter,
    required this.currentModel,
    required this.requestCount,
    required this.errorCount,
    required this.avgWordsPerChapter,
  });

  final int    totalBooks, totalChapters, totalWords;
  final int    inputTokens, outputTokens, totalTokens;
  final double costRmb, costPerChapter;
  final String currentModel;
  final int    requestCount, errorCount, avgWordsPerChapter;

  String get costLabel {
    if (costRmb < 0.001) return '<¥0.001';
    if (costRmb < 1)     return '¥${costRmb.toStringAsFixed(4)}';
    return '¥${costRmb.toStringAsFixed(2)}';
  }
  String get tokenLabel {
    if (totalTokens < 10000)  return '$totalTokens';
    if (totalTokens < 1000000) return '${(totalTokens/1000).toStringAsFixed(1)}K';
    return '${(totalTokens/1000000).toStringAsFixed(2)}M';
  }
  String get totalWordsLabel {
    if (totalWords < 10000) return '$totalWords字';
    return '${(totalWords / 10000).toStringAsFixed(1)}万字';
  }
  double get successRate => requestCount > 0
    ? (requestCount - errorCount) / requestCount : 1.0;
}

class BookStats {
  const BookStats({
    required this.title,
    required this.totalChapters,
    required this.totalWords,
    required this.tokensUsed,
    required this.costRmb,
    required this.chaptersWrittenByAi,
  });
  factory BookStats.empty() => const BookStats(
    title: '', totalChapters: 0, totalWords: 0,
    tokensUsed: 0, costRmb: 0, chaptersWrittenByAi: 0);

  final String title;
  final int    totalChapters, totalWords, tokensUsed, chaptersWrittenByAi;
  final double costRmb;
}
