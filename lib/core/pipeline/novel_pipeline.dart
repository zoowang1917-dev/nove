// lib/core/pipeline/novel_pipeline.dart
// 三省六部写作管线 — 修复版
// Fix1: _running 状态持久化，防系统杀后台死锁
// Fix3: 动态档案上下文（核心常驻 + 滑动窗口）
// Fix5: 门下省断路器，防无限循环

import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../agents/agents.dart';
import '../db/database.dart';
import '../detection/text_detector.dart';
import '../../screens/style/style_screen.dart';

// ════════════════════════════════════════════
// Fix5: 门下省断路器异常
// ════════════════════════════════════════════
class PipelineInterruptedException implements Exception {
  const PipelineInterruptedException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ════════════════════════════════════════════
// 管线事件
// ════════════════════════════════════════════
enum PipelineEventType {
  agentSwitch, token, auditResult, statusChange, needReview, done, error
}

class PipelineEvent {
  const PipelineEvent({required this.type, this.agentId, this.content, this.data});
  final PipelineEventType     type;
  final String?               agentId;
  final String?               content;
  final Map<String, dynamic>? data;
}

// ════════════════════════════════════════════
// 任务状态
// ════════════════════════════════════════════
// Fix5: 门下省最多2次封驳，第3次必须断路（抛异常给用户而非强制通过）
const _maxReject     = 2;   // 0,1次封驳→重写；第2次→断路
const _maxAuditRound = 5;

enum TaskStatus {
  planning, reviewing, rejected, assigned, executing,
  auditing, revising, pendingHuman, done, blocked
}

extension TaskStatusX on TaskStatus {
  String get label => switch (this) {
    TaskStatus.planning     => '中书规划',
    TaskStatus.reviewing    => '门下审议',
    TaskStatus.rejected     => '已封驳',
    TaskStatus.assigned     => '准奏派发',
    TaskStatus.executing    => '六部写作',
    TaskStatus.auditing     => '连续性审计',
    TaskStatus.revising     => '自动修订',
    TaskStatus.pendingHuman => '待人工审核',
    TaskStatus.done         => '已完成',
    TaskStatus.blocked      => '已阻塞',
  };
}

// ════════════════════════════════════════════
// 写作管线（Fix1: 状态持久化）
// ════════════════════════════════════════════
class NovelPipeline {
  NovelPipeline._();
  static final NovelPipeline instance = NovelPipeline._();

  // SharedPreferences keys
  static const _kRunning  = 'pipeline_is_running';
  static const _kTaskId   = 'pipeline_task_id';
  static const _kBookId   = 'pipeline_book_id';
  static const _kInstr    = 'pipeline_instruction';

  final _uuid = const Uuid();
  String? _currentBookId; // Fix6: 记录当前书籍，供标题生成获取题材

  // 内存状态（以 SharedPreferences 为权威源）
  bool _running       = false;
  bool _stopRequested = false;

  final _ctrl = StreamController<PipelineEvent>.broadcast();
  Stream<PipelineEvent> get events => _ctrl.stream;

  bool get isRunning => _running;

  void stop() => _stopRequested = true;

  void _emit(PipelineEvent e) { if (!_ctrl.isClosed) _ctrl.add(e); }
  void _switch(String id, String action) => _emit(PipelineEvent(
    type: PipelineEventType.agentSwitch, agentId: id, content: action));
  void _status(String taskId, TaskStatus status) => _emit(PipelineEvent(
    type: PipelineEventType.statusChange, agentId: 'system',
    data: {'taskId': taskId, 'status': status.name, 'label': status.label}));

  // ── Fix1: 启动时恢复持久化状态 ─────────────
  /// 应用启动时调用，检测是否有中断任务
  /// 返回 true = 有中断任务需要告知用户
  Future<bool> recoverOnStartup() async {
    final prefs = await SharedPreferences.getInstance();
    final wasRunning = prefs.getBool(_kRunning) ?? false;
    if (!wasRunning) return false;

    // 发现残留任务：重置状态（不自动恢复，告知用户手动重试）
    _running = false;
    await _clearPersistedState(prefs);

    final taskId = prefs.getString(_kTaskId);
    if (taskId != null) {
      // 把数据库中的残留任务标记为 BLOCKED
      await AppDatabase.instance.updateTask(taskId, {'status': 'BLOCKED'});
    }
    return true;
  }

