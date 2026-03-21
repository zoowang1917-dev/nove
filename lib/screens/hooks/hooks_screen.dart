// lib/screens/hooks/hooks_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/extensions.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';

class HooksScreen extends ConsumerStatefulWidget {
  const HooksScreen({super.key, required this.bookId});
  final String bookId;
  @override
  ConsumerState<HooksScreen> createState() => _HooksScreenState();
}

class _HooksScreenState extends ConsumerState<HooksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.bookId.isEmpty) {
      return const Scaffold(backgroundColor: AppColors.bg0,
        body: EmptyState(icon: Icons.link_outlined, title: '请先选择书籍'));
    }

    final hooks = ref.watch(hooksProvider(widget.bookId));
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('伏笔管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAdd(context),
          ),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: '待回收'), Tab(text: '已归档'),
        ]),
      ),
      body: hooks.when(
        data: (list) {
          final open   = list.where((h) => h.status == 'OPEN').toList()
            ..sort((a, b) => b.currentAge.compareTo(a.currentAge));
          final closed = list.where((h) => h.status != 'OPEN').toList();
          return Column(children: [
            _StatsBar(open: open),
            Expanded(child: TabBarView(controller: _tabs, children: [
              _HookList(hooks: open,   bookId: widget.bookId, ref: ref),
              _HookList(hooks: closed, bookId: widget.bookId, ref: ref, showClosed: true),
            ])),
          ]);
        },
        loading: () => const LoadingShimmer(),
        error:   (e, _) => EmptyState(icon: Icons.error_outline, title: '$e'),
      ),
    );
  }

  void _showAdd(BuildContext ctx) => showModalBottomSheet(
    context: ctx, isScrollControlled: true,
    builder: (_) => _AddHookSheet(bookId: widget.bookId, ref: ref));
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({super.key, required this.open});
  final List<PlotHook> open;
  @override
  Widget build(BuildContext context) {
    final critical = open.where((h) => h.urgency == 'CRITICAL').length;
    final warn     = open.where((h) => h.urgency == 'WARN').length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line1))),
      child: Row(children: [
        _Chip('${open.length}', '待回收', AppColors.text2),
        if (critical > 0) ...[const SizedBox(width: 8),
          _Chip('$critical', 'CRITICAL', AppColors.crimson2)],
        if (warn > 0) ...[const SizedBox(width: 8),
          _Chip('$warn', 'WARN', AppColors.gold2)],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.n, this.label, this.color);
  final String n, label; final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: color.withOpacity(.4)),
      color: color.withOpacity(.07)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(n, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14,
        fontWeight: FontWeight.w600, color: color)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.text3)),
    ]),
  );
}

class _HookList extends StatelessWidget {
  const _HookList({super.key, required this.hooks, required this.bookId,
    required this.ref, this.showClosed = false});
  final List<PlotHook> hooks;
  final String bookId;
  final WidgetRef ref;
  final bool showClosed;

  @override
  Widget build(BuildContext context) {
    if (hooks.isEmpty) return EmptyState(
      icon: showClosed ? Icons.check_circle_outline : Icons.link_outlined,
      title: showClosed ? '暂无已归档伏笔' : '暂无待回收伏笔',
    );
    return ListView.separated(
      itemCount: hooks.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.line1),
      itemBuilder: (_, i) => _HookCard(hook: hooks[i], bookId: bookId, ref: ref)
        .animate(delay: Duration(milliseconds: i * 30)).fadeIn(duration: 200.ms),
    );
  }
}

