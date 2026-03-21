// lib/screens/kanban/kanban_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/extensions.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';

class KanbanScreen extends ConsumerWidget {
  const KanbanScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookId   = ref.watch(currentBookIdProvider);
    final isRunning = ref.watch(pipelineRunningProvider);
    final agentId   = ref.watch(activeAgentProvider);

    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(title: const Text('任务看板')),
      body: bookId == null
        ? const EmptyState(icon: Icons.library_books_outlined,
            title: '请先选择书籍', subtitle: '从书库选择书籍后查看任务')
        : Column(children: [
            // 当前 Agent 状态
            if (isRunning) _RunningBanner(agentId: agentId),
            // 任务列表
            Expanded(child: _TaskList(bookId: bookId)),
          ]),
    );
  }
}

class _RunningBanner extends StatelessWidget {
  const _RunningBanner({super.key, required this.agentId});
  final String agentId;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: AppColors.bg2,
    child: Row(children: [
      const SizedBox(width: 12, height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.gold2)),
      const SizedBox(width: 10),
      Text(_agentLabel(agentId),
        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10,
          color: AppColors.gold2, letterSpacing: 1)),
      const Spacer(),
      const Text('运行中', style: TextStyle(fontFamily: 'JetBrainsMono',
        fontSize: 9, color: AppColors.text3)),
    ]),
  );

  String _agentLabel(String id) => switch (id) {
    'zhongshu' => '📜 中书省 · 规划中',  'menxia'  => '🔍 门下省 · 审议中',
    'shangshu' => '📮 尚书省 · 派发中',  'bingbu'  => '⚔️ 兵部 · 写作中',
    'gongbu'   => '🌍 工部 · 更新档案',  'libu'    => '📝 礼部 · 润色中',
    _          => '⚙️ 处理中...',
  };
}

class _TaskList extends ConsumerWidget {
  const _TaskList({super.key, required this.bookId});
  final String bookId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider(bookId));
    return tasks.when(
      data: (list) => list.isEmpty
        ? const EmptyState(icon: Icons.checklist_outlined,
            title: '暂无任务', subtitle: '前往写作台下达第一道旨意')
        : RefreshIndicator(
            color: AppColors.gold2, backgroundColor: AppColors.bg2,
            onRefresh: () async => ref.invalidate(tasksProvider(bookId)),
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.line1),
              itemBuilder: (_, i) => _TaskTile(task: list[i], ref: ref),
            ),
          ),
      loading: () => const LoadingShimmer(),
      error:   (e, _) => EmptyState(icon: Icons.error_outline, title: '$e'),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({super.key, required this.task, required this.ref});
  final Task task; final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.taskColor(task.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppBadge(label: task.status, color: color, small: true),
          if (task.rejectCount > 0) ...[
            const SizedBox(width: 6),
            AppBadge(label: '封驳${task.rejectCount}次', color: AppColors.crimson2, small: true),
          ],
          const Spacer(),
          Text(task.createdAt.relative,
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3)),
        ]),
        const SizedBox(height: 6),
        Text(task.instruction.truncate(60),
          style: const TextStyle(fontSize: 13, color: AppColors.text1)),
        if (task.status == 'PENDING_HUMAN') ...[
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton(
              onPressed: task.outputChapterId == null ? null
                : () => ref.read(tasksProvider(task.bookId).notifier)
                .approveChapter(task.outputChapterId!),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.jade2,
                side: const BorderSide(color: AppColors.jade2)),
              child: const Text('通过'),
            ),
          ]),
        ],
      ]),
    );
  }
}
