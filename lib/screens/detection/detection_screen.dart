// lib/screens/detection/detection_screen.dart
// 朱雀·AI文本检测屏幕
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/detection/text_detector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/db/database.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';
import '../../core/utils/extensions.dart';

// ── 检测状态 Provider ─────────────────────────
final _detectionProvider = StateProvider<DetectionResult?>((ref) => null);
final _detectingProvider = StateProvider<bool>((ref) => false);
final _selectedChapterProvider = StateProvider<Map<String,dynamic>?>((ref) => null);

class DetectionScreen extends ConsumerStatefulWidget {
  const DetectionScreen({super.key, this.bookId});
  final String? bookId;
  @override
  ConsumerState<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends ConsumerState<DetectionScreen> {
  final _textCtrl  = TextEditingController();
  bool _useLlm     = true;
  String _genre    = 'xuanhuan'; // 题材，影响检测阈值

  @override
  void initState() {
    super.initState();
    if (widget.bookId != null) _loadLatestChapter();
  }

  Future<void> _loadLatestChapter() async {
    final chapters = await AppDatabase.instance.getChapters(widget.bookId!);
    if (chapters.isNotEmpty) {
      final latest = chapters.last;
      ref.read(_selectedChapterProvider.notifier).state = latest;
      _textCtrl.text = latest['content'] as String? ?? '';
    }
  }

  @override
  void dispose() { _textCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final result    = ref.watch(_detectionProvider);
    final detecting = ref.watch(_detectingProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: _buildAppBar(),
      body: result == null
        ? _buildInput(detecting)
        : _buildResult(result),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: AppColors.surface,
    title: Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B35), Color(0xFFFF3366)]),
          borderRadius: BorderRadius.circular(8)),
        child: const Center(child: Text('雀', style: TextStyle(
          fontFamily: 'NotoSerifSC', fontSize: 13,
          fontWeight: FontWeight.w900, color: Colors.white))),
      ),
      const SizedBox(width: 10),
      const Text('朱雀·文本检测'),
    ]),
    actions: [
      if (ref.watch(_detectionProvider) != null)
        TextButton(
          onPressed: () {
            ref.read(_detectionProvider.notifier).state = null;
            ref.read(_selectedChapterProvider.notifier).state = null;
          },
          child: const Text('重新检测'),
        ),
    ],
  );

  // ── 输入界面 ──────────────────────────────────
  Widget _buildInput(bool detecting) {
    final chapters = widget.bookId != null
      ? ref.watch(chaptersProvider(widget.bookId!)).valueOrNull ?? []
      : <dynamic>[];
    final selected = ref.watch(_selectedChapterProvider);

    return Column(children: [
      // 顶部说明卡
      Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFF6B35).withOpacity(.12),
              const Color(0xFFFF3366).withOpacity(.08),
            ]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFF6B35).withOpacity(.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Text('🔥', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text('检测标准', style: TextStyle(
              fontFamily: 'NotoSerifSC', fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          const Text('≥ 85分 通过 · 70-84分 警告 · <70分 未通过\n'
            '检测文本须满足7项指标，包括句式多样性、词汇丰富度、'
            'AI特征词密度、段落节奏感等',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.65)),
        ]),
      ),

      // 章节选择（如果有书籍）
      if (chapters.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<Map<String,dynamic>?>(
            value: selected,
            dropdownColor: AppColors.cardBg,
            decoration: const InputDecoration(
              labelText: '选择章节检测',
              prefixIcon: Icon(Icons.article_outlined, size: 18)),
            items: [
              const DropdownMenuItem<Map<String,dynamic>?>(
                value: null, child: Text('自定义文本')),
              ...chapters.map((c) => DropdownMenuItem<Map<String,dynamic>>(
                value: c,
                child: Text('第${c['chapter_no']}章 · ${c['title']}',
                  style: const TextStyle(fontSize: 13)))),
            ],
            onChanged: (c) {
              ref.read(_selectedChapterProvider.notifier).state = c;
              if (c != null) _textCtrl.text = c['content'] as String? ?? '';
            }),
        ),
        const SizedBox(height: 12),
      ],

      // 文本输入
      Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Expanded(child: TextField(
              controller: _textCtrl,
              maxLines:   null,
              expands:    true,
              style: const TextStyle(
                fontFamily: 'NotoSerifSC', fontSize: 14,
                color: AppColors.textPrimary, height: 1.8),
              decoration: const InputDecoration(
                hintText:   '粘贴或输入待检测文本（建议500字以上）',
                border:     InputBorder.none,
                filled:     false,
                contentPadding: EdgeInsets.all(16)),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                Text(
                  '${RegExp(r'[\u4e00-\u9fa5]').allMatches(_textCtrl.text).length} 字',
                  style: const TextStyle(fontFamily: 'JetBrainsMono',
                    fontSize: 11, color: AppColors.textTertiary)),
                const Spacer(),
                // 题材选择
                DropdownButton<String>(
                  value: _genre,
                  dropdownColor: AppColors.surfaceL1,
                  underline: const SizedBox(),
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  items: const [
                    DropdownMenuItem(value: 'xuanhuan', child: Text('玄幻')),
                    DropdownMenuItem(value: 'xianxia',  child: Text('仙侠')),
                    DropdownMenuItem(value: 'dushi',    child: Text('都市')),
                    DropdownMenuItem(value: 'lishi',    child: Text('历史')),
                    DropdownMenuItem(value: 'yanqing',  child: Text('言情')),
                  ],
                  onChanged: (v) => setState(() => _genre = v ?? 'xuanhuan'),
                ),
                // LLM 检测开关
                Row(children: [
                  const Text('LLM精准检测', style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(width: 4),
                  Transform.scale(scale: .8,
                    child: Switch(
                      value: _useLlm,
                      onChanged: (v) => setState(() => _useLlm = v),
                      activeColor: AppColors.accent,
                    )),
                ]),
              ]),
            ),
          ]),
        ),
      )),
      const SizedBox(height: 16),

      // 检测按钮
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: detecting ? null : _detect,
            style: ElevatedButton.styleFrom(
              backgroundColor: detecting ? AppColors.border : const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0),
            child: detecting
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 12),
                  Text('朱雀检测中（${_useLlm ? "约10秒" : "约2秒"}）...'),
                ])
              : const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('🔥', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text('开始检测', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
          ),
        ),
      ),
    ]);
  }

  Future<void> _detect() async {
    final text = _textCtrl.text.trim();
    if (text.length < 50) {
      context.showError('文本太短，请至少输入50字');
      return;
    }
    ref.read(_detectingProvider.notifier).state = true;
    try {
      final result = await TextDetector.instance.detect(text, useLlm: _useLlm, genre: _genre);
      ref.read(_detectionProvider.notifier).state = result;
    } catch (e) {
      if (mounted) context.showError('检测失败：$e');
    } finally {
      ref.read(_detectingProvider.notifier).state = false;
    }
  }

  // ── 结果界面 ──────────────────────────────────
  Widget _buildResult(DetectionResult result) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 总分卡片
        _ScoreCard(result: result).animate().fadeIn(duration: 400.ms).scale(
          begin: const Offset(.95, .95), duration: 400.ms, curve: Curves.easeOutBack),
        const SizedBox(height: 16),

        // 7维度得分详情
        Text('检测维度', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ...result.dimensions.entries.toList().asMap().entries.map((entry) =>
          _DimCard(dim: entry.value.value)
            .animate(delay: Duration(milliseconds: entry.key * 60))
            .fadeIn(duration: 250.ms).slideY(begin: .1)),
        const SizedBox(height: 20),

        // 发现的问题
        if (result.issues.isNotEmpty) ...[
          Text('发现问题', style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600, color: AppColors.error)),
          const SizedBox(height: 10),
          ...result.issues.map((issue) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withOpacity(.2))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('⚠️', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: Text(issue, style: const TextStyle(
                fontSize: 13, color: AppColors.textPrimary, height: 1.6))),
            ]),
          ).animate().fadeIn()),
          const SizedBox(height: 20),
        ],

        // 改进建议
        Text('改进建议', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600, color: AppColors.accent)),
        const SizedBox(height: 10),
        ...result.suggestions.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accent.withOpacity(.2))),
          child: Text(e.value, style: const TextStyle(
            fontSize: 13, color: AppColors.textPrimary, height: 1.65)),
        ).animate(delay: Duration(milliseconds: e.key * 60)).fadeIn()),
        const SizedBox(height: 32),
      ]),
    );
  }
}

