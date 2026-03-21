// lib/models/models.dart
// 精简本地模型 — 不依赖代码生成，直接手写

import 'dart:convert';

// ═══ 书籍 ════════════════════════════════════
class Book {
  const Book({
    required this.id, required this.title, required this.genre,
    required this.brief, required this.status, required this.totalChapters,
    required this.currentChapter, required this.totalWords,
    required this.createdAt, this.targetPlatforms = const [],
  });
  final String       id, title, genre, brief, status;
  final int          totalChapters, currentChapter, totalWords;
  final DateTime     createdAt;
  final List<String> targetPlatforms;

  factory Book.fromMap(Map<String, dynamic> m) => Book(
    id:             m['id'] as String,
    title:          m['title'] as String,
    genre:          m['genre'] as String? ?? 'xuanhuan',
    brief:          m['brief'] as String? ?? '',
    status:         m['status'] as String? ?? 'writing',
    totalChapters:  m['total_chapters'] as int? ?? 0,
    currentChapter: m['current_chapter'] as int? ?? 0,
    totalWords:     m['total_words'] as int? ?? 0,
    createdAt:      DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    targetPlatforms: _parseList(m['target_platforms']),
  );

  Book copyWith({String? status, int? totalChapters, int? currentChapter, int? totalWords}) => Book(
    id: id, title: title, genre: genre, brief: brief,
    status:         status         ?? this.status,
    totalChapters:  totalChapters  ?? this.totalChapters,
    currentChapter: currentChapter ?? this.currentChapter,
    totalWords:     totalWords     ?? this.totalWords,
    createdAt:      createdAt,
    targetPlatforms: targetPlatforms,
  );
}

// ═══ 章节 ════════════════════════════════════
class Chapter {
  const Chapter({
    required this.id, required this.bookId, required this.chapterNo,
    required this.title, required this.content, required this.wordCount,
    required this.status, required this.createdAt, this.approvedAt,
  });
  final String    id, bookId, title, content, status;
  final int       chapterNo, wordCount;
  final DateTime  createdAt;
  final DateTime? approvedAt;

  factory Chapter.fromMap(Map<String, dynamic> m) => Chapter(
    id:         m['id'] as String,
    bookId:     m['book_id'] as String,
    chapterNo:  m['chapter_no'] as int,
    title:      m['title'] as String? ?? '',
    content:    m['content'] as String? ?? '',
    wordCount:  m['word_count'] as int? ?? 0,
    status:     m['status'] as String? ?? 'pending',
    createdAt:  DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    approvedAt: m['approved_at'] != null
      ? DateTime.fromMillisecondsSinceEpoch(m['approved_at'] as int) : null,
  );
}

// ═══ 任务 ════════════════════════════════════
class Task {
  const Task({
    required this.id, required this.bookId, required this.status,
    required this.instruction, required this.createdAt,
    this.rejectCount = 0, this.plan, this.verdict,
    this.outputChapterId, this.tokensUsed = 0, this.completedAt,
    this.logs = const [],
  });
  final String    id, bookId, status, instruction;
  final int       rejectCount, tokensUsed;
  final DateTime  createdAt;
  final DateTime? completedAt;
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? verdict;
  final String?   outputChapterId;
  final List<TaskLog> logs;

  factory Task.fromMap(Map<String, dynamic> m) => Task(
    id:               m['id'] as String,
    bookId:           m['book_id'] as String,
    status:           m['status'] as String,
    instruction:      m['instruction'] as String,
    rejectCount:      m['reject_count'] as int? ?? 0,
    tokensUsed:       m['tokens_used'] as int? ?? 0,
    outputChapterId:  m['output_chapter_id'] as String?,
    createdAt:        DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    completedAt: m['completed_at'] != null
      ? DateTime.fromMillisecondsSinceEpoch(m['completed_at'] as int) : null,
    plan:    _parseMapField(m['plan']),
    verdict: _parseMapField(m['verdict']),
  );

  bool get isDone    => status == 'DONE';
  bool get isBlocked => status == 'BLOCKED';
  bool get isActive  => !{'DONE','BLOCKED'}.contains(status);
}

class TaskLog {
  const TaskLog({required this.from, required this.to, required this.byAgent, this.note, required this.createdAt});
  final String    from, to, byAgent;
  final String?   note;
  final DateTime  createdAt;

