// lib/core/agents/agents.dart
// 三省六部 全部9个 Agent — 纯 Dart，直连 LLM API
import 'dart:convert';
import '../llm/llm_client.dart';

final _llm = LlmClient.instance;

/// 截断过长的上下文（防止超出模型 token 限制）
/// [maxChars] 约等于 token 数（中文1字≈1.5token，英文1词≈1.3token）
String _truncateCtx(String text, {int maxChars = 3000}) =>
    text.length > maxChars ? '${text.substring(0, maxChars)}\n...[内容过长已截断]' : text;

/// 安全截取草稿（审计/工部用）
String _draftPreview(String draft, {int maxChars = 4000}) =>
    draft.length > maxChars ? '${draft.substring(0, maxChars)}\n...[草稿已截断]' : draft;


// ════════════════════════════════════════════
// 共用类型
// ════════════════════════════════════════════
class AgentResult {
  const AgentResult({required this.content, this.tokensUsed = 0, this.parsed});
  final String  content;
  final int     tokensUsed;
  final Map<String, dynamic>? parsed;
}

Map<String, dynamic> _safeJson(String raw) {
  var s = raw.trim();
  // 剥离 markdown fence：```json ... ``` 或 ``` ... ```
  if (s.startsWith('```')) {
    final nl  = s.indexOf('\n');
    final end = s.lastIndexOf('```');
    if (nl >= 0 && end > nl) s = s.substring(nl + 1, end).trim();
  }
  try {
    final decoded = jsonDecode(s);
    if (decoded is Map<String, dynamic>) return decoded;
    // LLM 有时返回 {"result": {...}} 包装
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return {};
  } catch (_) {
    return {};
  }
}

// ════════════════════════════════════════════
// 📜 中书省 — 章节规划
// ════════════════════════════════════════════
class ZhongshuAgent {
  static Future<Map<String, dynamic>> plan({
    required String bookTitle,
    required String genre,
    required int chapterNo,
    required String instruction,
    required String archiveContext,
    required String openHooks,
  }) async {
    final resp = await _llm.chat('zhongshu', [
      {'role': 'system', 'content': _soul},
      {'role': 'user',   'content': '''
书名：$bookTitle（$genre）
当前章节：第${chapterNo}章
作者指令：$instruction

待回收伏笔：
$openHooks

六大真相档案摘要：
$archiveContext

请规划本章并输出JSON：'''},
    ], jsonMode: true);

    final plan = _safeJson(resp.content);
    return plan.isEmpty ? _fallback(instruction) : plan;
  }

  static Map<String, dynamic> _fallback(String instruction) => {
    'chapterGoal': instruction,
    'hookDesign':  '章节结尾制造悬念，驱动读者翻页',
    'sceneBeats':  [{'description': '按指令推进主线', 'purpose': 'advance', 'estimatedWords': 3000}],
    'hooksToClose': [],
    'tensionLevel': 'medium',
    'warnings': [],
  };

