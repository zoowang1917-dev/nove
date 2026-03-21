// lib/core/detection/text_detector.dart
// 朱雀·文本检测引擎 V2
// 基于一年实测反馈深度重写：10维度，权重重新校准，修复系统性偏差
import 'dart:math' as math;
import 'dart:isolate';
import '../llm/llm_client.dart';

// ════════════════════════════════════════════
// 数据模型
// ════════════════════════════════════════════
class DetectionResult {
  const DetectionResult({
    required this.totalScore,
    required this.dimensions,
    required this.verdict,
    required this.issues,
    required this.suggestions,
    required this.genre,
    this.llmOpinion,
  });
  final int    totalScore;
  final Map<String, DimScore> dimensions;
  final DetectionVerdict verdict;
  final List<String> issues;
  final List<String> suggestions;
  final String genre;       // 检测时使用的题材（影响阈值）
  final String? llmOpinion;

  bool get passed => totalScore >= 85;

  static DetectionVerdict scoreToVerdict(int s) => switch (s) {
    >= 85 => DetectionVerdict.pass,
    >= 70 => DetectionVerdict.warn,
    >= 50 => DetectionVerdict.fail,
    _     => DetectionVerdict.reject,
  };
}

enum DetectionVerdict { pass, warn, fail, reject }

extension DetectionVerdictX on DetectionVerdict {
  String get label => switch (this) {
    DetectionVerdict.pass   => '✅ 人类创作',
    DetectionVerdict.warn   => '⚠️ 疑似人类',
    DetectionVerdict.fail   => '❌ 疑似AI',
    DetectionVerdict.reject => '🚫 AI生成',
  };
  String get desc => switch (this) {
    DetectionVerdict.pass   => '具有明显人类写作特征，通过85分检测线',
    DetectionVerdict.warn   => '存在部分AI特征，建议针对性润色后重测',
    DetectionVerdict.fail   => 'AI特征明显，需要大量改写才能通过',
    DetectionVerdict.reject => 'AI生成文本，需彻底人工重写',
  };
}

class DimScore {
  const DimScore({
    required this.name, required this.score, required this.maxScore,
    required this.detail, this.evidence = const [],
  });
  final String name;
  final int    score, maxScore;
  final String detail;
  final List<String> evidence;  // 具体证据（供UI展示）
  double get ratio => maxScore > 0 ? score / maxScore : 0;
}

// ════════════════════════════════════════════
// 朱雀 V2 检测引擎
// ════════════════════════════════════════════
class TextDetector {
  TextDetector._();
  static final TextDetector instance = TextDetector._();

  // ─────────────────────────────────────────
  // 词库（扩充+精校）
  // ─────────────────────────────────────────

  // AI 禁忌词（56→80词，按危害度分级）
  static const _aiWordsTier1 = [  // 高危：每次命中 -4分
    '感受到', '感觉到', '感到一阵', '感到一股',
    '内心深处', '心中一动', '心头一紧', '心神一震',
    '与此同时', '此时此刻', '这一刻', '那一刻',
    '油然而生', '心中涌起', '心潮澎湃',
  ];
  static const _aiWordsTier2 = [  // 中危：每次命中 -2分
    '淡淡', '微微', '缓缓', '轻轻', '默默', '静静', '悄悄',
    '渐渐', '徐徐', '悄然', '悠悠', '款款', '轻缓',
    '不由自主', '情不自禁', '不禁', '不由得', '不由',
    '只见', '却见', '但见', '便见',
    '宛如利剑', '宛如烈火', '宛如春风', '宛如惊雷',
    '如同利剑', '犹如利剑', '好似春风', '仿佛烈火',
  ];
  static const _aiWordsTier3 = [  // 低危：每次命中 -1分
    '忽然间', '竟然', '此刻', '彼时', '就在这时',
    '目瞪口呆', '大惊失色', '热血沸腾', '心如死灰',
    '茅塞顿开', '醍醐灌顶', '怒发冲冠',
  ];

  // 突发动词（AI滥用）
  static const _suddenWords = [
    '突然', '忽然', '猛然', '顿时', '蓦然', '骤然', '陡然',
    '猛地', '忽地', '蓦地', '骤然间',
  ];

  // 情感词（AI堆砌）
  static const _emotionWords = [
    '愤怒', '震惊', '惊喜', '恐惧', '绝望', '悲伤', '兴奋',
    '惊恐', '惊讶', '愕然', '错愕', '诧异', '骇然',
    '惊骇', '慌乱', '慌张', '欣喜', '狂喜', '狂怒',
  ];