  factory TaskLog.fromMap(Map<String, dynamic> m) => TaskLog(
    from:      m['from_state'] as String,
    to:        m['to_state'] as String,
    byAgent:   m['by_agent'] as String,
    note:      m['note'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

// ═══ 伏笔 ════════════════════════════════════
class PlotHook {
  const PlotHook({
    required this.id, required this.bookId, required this.plantedChapter,
    required this.currentAge, required this.urgency, required this.hookType,
    required this.description, required this.readerExpectation,
    required this.status, this.suggestedClosure, this.closedChapter,
  });
  final String  id, bookId, urgency, hookType, description, readerExpectation, status;
  final int     plantedChapter, currentAge;
  final String? suggestedClosure;
  final int?    closedChapter;

  factory PlotHook.fromMap(Map<String, dynamic> m) => PlotHook(
    id:                m['id'] as String,
    bookId:            m['book_id'] as String,
    plantedChapter:    m['planted_chapter'] as int,
    currentAge:        m['current_age'] as int? ?? 0,
    urgency:           m['urgency'] as String? ?? 'NORMAL',
    hookType:          m['hook_type'] as String? ?? 'foreshadow',
    description:       m['description'] as String,
    readerExpectation: m['reader_expectation'] as String? ?? '',
    status:            m['status'] as String? ?? 'OPEN',
    suggestedClosure:  m['suggested_closure'] as String?,
    closedChapter:     m['closed_chapter'] as int?,
  );
}

// ═══ 角色 ════════════════════════════════════
class Character {
  const Character({
    required this.id, required this.bookId, required this.name,
    required this.role, required this.traits, required this.background,
    required this.currentGoal, required this.speechPatterns,
    required this.absoluteLimit, required this.arcDestination,
    required this.appearanceCount, required this.lastAppearChapter,
    this.isAlive = true, this.currentLocation, this.faction,
  });
  final String       id, bookId, name, role, background, currentGoal, absoluteLimit, arcDestination;
  final List<String> traits, speechPatterns;
  final int          appearanceCount, lastAppearChapter;
  final bool         isAlive;
  final String?      currentLocation, faction;

  factory Character.fromMap(Map<String, dynamic> m) => Character(
    id:                m['id'] as String,
    bookId:            m['book_id'] as String,
    name:              m['name'] as String,
    role:              m['role'] as String? ?? 'support',
    traits:            _parseList(m['traits']),
    background:        m['background'] as String? ?? '',
    currentGoal:       m['current_goal'] as String? ?? '',
    speechPatterns:    _parseList(m['speech_patterns']),
    absoluteLimit:     m['absolute_limit'] as String? ?? '',
    arcDestination:    m['arc_destination'] as String? ?? '',
    appearanceCount:   m['appearance_count'] as int? ?? 0,
    lastAppearChapter: m['last_appear_chapter'] as int? ?? 0,
    isAlive:           (m['is_alive'] as int? ?? 1) == 1,
    currentLocation:   m['current_location'] as String?,
    faction:           m['faction'] as String?,
  );
}

// ═══ LLM 配置 ═════════════════════════════
class LlmConfigModel {
  const LlmConfigModel({
    required this.agentId, required this.baseUrl,
    required this.model, this.temperature = 0.3, this.maxTokens = 2000,
  });
  final String agentId, baseUrl, model;
  final double temperature;
  final int    maxTokens;

  factory LlmConfigModel.fromMap(Map<String, dynamic> m) => LlmConfigModel(
    agentId:     m['agent_id'] as String,
    baseUrl:     m['base_url'] as String,
    model:       m['model'] as String,
    temperature: (m['temperature'] as num).toDouble(),
    maxTokens:   m['max_tokens'] as int,
  );
}

// ═══ 辅助函数 ════════════════════════════════
List<String> _parseList(dynamic v) {
  if (v == null) return [];
  if (v is List) return v.map((e) => e?.toString() ?? '').toList();
  if (v is String && v.startsWith('[')) {
    try {
      return (jsonDecode(v) as List).cast<String>();
    } catch (_) {}
  }
  return [];
}

Map<String, dynamic>? _parseMapField(dynamic v) {
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is String && v.isNotEmpty) {
    try {
      return jsonDecode(v) as Map<String, dynamic>;
    } catch (_) {}
  }
  return null;
}