  static const _soul = '''你是网文策划师"中书省"。用JSON规划章节：
{
  "chapterGoal": "本章最重要的一件事（一句话）",
  "hookDesign":  "结尾悬念设计（只写钩子，不提前解决）",
  "sceneBeats":  [{"description":"场景描述","purpose":"advance|tension|payoff|hook","estimatedWords":800}],
  "hooksToClose": ["本章应回收的伏笔描述"],
  "tensionLevel": "high|medium|low",
  "warnings": ["写作时需注意的连续性要点"]
}
只输出JSON，不加任何说明。''';
}


  // Fix6: 强化标题生成——题材感知+多重后处理+兜底逻辑（用户方案）
  static Future<String> generateTitle({
    required int chapterNo,
    required String preview,
    String genre = 'xuanhuan',
  }) async {
    try {
      final styleHint = switch (genre) {
        'xianxia' || 'xuanhuan' => '四字成语式，如：剑指云霄、天地变色',
        'dushi'   || 'yanqing'  => '简洁口语式，如：意外重逢',
        'lishi'                 => '文言感，如：风雨长安',
        _                       => '有概括性、有画面感的短标题',
      };
      final resp = await _llm.chat('zhongshu', [
        {'role': 'system', 'content':
          '你是网文标题专家。根据章节内容起精炼小标题。\n'
          '硬性规则：\n'
          '① 4-8个汉字\n'
          '② 绝对不含"第""章"等章节序号\n'
          '③ 不带任何标点符号\n'
          '④ 直接输出标题，不加任何解释\n'
          '风格参考：$styleHint'},
        {'role': 'user', 'content':
          '第${chapterNo}章正文开头：\n$preview\n\n请给出4-8字小标题：'},
      ], temperature: 0.4);

      var title = resp.content.trim();
      // Fix6: 多重后处理（用户方案）
      // 1. 移除所有章节号格式
      title = title.replaceAll(
        RegExp(r'第\s*\d+\s*章|第[一二三四五六七八九十百千万零]+章'), '');
      // 2. 移除标点
      title = title.replaceAll(
        RegExp(r'[，。！？、：；\s【】《》（）\[\]]'), '');
      // 3. 移除引号包裹
              title = title.replaceAll('"', '').replaceAll("'", "").trim();

      title = title.trim();
      if (title.length >= 4 && title.length <= 12) return title;
      return _fallbackTitle(chapterNo, preview);
    } catch (_) {
      return _fallbackTitle(chapterNo, preview);
    }
  }

  /// Fix6: 兜底标题——从首句取关键词
  static String _fallbackTitle(int chapterNo, String preview) {
    final chars = RegExp(r'[\u4e00-\u9fa5]')
      .allMatches(preview).take(6).map((m) => m.group(0)!).join();
    return chars.length >= 4 ? chars : '第${chapterNo}章';
  }
}

  }
}

// ════════════════════════════════════════════
// 🔍 门下省 — 规划审议
// ════════════════════════════════════════════
class MenxiaAgent {
  static Future<Map<String, dynamic>> review({
    required Map<String, dynamic> plan,
    required String archiveContext,
    required String criticalHooks,
    required int rejectCount,
  }) async {
    if (rejectCount >= 2) {
      // 第3次强制准奏，避免死锁
      return {'verdict': '准奏', 'critical': [], 'warnings': ['封驳次数达上限，强制通过'], 'suggestions': []};
    }

    final resp = await _llm.chat('menxia', [
      {'role': 'system', 'content': _soul},
      {'role': 'user',   'content': '''
规划方案：
${jsonEncode(plan)}

档案参考：
$archiveContext

紧急伏笔(CRITICAL)：
$criticalHooks

本轮已封驳：$rejectCount 次（上限3次）

输出JSON审议结论：'''},
    ], jsonMode: true);

    final v = _safeJson(resp.content);
    return v.isEmpty ? {'verdict': '准奏', 'critical': [], 'warnings': [], 'suggestions': []} : v;
  }

  static const _soul = '''你是门下省审议御史，严格但不刁难。审查规划方案：
必须封驳（CRITICAL）：角色出现在不应在的地方、使用不应知道的信息、无明确推进目的
建议修改（WARNING）：节奏问题、伏笔处理不当

输出JSON：
{
  "verdict": "准奏|封驳",
  "critical": ["必须修改的问题"],
  "warnings": ["建议修改"],
  "suggestions": ["改进建议"]
}
只输出JSON。''';
}

// ════════════════════════════════════════════
// ⚔️ 兵部 — 正文写手（支持流式）
// ════════════════════════════════════════════
class BingbuAgent {
  static const _forbiddenWords = [
    '淡淡','微微','缓缓','轻轻','默默','静静','悄悄',
    '只见','却见','但见','不禁','忽然间',
    '感受到','感觉到','感到一阵','内心深处','心中一动',
    '此刻','此时此刻','与此同时',
    '宛如春风','宛如利剑','宛如烈火',
  ];

