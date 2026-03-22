// lib/screens/writing/writing_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/extensions.dart';
import '../../core/pipeline/novel_pipeline.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../platform/platform_service.dart';
import '../../platform/notification_service.dart';
import '../../widgets/common/widgets.dart';

class WritingScreen extends ConsumerStatefulWidget {
  const WritingScreen({super.key, required this.bookId});
  final String bookId;
  @override
  ConsumerState<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends ConsumerState<WritingScreen>
    with TickerProviderStateMixin {

  late final TabController _tabs;
  final _instrCtrl = TextEditingController();
  StreamSubscription<PipelineEvent>? _sub;
  final _streamBuf = StringBuffer();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    platform.enterWritingMode();
    _listenPipeline();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fix1: 检测启动时发现的中断任务
    final interrupted = ref.read(interruptedTaskProvider);
    if (interrupted != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('检测到上次写作被中断（可能是App被系统终止），请重新下达指令')),
          ]),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: '知道了', onPressed: () {
            ref.read(interruptedTaskProvider.notifier).state = null;
          }),
        ));
      });
    }
  }

  void _listenPipeline() {
    _sub = NovelPipeline.instance.events.listen((event) {
      if (!mounted) return;
      switch (event.type) {
        case PipelineEventType.agentSwitch:
          ref.read(activeAgentProvider.notifier).state = event.agentId ?? '';
        case PipelineEventType.token:
          if (event.content != null) {
            _streamBuf.write(event.content);
            ref.read(streamingTextProvider.notifier).state = _streamBuf.toString();
          }
        case PipelineEventType.done:
          ref.read(activeAgentProvider.notifier).state = '';
          ref.read(pipelineRunningProvider.notifier).state = false;
          NotificationService.instance.clearWritingProgress();
          ref.invalidate(chaptersProvider(widget.bookId));
          ref.invalidate(bookDetailProvider(widget.bookId));
          ref.invalidate(hooksProvider(widget.bookId));
          final wordCount = event.data?['wordCount'] as int? ?? 0;
          final chapterNo = event.data?['chapterNo'] as int? ?? 0;
          if (mounted) {
            _instrCtrl.clear();
            context.showSuccess('第${chapterNo}章完成！${wordCount.wordCountLabel}');
            _tabs.animateTo(1); // 自动切换到章节列表 Tab
          }
        case PipelineEventType.needReview:
          ref.read(pipelineRunningProvider.notifier).state = false;
          if (mounted) _showReviewDialog(
            event.data?['reason'] as String? ?? '需要人工处理',
            isMenxiaBlocked: event.data?['type'] == 'menxia_blocked',
          );
        case PipelineEventType.auditResult:
          final detType = event.data?['type'] as String? ?? '';
          if (detType == 'detection' || detType == 'detection_final') {
            final score   = event.data?['score']   as int? ?? 0;
            final verdict = event.data?['verdict'] as String? ?? '';
            final passed  = event.data?['passed']  as bool? ?? false;
            if (mounted) {
              final color = passed ? AppColors.success : AppColors.warning;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  Text(passed ? '✅' : '⚠️', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('朱雀检测 $score/100 · $verdict'),
                ]),
                backgroundColor: color.withOpacity(.9),
                duration: const Duration(seconds: 4),
              ));
            }
          }
          final critical = event.data?['criticalCount'] as int? ?? 0;
          final warning  = event.data?['warningCount']  as int? ?? 0;
          final passed   = event.data?['passed']        as bool? ?? false;
          if (mounted) {
            ref.read(activeAgentProvider.notifier).state =
              critical > 0 ? 'gongbu_revising' : 'gongbu';
            // 显示审计轮次提示（幻觉修正可视化）
            if (critical > 0) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Row(children: [
                  const Icon(Icons.auto_fix_high, size: 14, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('发现 $critical 处逻辑矛盾，自动修正中...'),
                ]),
                backgroundColor: AppColors.crimson2.withOpacity(.9),
                duration: const Duration(seconds: 3),
              ));
            }
          }
        case PipelineEventType.statusChange:
          // 任务状态变化时更新任务列表（kanban 刷新由 provider 负责）
          break;
        case PipelineEventType.error:
          ref.read(pipelineRunningProvider.notifier).state = false;
          if (mounted) context.showError(event.content ?? '写作失败');
        default: break;
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _instrCtrl.dispose();
    _sub?.cancel();
    platform.exitWritingMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(bookDetailProvider(widget.bookId));
    final isRunning = ref.watch(pipelineRunningProvider);
    final activeAgent = ref.watch(activeAgentProvider);
    final streamText  = ref.watch(streamingTextProvider);

    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: bookAsync.when(
          data: (b) => b == null ? const Text('写作台') : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.title, style: const TextStyle(fontSize: 15)),
              Text('第${b.currentChapter + 1}章 · ${b.totalWords.wordCountLabel}',
                style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9,
                  color: AppColors.text3, letterSpacing: 1)),
            ],
          ),
          loading: () => const Text('写作台'),
          error:   (_, __) => const Text('写作台'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => context.push('/reader/${widget.bookId}'),
          ),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: '写作'), Tab(text: '章节'), Tab(text: '任务'),
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [
        // ── 写作标签 ──
        Column(children: [
          if (isRunning) _AgentProgressBar(agentId: activeAgent),
          Expanded(child: isRunning || streamText.isNotEmpty
            ? _StreamView(text: streamText, isLive: isRunning)
            : _IdlePrompt(bookId: widget.bookId, onQuickInstruct: (s) {
                _instrCtrl.text = s;
              })),
          _InputBar(
            ctrl:      _instrCtrl,
            isRunning: isRunning,
            onStart:   _startWriting,
            onStop:    () {
              NovelPipeline.instance.stop();
              ref.read(pipelineRunningProvider.notifier).state = false;
            },
          ),
        ]),
        // ── 章节列表 ──
        _ChaptersList(bookId: widget.bookId, onEdit: (ch) => _editChapter(context, ref, ch)),
        // ── 任务记录 ──
        _TasksList(bookId: widget.bookId),
      ]),
    );
  }

  Future<void> _startWriting() async {
    final instr = _instrCtrl.text.trim();
    // 每次开始写作前清空流式缓冲
    _streamBuf.clear();
    ref.read(streamingTextProvider.notifier).state = '';
    _instrCtrl.clear(); // 清空指令输入框
    ref.read(pipelineRunningProvider.notifier).state = true;

    await NotificationService.instance.showWritingProgress(
      bookTitle: '', agentName: '中书省');

    // 启动管线（在后台运行，不 await — 事件通过 Stream 回传）
    ref.read(tasksProvider(widget.bookId).notifier)
      .startWriting(instr.isEmpty ? '写下一章' : instr);
  }

  // Fix5: 门下省断路器专用对话框
  void _showReviewDialog(String reason, {bool isMenxiaBlocked = false}) {
    if (!mounted) return;
    showDialog(
      context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: const Text('需要您介入', style: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 16)),
        content: Text(reason, style: const TextStyle(color: AppColors.text2, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了，修改指令重试'),
          ),
        ],
      ),
    );
  }
}

