// lib/screens/characters/characters_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/extensions.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';

class CharactersScreen extends ConsumerWidget {
  const CharactersScreen({super.key, required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charsAsync  = ref.watch(charactersProvider(bookId));
    final bookAsync   = ref.watch(bookDetailProvider(bookId));
    final curChapter  = bookAsync.valueOrNull?.currentChapter ?? 0;
    final forgotten   = ref.watch(forgottenCharsProvider(
      (bookId: bookId, currentChapter: curChapter)));

    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('角色圣经'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => _showAdd(context, ref),
          ),
        ],
      ),
      body: charsAsync.when(
        data: (chars) {
          if (chars.isEmpty) return EmptyState(
            icon: Icons.people_outline,
            title: '暂无角色',
            subtitle: 'AI 写作时会自动提取，也可手动添加',
            action: ElevatedButton(
              onPressed: () => _showAdd(context, ref),
              child: const Text('添加第一个角色'),
            ),
          );

          final grouped = <String, List<Character>>{};
          for (final c in chars) {
            grouped.putIfAbsent(c.role, () => []).add(c);
          }

          return ListView(children: [
            // 遗忘告警
            if (forgotten.isNotEmpty) _ForgottenBanner(chars: forgotten),
            // 按角色类型分组
            for (final role in ['protagonist', 'antagonist', 'support', 'minor'])
              if (grouped.containsKey(role)) ...[
                SectionLabel(_roleLabel(role), color: _roleColor(role)),
                ...grouped[role]!.asMap().entries.map((e) =>
                  _CharCard(char: e.value, currentChapter: curChapter)
                    .animate(delay: Duration(milliseconds: e.key * 40))
                    .fadeIn(duration: 220.ms)),
              ],
          ]);
        },
        loading: () => const LoadingShimmer(),
        error:   (e, _) => EmptyState(icon: Icons.error_outline, title: '$e'),
      ),
    );
  }

  void _showAdd(BuildContext ctx, WidgetRef ref) => showModalBottomSheet(
    context: ctx, isScrollControlled: true,
    builder: (_) => _AddCharSheet(bookId: bookId, ref: ref));

  String _roleLabel(String r) => switch (r) {
    'protagonist' => '主角', 'antagonist' => '反派',
    'support'     => '配角', _            => '路人',
  };
  Color _roleColor(String r) => switch (r) {
    'protagonist' => AppColors.gold2,   'antagonist' => AppColors.crimson2,
    'support'     => AppColors.jade2,   _            => AppColors.text3,
  };
}

class _ForgottenBanner extends StatelessWidget {
  const _ForgottenBanner({super.key, required this.chars});
  final List<Character> chars;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.goldDim,
      border: const Border(left: BorderSide(color: AppColors.gold2, width: 2))),
    child: Row(children: [
      const Text('👥', style: TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      Expanded(child: Text(
        '吏部提醒：${chars.map((c) => c.name).join("、")} 已超10章未出场',
        style: const TextStyle(fontSize: 12, color: AppColors.gold2))),
    ]),
  );
}

class _CharCard extends StatelessWidget {
  const _CharCard({super.key, required this.char, required this.currentChapter});
  final Character char;
  final int currentChapter;