  /// 流式写作，返回 Stream<String>
  // Fix6: 注入 chapterNo，确保正文永远是正确章节号
  static Stream<String> writeStream({
    required String bookTitle,
    required String genre,
    required Map<String, dynamic> plan,
    required String archiveContext,
    required List<String> warnings,
    required int chapterNo,          // Fix6: 必传，防止AI生成错误章节号
    String? prevEnding,
    String? styleHint,
    (int, int) wordTarget = (2500, 4000),
  }) async* {
    final msgs = _buildMessages(
      bookTitle: bookTitle, genre: genre, plan: plan,
      archiveContext: archiveContext, warnings: warnings,
      prevEnding: prevEnding, styleHint: styleHint,
      wordTarget: wordTarget, chapterNo: chapterNo,
    );
    try {
      // Fix6: 对流式输出做后处理，剔除顽固的错误章节号
      String buffer = '';
      bool headerCleaned = false;
      await for (final token in _llm.stream('bingbu', msgs, temperature: 0.85)) {
        if (!headerCleaned) {
          buffer += token;
          // 积累足够字符后做一次性清理
          if (buffer.length >= 30 || token.contains('。') || token.contains('\n')) {
            buffer = _cleanChapterHeader(buffer, chapterNo);
            headerCleaned = true;
            yield buffer;
            buffer = '';
          }
        } else {
          yield token;
        }
      }
      if (buffer.isNotEmpty) yield buffer;
    } catch (e) {
      yield '\n[WRITE_ERROR:$e]';
    }
  }

  /// Fix6: 后处理 — 剔除正文开头的错误章节号（AI顽固行为）
  // Fix6: 强化后处理——剥除 AI 顽固生成的错误章节号（用户方案）
  static String _cleanChapterHeader(String rawText, int chapterNo) {
    var text = rawText.trimLeft();
    // 1. 剥除开头的各种章节号格式
    text = text.replaceAll(
      RegExp(
        r'^(第\s*\d+\s*章|第[一二三四五六七八九十百千万零]+章|Chapter\s*\d+)[：:：\s]*',
        multiLine: false, caseSensitive: false,
      ), '',
    );
    // 2. 剥除段落内重复章节号
    text = text.replaceAll(
      RegExp('\\n第\\s*${chapterNo}\\s*章[：:\\s]*'),
      '\n',
    );
    // 3. 剥除 AI 添加的常见标题行
    text = text.replaceAll(
      RegExp(r'^(正文|开始|内容如下|以下是正文|以下内容|【正文】)[：:：\s]*\n', multiLine: false),
      '',
    );
    return text.trimLeft();
  }

  /// 非流式（用于重新生成/修订）
  static Future<AgentResult> write({
    required String bookTitle,
    required String genre,
    required Map<String, dynamic> plan,
    required String archiveContext,
    required List<String> warnings,
    required int chapterNo,
    String? prevEnding,
  }) async {
    final msgs = _buildMessages(
      bookTitle: bookTitle, genre: genre, plan: plan,
      archiveContext: archiveContext, warnings: warnings,
      prevEnding: prevEnding, chapterNo: chapterNo,
    );
    final resp = await _llm.chat('bingbu', msgs, temperature: 0.85);
    final content = resp.content.trim();
    if (content.length < 200) throw LlmException('兵部返回内容过短（${content.length}字），请检查 API Key 和模型配置');
    return AgentResult(content: content, tokensUsed: resp.tokensUsed);
  }

  /// AI味检测分数（0-100，越低越好）
  static int aiSmellScore(String text) {
    int score = 0;
    for (final w in _forbiddenWords) {
      score += (text.split(w).length - 1) * 5;
    }
    score += (RegExp(r'感[到受]到?[\u4e00-\u9fa5]').allMatches(text).length) * 8;
    return score.clamp(0, 100);
  }