  // 句首高频词（AI倾向）
  static const _aiStarterWords = [
    '他', '她', '随后', '顿时', '这时', '此时', '然后',
    '接着', '随即', '紧接着', '与此同时', '就在这时',
  ];

  // 口语词（按题材分类）
  static const _colloquialModern = [
    '哎', '啧', '唉', '哟', '哎哟', '咋', '嗯', '呗', '嘛',
  ];
  static const _colloquialAncient = [
    '哦', '罢了', '也罢', '且说', '且道', '话说', '且慢',
    '岂料', '不料', '岂知',
  ];
  static const _colloquialNovel = [  // 网文通用
    '卧槽', '我去', '666', '离谱', '离了个大谱',
  ];

  // 陈词滥调比喻
  static const _clicheMetaphors = [
    '目光如炬', '眼神如刀', '心如死灰', '万念俱灰',
    '如芒在背', '如鲠在喉', '如获至宝', '如临大敌',
    '如履薄冰', '如坐针毡', '大喜过望', '喜出望外',
  ];

  // ─────────────────────────────────────────
  // 主入口
  // ─────────────────────────────────────────
  // UI 安全调用入口 — 将重度正则计算迁移到后台 Isolate，绝对不卡 UI
  Future<DetectionResult> detectSafe(String text, {
    bool useLlm  = false,   // 在 Isolate 中无法调用异步 LLM，先禁用
    String genre = 'xuanhuan',
  }) async {
    // Isolate.run 会在独立线程执行，UI 线程完全不受影响
    final localResult = await Isolate.run(() => _heavyAnalysis(text, genre));
    if (!useLlm) return localResult;
    // LLM 部分在主线程运行（需要异步 IO）
    final llmDim  = await _llmJudge(text, genre);
    final newDims = {...localResult.dimensions, 'llm': llmDim};
    final total   = newDims.values.fold(0, (s, d) => s + d.score).clamp(0, 100);
    return DetectionResult(
      totalScore: total, dimensions: newDims,
      verdict:    DetectionResult.scoreToVerdict(total),
      issues:     localResult.issues,
      suggestions: _buildSuggestions(newDims, localResult.issues, genre),
      genre:      genre,
      llmOpinion: llmDim.detail,
    );
  }

  // 内部重度计算（纯同步，适合在 Isolate 中运行）
  static DetectionResult _heavyAnalysis(String text, String genre) {
    final instance = TextDetector._();
    final dims     = <String, DimScore>{};
    final issues   = <String>[];
    dims['variety']   = instance._checkSentenceVariety(text, issues);
    dims['vocab']     = instance._checkVocabMATTR(text, issues);
    final (narrative, dialogue) = instance._splitNarrativeDialogue(text);
    dims['aiwords']   = instance._checkAiWordsDensity(narrative, text, issues);
    dims['sudden']    = instance._checkSuddenWords(text, issues);
    dims['starter']   = instance._checkSentenceStarters(text, issues);
    dims['punct']     = instance._checkPunctuation(text, issues);
    dims['emotion']   = instance._checkEmotionDensity(narrative, issues);
    dims['colloquial'] = instance._checkColloquialByGenre(dialogue, genre);
    dims['rhythm']    = instance._checkParagraphRhythm(text, issues);
    // LLM 维度在 Isolate 中跳过，给保守分
    dims['llm'] = const DimScore(name: 'LLM深度判断', score: 3, maxScore: 5, detail: '（Isolate模式）');
    final total   = dims.values.fold(0, (s, d) => s + d.score).clamp(0, 100);
    return DetectionResult(
      totalScore: total, dimensions: dims,
      verdict:    DetectionResult.scoreToVerdict(total),
      issues:     issues,
      suggestions: instance._buildSuggestions(dims, issues, genre),
      genre:      genre,
    );
  }

