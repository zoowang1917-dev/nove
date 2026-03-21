// lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/extensions.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/db/database.dart';
import '../../platform/local_db.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider);
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('书库'),
        actions: [
          IconButton(icon: const Icon(Icons.palette_outlined), tooltip: '写作风格',
            onPressed: () => context.push('/style')),
          IconButton(icon: const Icon(Icons.add), onPressed: () => _showCreate(context, ref)),
        ],
      ),
      body: books.when(
        data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.auto_stories_outlined, title: '还没有书籍',
              subtitle: '点击右上角 + 开始创作',
              action: ElevatedButton(onPressed: () => _showCreate(context, ref), child: const Text('创建第一本书')),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 1, mainAxisSpacing: 1, childAspectRatio: .68),
              itemCount: list.length,
              itemBuilder: (_, i) => _BookCard(book: list[i])
                .animate(delay: Duration(milliseconds: i * 50)).fadeIn(duration: 250.ms),
            ),
        loading: () => const LoadingShimmer(),
        error:   (e, _) => EmptyState(icon: Icons.error_outline, title: '$e'),
      ),
    );
  }

  void _showCreate(BuildContext ctx, WidgetRef ref) =>
    showModalBottomSheet(context: ctx, isScrollControlled: true,
      builder: (_) => _CreateSheet(ref: ref));
}

class _BookCard extends ConsumerWidget {
  const _BookCard({super.key, required this.book});
  final Book book;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gc = _gc(book.genre);
    return GestureDetector(
      onTap: () {
        ref.read(currentBookIdProvider.notifier).state = book.id;
        context.push('/writing/${book.id}');
      },
      child: Container(
        decoration: BoxDecoration(color: AppColors.bg1, border: Border.all(color: AppColors.line1)),
        child: Column(children: [
          Expanded(flex: 5, child: Stack(fit: StackFit.expand, children: [
            Container(decoration: BoxDecoration(gradient: LinearGradient(
              colors: [gc.withOpacity(.3), AppColors.bg2]))),
            Center(child: Text(book.title.firstChar,
              style: const TextStyle(fontFamily: 'NotoSerifSC', fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.text1))),
            Positioned(top: 8, right: 8,
              child: AppBadge(label: '${book.totalChapters}章', color: AppColors.text3, small: true)),
          ])),
          Expanded(flex: 3, child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text1)),
              const SizedBox(height: 3),
              Text('${book.totalWords.wordCountLabel}',
                style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3)),
              const Spacer(),
              LinearProgressIndicator(
                value: (book.currentChapter / 100.0).clamp(0.0, 1.0),
                backgroundColor: AppColors.line1,
                valueColor: AlwaysStoppedAnimation(gc), minHeight: 2,
              ),
            ]),
          )),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line1))),
            child: Row(children: [
              _Btn('写作', Icons.edit_outlined, () {
                ref.read(currentBookIdProvider.notifier).state = book.id;
                context.push('/writing/${book.id}');
              }),
              const VerticalDivider(width: 1, color: AppColors.line1),
              _Btn('看板', Icons.account_balance_outlined, () {
                ref.read(currentBookIdProvider.notifier).state = book.id;
                context.go('/kanban');
              }),
              const VerticalDivider(width: 1, color: AppColors.line1),
              _Btn('更多', Icons.more_horiz, () => _showMenu(context, ref)),
            ]),
          ),
        ]),
      ),
    );
  }

  void _showMenu(BuildContext ctx, WidgetRef ref) =>
    showModalBottomSheet(context: ctx, builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.people_outline, size: 20), title: const Text('角色圣经'),
        onTap: () { Navigator.pop(ctx); ctx.push('/characters/${book.id}'); }),
      ListTile(leading: const Icon(Icons.link, size: 20), title: const Text('伏笔管理'),
        onTap: () { Navigator.pop(ctx); ctx.go('/hooks?bookId=${book.id}'); }),
      ListTile(leading: const Icon(Icons.map_outlined, size: 20), title: const Text('世界观'),
        onTap: () { Navigator.pop(ctx); ctx.go('/world?bookId=${book.id}'); }),
      ListTile(leading: const Icon(Icons.menu_book_outlined, size: 20), title: const Text('阅读'),
        onTap: () async {
          Navigator.pop(ctx);
          final progress = await LocalDb.instance.getReadingProgress(book.id);
          if (ctx.mounted) ctx.push('/reader/${book.id}?chapter=${progress?.chapterNo ?? 1}');
        }),
      const Divider(height: 1, color: AppColors.line1),
      ListTile(leading: const Icon(Icons.file_download_outlined, size: 20), title: const Text('导出全书'),
        onTap: () { Navigator.pop(ctx); ctx.push('/export/${book.id}'); }),
      const Divider(height: 1, color: AppColors.line1),
      ListTile(
        leading: const Icon(Icons.delete_outline, size: 20, color: AppColors.crimson2),
        title: const Text('删除', style: TextStyle(color: AppColors.crimson2)),
        onTap: () async {
          Navigator.pop(ctx);
          await ref.read(booksProvider.notifier).deleteBook(book.id);
        }),
      const SizedBox(height: 16),
    ]));

  Color _gc(String g) => switch (g) {
    'xuanhuan'||'xianxia' => AppColors.purple2,
    'dushi'||'xiandai'    => AppColors.blue2,
    'lishi'||'gukong'     => AppColors.gold2,
    _                     => AppColors.jade2,
  };
}