// ── Agent 进度条 ──────────────────────────────
class _AgentProgressBar extends StatelessWidget {
  const _AgentProgressBar({super.key, required this.agentId});
  final String agentId;

  static const _pipeline = ['zhongshu','menxia','shangshu','bingbu','gongbu','libu'];
  static const _labels   = ['中书','门下','尚书','兵部','工部','礼部'];

  String get _emoji => switch (agentId) {
    'zhongshu' => '📜', 'menxia' => '🔍', 'shangshu' => '📮',
    'bingbu'   => '⚔️', 'gongbu' => '🌍', 'libu'     => '📝',
    _          => '🤖',
  };
  String get _label => switch (agentId) {
    'zhongshu' => '中书省规划', 'menxia'  => '门下省审议',
    'shangshu' => '尚书省派发', 'bingbu'  => '兵部写作中',
    'gongbu'   => '工部审计/更新档案', 'libu' => '礼部润色',
    _ => '处理中...',
  };

  @override
  Widget build(BuildContext context) {
    final idx = _pipeline.indexOf(agentId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.bg2,
      child: Row(children: [
        Text(_emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Text(_label, style: const TextStyle(fontFamily: 'JetBrainsMono',
          fontSize: 10, color: AppColors.gold2, letterSpacing: 1)),
        const SizedBox(width: 10),
        Expanded(child: Row(children: List.generate(_pipeline.length, (i) => Expanded(
          child: Container(
            height: 2, margin: const EdgeInsets.symmetric(horizontal: 1),
            color: i == idx ? AppColors.gold2 : i < idx ? AppColors.jade2 : AppColors.line2,
          ),
        )))),
        const SizedBox(width: 8),
        const SizedBox(width: 12, height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.gold2)),
      ]),
    ).animate().fadeIn(duration: 200.ms);
  }
}