  @override
  Widget build(BuildContext context) {
    final missed    = currentChapter - char.lastAppearChapter;
    final isMissing = missed >= 10 && char.role != 'minor' && char.isAlive;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isMissing ? AppColors.goldDim : AppColors.bg3,
        radius: 20,
        child: Text(char.name.firstChar,
          style: const TextStyle(fontFamily: 'NotoSerifSC',
            fontSize: 14, color: AppColors.text1)),
      ),
      title: Row(children: [
        Text(char.name, style: const TextStyle(fontSize: 13)),
        if (!char.isAlive) ...[
          const SizedBox(width: 6),
          const AppBadge(label: '已死亡', color: AppColors.crimson2, small: true),
        ],
        if (isMissing) ...[
          const SizedBox(width: 6),
          AppBadge(label: '${missed}章未出', color: AppColors.gold2, small: true),
        ],
      ]),
      subtitle: char.traits.isEmpty
        ? null
        : Text(char.traits.take(3).join(' · '),
            style: const TextStyle(fontSize: 11, color: AppColors.text3)),
      trailing: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('出场${char.appearanceCount}次',
            style: const TextStyle(fontFamily: 'JetBrainsMono',
              fontSize: 9, color: AppColors.text3)),
          if (char.faction != null)
            Text(char.faction!,
              style: const TextStyle(fontFamily: 'JetBrainsMono',
                fontSize: 9, color: AppColors.text3)),
        ]),
      onTap: () => _showDetail(context),
    );
  }

  void _showDetail(BuildContext ctx) => showModalBottomSheet(
    context: ctx, isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: .75, expand: false,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          Text(char.name, style: const TextStyle(fontFamily: 'NotoSerifSC',
            fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text1)),
          const SizedBox(height: 4),
          Text(char.faction ?? '', style: const TextStyle(
            fontFamily: 'JetBrainsMono', fontSize: 10, color: AppColors.text3)),
          const SizedBox(height: 20),
          _Field('性格', char.traits.join(' · ')),
          _Field('过往经历', char.background),
          _Field('当前目标', char.currentGoal),
          _Field('语言特征', char.speechPatterns.join('、')),
          _Field('行为边界', char.absoluteLimit),
          _Field('成长终点', char.arcDestination),
          if (char.currentLocation != null)
            _Field('当前位置', char.currentLocation!),
        ],
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'JetBrainsMono',
        fontSize: 9, color: AppColors.gold, letterSpacing: 2)),
      const SizedBox(height: 4),
      Text(value.isEmpty ? '—' : value,
        style: const TextStyle(fontSize: 13, color: AppColors.text1, height: 1.7)),
      const SizedBox(height: 14),
    ],
  );
}

class _AddCharSheet extends StatefulWidget {
  const _AddCharSheet({super.key, required this.bookId, required this.ref});
  final String bookId; final WidgetRef ref;
  @override
  State<_AddCharSheet> createState() => _AddCharSheetState();
}

class _AddCharSheetState extends State<_AddCharSheet> {
  final _ctrls = <String, TextEditingController>{
    for (final k in ['name','background','currentGoal','absoluteLimit','arcDestination'])
      k: TextEditingController()
  };
  String _role = 'support';
  bool   _saving = false;

  @override
  void dispose() { for (final c in _ctrls.values) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line1))),
        child: Row(children: [
          const Text('添加角色', style: TextStyle(fontFamily: 'NotoSerifSC',
            fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 18)),
        ])),
      Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Lbl('姓名 *'), const SizedBox(height: 6),
          TextField(controller: _ctrls['name'],
            decoration: const InputDecoration(hintText: '角色名字')),
          const SizedBox(height: 12),
          const _Lbl('类型'), const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final r in [
              ('protagonist','主角'), ('antagonist','反派'),
              ('support','配角'),     ('minor','路人')])
              FilterChip(label: Text(r.$2), selected: _role == r.$1,
                onSelected: (_) => setState(() => _role = r.$1)),
          ]),
          const SizedBox(height: 12),
          const _Lbl('过往经历'), const SizedBox(height: 6),
          TextField(controller: _ctrls['background'], maxLines: 2,
            decoration: const InputDecoration(hintText: '影响其行为的关键经历')),
          const SizedBox(height: 12),
          const _Lbl('当前目标'), const SizedBox(height: 6),
          TextField(controller: _ctrls['currentGoal'],
            decoration: const InputDecoration(hintText: '他现在最想要什么')),
          const SizedBox(height: 12),
          const _Lbl('行为边界'), const SizedBox(height: 6),
          TextField(controller: _ctrls['absoluteLimit'],
            decoration: const InputDecoration(hintText: '绝对不会做的事')),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _save, child: const Text('添加'),
          )),
        ]),
      )),
    ]),
  );

  Future<void> _save() async {
    final name = _ctrls['name']!.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.ref.read(charactersProvider(widget.bookId).notifier).add({
        'name':             name,
        'role':             _role,
        'traits':           '[]',
        'background':       _ctrls['background']!.text.trim(),
        'current_goal':     _ctrls['currentGoal']!.text.trim(),
        'speech_patterns':  '[]',
        'absolute_limit':   _ctrls['absoluteLimit']!.text.trim(),
        'arc_destination':  _ctrls['arcDestination']!.text.trim(),
        'appearance_count': 0,
        'last_appear_chapter': 0,
        'is_alive': 1,
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