  Future<DetectionResult> detect(String text, {
    bool useLlm   = true,
    String genre  = 'xuanhuan',  // 题材：xuanhuan/xianxia/dushi/lishi/yanqing
  }) async {
    if (text.trim().length < 100) {
      return DetectionResult(
        totalScore: 50, dimensions: {},
        verdict:    DetectionVerdict.fail,
        issues:     ['文本过短，无法准确检测'],
        suggestions: ['请提供至少500字的文本进行检测'],
        genre: genre,
      );
    }

    // 预处理：分离对话和叙述（关键！）
    final (narrative, dialogue) = _splitNarrativeDialogue(text);
    final issues = <String>[];
    final dims   = <String, DimScore>{};

    // D1. 句式多样性 (15分) — 核心指标
    dims['variety']   = _checkSentenceVariety(text, issues);

    // D2. 词汇丰富度 MATTR (12分) — 修复：用二元组近似词汇
    dims['vocab']     = _checkVocabMATTR(text, issues);

    // D3. AI特征词密度 (15分) — 修复：密度归一化+分对话叙述
    dims['aiwords']   = _checkAiWordsDensity(narrative, text, issues);

    // D4. 突发动词密度 (10分) — 新增：AI最明显特征之一
    dims['sudden']    = _checkSuddenWords(text, issues);

    // D5. 句首词多样性 (12分) — 新增：最能区分AI的指标
    dims['starter']   = _checkSentenceStarters(text, issues);

    // D6. 标点多样性 (8分) — 新增：AI严重缺失——和……
    dims['punct']     = _checkPunctuation(text, issues);

    // D7. 情感词密度 (8分) — 新增：AI情感堆砌
    dims['emotion']   = _checkEmotionDensity(narrative, issues);

    // D8. 对话自然度 (8分) — 修复：按题材区分口语化期望
    dims['colloquial'] = _checkColloquialByGenre(dialogue, genre);

    // D9. 段落节奏 (7分) — 保留并改进
    dims['rhythm']    = _checkParagraphRhythm(text, issues);

    // D10. LLM深度判断 (5分) — 修复：跳过给3分而非7分
    if (useLlm) {
      dims['llm'] = await _llmJudge(text, genre);
    } else {
      dims['llm'] = const DimScore(
        name: 'LLM深度', score: 3, maxScore: 5,
        detail: '（未启用，最低保守分）');
    }

    final raw   = dims.values.fold(0, (s, d) => s + d.score);
    final total = raw.clamp(0, 100);

    return DetectionResult(
      totalScore:  total,
      dimensions:  dims,
      verdict:     DetectionResult.scoreToVerdict(total),
      issues:      issues,
      suggestions: _buildSuggestions(dims, issues, genre),
      genre:       genre,
      llmOpinion:  dims['llm']?.detail,
    );
  }

  // ─────────────────────────────────────────
  // 预处理：分离对话和叙述
  // ─────────────────────────────────────────
  (String, String) _splitNarrativeDialogue(String text) {
    final dialogueRe = RegExp(r'[「『""]([^」』""]{2,200})[」』""]');
    final dialogueBuf  = StringBuffer();
    final narrativeBuf = StringBuffer();

    int pos = 0;
    for (final m in dialogueRe.allMatches(text)) {
      narrativeBuf.write(text.substring(pos, m.start));
      dialogueBuf.write(m.group(1) ?? '');
      pos = m.end;
    }
    if (pos < text.length) narrativeBuf.write(text.substring(pos));

    return (narrativeBuf.toString(), dialogueBuf.toString());
  }

  // ─────────────────────────────────────────
  // D1. 句式多样性 (15分)
  // ─────────────────────────────────────────
  DimScore _checkSentenceVariety(String text, List<String> issues) {
    final sents = text
      .split(RegExp(r'[。！？…]'))
      .where((s) => s.trim().length > 4)
      .map((s) => s.trim().length)
      .toList();

    if (sents.length < 5) {
      return const DimScore(name: '句式多样性', score: 10, maxScore: 15, detail: '样本不足');
    }

    final mean = sents.reduce((a,b)=>a+b) / sents.length;
    final std  = math.sqrt(sents.map((s)=>math.pow(s-mean,2)).reduce((a,b)=>a+b) / sents.length);
    final cv   = mean > 0 ? std / mean : 0;

    // 同时检查极短句（<6字）和极长句（>40字）的占比
    final veryShort = sents.where((s) => s < 6).length / sents.length;
    final veryLong  = sents.where((s) => s > 40).length / sents.length;
    // 人类：有短句爆发 + 长句沉淀，两者各占10%+
    final hasRhythm = veryShort >= 0.08 && veryLong >= 0.08;

    int score;
    String detail;
    final evidence = <String>[];

    if (cv >= 0.55 && hasRhythm) {
      score  = 15; detail = '句式节奏感强（CV=${cv.toStringAsFixed(2)}，有短句爆发和长句沉淀）';
    } else if (cv >= 0.45) {
      score  = 12; detail = '句式有变化（CV=${cv.toStringAsFixed(2)}）';
    } else if (cv >= 0.3) {
      score  = 8;  detail = '句式略均匀（CV=${cv.toStringAsFixed(2)}）';
      issues.add('句式长度过于均匀，缺乏节奏感');
    } else {
      score  = 3;  detail = '句式高度均匀（CV=${cv.toStringAsFixed(2)}），强烈AI特征';
      issues.add('🔴 句式长度极其均匀 — AI最典型特征，平均${mean.toStringAsFixed(0)}字/句，几乎无变化');
      evidence.add('平均句长: ${mean.toStringAsFixed(1)}字，标准差仅 ${std.toStringAsFixed(1)}');
    }
    return DimScore(name: '句式多样性', score: score, maxScore: 15, detail: detail, evidence: evidence);
  }