// ── 空白引导 ─────────────────────────────────
class _IdlePrompt extends ConsumerWidget {
  const _IdlePrompt({super.key, required this.bookId, required this.onQuickInstruct});
  final String bookId;
  final ValueChanged<String> onQuickInstruct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final criticals = ref.watch(criticalHooksProvider(bookId));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionLabel('快速指令'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _QuickBtn('⚔️ 写下一章',  '写下一章，推进主线',                onQuickInstruct),
          _QuickBtn('🎣 回收伏笔',  '本章安排回收一条待处理的伏笔',      onQuickInstruct),
          _QuickBtn('💥 加强爽点',  '本章增加一个让读者爽的情节高潮',    onQuickInstruct),
          _QuickBtn('👥 群像出场',  '本章让配角有存在感，展示其独立立场', onQuickInstruct),
          _QuickBtn('🌍 世界展开',  '本章通过情节自然展示世界观设定',    onQuickInstruct),
        ]),
        // 成本估算提示
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.bg2, border: Border.all(color: AppColors.line2)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('费用估算（DeepSeek Chat）', style: TextStyle(fontFamily: 'JetBrainsMono',
              fontSize: 9, color: AppColors.text3, letterSpacing: 2)),
            SizedBox(height: 6),
            Text('每章（约3000字）完整流程', style: TextStyle(fontSize: 12, color: AppColors.text2)),
            SizedBox(height: 3),
            Text('输入约 6k token + 输出约 4k token ≈ ¥0.02-0.05',
              style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: AppColors.gold2)),
          ]),
        ),
        if (criticals.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionLabel('⚠️ 紧急伏笔（${criticals.length}条超20章未收）',
            color: AppColors.crimson2),
          const SizedBox(height: 8),
          ...criticals.take(3).map((h) => _HookAlert(hook: h)),
        ],
      ]),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  const _QuickBtn(this.label, this.instruction, this.onTap);
  final String label, instruction;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () => onTap(instruction),
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );
}

class _HookAlert extends StatelessWidget {
  const _HookAlert({super.key, required this.hook});
  final PlotHook hook;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(10),
    decoration: const BoxDecoration(
      color: AppColors.crimsonDim,
      border: Border(left: BorderSide(color: AppColors.crimson2, width: 2)),
    ),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(hook.description, style: const TextStyle(fontSize: 12, color: AppColors.text1)),
        Text('第${hook.plantedChapter}章埋·已${hook.currentAge}章未收',
          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3)),
      ])),
      AppBadge(label: '${hook.currentAge}章', color: AppColors.crimson2, small: true),
    ]),
  );
}

