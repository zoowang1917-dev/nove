// lib/core/db/database.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _db;

  Future<Database> get db async { _db ??= await _open(); return _db!; }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'novel_ai.db');
    return openDatabase(path, version: 3,
      onCreate: _onCreate, onUpgrade: _onUpgrade, onOpen: _onOpen);
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('PRAGMA journal_mode=WAL');
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute('PRAGMA cache_size=-8000');
    await db.execute('PRAGMA synchronous=NORMAL');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE books(
      id TEXT PRIMARY KEY, title TEXT NOT NULL, genre TEXT NOT NULL DEFAULT 'xuanhuan',
      brief TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'writing',
      total_chapters INTEGER NOT NULL DEFAULT 0, current_chapter INTEGER NOT NULL DEFAULT 0,
      total_words INTEGER NOT NULL DEFAULT 0, target_platforms TEXT NOT NULL DEFAULT '[]',
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');

    await db.execute('''CREATE TABLE chapters(
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
      chapter_no INTEGER NOT NULL, title TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '', word_count INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending', created_at INTEGER NOT NULL,
      approved_at INTEGER, UNIQUE(book_id, chapter_no))''');
    await db.execute('CREATE INDEX idx_ch_book ON chapters(book_id,chapter_no)');

    await db.execute('''CREATE TABLE tasks(
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
      status TEXT NOT NULL DEFAULT 'PLANNING', instruction TEXT NOT NULL,
      plan TEXT, verdict TEXT, reject_count INTEGER NOT NULL DEFAULT 0,
      tokens_used INTEGER NOT NULL DEFAULT 0, output_chapter_id TEXT,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, completed_at INTEGER)''');
    await db.execute('CREATE INDEX idx_task_book ON tasks(book_id,created_at DESC)');

    await db.execute('''CREATE TABLE task_logs(
      id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL REFERENCES tasks(id),
      from_state TEXT NOT NULL, to_state TEXT NOT NULL, by_agent TEXT NOT NULL,
      note TEXT, created_at INTEGER NOT NULL)''');
    await db.execute('CREATE INDEX idx_tlog_task ON task_logs(task_id)');

    await db.execute('''CREATE TABLE archives(
      book_id TEXT NOT NULL REFERENCES books(id), archive_type TEXT NOT NULL,
      content TEXT NOT NULL DEFAULT '', chapter_no INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL, PRIMARY KEY(book_id,archive_type))''');

    await db.execute('''CREATE TABLE plot_hooks(
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
      planted_chapter INTEGER NOT NULL, current_age INTEGER NOT NULL DEFAULT 0,
      urgency TEXT NOT NULL DEFAULT 'NORMAL', hook_type TEXT NOT NULL DEFAULT 'foreshadow',
      description TEXT NOT NULL, reader_expectation TEXT NOT NULL DEFAULT '',
      suggested_closure TEXT, status TEXT NOT NULL DEFAULT 'OPEN',
      closed_chapter INTEGER, created_at INTEGER NOT NULL)''');
    await db.execute('CREATE INDEX idx_hook_book ON plot_hooks(book_id,status,urgency)');

    await db.execute('''CREATE TABLE characters(
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
      name TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'support',
      traits TEXT NOT NULL DEFAULT '[]', background TEXT NOT NULL DEFAULT '',
      current_goal TEXT NOT NULL DEFAULT '', speech_patterns TEXT NOT NULL DEFAULT '[]',
      absolute_limit TEXT NOT NULL DEFAULT '', arc_destination TEXT NOT NULL DEFAULT '',
      appearance_count INTEGER NOT NULL DEFAULT 0, last_appear_chapter INTEGER NOT NULL DEFAULT 0,
      is_alive INTEGER NOT NULL DEFAULT 1, current_location TEXT, faction TEXT,
      known_info TEXT, created_at INTEGER NOT NULL)''');
    await db.execute('CREATE INDEX idx_char_book ON characters(book_id,role)');

    await db.execute('''CREATE TABLE llm_configs(
      agent_id TEXT PRIMARY KEY, base_url TEXT NOT NULL, model TEXT NOT NULL,
      temperature REAL NOT NULL DEFAULT 0.3, max_tokens INTEGER NOT NULL DEFAULT 2000,
      updated_at INTEGER NOT NULL)''');

    await db.execute('''CREATE TABLE app_settings(
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        book_id TEXT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        mode TEXT NOT NULL DEFAULT 'general',
        created_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_chat_session ON chat_messages(session_id)');

    await _seedLlmConfigs(db);
  }

  Future<void> _onUpgrade(Database db, int oldVer, int newVer) async {
    if (oldVer < 2) {
      for (final sql in [
        'CREATE INDEX IF NOT EXISTS idx_ch_book ON chapters(book_id,chapter_no)',
        'CREATE INDEX IF NOT EXISTS idx_task_book ON tasks(book_id,created_at DESC)',
        'CREATE INDEX IF NOT EXISTS idx_hook_book ON plot_hooks(book_id,status,urgency)',
      ]) { try { await db.execute(sql); } catch (_) {} }
    }
    // Fix2: 版本3 — 添加 archive_snapshots 表
    if (oldVer < 3) {
      try {
        await db.execute('''CREATE TABLE IF NOT EXISTS archive_snapshots(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id TEXT NOT NULL, archive_type TEXT NOT NULL,
          content TEXT NOT NULL, chapter_no INTEGER NOT NULL,
          created_at INTEGER NOT NULL)''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_snap ON archive_snapshots(book_id, chapter_no)');
        // Fix2: 给 books 表加写作目标字段（如已有则忽略）
        try { await db.execute('ALTER TABLE books ADD COLUMN word_target_min INTEGER NOT NULL DEFAULT 2500'); } catch (_) {}
        try { await db.execute('ALTER TABLE books ADD COLUMN word_target_max INTEGER NOT NULL DEFAULT 4000'); } catch (_) {}
        // Fix2: 给 books 表加索引
        await db.execute('CREATE INDEX IF NOT EXISTS idx_books_created ON books(created_at DESC)');
      } catch (_) {}
    }
  }

  Future<void> _seedLlmConfigs(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final (id, temp, tok) in [
      ('bingbu', 0.85, 6000), ('gongbu', 0.20, 2000),  ('zhongshu', 0.70, 2000),
      ('menxia', 0.10, 1500), ('shangshu',0.20, 1000), ('libu',    0.40, 3000),
      ('hubu',   0.10, 1000), ('libu_hr', 0.20, 1000), ('xingbu',  0.10, 1000),
    ]) {
      await db.insert('llm_configs', {
        'agent_id': id, 'base_url': 'https://api.deepseek.com/v1',
        'model': 'deepseek-chat', 'temperature': temp,
        'max_tokens': tok, 'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ─── Books ────────────────────────────────
  // Fix2: 书库列表绝对不加载 content（防止35万字全量加载3-4秒卡顿）
  Future<List<Map<String,dynamic>>> getBooks() async =>
    (await db).query('books',
      columns: ['id','title','genre','brief','status',
                'total_chapters','current_chapter','total_words',
                'target_platforms','created_at','updated_at',
                'word_target_min','word_target_max'],
      orderBy: 'updated_at DESC');
  Future<Map<String,dynamic>?> getBook(String id) async {
    final r = await (await db).query('books', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }
  Future<void> insertBook(Map<String,dynamic> b) async =>
    (await db).insert('books', b, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> updateBook(String id, Map<String,dynamic> v) async =>
    (await db).update('books',
      {...v, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id=?', whereArgs: [id]);
  Future<void> deleteBook(String id) async {
    final d = await db;
    // 先删子表，再删主表（顺序重要）
    await d.delete('task_logs',  where: 'task_id IN (SELECT id FROM tasks WHERE book_id=?)', whereArgs: [id]);
    await d.delete('tasks',      where: 'book_id=?', whereArgs: [id]);
    await d.delete('chapters',   where: 'book_id=?', whereArgs: [id]);
    await d.delete('archives',   where: 'book_id=?', whereArgs: [id]);
    await d.delete('plot_hooks', where: 'book_id=?', whereArgs: [id]);
    await d.delete('characters', where: 'book_id=?', whereArgs: [id]);
    await d.delete('books',      where: 'id=?',      whereArgs: [id]);
  }

  // ─── Chapters ─────────────────────────────
  Future<Map<String,dynamic>?> getChapterByNo(String bookId, int chapterNo) async {
    final rows = await (await db).query('chapters',
      where: 'book_id=? AND chapter_no=?', whereArgs: [bookId, chapterNo]);
    return rows.isEmpty ? null : rows.first;
  }

  // Fix3: 近期章节摘要（只取 title + 首尾各200字，不加载全文）
  Future<List<Map<String,dynamic>>> getRecentChapterSummaries(String bookId, {int limit = 3}) async {
    final rows = await (await db).query('chapters',
      columns: ['chapter_no','title','content'],
      where: 'book_id=?', whereArgs: [bookId],
      orderBy: 'chapter_no DESC', limit: limit);
    // 只截取首尾，不返回全文
    return rows.map((r) {
      final content = r['content'] as String? ?? '';
      final brief   = content.length > 400
        ? content.substring(0, 200) + '…' + content.substring(content.length - 200)
        : content;
      return {...r, 'content': brief};
    }).toList();
  }

  Future<List<Map<String,dynamic>>> getChapters(String bookId) async =>
    (await db).query('chapters', where:'book_id=?', whereArgs:[bookId], orderBy:'chapter_no');
  Future<void> insertChapter(Map<String,dynamic> ch) async =>
    (await db).insert('chapters', ch, conflictAlgorithm: ConflictAlgorithm.replace);

  // 事务方法：章节+书籍统计+档案原子写入（防 database is locked 并发问题）
  Future<void> saveChapterWithArchivesTransaction({
    required Map<String, dynamic> chapter,
    required String bookId,
    required int chapterNo,
    required int wordCount,
    required Map<String, String> archives,
  }) async {
    final d   = await db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await d.transaction((txn) async {
      // 1. 写入章节
      await txn.insert('chapters', chapter,
        conflictAlgorithm: ConflictAlgorithm.replace);

      // 2. 原子更新书籍统计（rawUpdate 在事务内执行）
      await txn.rawUpdate('''
        UPDATE books SET
          current_chapter = ?,
          total_chapters  = MAX(total_chapters, ?),
          total_words     = total_words + ?,
          updated_at      = ?
        WHERE id = ?
      ''', [chapterNo, chapterNo, wordCount, now, bookId]);

      // 3. 写入档案（同一事务内）
      for (final entry in archives.entries) {
        await txn.insert('archives', {
          'book_id':      bookId,
          'archive_type': entry.key,
          'content':      entry.value,
          'chapter_no':   chapterNo,
          'updated_at':   now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
  // Fix8: 更新章节内容（乐观更新 + 异步写库）
  Future<void> updateChapterContent(String id, String content) async {
    final wordCount = RegExp(r'[一-龥]').allMatches(content).length;
    await (await db).update('chapters', {
      'content':    content,
      'word_count': wordCount,
    }, where: 'id=?', whereArgs: [id]);
  }

  // Fix8: 单独更新章节标题
  Future<void> updateChapterTitle(String id, String title) async =>
    (await db).update('chapters', {'title': title},
      where: 'id=?', whereArgs: [id]);

  Future<void> approveChapter(String id) async =>
    (await db).update('chapters',
      {'status':'approved','approved_at':DateTime.now().millisecondsSinceEpoch},
      where:'id=?', whereArgs:[id]);
  Future<String?> getLastChapterContent(String bookId) async {
    final r = await (await db).query('chapters',
      columns:['content'], where:"book_id=? AND status='approved'",
      whereArgs:[bookId], orderBy:'chapter_no DESC', limit:1);
    final c = r.isEmpty ? null : r.first['content'] as String?;
    if (c == null || c.isEmpty) return null;
    return c.length > 400 ? c.substring(c.length - 400) : c;
  }

  // ─── Tasks ────────────────────────────────
  Future<List<Map<String,dynamic>>> getTasks(String bookId) async =>
    (await db).query('tasks', where:'book_id=?', whereArgs:[bookId], orderBy:'created_at DESC');
  Future<Map<String,dynamic>?> getTask(String id) async {
    final r = await (await db).query('tasks', where:'id=?', whereArgs:[id]);
    return r.isEmpty ? null : r.first;
  }
  Future<void> insertTask(Map<String,dynamic> t) async =>
    (await db).insert('tasks', t, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> updateTask(String id, Map<String,dynamic> v) async =>
    (await db).update('tasks',
      {...v, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where:'id=?', whereArgs:[id]);
  Future<void> logTaskTransition({required String taskId, required String from,
    required String to, required String byAgent, String? note}) async =>
    (await db).insert('task_logs', {
      'task_id':from,'from_state':from,'to_state':to,'by_agent':byAgent,
      'note':note,'created_at':DateTime.now().millisecondsSinceEpoch});
  Future<List<Map<String,dynamic>>> getTaskLogs(String taskId) async =>
    (await db).query('task_logs', where:'task_id=?', whereArgs:[taskId], orderBy:'created_at');

  // ─── Archives ─────────────────────────────
  Future<String> getArchive(String bookId, String type) async {
    final r = await (await db).query('archives',
      where:'book_id=? AND archive_type=?', whereArgs:[bookId,type]);
    return r.isEmpty ? '' : r.first['content'] as String;
  }
  Future<Map<String,dynamic>> getAllArchives(String bookId) async {
    final r = await (await db).query('archives', where:'book_id=?', whereArgs:[bookId]);
    return {for (final row in r) row['archive_type'] as String: row['content'] as String};
  }
  Future<void> saveArchive(String bookId, String type, String content, int chapterNo) async =>
    (await db).insert('archives', {
      'book_id':bookId,'archive_type':type,'content':content,
      'chapter_no':chapterNo,'updated_at':DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ─── Hooks ────────────────────────────────
  Future<List<Map<String,dynamic>>> getHooks(String bookId) async =>
    (await db).query('plot_hooks', where:'book_id=?', whereArgs:[bookId], orderBy:'current_age DESC');
  Future<void> insertHook(Map<String,dynamic> h) async =>
    (await db).insert('plot_hooks', h, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> incrementHookAges(String bookId) async =>
    (await db).rawUpdate('''
      UPDATE plot_hooks SET current_age=current_age+1,
        urgency=CASE WHEN current_age+1>=20 THEN 'CRITICAL'
                     WHEN current_age+1>=10 THEN 'WARN' ELSE 'NORMAL' END
      WHERE book_id=? AND status='OPEN' ''', [bookId]);
  Future<void> closeHook(String hookId, int chapterNo) async =>
    (await db).update('plot_hooks',
      {'status':'CLOSED','closed_chapter':chapterNo}, where:'id=?', whereArgs:[hookId]);

  // ─── Characters ───────────────────────────
  Future<List<Map<String,dynamic>>> getCharacters(String bookId) async =>
    (await db).query('characters', where:'book_id=?', whereArgs:[bookId]);
  Future<void> insertCharacter(Map<String,dynamic> c) async =>
    (await db).insert('characters', c, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> updateCharacter(String id, Map<String,dynamic> v) async =>
    (await db).update('characters', v, where:'id=?', whereArgs:[id]);

  // ─── LLM Config ───────────────────────────
  Future<Map<String,dynamic>?> getLlmConfig(String agentId) async {
    final r = await (await db).query('llm_configs', where:'agent_id=?', whereArgs:[agentId]);
    return r.isEmpty ? null : r.first;
  }
  Future<List<Map<String,dynamic>>> getAllLlmConfigs() async =>
    (await db).query('llm_configs', orderBy:'agent_id');
  Future<void> saveLlmConfig(Map<String,dynamic> cfg) async =>
    (await db).insert('llm_configs',
      {...cfg,'updated_at':DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> saveDefaultLlm({required String baseUrl}) async =>
    setSetting('default_llm_url', baseUrl);

  // ─── Settings ─────────────────────────────
  Future<String?> getSetting(String key) async {
    final r = await (await db).query('app_settings', where:'key=?', whereArgs:[key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }
  Future<void> setSetting(String key, String value) async =>
    (await db).insert('app_settings',{'key':key,'value':value},
      conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> close() async => (await db).close();

  // ═══ Raw Query ═══════════════════════════
  Future<List<Map<String,dynamic>>> rawQuery(String sql, [List<Object?>? args]) async =>
    (await db).rawQuery(sql, args);

  // ═══ Chat Messages ════════════════════════
  Future<void> insertChatMsg({
    required String sessionId,
    required String role,
    required String content,
    String? bookId,
    String mode = 'general',
  }) async =>
    (await db).insert('chat_messages', {
      'session_id': sessionId, 'book_id': bookId,
      'role':       role,       'content':  content,
      'mode':       mode,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

  Future<List<Map<String,dynamic>>> getChatHistory(String sessionId, {int limit = 50}) async =>
    (await db).query('chat_messages',
      where: 'session_id=?', whereArgs: [sessionId],
      orderBy: 'created_at DESC', limit: limit);

  Future<List<Map<String,dynamic>>> getRecentSessions({int limit = 10}) async =>
    (await db).rawQuery('''
      SELECT session_id, book_id, mode, MAX(created_at) as last_at,
             COUNT(*) as msg_count
      FROM chat_messages
      GROUP BY session_id
      ORDER BY last_at DESC
      LIMIT ?
    ''', [limit]);

  Future<void> clearChatSession(String sessionId) async =>
    (await db).delete('chat_messages', where: 'session_id=?', whereArgs: [sessionId]);

  Future<void> clearAllChat() async => (await db).delete('chat_messages');
}
  // ═══ Archive Snapshots ═══════════════════════
  Future<void> insertArchiveSnapshot({
    required String bookId, required String archiveType,
    required String content, required int chapterNo,
  }) async =>
    (await db).insert('archive_snapshots', {
      'book_id': bookId, 'archive_type': archiveType,
      'content': content, 'chapter_no': chapterNo,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

  Future<List<Map<String,dynamic>>> getSnapshotList(String bookId) async =>
    (await db).rawQuery('''
      SELECT DISTINCT chapter_no FROM archive_snapshots
      WHERE book_id=? ORDER BY chapter_no DESC LIMIT 20
    ''', [bookId]);

  Future<Map<String,String>> getSnapshot(String bookId, int chapterNo) async {
    final rows = await (await db).query('archive_snapshots',
      where: 'book_id=? AND chapter_no=?', whereArgs: [bookId, chapterNo]);
    final result = <String,String>{};
    for (final r in rows) {
      result[r['archive_type'] as String] = r['content'] as String;
    }
    return result;
  }

  Future<void> rollbackToSnapshot(String bookId, int chapterNo) async {
    final snap = await getSnapshot(bookId, chapterNo);
    for (final e in snap.entries) {
      await saveArchive(bookId, e.key, e.value, chapterNo);
    }
    // 删除该快照点之后的快照
    await (await db).delete('archive_snapshots',
      where: 'book_id=? AND chapter_no>?', whereArgs: [bookId, chapterNo]);
  }