  // ─────────────────────────────────────────
  // D2. 词汇丰富度 MATTR (12分)
  // 使用移动平均 TTR，用二元字组近似中文词汇单位
  // ─────────────────────────────────────────
  DimScore _checkVocabMATTR(String text, List<String> issues) {
    final chars = RegExp(r'[\u4e00-\u9fa5]').allMatches(text).map((m) => m.group(0)!).toList();
    if (chars.length < 100) {
      return const DimScore(name: '词汇丰富度', score: 8, maxScore: 12, detail: '样本过短');
    }

    // 用二元字组（bigrams）近似词汇单位，比单字更准确
    final bigrams = <String>[];
    for (int i = 0; i < chars.length - 1; i++) {
      bigrams.add('${chars[i]}${chars[i+1]}');
    }

    // MATTR：移动窗口平均 TTR（窗口200个bigram）
    const windowSize = 200;
    final mattrValues = <double>[];
    for (int i = 0; i + windowSize <= bigrams.length; i += windowSize ~/ 4) {
      final window = bigrams.sublist(i, math.min(i + windowSize, bigrams.length));
      mattrValues.add(window.toSet().length / window.length);
    }
    final mattr = mattrValues.isEmpty ? 0.5
      : mattrValues.reduce((a,b)=>a+b) / mattrValues.length;

    int score;
    String detail;
    if (mattr >= 0.68) {
      score  = 12; detail = 'MATTR=${mattr.toStringAsFixed(3)} — 词汇极为丰富';
    } else if (mattr >= 0.58) {
      score  = 9;  detail = 'MATTR=${mattr.toStringAsFixed(3)} — 词汇较丰富';
    } else if (mattr >= 0.48) {
      score  = 6;  detail = 'MATTR=${mattr.toStringAsFixed(3)} — 词汇有重复';
      issues.add('词汇重复率较高，建议增加同义词变换');
    } else {
      score  = 2;  detail = 'MATTR=${mattr.toStringAsFixed(3)} — 词汇严重重复';
      issues.add('🔴 词汇极度单一（MATTR=${mattr.toStringAsFixed(3)}），大量词语重复出现，AI特征');
    }
    return DimScore(name: '词汇MATTR', score: score, maxScore: 12, detail: detail);
  }

  // ─────────────────────────────────────────
  // D3. AI特征词密度 (15分) — 密度归一化+分级
  // ─────────────────────────────────────────
  DimScore _checkAiWordsDensity(String narrative, String fullText, List<String> issues) {
    final charCount = RegExp(r'[\u4e00-\u9fa5]').allMatches(narrative.isNotEmpty ? narrative : fullText).length;
    if (charCount < 30) {
      return const DimScore(name: 'AI特征词', score: 12, maxScore: 15, detail: '叙述部分样本不足');
    }

    // 在叙述部分（非对话）检测
    final target = narrative.isNotEmpty ? narrative : fullText;
    int deduction = 0;
    final hits    = <String>[];

    for (final w in _aiWordsTier1) {
      final cnt = RegExp(RegExp.escape(w)).allMatches(target).length;
      if (cnt > 0) { hits.add('「$w」×$cnt'); deduction += cnt * 4; }
    }
    for (final w in _aiWordsTier2) {
      final cnt = RegExp(RegExp.escape(w)).allMatches(target).length;
      if (cnt > 0) { hits.add('「$w」×$cnt'); deduction += cnt * 2; }
    }
    for (final w in _aiWordsTier3) {
      final cnt = RegExp(RegExp.escape(w)).allMatches(target).length;
      if (cnt > 0) { hits.add('「$w」×$cnt'); deduction += cnt * 1; }
    }

    // 密度归一化（每千字的扣分，防止长文被过度惩罚）
    final deductionPer1k = charCount > 0 ? (deduction / charCount * 1000) : 0;
    final score = (15 - deductionPer1k.round().clamp(0, 15)).clamp(0, 15);

    final detail = hits.isEmpty
      ? '叙述部分无AI特征词'
      : '叙述中命中 ${hits.length} 种：${hits.take(4).join('、')}';

    if (hits.isNotEmpty) {
      issues.add('AI高频词（仅计叙述，不含对话）：${hits.take(6).join('、')}');
    }
    return DimScore(name: 'AI特征词密度', score: score, maxScore: 15,
      detail: detail, evidence: hits.take(5).toList());
  }