// ── 流式文字显示 ──────────────────────────────
class _StreamView extends StatefulWidget {
  const _StreamView({super.key, required this.text, required this.isLive});
  final String text;
  final bool   isLive;
  @override
  State<_StreamView> createState() => _StreamViewState();
}
class _StreamViewState extends State<_StreamView> with SingleTickerProviderStateMixin {
  late final AnimationController _cur;
  @override
  void initState() { super.initState(); _cur = AnimationController(vsync: this, duration: 600.ms)..repeat(reverse: true); }
  @override
  void dispose() { _cur.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    reverse: true, padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
    child: RichText(text: TextSpan(
      style: const TextStyle(fontFamily: 'NotoSerifSC', fontSize: 15,
        color: AppColors.text1, height: 2.0),
      children: [
        TextSpan(text: widget.text),
        if (widget.isLive) WidgetSpan(child: FadeTransition(
          opacity: _cur,
          child: Container(width: 2, height: 16,
            margin: const EdgeInsets.only(left: 2), color: AppColors.gold2),
        )),
      ],
    )),
  );
}

// ── 指令输入栏 ────────────────────────────────
class _InputBar extends StatelessWidget {
  const _InputBar({super.key, required this.ctrl, required this.isRunning,
    required this.onStart, required this.onStop});
  final TextEditingController ctrl;
  final bool isRunning;
  final VoidCallback onStart, onStop;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: const BoxDecoration(color: AppColors.bg1,
      border: Border(top: BorderSide(color: AppColors.line1))),
    child: SafeArea(top: false, child: Row(children: [
      Expanded(child: TextField(
        controller: ctrl, enabled: !isRunning, maxLines: 2, minLines: 1,
        decoration: const InputDecoration(hintText: '给中书省下旨…（留空=写下一章）'),
      )),
      const SizedBox(width: 8),
      if (isRunning)
        IconButton.outlined(
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded, color: AppColors.crimson2),
          style: IconButton.styleFrom(
            side: const BorderSide(color: AppColors.crimson2),
            shape: const RoundedRectangleBorder()),
        )
      else
        ElevatedButton(onPressed: onStart,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
          child: const Icon(Icons.send_rounded, size: 18)),
    ])),
  );
}

// ── 章节列表 ──────────────────────────────────
class _ChaptersList extends ConsumerWidget {
  const _ChaptersList({super.key, required this.bookId, this.onEdit});
  final String bookId;
  final void Function(Chapter)? onEdit;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(chaptersProvider(bookId));
    return chapters.when(
      data: (list) {
        if (list.isEmpty) return const EmptyState(icon: Icons.article_outlined, title: '暂无章节');
        // UI 渲染优化：itemExtent 固定高度，Flutter 跳过测量直接渲染，100章零卡顿
        return ListView.builder(
          itemCount:  list.length,
          itemExtent: 68.0,   // 固定行高（ListTile dense=true 约68px）
          itemBuilder: (_, i) {
            final ch    = list[i];
            final color = ch.status == 'approved' ? AppColors.jade2
              : ch.status == 'pending' ? AppColors.gold2 : AppColors.text3;
            return SizedBox(
              height: 68,
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                leading: SizedBox(width: 28, child: Text('${ch.chapterNo}',
                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: AppColors.textTertiary))),
                title: Text(ch.title,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${ch.wordCount.wordCountLabel} · ${ch.createdAt.relative}',
                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.textTertiary)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppBadge(label: ch.status == 'approved' ? '已通过' : '待审', color: color, small: true),
                  if (ch.status == 'pending') ...[
                    const SizedBox(width: 4),
                    // 编辑按钮（Fix8）
                    GestureDetector(
                      onTap: () => onEdit(ch),
                      child: Container(
                        margin: const EdgeInsets.only(left: 2),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.edit_outlined, size: 13, color: AppColors.textTertiary)),
                    ),
                    // 审核通过按钮
                    GestureDetector(
                      onTap: () => ref.read(tasksProvider(bookId).notifier).approveChapter(ch.id),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(border: Border.all(color: AppColors.jade2.withOpacity(.4))),
                        child: const Icon(Icons.check, size: 13, color: AppColors.jade2)),
                    ),
                  ],
                ]),
                onTap: () => context.push('/reader/$bookId?chapter=${ch.chapterNo}'),
              ),
            );
          },
        );
      },
      loading: () => const LoadingShimmer(),
      error:   (e, _) => EmptyState(icon: Icons.error_outline, title: '$e'),
    );
  }
}

