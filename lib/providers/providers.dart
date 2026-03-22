// lib/providers/providers.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../core/db/database.dart';
import '../core/pipeline/novel_pipeline.dart';
import '../core/llm/llm_client.dart' as llm;

const _uuid = Uuid();
final _db   = AppDatabase.instance;

// ════════════════════════════════════════════
// Pipeline 事件流
// ════════════════════════════════════════════
final pipelineEventsProvider = StreamProvider<PipelineEvent>((ref) {
  return NovelPipeline.instance.events;
});

final pipelineRunningProvider   = StateProvider<bool>((ref) => false);
// Fix1: 启动时检测到的中断任务（系统杀后台残留）
final interruptedTaskProvider   = StateProvider<String?>((ref) => null);
final currentBookIdProvider   = StateProvider<String?>((ref) => null);

// ════════════════════════════════════════════
// 书籍 Providers
// ════════════════════════════════════════════
final booksProvider = AsyncNotifierProvider<BooksNotifier, List<Book>>(
  BooksNotifier.new,
);

class BooksNotifier extends AsyncNotifier<List<Book>> {
  @override
  Future<List<Book>> build() async {
    final rows = await _db.getBooks();
    return rows.map(Book.fromMap).toList();
  }

  Future<Book> createBook({
    required String title,
    required String genre,
    required String brief,
    List<String> targetPlatforms = const [],
  }) async {
    final now  = DateTime.now().millisecondsSinceEpoch;
    final book = {
      'id':               _uuid.v4(),
      'title':            title,
      'genre':            genre,
      'brief':            brief,
      'status':           'writing',
      'total_chapters':   0,
      'current_chapter':  0,
      'total_words':      0,
      'target_platforms': jsonEncode(targetPlatforms),
      'created_at':       now,
      'updated_at':       now,
    };
    await _db.insertBook(book);
    await ref.read(booksProvider.notifier).refresh();
    return Book.fromMap(book);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final rows = await _db.getBooks();
      return rows.map(Book.fromMap).toList();
    });
  }

  Future<void> deleteBook(String id) async {
    await _db.deleteBook(id);
    await refresh();
  }
}

final bookDetailProvider = FutureProvider.family<Book?, String>((ref, id) async {
  final row = await _db.getBook(id);
  return row == null ? null : Book.fromMap(row);
});

// ════════════════════════════════════════════
// 章节 Providers
// ════════════════════════════════════════════
final chaptersProvider = FutureProvider.family<List<Chapter>, String>((ref, bookId) async {
  final rows = await _db.getChapters(bookId);
  final list  = rows.map(Chapter.fromMap).toList();
  // 按章节号升序（第1章在前），方便阅读导航
  list.sort((a, b) => a.chapterNo.compareTo(b.chapterNo));
  return list;
});

// ════════════════════════════════════════════
// 任务 Providers
// ════════════════════════════════════════════
final tasksProvider = AsyncNotifierProvider.family<TasksNotifier, List<Task>, String>(
  TasksNotifier.new,
);

class TasksNotifier extends FamilyAsyncNotifier<List<Task>, String> {
  StreamSubscription<PipelineEvent>? _sub;