  // ─────────────────────────────────────────
  // D4. 突发动词密度 (10分) — 新增
  // ─────────────────────────────────────────
  // Fix4: 突发词密度检测（参考用户方案：每千字>3次即AI典型）
  DimScore _checkSuddenWords(String text, List<String> issues) {
    final charCount = RegExp(r'[\u4e00-\u9fa5]').allMatches(text).length;
    if (charCount < 100) return const DimScore(name: '突发词密度', score: 7, maxScore: 10, detail: '样本不足');

    // 突发动词（完整列表）
    final suddenRe = RegExp(r'(突然|忽然|猛然|顿时|刹那间|蓦然|骤然|陡然|猛地|忽地|蓦地)');
    final matches   = suddenRe.allMatches(text);
    final total     = matches.length;
    final density   = total / (charCount / 1000); // 每千字频次

    final foundWords = <String>{};
    for (final m in matches) foundWords.add(m.group(0) ?? '');

    int score;
    String detail;
    if (density <= 1.0) {
      score = 10; detail = '突发词适量（${density.toStringAsFixed(1)}次/千字）';
    } else if (density <= 2.0) {
      score = 7;  detail = '突发词略多（${density.toStringAsFixed(1)}次/千字）';
    } else if (density <= 3.0) {
      score = 4;  detail = '突发词过多（${density.toStringAsFixed(1)}次/千字），AI制造假紧张感';
      issues.add('「突然/忽然/猛然」出现${total}次（${density.toStringAsFixed(1)}次/千字），人工写作极少如此密集');
    } else {
      score = 1;  detail = '突发词泛滥（${density.toStringAsFixed(1)}次/千字），强烈AI特征';
      issues.add('🔴 突发动词每千字${density.toStringAsFixed(1)}次，是正常值3倍以上（${foundWords.take(4).join("、")}）');
    }
    return DimScore(name: '突发词密度', score: score, maxScore: 10, detail: detail);
  }