// ── 任务记录 ──────────────────────────────────
class _TasksList extends ConsumerWidget {
  const _TasksList({super.key, required this.bookId});
  final String bookId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider(bookId));
    return tasks.when(
      data: (list) => list.isEmpty
        ? const EmptyState(icon: Icons.checklist_outlined, title: '暂无任务记录')
        : ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.line1),
            itemBuilder: (_, i) {
              final t = list[i];
              final color = AppColors.taskColor(t.status);
              return ListTile(
                dense: true,
                leading: Container(width: 8, height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  color: color),
                title: Text(t.instruction.truncate(40), style: const TextStyle(fontSize: 13)),
                subtitle: Text(t.createdAt.relative,
                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3)),
                trailing: AppBadge(label: t.status, color: color, small: true),
              );
            },
          ),
      loading: () => const LoadingShimmer(),
      error:   (e, _) => EmptyState(icon: Icons.error_outline, title: '$e'),
    );
  }
}

  // ————— Fix8: 章节直接编辑 —————
  void _editChapter(BuildContext ctx, WidgetRef ref,Chapter chapter) {
    final ctrl = TextEditingController(text: chapter.content);
    final titleCtrl = TextEditingController(text: chapter.title);
    bool saving = false;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceL1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx2).size.height * 0.88,
            child: Column(children: [
              // 拖拽指示条
              Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 4), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
              // 标题栏
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(children: [
                  const Text('编辑章节', style: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: saving ? null : () async {
                      setState(() => saving = true);
                      try {
                        if (titleCtrl.text.trim() != chapter.title) {
                          await ref.read(tasksProvider(chapter.bookId).notifier).updateChapterTitle(chapter.id, titleCtrl.text.trim());
                        }
                        await ref.read(tasksProvider(chapter.bookId).notifier).updateChapterContent(chapter.id, ctrl.text);
                        if (ctx2.mounted) {
                          Navigator.pop(ctx2);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('第${chapter.chapterNo}章已保存')));
                        }
                      } finally {
                        if (ctx2.mounted) setState(() => saving = false);
                      }
                    },
                    child: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.accent)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx2), icon: const Icon(Icons.close, size: 20)),
                ]),
              ),
              // 章节标题编辑
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: titleCtrl,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  decoration: const InputDecoration(labelText: '章节标题', prefixIcon: Icon(Icons.title, size: 18)),
                ),
              ),
              const SizedBox(height: 8),
              // 字数统计
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ValueListenableBuilder(
                  valueListenable: ctrl,
                  builder: (_, v, __) {
                    final cnt = RegExp(r'[\u4e00-\u9fa5]').allMatches(v.text).length;
                    return Row(children: [
                      Text('$cnt 字', style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: AppColors.textTertiary)),
                      const Spacer(),
                      const Text('长按选中可批量替换', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                    ]);
                  },
                ),
              ),
              const SizedBox(height: 4),
              // 正文编辑区
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: ctrl,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(fontFamily: 'NotoSerifSC', fontSize: 14, color: AppColors.textPrimary, height: 1.85),
                    decoration: const InputDecoration(border: InputBorder.none, filled: false, contentPadding: EdgeInsets.all(4), hintText: '章节正文...'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
} // <--- 🌟 极其重要：这扇大门死死地关上了 _WritingScreenState 这个大房子！

// --- 独立出来的审核角标组件 (绝对干净版，绝不会报 ref 错误) ---
class _AuditBadge extends StatelessWidget {
  const _AuditBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: AppColors.crimson2.withOpacity(.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.crimson2.withOpacity(.2), width: 0.5),
      ),
      child: const Text(
        '待审核',
        style: TextStyle(
          color: AppColors.crimson2, 
          fontSize: 10, 
          fontWeight: FontWeight.bold
        ),
      ),
    );
  }
}