class _Btn extends StatelessWidget {
  const _Btn(this.label, this.icon, this.onTap);
  final String label; final IconData icon; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(child: InkWell(
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: AppColors.text3),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.text3, fontFamily: 'JetBrainsMono')),
      ])),
  ));
}

class _CreateSheet extends ConsumerStatefulWidget {
  const _CreateSheet({super.key, required this.ref});
  final WidgetRef ref;
  @override
  ConsumerState<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends ConsumerState<_CreateSheet> {
  final _titleCtrl = TextEditingController();
  final _briefCtrl = TextEditingController();
  String _genre    = 'xuanhuan';
  bool   _loading  = false;

  static const _genres = [
    ('xuanhuan','玄幻'),('xianxia','仙侠'),('dushi','都市'),
    ('lishi','历史'),('yanqing','言情'),('kehuanweilai','科幻'),
  ];

  @override
  void dispose() { _titleCtrl.dispose(); _briefCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.fromLTRB(20,18,12,14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line1))),
        child: Row(children: [
          const Text('新建书籍', style: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18)),
        ])),
      Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Lbl('书名'), const SizedBox(height: 6),
          TextField(controller: _titleCtrl, decoration: const InputDecoration(hintText: '例：吞天魔帝')),
          const SizedBox(height: 14),
          const _Lbl('简介（可选）'), const SizedBox(height: 6),
          TextField(controller: _briefCtrl, maxLines: 2,
            decoration: const InputDecoration(hintText: '主角设定、世界背景...')),
          const SizedBox(height: 14),
          const _Lbl('题材'), const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: _genres.map((g) => FilterChip(
            label: Text(g.$2), selected: _genre == g.$1,
            onSelected: (_) => setState(() => _genre = g.$1),
            selectedColor: AppColors.goldDim, checkmarkColor: AppColors.gold2,
          )).toList()),
        ],
      ))),
      Padding(padding: const EdgeInsets.all(20), child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg0))
            : const Text('开始创作'),
        ),
      )),
    ]),
  );

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(booksProvider.notifier).createBook(
        title: _titleCtrl.text.trim(),
        genre: _genre,
        brief: _briefCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _Lbl extends StatelessWidget {
  const _Lbl(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Text(t, style: const TextStyle(
    fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3, letterSpacing: 2));
}

// ── 导出全书 ──────────────────────────────────
Future<void> _exportBook(BuildContext ctx, String bookId, String title) async {
  final chapters = await AppDatabase.instance.getChapters(bookId);
  if (chapters.isEmpty) {
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(content: Text('暂无章节可导出')));
    return;
  }
  final buf = StringBuffer();
  buf.writeln(title);
  buf.writeln('=' * 40);
  buf.writeln();
  for (final ch in chapters) {
    buf.writeln(ch['title'] ?? '第${ch['chapter_no']}章');
    buf.writeln();
    buf.writeln(ch['content'] ?? '');
    buf.writeln();
    buf.writeln('-' * 20);
    buf.writeln();
  }
  await Share.share(buf.toString(), subject: '$title - 全文导出');
}