  // ─────────────────────────────────────────
  // D5. 句首词多样性 (12分) — 新增（最关键指标）
  // ─────────────────────────────────────────
  // Fix4: 句首词重复检测（用户方案：前两字 + 25%阈值）
  DimScore _checkSentenceStarters(String text, List<String> issues) {
    final sentences = text.split(RegExp(r'[。！？]'))
      .map((s) => s.trim())
      .where((s) => s.length > 2)
      .toList();

    if (sentences.length < 8) {
      return const DimScore(name: '句首多样性', score: 8, maxScore: 12, detail: '句子数量不足');
    }

    // 提取句首前两字（用户方案）
    final starterCounts = <String, int>{};
    for (var sentence in sentences) {
      final chs = RegExp(r'[\u4e00-\u9fa5]').allMatches(sentence)
        .take(2).map((m) => m.group(0)!).toList();
      if (chs.isEmpty) continue;
      final starter = chs.join();
      // 统计 AI 高频句首词（用户建议的词表）
      const aiStarters = ['他说','她说','随后','这时','只见','顿时','紧接','此时'];
      final isAiWord   = aiStarters.any((w) => starter.startsWith(w.substring(0, math.min(2, w.length))));
      if (isAiWord || true) { // 统计所有句首词
        starterCounts[starter] = (starterCounts[starter] ?? 0) + 1;
      }
    }

    if (starterCounts.isEmpty) {
      return const DimScore(name: '句首多样性', score: 8, maxScore: 12, detail: '无法提取句首词');
    }

    // 最高频的单个句首词占比（用户方案的25%阈值）
    final sorted       = (starterCounts.entries.toList()..sort((a,b) => b.value.compareTo(a.value)));
    final maxCount     = sorted.first.value;
    final maxRatio     = maxCount / sentences.length;
    final top3Total    = sorted.take(3).fold(0, (s, e) => s + e.value);
    final top3Ratio    = top3Total / sentences.length;
    final diversity    = starterCounts.length / sentences.length;
    final evidence     = sorted.take(3).map((e) => '「${e.key}」×${e.value}').toList();

    int score;
    String detail;

    if (maxRatio <= 0.15 && top3Ratio <= 0.35) {
      score = 12; detail = '句首词高度多样（多样性=${diversity.toStringAsFixed(2)}）';
    } else if (maxRatio <= 0.20 && top3Ratio <= 0.45) {
      score = 9;  detail = '句首词较多样';
    } else if (maxRatio <= 0.25) {
      // 用户方案：超过25%为异常阈值
      score = 6;  detail = '句首词略重复（最高频占${(maxRatio*100).round()}%）';
      issues.add('句首词重复：${sorted.take(2).map((e)=>"「${e.key}」${e.value}次").join("、")}');
    } else {
      score = 2;  detail = '句首词高度重复（最高频占${(maxRatio*100).round()}%）—— AI典型';
      issues.add('🔴 超过${(maxRatio*100).round()}%的句子以「${sorted.first.key}」开头，句式结构单一（AI典型特征）');
    }
    return DimScore(name: '句首多样性', score: score, maxScore: 12, detail: detail, evidence: evidence);
  }

  // ─────────────────────────────────────────
  // D6. 标点多样性 (8分) — 新增
  // ─────────────────────────────────────────
  DimScore _checkPunctuation(String text, List<String> issues) {
    final allPunct = RegExp(r'[，。！？；：—…""''「」【】]').allMatches(text).map((m) => m.group(0)!).toList();
    if (allPunct.length < 20) {
      return const DimScore(name: '标点多样性', score: 5, maxScore: 8, detail: '标点数量不足');
    }

    final total      = allPunct.length;
    final comma      = allPunct.where((p) => p == '，').length;
    final emDash     = allPunct.where((p) => p == '—').length;
    final ellipsis   = allPunct.where((p) => p == '…').length;
    final question   = allPunct.where((p) => p == '？').length;
    final exclamation= allPunct.where((p) => p == '！').length;

    final commaRatio   = comma / total;
    final dashEllipsis = (emDash + ellipsis) / total;
    final emotivePunct = (question + exclamation) / total;

    // AI特征：逗号>85%，破折号省略号<2%
    int score;
    String detail;

    if (commaRatio <= 0.72 && dashEllipsis >= 0.06) {
      score  = 8; detail = '标点丰富（逗号${(commaRatio*100).round()}%，——/…占${(dashEllipsis*100).round()}%）';
    } else if (commaRatio <= 0.80 && dashEllipsis >= 0.03) {
      score  = 6; detail = '标点较丰富（逗号${(commaRatio*100).round()}%）';
    } else if (commaRatio <= 0.87) {
      score  = 4; detail = '标点略单调（逗号${(commaRatio*100).round()}%，——/…仅${(dashEllipsis*100).round()}%）';
      issues.add('标点单调，破折号「——」和省略号「……」使用过少（${emDash+ellipsis}次）');
    } else {
      score  = 1; detail = '标点严重单调（逗号${(commaRatio*100).round()}%，——/…几乎为0）';
      issues.add('🔴 标点严重失衡：逗号占${(commaRatio*100).round()}%，「——」「……」共仅${emDash+ellipsis}次 — AI最典型标点特征');
    }
    return DimScore(name: '标点多样性', score: score, maxScore: 8,
      detail: detail,
      evidence: ['逗号${(commaRatio*100).round()}%', '——/…${(dashEllipsis*100).round()}%',
        '情绪标点${(emotivePunct*100).round()}%']);
  }