  static List<Map<String, String>> _buildMessages({
    required String bookTitle,
    required String genre,
    required Map<String, dynamic> plan,
    required String archiveContext,
    required List<String> warnings,
    required int chapterNo,
    String? prevEnding,
    String? styleHint,
    (int, int) wordTarget = (2500, 4000),
  }) {
    final warnBlock = warnings.isNotEmpty
      ? '\n\n⚠️ 门下省提醒：\n${warnings.map((w) => '- $w').join('\n')}'
      : '';
    final prevBlock = prevEnding != null
      ? '\n\n上章结尾（保持衔接）：\n$prevEnding'
      : '';
    final styleBlock = styleHint != null
      ? '\n\n风格参考：\n$styleHint'
      : '';
    final beats = (plan['sceneBeats'] as List? ?? [])
      .asMap().entries
      .map((e) => '场景${e.key+1}：${(e.value as Map)['description']}')
      .join('\n');

    return [
      {'role': 'system', 'content': _soul(genre)},
      {'role': 'user', 'content': '''
# 写作任务：$bookTitle

## 六大真相档案
$archiveContext
$prevBlock
$styleBlock

## 本章目标
${plan['chapterGoal'] ?? '推进主线'}

## 场景节拍
$beats

## 结尾钩子
${plan['hookDesign'] ?? '留下悬念'}
$warnBlock

要求：
- 本章是全书第 $chapterNo 章，这是必须遵守的事实
- 字数${wordTarget.$1}-${wordTarget.$2}字（严格控制，不能少于${wordTarget.$1}字）
- 第三人称限制视角（跟随主角）
- 结尾停在最高张力处，不提前解决钩子
- 【格式强约束】直接输出正文内容。绝对不要在正文中写"第1章"或任何章节序号，不要输出任何章节标题行'''},
    ];
  }

  static String _soul(String genre) => '''你是经验丰富的${_genreLabel(genre)}网文写手"兵部"。

创作铁律：
1. 档案即圣经：每个细节都必须与六大真相档案一致
2. 绝对禁用词：淡淡/微微/缓缓/只见/却见/不禁/感受到/感觉到/内心深处/此刻
3. 情感用身体反应表达，不写"感到愤怒"，写"咬紧后槽牙，喉咙发紧"
4. 比喻从当前场景生长，不套"宛如烈火/宛如利剑"
5. 结尾必须停在钩子的最高张力点，不提前解决
6. 动作场景短句为主（≤15字），心理描写长短交替
7. 反派的决策在他自己视角下必须合理''';

  static String _genreLabel(String g) => const {
    'xuanhuan': '玄幻', 'xianxia': '仙侠', 'dushi': '都市',
    'lishi': '历史', 'yanqing': '言情', 'wuxia': '武侠',
    'kehuanweilai': '科幻', 'mohuan': '魔法',
  }[g] ?? '网文';
}

// ════════════════════════════════════════════
// 🌍 工部 — 世界官（档案更新）
// ════════════════════════════════════════════
class GongbuAgent {
  static Future<Map<String, dynamic>> settle({
    required String draft,
    required int chapterNo,
    required Map<String, String> archives,
  }) async {
    final resp = await _llm.chat('gongbu', [
      {'role': 'system', 'content': _soul},
      {'role': 'user',   'content': '''
第${chapterNo}章内容（节选）：
${draft.length > 3000 ? '...(前略)\n' + draft.substring(draft.length - 2500) : draft}

当前档案：
世界状态：${(archives['world'] ?? '').length > 800 ? archives['world']!.substring(0, 800) : archives['world'] ?? ''}
资源账本：${archives['ledger'] ?? ''}

输出JSON：'''},
    ], jsonMode: true);

    final p = _safeJson(resp.content);
    return {
      'world':      p['world']      ?? archives['world']      ?? '',
      'ledger':     p['ledger']     ?? archives['ledger']     ?? '',
      'characters': p['characters'] ?? archives['characters'] ?? '',
      'timeline':   p['timeline']   ?? archives['timeline']   ?? '',
      'newHooks':   p['newHooks']   ?? [],
      'closedHooks': p['closedHooks'] ?? [],
      'tokensUsed': resp.tokensUsed,
    };
  }

  static const _soul = '''你是工部世界官，负责维护六大真相档案。
根据本章内容更新档案，输出JSON：
{
  "world":      "更新后的世界状态（Markdown）",
  "ledger":     "更新后的资源账本",
  "characters": "更新后的角色圣经",
  "timeline":   "更新后的时间线",
  "newHooks":   [{"hookType":"foreshadow|promise|secret","description":"","readerExpectation":""}],
  "closedHooks": ["已回收伏笔的描述关键词"]
}
只输出JSON。''';
}

