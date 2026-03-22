// lib/screens/world/world_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/db/database.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';

class WorldScreen extends ConsumerStatefulWidget {
  const WorldScreen({super.key, required this.bookId});
  final String bookId;
  @override
  ConsumerState<WorldScreen> createState() => _WorldScreenState();
}

class _WorldScreenState extends ConsumerState<WorldScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const _types = [
    ('world',      '🌍', '世界状态'),
    ('ledger',     '💰', '资源账本'),
    ('characters', '👥', '角色圣经'),
    ('timeline',   '📅', '时间线'),
    ('factions',   '⚔️', '势力图谱'),
    ('hooks',      '🔗', '伏笔'),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _types.length, vsync: this);
  }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.bookId.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.bg0,
        body: EmptyState(icon: Icons.map_outlined,
          title: '请先选择书籍', subtitle: '从书库选择书籍后查看世界观'),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('世界观面板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(archivesProvider(widget.bookId)),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _types.map((t) => Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(t.$2), const SizedBox(width: 4), Text(t.$3),
            ]),
          )).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: _types.map((t) => _ArchiveView(
          bookId:      widget.bookId,
          archiveType: t.$1,
          icon:        t.$2,
          label:       t.$3,
        )).toList(),
      ),
    );
  }
}

class _ArchiveView extends ConsumerWidget {
  const _ArchiveView({super.key, required this.bookId, required this.archiveType,
    required this.icon, required this.label});
  final String bookId, archiveType, icon, label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider((bookId: bookId, type: archiveType)));
    return archive.when(
      data: (content) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontFamily: 'NotoSerifSC',
              fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text1)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.text3),
              onPressed: () => _showEdit(context, ref, content),
            ),
          ]),
          const Divider(color: AppColors.line1, height: 20),
          content.isEmpty
            ? const Text('暂无数据，写完第一章后自动填充',
                style: TextStyle(color: AppColors.text3, fontSize: 13, fontStyle: FontStyle.italic))
            : Text(content, style: const TextStyle(
                fontFamily: 'NotoSerifSC', fontSize: 13,
                color: AppColors.text2, height: 1.85)),
        ]),
      ),
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error:   (e, _) => EmptyState(icon: Icons.error_outline, title: '$e'),
    );
  }

  void _showEdit(BuildContext ctx, WidgetRef ref, String current) {
    final ctrl = TextEditingController(text: current);
    showModalBottomSheet(
      context: ctx, isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx2, setState) {
        bool saving = false;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line1))),
              child: Row(children: [
                Text('编辑 $label', style: const TextStyle(fontFamily: 'NotoSerifSC',
                  fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(ctx2),
                  icon: const Icon(Icons.close, size: 18)),
              ]),
            ),
            SizedBox(
              height: 340,
              child: TextField(
                controller: ctrl, maxLines: null, expands: true,
                style: const TextStyle(fontFamily: 'NotoSerifSC', fontSize: 13,
                  color: AppColors.text1, height: 1.8),
                decoration: const InputDecoration(
                  border: InputBorder.none, contentPadding: EdgeInsets.all(20)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: saving ? null : () async {
                  setState(() => saving = true);
                  await saveArchive(bookId, archiveType, ctrl.text,
                      container: ProviderScope.containerOf(ctx2));
                  ref.invalidate(archiveProvider((bookId: bookId, type: archiveType)));
                  ref.invalidate(archivesProvider(bookId));
                  if (ctx2.mounted) Navigator.pop(ctx2);
                },
                child: const Text('保存'),
              )),
            ),
          ]),
        );
      }),
    );
  }
}