  // ─────────────────────────────────────────
  // D7. 情感词密度 (8分) — 新增
  // ─────────────────────────────────────────
  DimScore _checkEmotionDensity(String narrative, List<String> issues) {
    final target    = narrative.isNotEmpty ? narrative : '';
    final charCount = RegExp(r'[\u4e00-\u9fa5]').allMatches(target).length;
    if (charCount < 50) {
      return const DimScore(name: '情感词密度', score: 6, maxScore: 8, detail: '叙述样本不足');
    }

    int total = 0;
    final hits = <String>[];
    for (final w in _emotionWords) {
      final cnt = RegExp(RegExp.escape(w)).allMatches(target).length;
      if (cnt > 0) { total += cnt; hits.add('$w×$cnt'); }
    }

    final density = total / charCount * 1000; // 每千字情感词数
    // 正常人类叙述：直接情感词密度 < 1‰，AI通常 > 3‰
    int score;
    String detail;
    if (density <= 1.0) {
      score  = 8; detail = '情感词密度适宜（${density.toStringAsFixed(1)}‰）—— 情感通过行为暗示';
    } else if (density <= 2.0) {
      score  = 6; detail = '情感词略多（${density.toStringAsFixed(1)}‰）';
    } else if (density <= 4.0) {
      score  = 3; detail = '情感词过密（${density.toStringAsFixed(1)}‰）—— AI堆砌特征';
      issues.add('直接情感词过密（${density.toStringAsFixed(1)}‰）：${hits.take(4).join("、")}，建议改为行为/生理反应');
    } else {
      score  = 1; detail = '情感词泛滥（${density.toStringAsFixed(1)}‰）—— 强烈AI特征';
      issues.add('🔴 情感词密度${density.toStringAsFixed(1)}‰，是正常值4倍，AI惯用直述情感代替具体描写');
    }
    return DimScore(name: '情感词密度', score: score, maxScore: 8, detail: detail);
  }

  // ─────────────────────────────────────────
  // D8. 对话口语化（按题材校准）(8分) — 修复
  // ─────────────────────────────────────────
  // Fix4: 题材感知口语化检测（古言/历史不扣现代口语分）
  DimScore _checkColloquialByGenre(String dialogue, String genre) {
    if (dialogue.length < 50) {
      return const DimScore(name: '对话自然度', score: 6, maxScore: 8, detail: '对话量不足');
    }

    // Fix4: 古言/历史题材不检测现代网络词，改检测文言口语词
    final isAncient = genre == 'lishi' || genre == 'gukong' ||
                      genre == 'xianxia' || genre == '古言' || genre == '历史';
    if (isAncient) {
      // 古代题材检测：有文言口语词即满分（不惩罚没有现代词）
      final ancientHits = _colloquialAncient.fold(0, (sum, w) =>
        sum + RegExp(RegExp.escape(w)).allMatches(dialogue).length);
      if (ancientHits > 0) {
        return DimScore(name: '对话自然度', score: 8, maxScore: 8,
          detail: '古代文风对话自然（检测到文言口语词${ancientHits}处）');
      }
      return const DimScore(name: '对话自然度', score: 7, maxScore: 8,
        detail: '古代/仙侠题材，对话文风正常（不强求现代口语）');
    }

    // 现代/都市/言情题材：检测现代口语词
    final charCount = RegExp(r'[\u4e00-\u9fa5]').allMatches(dialogue).length;
    final modernWords = [..._colloquialModern, ..._colloquialNovel];
    int hits = 0;
    for (final w in modernWords) {
      hits += RegExp(RegExp.escape(w)).allMatches(dialogue).length;
    }
    final density = charCount > 0 ? hits / charCount * 1000 : 0;

    int score;
    String detail;
    if (density >= 1.0) {
      score = 8; detail = '对话口语化自然（密度${density.toStringAsFixed(1)}‰）';
    } else if (density >= 0.3) {
      score = 6; detail = '对话有口语化表达';
    } else {
      score = 4; detail = '现代题材对话口语化不足（密度${density.toStringAsFixed(1)}‰）';
    }
    return DimScore(name: '对话自然度', score: score, maxScore: 8, detail: detail);
  }