  @override
  Future<List<Task>> build(String bookId) async {
    // 监听管线事件，实时刷新任务列表
    _sub?.cancel();
    _sub = NovelPipeline.instance.events.listen((event) {
      // 只在 statusChange 时轻量刷新任务状态；done 由 writing_screen 负责全量刷新
      if (event.type == PipelineEventType.statusChange) {
        refresh();
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return _loadTasks(bookId);
  }

  Future<List<Task>> _loadTasks(String bookId) async {
    final rows = await _db.getTasks(bookId);
    return rows.map(Task.fromMap).toList();
  }

  Future<void> refresh() async {
    state = AsyncData(await _loadTasks(arg));
  }

  /// 启动写作管线（非阻塞；Fix1: SharedPreferences 持久化运行状态）
  void startWriting(String instruction) {
    // 清除可能残留的中断标记
    ref.read(interruptedTaskProvider.notifier).state = null;
    ref.read(pipelineRunningProvider.notifier).state = true;

    NovelPipeline.instance.run(
      bookId:      arg,
      instruction: instruction,
    ).then((_) {
      refresh();
      ref.invalidate(chaptersProvider(arg));
      ref.invalidate(bookDetailProvider(arg));
      ref.read(pipelineRunningProvider.notifier).state = false;
    }).catchError((e) {
      ref.read(pipelineRunningProvider.notifier).state = false;
    });
  }

  void stopWriting() => NovelPipeline.instance.stop();

  // Fix8: 乐观更新章节内容（UI立即响应，后台写库）
    Future<void> updateChapterContent(String chapterId, String newContent) async {
    await _db.updateChapterContent(chapterId, newContent);
    ref.invalidate(bookDetailProvider(arg));
    ref.invalidate(chaptersProvider(arg));
    await refresh();
  }

    // 2. 异步写入数据库（不阻塞UI）
    await _db.updateChapterContent(chapterId, newContent);

    // 3. 同步刷新书籍总字数
    ref.invalidate(bookDetailProvider(arg));
  }

  // Fix8: 更新章节标题
  Future<void> updateChapterTitle(String chapterId, String newTitle) async {
    await _db.updateChapterTitle(chapterId, newTitle);
    await refresh();
  }

  Future<void> approveChapter(String chapterId) async {
    await _db.approveChapter(chapterId);
    await refresh();
    ref.invalidate(chaptersProvider(arg));
  }
}

// ════════════════════════════════════════════
// 档案 Providers
// ════════════════════════════════════════════
final archivesProvider = FutureProvider.family<Map<String, String>, String>(
  (ref, bookId) async {
    final all = await _db.getAllArchives(bookId);
    return all.map((k, v) => MapEntry(k, v as String));
  },
);

final archiveProvider = FutureProvider.family<String, ({String bookId, String type})>(
  (ref, args) async {
    return _db.getArchive(args.bookId, args.type);
  },
);

/// 保存档案并通知相关 Provider 更新
/// [container] 从界面层传入，用于 invalidate
Future<void> saveArchive(
  String bookId, String type, String content, {
  ProviderContainer? container,
}) async {
  final book = await _db.getBook(bookId);
  final chapterNo = book?['current_chapter'] as int? ?? 0;
  await _db.saveArchive(bookId, type, content, chapterNo);
  container?.invalidate(archiveProvider((bookId: bookId, type: type)));
  container?.invalidate(archivesProvider(bookId));
}

// ════════════════════════════════════════════
// 伏笔 Providers
// ════════════════════════════════════════════
final hooksProvider = AsyncNotifierProvider.family<HooksNotifier, List<PlotHook>, String>(
  HooksNotifier.new,
);

class HooksNotifier extends FamilyAsyncNotifier<List<PlotHook>, String> {
  @override
  Future<List<PlotHook>> build(String bookId) async {
    final rows = await _db.getHooks(bookId);
    return rows.map(PlotHook.fromMap).toList();
  }

  Future<void> add(Map<String, dynamic> data) async {
    await _db.insertHook({...data, 'id': _uuid.v4(), 'book_id': arg,
      'created_at': DateTime.now().millisecondsSinceEpoch});
    ref.invalidateSelf();
  }

  Future<void> close(String hookId) async {
    final book = await _db.getBook(arg);
    await _db.closeHook(hookId, book?['current_chapter'] as int? ?? 0);
    ref.invalidateSelf();
  }
}

final openHooksProvider = Provider.family<List<PlotHook>, String>((ref, bookId) {
  return ref.watch(hooksProvider(bookId)).valueOrNull
    ?.where((h) => h.status == 'OPEN').toList() ?? [];
});

final criticalHooksProvider = Provider.family<List<PlotHook>, String>((ref, bookId) {
  return ref.watch(openHooksProvider(bookId))
    .where((h) => h.urgency == 'CRITICAL').toList();
});

// ════════════════════════════════════════════
// 角色 Providers
// ════════════════════════════════════════════
final charactersProvider = AsyncNotifierProvider.family<CharactersNotifier, List<Character>, String>(
  CharactersNotifier.new,
);

class CharactersNotifier extends FamilyAsyncNotifier<List<Character>, String> {
  @override
  Future<List<Character>> build(String bookId) async {
    final rows = await _db.getCharacters(bookId);
    return rows.map(Character.fromMap).toList();
  }

  Future<void> add(Map<String, dynamic> data) async {
    await _db.insertCharacter({...data, 'id': _uuid.v4(), 'book_id': arg,
      'created_at': DateTime.now().millisecondsSinceEpoch});
    ref.invalidateSelf();
  }
}

final forgottenCharsProvider = Provider.family<List<Character>, ({String bookId, int currentChapter})>(
  (ref, args) {
    final chars = ref.watch(charactersProvider(args.bookId)).valueOrNull ?? [];
    return chars.where((c) {
      if (c.role == 'minor' || !c.isAlive) return false;
      return (args.currentChapter - c.lastAppearChapter) >= 10;
    }).toList();
  },
);

// ════════════════════════════════════════════
// LLM 配置 Providers
// ════════════════════════════════════════════
final llmConfigsProvider = AsyncNotifierProvider<LlmConfigsNotifier, List<LlmConfigModel>>(
  LlmConfigsNotifier.new,
);

class LlmConfigsNotifier extends AsyncNotifier<List<LlmConfigModel>> {
  @override
  Future<List<LlmConfigModel>> build() async {
    final rows = await _db.getAllLlmConfigs();
    return rows.map(LlmConfigModel.fromMap).toList();
  }

  Future<bool> save({
    required String agentId,
    required String baseUrl,
    required String model,
    required String apiKey,
    double temperature = 0.3,
    int maxTokens = 2000,
  }) async {
    final ok = await llm.LlmClient.instance.testConnection(
      baseUrl: baseUrl, model: model, apiKey: apiKey,
    );
    if (!ok) return false;

    await llm.LlmClient.instance.saveConfig(
      llm.LlmConfig(agentId: agentId, baseUrl: baseUrl, model: model,
        temperature: temperature, maxTokens: maxTokens),
      apiKey: apiKey,
    );
    llm.LlmClient.instance.invalidateCache(); // 清除内存缓存，下次调用重新读取新配置
    ref.invalidateSelf();
    return true;
  }

  Future<bool> setDefault({
    required String baseUrl, required String model, required String apiKey,
  }) async {
    final ok = await llm.LlmClient.instance.testConnection(
      baseUrl: baseUrl, model: model, apiKey: apiKey,
    );
    if (!ok) return false;

    await llm.LlmClient.instance.saveDefaultKey(baseUrl, apiKey);
    llm.LlmClient.instance.invalidateCache(); // 清除内存缓存
    // 批量更新所有 agent 的 baseUrl + model
    for (final id in ['bingbu','gongbu','zhongshu','menxia','shangshu',
                      'libu','hubu','libu_hr','xingbu']) {
      await _db.saveLlmConfig({
        'agent_id': id, 'base_url': baseUrl, 'model': model,
        'temperature': id == 'bingbu' ? 0.85 : 0.2,
        'max_tokens': id == 'bingbu' ? 6000 : 2000,
      });
    }
    ref.invalidateSelf();
    return true;
  }
}

// ════════════════════════════════════════════
// UI 状态
// ════════════════════════════════════════════
final streamingTextProvider  = StateProvider<String>((ref) => '');
final activeAgentProvider    = StateProvider<String>((ref) => '');
final activeTaskIdProvider   = StateProvider<String?>((ref) => null);