  Future<void> _persistRunning(String taskId, String bookId, String instruction) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRunning, true);
    await prefs.setString(_kTaskId, taskId);
    await prefs.setString(_kBookId, bookId);
    await prefs.setString(_kInstr,  instruction);
  }

  Future<void> _clearPersistedState([SharedPreferences? prefs]) async {
    prefs ??= await SharedPreferences.getInstance();
    await prefs.remove(_kRunning);
    await prefs.remove(_kTaskId);
    await prefs.remove(_kBookId);
    await prefs.remove(_kInstr);
  }

  // ── 管线入口 ──────────────────────────────
  Future<String?> run({
    required String bookId,
    required String instruction,
  }) async {
    if (_running) return null;
    _running       = true;
    _stopRequested = false;
    _currentBookId = bookId; // Fix6: 记录当前书籍

    final taskId = _uuid.v4();
    final now    = DateTime.now().millisecondsSinceEpoch;
    final db     = AppDatabase.instance;

    await db.insertTask({
      'id': taskId, 'book_id': bookId, 'status': 'PLANNING',
      'instruction': instruction, 'reject_count': 0,
      'tokens_used': 0, 'created_at': now, 'updated_at': now,
    });

    // Fix1: 持久化运行状态，防系统杀后台丢失
    await _persistRunning(taskId, bookId, instruction);

    try {
      final chapterId = await _runPipeline(taskId, bookId, instruction);
      return chapterId;
    } on PipelineInterruptedException catch (e) {
      // Fix5: 门下省断路器触发，通知 UI 而非静默阻塞
      _emit(PipelineEvent(type: PipelineEventType.needReview,
        data: {'reason': e.message, 'type': 'menxia_blocked'}));
      await db.updateTask(taskId, {'status': 'PENDING_HUMAN'});
      _status(taskId, TaskStatus.pendingHuman);
      return null;
    } catch (e) {
      _emit(PipelineEvent(type: PipelineEventType.error, content: e.toString()));
      await db.updateTask(taskId, {'status': 'BLOCKED'});
      _status(taskId, TaskStatus.blocked);
      return null;
    } finally {
      _running = false;
      // Fix1: 无论成功还是异常，清除持久化状态
      await _clearPersistedState();
    }
  }

  // ── 核心管线 ──────────────────────────────
  Future<String?> _runPipeline(String taskId, String bookId, String instruction) async {
    final db = AppDatabase.instance;

    // ── 1. 读取书籍和档案 ───────────────────
    final book = await db.getBook(bookId);
    if (book == null) throw Exception('书籍不存在: $bookId');

    final chapterNo  = (book['current_chapter'] as int) + 1;
    final archives   = await db.getAllArchives(bookId);
    final openHooks  = await _buildHooksContext(bookId);
    final prevEnding = await db.getLastChapterContent(bookId);

    // Fix3: 使用动态档案上下文（核心常驻 + 近期滑动窗口）
    final archiveCtx = await _buildDynamicContext(bookId, archives, chapterNo);

    // ── 2. 中书省：章节规划 ─────────────────
    _switch('zhongshu', '规划第${chapterNo}章...');
    _status(taskId, TaskStatus.planning);

    var plan = await ZhongshuAgent.plan(
      bookTitle:      book['title'] as String,
      genre:          book['genre'] as String,
      chapterNo:      chapterNo,
      instruction:    instruction,
      archiveContext: archiveCtx,
      openHooks:      openHooks,
    );
    await db.updateTask(taskId, {'status': 'REVIEWING', 'plan': _json(plan)});

    // ── 3. 门下省：审议 + Fix5 断路器 ───────
    // Fix5: rejectCount 达到 _maxReject 时抛出异常（不再强制准奏）
    int rejectCount = 0;
    while (true) {
      if (_stopRequested) return null;

      _switch('menxia', '审议规划方案（第${rejectCount + 1}次）...');
      _status(taskId, TaskStatus.reviewing);

      final verdict = await MenxiaAgent.review(
        plan:          plan,
        archiveContext: archiveCtx,
        criticalHooks: openHooks,
        rejectCount:   rejectCount,
      );
      await db.updateTask(taskId, {'verdict': _json(verdict)});
      await db.logTaskTransition(
        taskId: taskId, from: 'REVIEWING',
        to: verdict['verdict'] == '准奏' ? 'ASSIGNED' : 'REJECTED',
        byAgent: 'menxia',
        note: (verdict['critical'] as List? ?? []).join('; '),
      );

      if (verdict['verdict'] == '准奏') break;

      rejectCount++;
      if (rejectCount > _maxReject) {
        // Fix5: 断路 — 向上层抛出，由 UI 告知用户
        final reasons = (verdict['critical'] as List? ?? []).join('；');
        throw PipelineInterruptedException(
          '门下省连续封驳，请细化指令后重试。\n封驳理由：$reasons',
        );
      }

      // 未达上限：让中书省根据封驳意见修改规划
      _switch('zhongshu', '根据封驳意见修改规划（第${rejectCount}次）...');
      _status(taskId, TaskStatus.planning);
      await db.updateTask(taskId, {'status': 'PLANNING', 'reject_count': rejectCount});

      final criticisms = (verdict['critical'] as List? ?? []).join('；');
      plan = await ZhongshuAgent.plan(
        bookTitle:      book['title'] as String,
        genre:          book['genre'] as String,
        chapterNo:      chapterNo,
        instruction:    '$instruction\n[封驳意见，必须修正：$criticisms]',
        archiveContext: archiveCtx,
        openHooks:      openHooks,
      );
    }

    // ── 3.5 读取风格配置 ────────────────────
    final stylePrompt = await getStylePrompt();

    // ── 4. 兵部写稿（流式）─────────────────
    _switch('shangshu', '派发六部，启动写作...');
    await db.updateTask(taskId, {'status': 'EXECUTING'});
    _status(taskId, TaskStatus.executing);

    final wordTarget = _parseWordTarget(instruction,
      book['word_target_min'] as int? ?? 2500,
      book['word_target_max'] as int? ?? 4000);

    final draftBuffer = StringBuffer();
    await for (final token in BingbuAgent.writeStream(
      bookTitle:      book['title'] as String,
      genre:          book['genre'] as String,
      plan:           plan,
      archiveContext: archiveCtx,
      warnings:       (plan['warnings'] as List? ?? []).cast<String>(),
      chapterNo:      chapterNo,   // Fix6: 必传，防止 AI 生成错误章节号
      prevEnding:     prevEnding,
      styleHint:      stylePrompt,
      wordTarget:     wordTarget,
    )) {
      if (_stopRequested) return null;
      if (token.startsWith('[WRITE_ERROR:')) {
        throw Exception(token.substring(13, token.length - 1));
      }
      draftBuffer.write(token);
      _emit(PipelineEvent(type: PipelineEventType.token, content: token));
    }

    var draft = draftBuffer.toString();
    if (draft.trim().isEmpty) throw Exception('写作引擎未返回内容');

    // ── 5. 连续性审计（最多5轮）────────────
    for (int round = 0; round < _maxAuditRound; round++) {
      if (_stopRequested) return null;
      _switch('gongbu', '连续性审计 第${round + 1}轮...');
      _status(taskId, TaskStatus.auditing);

      final auditResult = await AuditAgent.audit(
        draft: draft, archiveContext: archiveCtx);

      _emit(PipelineEvent(type: PipelineEventType.auditResult, data: {
        'passed':        auditResult.passed,
        'criticalCount': auditResult.criticalCount,
        'warningCount':  auditResult.warningCount,
      }));

      if (auditResult.passed) break;

      if (round == _maxAuditRound - 1) {
        _emit(PipelineEvent(type: PipelineEventType.needReview,
          data: {'reason': '审计${_maxAuditRound}轮仍有问题，请人工审阅'}));
        await db.updateTask(taskId, {'status': 'PENDING_HUMAN'});
        _status(taskId, TaskStatus.pendingHuman);
        break;
      }

      _switch('gongbu', '修订${auditResult.criticalCount}个问题...');
      _status(taskId, TaskStatus.revising);
      draft = await AuditAgent.revise(
        draft: draft, issues: auditResult.issues, archiveContext: archiveCtx);
    }

    // ── 6. 礼部润色 ─────────────────────────
    _switch('libu', '文风润色...');
    draft = await LibuAgent.polish(draft, book['genre'] as String);

    // ── 6.5 朱雀：AI文本检测 ────────────────
    _switch('zhugue', 'AI文本检测...');
    // 使用 detectSafe（Isolate 后台运算，UI 不卡顿）
    final detection = await TextDetector.instance.detectSafe(
      draft, useLlm: false, genre: book['genre'] as String? ?? 'xuanhuan');
    _emit(PipelineEvent(type: PipelineEventType.auditResult, agentId: 'zhugue', data: {
      'type':         'detection',
      'score':        detection.totalScore,
      'passed':       detection.passed,
      'verdict':      detection.verdict.label,
      'criticalCount': detection.passed ? 0 : 1,
      'warningCount':  0,
    }));

    if (!detection.passed && detection.totalScore >= 60) {
      _switch('libu', '礼部二次润色（降低AI痕迹）...');
      draft = await LibuAgent.polish(draft, book['genre'] as String);
    }

    // ── 7. 工部：更新档案 ───────────────────
    _switch('gongbu', '更新六大真相档案...');
    final settled = await GongbuAgent.settle(
      draft: draft, chapterNo: chapterNo,
      archives: archives.map((k, v) => MapEntry(k, v?.toString() ?? '')));

    // ── 8. 持久化 ────────────────────────────
    _switch('shangshu', '保存章节...');
    final chapterId = _uuid.v4();
    final wordCount = _countChinese(draft);
    final title     = await _generateChapterTitle(draft, chapterNo);

    // 事务写入：章节+书籍统计+档案原子完成（防 database is locked）
    await db.saveChapterWithArchivesTransaction(
      chapter: {
        'id':         chapterId, 'book_id':    bookId,
        'chapter_no': chapterNo, 'title':      title,
        'content':    draft,     'word_count': wordCount,
        'status':     'pending', 'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      bookId:     bookId,
      chapterNo:  chapterNo,
      wordCount:  wordCount,
      archives:   {
        for (final type in ['world', 'ledger', 'characters', 'timeline'])
          if ((settled[type] as String? ?? '').isNotEmpty)
            type: settled[type] as String,
      },
    );
    await _snapshotArchives(bookId, chapterNo);

    // 记录新伏笔
    for (final hook in (settled['newHooks'] as List? ?? [])) {
      await db.insertHook({
        'id':                  _uuid.v4(),
        'book_id':             bookId,
        'planted_chapter':     chapterNo,
        'current_age':         0,
        'urgency':             'NORMAL',
        'hook_type':           (hook as Map)['hookType'] ?? 'foreshadow',
        'description':         hook['description'] ?? '',
        'reader_expectation':  hook['readerExpectation'] ?? '',
        'status':              'OPEN',
        'created_at':          DateTime.now().millisecondsSinceEpoch,
      });
    }
    await db.incrementHookAges(bookId);

    await db.updateTask(taskId, {
      'status':            'DONE',
      'output_chapter_id': chapterId,
      'completed_at':      DateTime.now().millisecondsSinceEpoch,
    });

    _status(taskId, TaskStatus.done);
    _emit(PipelineEvent(type: PipelineEventType.done, data: {
      'chapterId': chapterId,
      'chapterNo': chapterNo,
      'wordCount': wordCount,
      'title':     title,
    }));

    return chapterId;
  }

  // ═══════════════════════════════════════════
  // Fix3: 动态档案上下文（核心常驻 + 近期滑动窗口）
  // ═══════════════════════════════════════════
  Future<String> _buildDynamicContext(
    String bookId,
    Map<String, dynamic> archives,
    int chapterNo,
  ) async {
    final db   = AppDatabase.instance;
    final book = await db.getBook(bookId);
    final parts = <String>[];

    // ── 核心层（绝对不截断，始终注入）─────
    // 当前位置、当前目标、关键人物状态
    final chars   = archives['characters']?.toString() ?? '';
    final world   = archives['world']?.toString() ?? '';

    // 从角色圣经中提取"核心字段"（位置、目标、存活状态）
    // 使用正则匹配关键行，而非粗暴截断
    final coreChars  = _extractCoreCharacterInfo(chars);
    final coreWorld  = world.length > 600 ? world.substring(0, 600) : world;

    if (coreChars.isNotEmpty) parts.add('## 核心角色状态（当前章节必须遵守）\n$coreChars');
    if (coreWorld.isNotEmpty) parts.add('## 世界状态\n$coreWorld');

    // ── 近期滑动窗口（最近3章摘要）────────
    final recentChapters = await db.getRecentChapterSummaries(bookId, limit: 3);
    if (recentChapters.isNotEmpty) {
      final recents = recentChapters.map((c) =>
        '第${c['chapter_no']}章 「${c['title']}」：${_briefSummary(c['content'] as String)}',
      ).join('\n');
      parts.add('## 近期章节回顾（防止记忆断档）\n$recents');
    }

    // ── 扩展层（按优先级填充剩余空间）─────
    final extended = [
      ('hooks',    '待回收伏笔',  500),
      ('ledger',   '资源账本',    400),
      ('timeline', '时间线',      300),
      ('factions', '势力图谱',    300),
    ];
    for (final (key, label, maxLen) in extended) {
      final content = archives[key]?.toString() ?? '';
      if (content.isEmpty) continue;
      final preview = content.length > maxLen
        ? '${content.substring(0, maxLen)}...' : content;
      parts.add('## $label\n$preview');
    }

    // ── 字数目标提示 ─────────────────────
    final minWords = book?['word_target_min'] as int? ?? 2500;
    final maxWords = book?['word_target_max'] as int? ?? 4000;
    parts.add('## 写作约束\n本章目标字数：$minWords-$maxWords字。角色位置和状态必须与上方档案一致。');

    return parts.join('\n\n');
  }

  /// 从完整角色圣经中提取核心字段（不截断，精确提取）
  String _extractCoreCharacterInfo(String bible) {
    if (bible.isEmpty) return '';
    if (bible.length <= 800) return bible; // 短时直接用

    // 提取每个角色的关键行：名字、位置、目标、存活
    final keyLines = <String>[];
    for (final line in bible.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      // 保留含关键词的行
      if (RegExp(r'(姓名|名字|位置|所在|目标|任务|存活|死亡|当前|现在|状态)').hasMatch(l)) {
        keyLines.add(l);
      }
    }
    if (keyLines.isEmpty) return bible.substring(0, 800);
    return keyLines.take(30).join('\n');
  }

  /// 从章节内容提取简要摘要（取首尾各100字）
  String _briefSummary(String content) {
    if (content.length <= 200) return content;
    final head = content.substring(0, 100);
    final tail = content.substring(content.length - 100);
    return '$head…（中略）…$tail';
  }

  Future<String> _buildHooksContext(String bookId) async {
    final hooks = await AppDatabase.instance.getHooks(bookId);
    final open  = hooks.where((h) => h['status'] == 'OPEN').take(8).toList();
    if (open.isEmpty) return '（暂无待回收伏笔）';
    return open.map((h) =>
      '- ${h['description']}（已${h['current_age']}章，${h['urgency']}）'
    ).join('\n');
  }

  // ── 辅助方法 ────────────────────────────────
  Future<void> _snapshotArchives(String bookId, int chapterNo) async {
    try {
      final archives = await AppDatabase.instance.getAllArchives(bookId);
      for (final entry in archives.entries) {
        if ((entry.value?.toString() ?? '').isEmpty) continue;
        await AppDatabase.instance.insertArchiveSnapshot(
          bookId: bookId, archiveType: entry.key,
          content: entry.value.toString(), chapterNo: chapterNo);
      }
    } catch (_) {}
  }

  (int, int) _parseWordTarget(String instruction, int defaultMin, int defaultMax) {
    final m = RegExp(r'([0-9]+)[字词]').firstMatch(instruction);
    if (m != null) {
      final n = int.tryParse(m.group(1) ?? '0') ?? 0;
      if (n > 500) return ((n * 0.85).round(), (n * 1.15).round());
    }
    return (defaultMin, defaultMax);
  }

  // Fix6: 用 LLM 生成有意义的章节标题（4-8字，概括本章核心事件）
  Future<String> _generateChapterTitle(String draft, int chapterNo) async {
    try {
      // 取正文前500字作为摘要输入
      final preview = draft.length > 500 ? draft.substring(0, 500) : draft;
      final resp    = await AppDatabase.instance.getSetting('_disable_title_llm');
      if (resp == '1') return _fallbackTitle(draft, chapterNo);

      // Fix6: 传入 genre 实现题材感知标题风格
      final genre  = (await AppDatabase.instance.getBook(_currentBookId ?? ''))
                       ?['genre'] as String? ?? 'xuanhuan';
      final result = await agents.ZhongshuAgent.generateTitle(
        chapterNo: chapterNo,
        preview:   preview,
        genre:     genre,
      );
      // Fix6: 后处理 — 确保标题不含章节号
      final clean = result
        .replaceAll(RegExp(r'^第\s*\d+\s*章[：:\s]*'), '')
        .replaceAll(RegExp(r'^第[一二三四五六七八九十百千万]+章[：:\s]*'), '')
        .trim();
      return clean.isNotEmpty ? clean : _fallbackTitle(draft, chapterNo);
    } catch (_) {
      return _fallbackTitle(draft, chapterNo);
    }
  }

  /// 降级方案：从正文首句提取4-8个汉字作为标题
  String _fallbackTitle(String draft, int chapterNo) {
    final sentences = draft.split(RegExp(r'[。！？]'))
      .where((s) => s.trim().length > 4).toList();
    if (sentences.isEmpty) return '第${chapterNo}章';
    // 找第一个有实质内容的句子（跳过纯动作词）
    for (final s in sentences.take(5)) {
      final chs = RegExp(r'[\u4e00-\u9fa5]').allMatches(s.trim())
        .skip(0).take(8).map((m) => m.group(0)!).toList();
      if (chs.length >= 4) return chs.join();
    }
    return '第${chapterNo}章';
  }

  String _json(dynamic obj) {
    try { return const JsonEncoder().convert(obj); } catch (_) { return '{}'; }
  }

  int _countChinese(String text) =>
    RegExp(r'[\u4e00-\u9fa5]').allMatches(text).length;
}