  // ─────────────────────────────────────────
  // D9. 段落节奏 (7分)
  // ─────────────────────────────────────────
  DimScore _checkParagraphRhythm(String text, List<String> issues) {
    final paras = text.split('\n\n').where((p) => p.trim().length > 8)
      .map((p) => p.trim().length).toList();
    if (paras.length < 4) {
      return const DimScore(name: '段落节奏', score: 5, maxScore: 7, detail: '段落数不足');
    }

    final mean = paras.reduce((a,b)=>a+b) / paras.length;
    final cv   = mean > 0 ? math.sqrt(
      paras.map((p)=>math.pow(p-mean,2)).reduce((a,b)=>a+b) / paras.length
    ) / mean : 0;

    // 额外检测：是否有超短段（1-2句）
    final hasShortPara = paras.any((p) => p < 30);

    int score;
    String detail;
    if (cv >= 0.55 && hasShortPara) {
      score  = 7; detail = '段落节奏生动（CV=${cv.toStringAsFixed(2)}，含短段）';
    } else if (cv >= 0.4) {
      score  = 5; detail = '段落节奏尚可（CV=${cv.toStringAsFixed(2)}）';
    } else if (cv >= 0.25) {
      score  = 3; detail = '段落偏均匀（CV=${cv.toStringAsFixed(2)}）';
      issues.add('段落长度过于一致，缺乏视觉节奏感');
    } else {
      score  = 1; detail = '段落极均匀（CV=${cv.toStringAsFixed(2)}）—— AI特征';
      issues.add('🔴 段落长度高度一致，无短段爆发，AI生成的标志');
    }
    return DimScore(name: '段落节奏', score: score, maxScore: 7, detail: detail);
  }

  // ─────────────────────────────────────────
  // D10. LLM深度判断 (5分) — 修复：跳过给3分
  // ─────────────────────────────────────────
  Future<DimScore> _llmJudge(String text, String genre) async {
    try {
      final preview = text.length > 800 ? text.substring(0, 800) : text;
      final resp    = await LlmClient.instance.chat('libu', [
        {'role': 'system', 'content': '''你是资深文学编辑，专精识别AI生成文本。
题材：$genre。仅输出JSON，不加任何说明：
{
  "ai_probability": 0-100,
  "top_evidence": ["最具说服力的3条AI证据"],
  "human_evidence": ["支持人类创作的1-2条证据"]
}
AI概率判断依据：句式模式、情感表达方式、细节具体性、节奏自然度。'''},
        {'role': 'user', 'content': '分析：\n\n$preview'},
      ], jsonMode: true, temperature: 0.05);

      final aiProbMatch = RegExp(r'"ai_probability"\s*:\s*(\d+)').firstMatch(resp.content);
      final aiProb      = int.tryParse(aiProbMatch?.group(1) ?? '60') ?? 60;
      final score       = ((100 - aiProb) / 20).round().clamp(0, 5);
      return DimScore(
        name: 'LLM深度判断', score: score, maxScore: 5,
        detail: 'AI概率估计 $aiProb%',
      );
    } catch (e) {
      // 修复：跳过时给保守分3（而非虚高的7）
      return const DimScore(name: 'LLM深度判断', score: 3, maxScore: 5,
        detail: 'LLM跳过（保守估计）');
    }
  }

  // ─────────────────────────────────────────
  // 生成建议（按题材定制）
  // ─────────────────────────────────────────
  List<String> _buildSuggestions(Map<String, DimScore> d, List<String> issues, String genre) {
    final sug = <String>[];

    if ((d['starter']?.score ?? 10) < 8) {
      sug.add('✍️ 变化句首词：刻意避免连续用「他/她/随后」开头，尝试用场景/动作/感官开句');
    }
    if ((d['sudden']?.score ?? 8) < 6) {
      sug.add('⚡ 减少突发词：每200字最多用1次「突然/忽然」，改为具体动作前置表现突发感');
    }
    if ((d['punct']?.score ?? 6) < 5) {
      sug.add('—— 增加「——」「……」：对话停顿用「——」，情绪未尽用「……」，每章至少各用5次');
    }
    if ((d['emotion']?.score ?? 6) < 5) {
      sug.add('💭 情感具身化：把「他愤怒了」改为「他的手握紧，指关节泛白」');
    }
    if ((d['aiwords']?.score ?? 12) < 10) {
      sug.add('🔤 替换AI词：把「感受到愤怒」改为具体身体反应，把「淡淡」「微微」全部删除');
    }
    if ((d['variety']?.score ?? 12) < 9) {
      sug.add('📏 制造句式对比：每3-4个长句后，插入1个5字以内的极短句，强化节奏冲击感');
    }

    if (sug.isEmpty) {
      sug.add('✅ 文本整体达标！各维度表现均衡，人类写作特征明显');
    }
    return sug;
  }
}