// ════════════════════════════════════════════
// 🔍 连续性审计（InkOS 核心）
// ════════════════════════════════════════════
class AuditAgent {
  static Future<AuditResult> audit({
    required String draft,
    required String archiveContext,
  }) async {
    final resp = await _llm.chat('gongbu', [
      {'role': 'system', 'content': _soul},
      {'role': 'user',   'content': '''
档案（权威参考）：
$archiveContext

待审稿件（节选）：
${draft.length > 4000 ? draft.substring(draft.length - 4000) : draft}

输出JSON：'''},
    ], jsonMode: true, temperature: 0.1);

    final p = _safeJson(resp.content);
    final issues = (p['issues'] as List? ?? [])
      .map((i) => AuditIssue.fromMap(i as Map<String, dynamic>))
      .toList();

    final critical = issues.where((i) => i.level == 'CRITICAL').length;
    return AuditResult(
      passed:        critical == 0,
      criticalCount: critical,
      warningCount:  issues.where((i) => i.level == 'WARNING').length,
      issues:        issues,
    );
  }

  static Future<String> revise({
    required String draft,
    required List<AuditIssue> issues,
    required String archiveContext,
  }) async {
    final criticals = issues.where((i) => i.level == 'CRITICAL').toList();
    if (criticals.isEmpty) return draft;

    final issueBlock = criticals.asMap().entries
      .map((e) => '问题${e.key+1}：${e.value.description}\n建议：${e.value.suggestion ?? "按档案修正"}')
      .join('\n\n');

    final resp = await _llm.chat('gongbu', [
      {'role': 'system', 'content': '你是连续性修订者。只修正列出的CRITICAL问题，最小化改动。直接输出完整修正版正文。'},
      {'role': 'user',   'content': '档案参考：\n$archiveContext\n\n问题：\n$issueBlock\n\n原稿：\n$draft\n\n输出修正版：'},
    ], temperature: 0.3);

    return resp.content.isNotEmpty ? resp.content : draft;
  }

  static const _soul = '''你是连续性审计官。检查稿件与档案的矛盾。
输出JSON：
{
  "issues": [
    {
      "level": "CRITICAL|WARNING|INFO",
      "type": "位置矛盾|信息越界|道具错误|时间线错误|角色口吻",
      "description": "问题描述",
      "location": "原文片段",
      "suggestion": "修改建议"
    }
  ]
}
CRITICAL=必须修正（位置/信息/道具/规则矛盾）
WARNING=建议修正（口吻/词汇/节奏）
只输出JSON。''';
}

class AuditResult {
  const AuditResult({
    required this.passed,
    required this.criticalCount,
    required this.warningCount,
    required this.issues,
  });
  final bool passed;
  final int  criticalCount;
  final int  warningCount;
  final List<AuditIssue> issues;
}

class AuditIssue {
  const AuditIssue({
    required this.level,
    required this.type,
    required this.description,
    this.location,
    this.suggestion,
  });
  final String  level;
  final String  type;
  final String  description;
  final String? location;
  final String? suggestion;

  factory AuditIssue.fromMap(Map<String, dynamic> m) => AuditIssue(
    level:       m['level']       as String? ?? 'INFO',
    type:        m['type']        as String? ?? '',
    description: m['description'] as String? ?? '',
    location:    m['location']    as String?,
    suggestion:  m['suggestion']  as String?,
  );
}

// ════════════════════════════════════════════
// 📝 礼部 — 去AI味润色
// ════════════════════════════════════════════
class LibuAgent {
  static Future<String> polish(String draft, String genre) async {
    if (BingbuAgent.aiSmellScore(draft) < 20) return draft; // 质量足够，跳过

    final resp = await _llm.chat('libu', [
      {'role': 'system', 'content': _soul},
      {'role': 'user',   'content': '以下是$genre网文草稿，请去AI味润色（保持情节不变）：\n\n$draft'},
    ], temperature: 0.4);

    return resp.content.isNotEmpty ? resp.content : draft;
  }