// ── 总分卡片 ─────────────────────────────────────
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({super.key, required this.result});
  final DetectionResult result;

  @override
  Widget build(BuildContext context) {
    final (bgGrad, borderColor, emoji) = switch (result.verdict) {
      DetectionVerdict.pass   => (
        [const Color(0xFF22C55E).withOpacity(.15), const Color(0xFF16A34A).withOpacity(.05)],
        const Color(0xFF22C55E),
        '✅'),
      DetectionVerdict.warn   => (
        [const Color(0xFFF59E0B).withOpacity(.15), const Color(0xFFD97706).withOpacity(.05)],
        const Color(0xFFF59E0B),
        '⚠️'),
      DetectionVerdict.fail   => (
        [const Color(0xFFEF4444).withOpacity(.12), const Color(0xFFDC2626).withOpacity(.05)],
        const Color(0xFFEF4444),
        '❌'),
      DetectionVerdict.reject => (
        [const Color(0xFF7C3AED).withOpacity(.15), const Color(0xFF6D28D9).withOpacity(.05)],
        const Color(0xFF7C3AED),
        '🚫'),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bgGrad),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor.withOpacity(.35))),
      child: Column(children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(result.verdict.label, style: TextStyle(
              fontFamily: 'NotoSerifSC', fontSize: 20, fontWeight: FontWeight.w900,
              color: borderColor)),
            const SizedBox(height: 4),
            Text(result.verdict.desc, style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
          ])),
          // 圆形得分
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2.5),
              color: borderColor.withOpacity(.1)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${result.totalScore}', style: TextStyle(
                fontFamily: 'JetBrainsMono', fontSize: 24,
                fontWeight: FontWeight.w900, color: borderColor)),
              Text('/100', style: const TextStyle(
                fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.textTertiary)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        // 进度条
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: result.totalScore / 100,
            minHeight: 8,
            backgroundColor: borderColor.withOpacity(.15),
            valueColor: AlwaysStoppedAnimation(borderColor),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0', style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.textTertiary)),
          Text(result.passed ? '通过线: 85分' : '未达通过线 (需≥85分)',
            style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9,
              color: result.passed ? borderColor : AppColors.error)),
          Text('100', style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.textTertiary)),
        ]),
      ]),
    );
  }
}

// ── 维度得分卡片 ─────────────────────────────────
class _DimCard extends StatelessWidget {
  const _DimCard({super.key, required this.dim});
  final DimScore dim;

  Color get _color => dim.ratio >= .85 ? AppColors.success
    : dim.ratio >= .6  ? AppColors.warning
    : AppColors.error;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(dim.name, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w500))),
        Text('${dim.score}/${dim.maxScore}', style: TextStyle(
          fontFamily: 'JetBrainsMono', fontSize: 12,
          fontWeight: FontWeight.w700, color: _color)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: dim.ratio,
          minHeight: 5,
          backgroundColor: AppColors.border,
          valueColor: AlwaysStoppedAnimation(_color),
        ),
      ),
      const SizedBox(height: 6),
      Text(dim.detail, style: const TextStyle(
        fontSize: 11, color: AppColors.textSecondary, height: 1.5)),
    ]),
  );
}