class _HookCard extends StatelessWidget {
  const _HookCard({super.key, required this.hook, required this.bookId, required this.ref});
  final PlotHook hook; final String bookId; final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final color = switch (hook.urgency) {
      'CRITICAL' => AppColors.crimson2,
      'WARN'     => AppColors.gold2,
      _          => hook.status == 'OPEN' ? AppColors.text2 : AppColors.jade2,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(.4)),
              color: color.withOpacity(.07)),
            child: Text(
              hook.status == 'OPEN'
                ? '第${hook.plantedChapter}章埋 · 已${hook.currentAge}章'
                : '第${hook.plantedChapter}→${hook.closedChapter ?? "?"}章',
              style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: color),
            ),
          ),
          const Spacer(),
          _TypeBadge(type: hook.hookType),
          if (hook.status == 'OPEN') ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ref.read(hooksProvider(bookId).notifier).close(hook.id),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.jade2.withOpacity(.4)),
                  color: AppColors.jadeDim),
                child: const Icon(Icons.check, size: 14, color: AppColors.jade2),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 7),
        Text(hook.description, style: const TextStyle(fontSize: 13, color: AppColors.text1)),
        if (hook.readerExpectation.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(hook.readerExpectation,
            style: const TextStyle(fontSize: 11.5, color: AppColors.text2,
              fontStyle: FontStyle.italic)),
        ],
        if (hook.suggestedClosure != null && hook.status == 'OPEN') ...[
          const SizedBox(height: 4),
          Text('建议：${hook.suggestedClosure}',
            style: const TextStyle(fontFamily: 'JetBrainsMono',
              fontSize: 10, color: AppColors.jade2)),
        ],
      ]),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({super.key, required this.type});
  final String type;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'promise'   => ('承诺', AppColors.purple2), 'secret'    => ('秘密', AppColors.blue2),
      'item'      => ('物品', AppColors.gold2),   'character' => ('角色', AppColors.jade2),
      _           => ('伏笔', AppColors.teal2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(.4)), color: color.withOpacity(.07)),
      child: Text(label, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: color)),
    );
  }
}

class _AddHookSheet extends StatefulWidget {
  const _AddHookSheet({super.key, required this.bookId, required this.ref});
  final String bookId; final WidgetRef ref;
  @override
  State<_AddHookSheet> createState() => _AddHookSheetState();
}

class _AddHookSheetState extends State<_AddHookSheet> {
  final _descCtrl   = TextEditingController();
  final _expectCtrl = TextEditingController();
  String _type = 'foreshadow';
  bool _saving = false;

  static const _types = [
    ('foreshadow','伏笔'), ('promise','承诺'), ('secret','秘密'),
    ('item','物品'),       ('character','角色'),
  ];

  @override
  void dispose() { _descCtrl.dispose(); _expectCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line1))),
        child: Row(children: [
          const Text('手动添加伏笔', style: TextStyle(fontFamily: 'NotoSerifSC',
            fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18)),
        ])),
      Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Lbl('伏笔内容 *'), const SizedBox(height: 6),
          TextField(controller: _descCtrl,
            decoration: const InputDecoration(hintText: '描述这条伏笔...')),
          const SizedBox(height: 12),
          const _Lbl('读者期待'), const SizedBox(height: 6),
          TextField(controller: _expectCtrl,
            decoration: const InputDecoration(hintText: '读者会期待看到什么...')),
          const SizedBox(height: 12),
          const _Lbl('类型'), const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: _types.map((t) => FilterChip(
            label: Text(t.$2), selected: _type == t.$1,
            onSelected: (_) => setState(() => _type = t.$1),
          )).toList()),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _save, child: const Text('添加'),
          )),
        ]),
      )),
    ]),
  );

  Future<void> _save() async {
    if (_descCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.ref.read(hooksProvider(widget.bookId).notifier).add({
        'planted_chapter':    0,
        'current_age':        0,
        'urgency':            'NORMAL',
        'hook_type':          _type,
        'description':        _descCtrl.text.trim(),
        'reader_expectation': _expectCtrl.text.trim(),
        'status':             'OPEN',
      });
      if (mounted) Navigator.pop(context);
    } finally { if (mounted) setState(() => _saving = false); }
  }
}

class _Lbl extends StatelessWidget {
  const _Lbl(this.t); final String t;
  @override
  Widget build(BuildContext context) => Text(t, style: const TextStyle(
    fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3, letterSpacing: 2));
}