  static const _soul = '''你是礼部文风润色师。去AI味规则：
1. "感到/感受到/感觉到+情绪" → 改为身体反应
2. 替换禁忌词（淡淡/微微/缓缓/只见/不禁）为具体词
3. 比喻从场景生长，不套宛如烈火/宛如春风
4. 连续5句以上纯对话，插入动作描写
保持原有情节和字数，只输出润色后正文。''';
}

// ════════════════════════════════════════════
// 💰 户部 — 数值账本验算
// ════════════════════════════════════════════
class HubuAgent {
  static Future<List<String>> verify(String draft, String ledger) async {
    if (ledger.trim().isEmpty) return [];

    final resp = await _llm.chat('hubu', [
      {'role': 'system', 'content': '你是户部账本官。检查章节中的数值/物品/境界矛盾。输出JSON：{"issues":["问题描述"]}。无问题输出{"issues":[]}。'},
      {'role': 'user',   'content': '账本：\n$ledger\n\n章节：\n${draft.length > 2000 ? draft.substring(0, 2000) : draft}'},
    ], jsonMode: true, temperature: 0.1);

    final p = _safeJson(resp.content);
    return (p['issues'] as List? ?? []).cast<String>();
  }
}

// ════════════════════════════════════════════
// 👥 吏部 — 群像调度
// ════════════════════════════════════════════
class LibuHrAgent {
  static Future<LibuHrResult> check(String draft, String characterBible) async {
    if (characterBible.trim().isEmpty) {
      return const LibuHrResult(flags: [], forgottenChars: []);
    }

    final resp = await _llm.chat('libu_hr', [
      {'role': 'system', 'content': '你是吏部群像司。检查角色行为是否符合角色圣经。输出JSON：{"flags":[{"charName":"","issue":"","level":"WARNING"}],"forgottenChars":[]}'},
      {'role': 'user',   'content': '角色圣经：\n$characterBible\n\n章节：\n${draft.length > 2000 ? draft.substring(0, 2000) : draft}'},
    ], jsonMode: true, temperature: 0.2);

    final p = _safeJson(resp.content);
    return LibuHrResult(
      flags:          (p['flags'] as List? ?? []).map((i) => i as Map<String,dynamic>).toList(),
      forgottenChars: (p['forgottenChars'] as List? ?? []).cast<String>(),
    );
  }
}

class LibuHrResult {
  const LibuHrResult({required this.flags, required this.forgottenChars});
  final List<Map<String, dynamic>> flags;
  final List<String>               forgottenChars;
}

// ════════════════════════════════════════════
// ⚖️ 刑部 — 合规审查
// ════════════════════════════════════════════
class XingbuAgent {
  static Future<Map<String, dynamic>> scan(
    String draft, List<String> platforms) async {
    if (platforms.isEmpty) {
      return {'ratings': {}, 'issues': [], 'passed': true};
    }

    final rules = {
      'qidian':   '政治敏感/血腥器官/宗教攻击需处理',
      'tomato':   '违禁词多/暴力中等/感情不露骨/避免封建迷信',
      'jjwxc':    '感情尺度较宽/历史架空可/现实敏感慎',
      'zhangyue': '偏保守/大众阅读',
    };
    final ruleBlock = platforms.map((p) => '$p：${rules[p] ?? "通用规范"}').join('\n');

    final resp = await _llm.chat('xingbu', [
      {'role': 'system', 'content': '你是刑部合规官。输出JSON：{"ratings":{"平台":"PASS|WARN|FAIL"},"issues":[{"platform":"","desc":"","suggestion":""}]}'},
      {'role': 'user',   'content': '平台规范：\n$ruleBlock\n\n章节：\n${draft.length > 2000 ? draft.substring(0, 2000) : draft}'},
    ], jsonMode: true, temperature: 0.1);

    final p = _safeJson(resp.content);
    return {
      'ratings': p['ratings'] ?? {},
      'issues':  p['issues']  ?? [],
      'passed':  (p['ratings'] as Map<String,dynamic>? ?? {}).values.every((v) => v != 'FAIL'),
    };
  }
}
