// lib/screens/settings/settings_screen.dart
// RikkaHub 式模型自动发现 + 成本估算 + Agent 高级配置
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/llm/llm_client.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';
import '../../core/utils/extensions.dart';
import '../../core/db/database.dart';
import '../../core/utils/statistics_manager.dart';
import '../../core/utils/backup_manager.dart';

// 模型列表本地状态
final _fetchedModelsProvider = StateProvider<List<ModelInfo>>((ref) => []);
final _fetchingProvider      = StateProvider<bool>((ref) => false);

const _kStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

// ════════════════════════════════════════════
// 主体
// ════════════════════════════════════════════
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  @override void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this); }
  @override void dispose()   { _tabs.dispose();  super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg0,
    appBar: AppBar(
      title: const Text('设置'),
      bottom: TabBar(controller: _tabs, tabs: const [
        Tab(text: '模型配置'), Tab(text: '高级 Agent'), Tab(text: '统计'),
      ]),
    ),
    body: TabBarView(controller: _tabs,
      children: const [_ModelConfigTab(), _AdvancedAgentTab(), _StatsTab()]),
  );
}

// ════════════════════════════════════════════
// Tab 1 — 模型配置（核心：RikkaHub 自动发现）
// ════════════════════════════════════════════
class _ModelConfigTab extends ConsumerStatefulWidget {
  const _ModelConfigTab();
  @override
  ConsumerState<_ModelConfigTab> createState() => _ModelConfigTabState();
}

class _ModelConfigTabState extends ConsumerState<_ModelConfigTab> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool   _showKey = false, _saving = false, _hasKey = false;
  String? _selectedModel;
  String? _testResult;

  @override
  void initState() { super.initState(); _loadCurrent(); }

  Future<void> _loadCurrent() async {
    final row = await AppDatabase.instance.getLlmConfig('bingbu');
    if (row != null) {
      _urlCtrl.text  = (row['base_url'] as String?) ?? '';
      _selectedModel = row['model'] as String?;
    }
    final k = await _kStorage.read(key: 'apikey_default')
           ?? await _kStorage.read(key: 'apikey_bingbu');
    if (k != null && mounted) setState(() => _hasKey = true);
  }

  @override
  void dispose() { _urlCtrl.dispose(); _keyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final models   = ref.watch(_fetchedModelsProvider);
    final fetching = ref.watch(_fetchingProvider);

    return ListView(padding: const EdgeInsets.all(16), children: [
      // 说明横幅
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.goldDim,
          border: const Border(left: BorderSide(color: AppColors.gold2, width: 2))),
        child: const Text(
          '填写供应商 API，点「🔍 搜索可用模型」自动拉取模型列表，一键选择配置全部 Agent。\n推荐 DeepSeek：国内直连·每章约 ¥0.01~0.03',
          style: TextStyle(fontSize: 12, color: AppColors.text2, height: 1.7))),
      const SizedBox(height: 20),

      // 供应商快选（水平滚动）
      const SectionLabel('快速选择供应商'),
      const SizedBox(height: 8),
      SizedBox(height: 36, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: LlmPresets.providers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = LlmPresets.providers[i];
          final active = _urlCtrl.text == p.$2;
          return GestureDetector(
            onTap: () => setState(() {
              _urlCtrl.text = p.$2; _selectedModel = p.$3;
              ref.read(_fetchedModelsProvider.notifier).state = [];
              _testResult = null;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color:  active ? AppColors.goldDim : AppColors.bg2,
                border: Border.all(color: active ? AppColors.gold : AppColors.line2)),
              child: Text(p.$1, style: TextStyle(
                fontSize: 12,
                color: active ? AppColors.gold2 : AppColors.text2,
                fontWeight: active ? FontWeight.w500 : FontWeight.w300))));
        },
      )),
      const SizedBox(height: 16),

      // Base URL
      const SectionLabel('Base URL'),
      const SizedBox(height: 6),
      TextField(
        controller: _urlCtrl,
        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
        decoration: InputDecoration(
          hintText: 'https://api.deepseek.com/v1',
          suffixIcon: IconButton(
            icon: const Icon(Icons.content_paste, size: 16),
            onPressed: () async {
              final d = await Clipboard.getData('text/plain');
              if (d?.text != null) setState(() => _urlCtrl.text = d!.text!.trim());
            }))),
      const SizedBox(height: 12),

      // API Key
      const SectionLabel('API Key'),
      const SizedBox(height: 6),
      TextField(
        controller: _keyCtrl,
        obscureText: !_showKey,
        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
        decoration: InputDecoration(
          hintText: _hasKey ? '已保存（输入新 Key 替换）' : 'sk-... 或对应格式',
          suffixIcon: IconButton(
            icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 18),
            onPressed: () => setState(() => _showKey = !_showKey)))),
      const Text('Key 通过系统安全区加密存储，不上传任何服务器',
        style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3)),
      const SizedBox(height: 16),

      // 核心行：搜索模型 + 测试
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: fetching ? null : _fetchModels,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.bg3,
            foregroundColor: AppColors.gold2,
            side: const BorderSide(color: AppColors.gold)),
          icon: fetching
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.gold2))
            : const Icon(Icons.search, size: 16),
          label: Text(fetching ? '搜索中...' : '🔍 搜索可用模型'))),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _test,
          style: OutlinedButton.styleFrom(
            foregroundColor: _testResult == 'ok'   ? AppColors.jade2
                           : _testResult == 'fail' ? AppColors.crimson2
                           : AppColors.text3),
          child: Icon(
            _testResult == 'ok'   ? Icons.check_circle_outline
            : _testResult == 'fail' ? Icons.cancel_outlined
            : Icons.wifi_tethering, size: 16)),
      ]),

      // 模型列表
      if (models.isNotEmpty) ...[
        const SizedBox(height: 16),
        SectionLabel('发现 ${models.length} 个模型', color: AppColors.jade2),
        const SizedBox(height: 8),
        ...models.map((m) => _ModelTile(
          model: m, selected: _selectedModel == m.id,
          onTap: () => setState(() => _selectedModel = m.id))),
      ] else if (_selectedModel != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.bg2, border: Border.all(color: AppColors.line2)),
          child: Row(children: [
            const Icon(Icons.model_training, size: 16, color: AppColors.text3),
            const SizedBox(width: 8),
            Expanded(child: Text(_selectedModel!,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: AppColors.text2))),
            GestureDetector(
              onTap: () => setState(() => _selectedModel = null),
              child: const Icon(Icons.edit_outlined, size: 14, color: AppColors.text3)),
          ])),
      ] else ...[
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(12), color: AppColors.bg3,
          child: const Row(children: [
            Icon(Icons.lightbulb_outline, size: 14, color: AppColors.gold),
            SizedBox(width: 8),
            Expanded(child: Text('填写 URL 和 Key 后点「搜索模型」，自动列出所有可用模型',
              style: TextStyle(fontSize: 11, color: AppColors.text3, height: 1.6))),
          ])),
      ],

      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: _saving ? null : _save,
        child: _saving
          ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg0))
          : const Text('保存并应用到全部 Agent'))),
      const SizedBox(height: 32),
    ]);
  }

  Future<void> _fetchModels() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) { context.showError('请先填写 Base URL'); return; }
    final key = _keyCtrl.text.trim().isNotEmpty ? _keyCtrl.text.trim()
      : await _kStorage.read(key: 'apikey_default') ?? '';
    ref.read(_fetchingProvider.notifier).state = true;
    try {
      final list = await LlmClient.instance.fetchModels(baseUrl: url, apiKey: key);
      ref.read(_fetchedModelsProvider.notifier).state = list;
      if (list.isEmpty) {
        if (mounted) context.showError('未发现模型，请检查 URL 和 Key');
      } else {
        if (_selectedModel == null || !list.any((m) => m.id == _selectedModel)) {
          setState(() => _selectedModel = list.first.id);
        }
        if (mounted) context.showSuccess('发现 ${list.length} 个模型');
      }
    } finally { ref.read(_fetchingProvider.notifier).state = false; }
  }

  Future<void> _test() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || _selectedModel == null) return;
    final key = _keyCtrl.text.trim().isNotEmpty ? _keyCtrl.text.trim()
      : await _kStorage.read(key: 'apikey_default') ?? '';
    final ok = await LlmClient.instance.testConnection(
      baseUrl: url, model: _selectedModel!, apiKey: key);
    setState(() => _testResult = ok ? 'ok' : 'fail');
    if (mounted) ok ? context.showSuccess('连接成功') : context.showError('连接失败');
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty) { context.showError('请填写 Base URL'); return; }
    if (_selectedModel == null) { context.showError('请选择模型'); return; }
    if (key.isEmpty && !_hasKey) { context.showError('请填写 API Key'); return; }
    setState(() => _saving = true);
    final effectiveKey = key.isNotEmpty ? key
      : await _kStorage.read(key: 'apikey_default') ?? '';
    final ok = await ref.read(llmConfigsProvider.notifier).setDefault(
      baseUrl: url, model: _selectedModel!, apiKey: effectiveKey);
    setState(() => _saving = false);
    if (mounted) ok
      ? context.showSuccess('已保存！全部 Agent 使用新配置')
      : context.showError('连接测试失败');
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({super.key, required this.model, required this.selected, required this.onTap});
  final ModelInfo model; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:  selected ? AppColors.goldDim : AppColors.bg2,
        border: Border.all(color: selected ? AppColors.gold : AppColors.line2)),
      child: Row(children: [
        Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 16, color: selected ? AppColors.gold2 : AppColors.text3),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(model.displayName, style: TextStyle(fontSize: 13,
            color: selected ? AppColors.text1 : AppColors.text2,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w300)),
          Text(model.id, style: const TextStyle(
            fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if (model.ctxLabel.isNotEmpty)
            Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              color: AppColors.bg3,
              child: Text(model.ctxLabel, style: const TextStyle(
                fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3))),
          if (model.chapterCostEstimate.isNotEmpty)
            Text(model.chapterCostEstimate, style: const TextStyle(
              fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.jade2)),
        ]),
      ])));
}

// ════════════════════════════════════════════
// Tab 2 — 高级 Agent 配置
// ════════════════════════════════════════════
class _AdvancedAgentTab extends ConsumerWidget {
  const _AdvancedAgentTab();
  static const _agents = [
    ('bingbu',   '⚔️ 兵部',  '正文写稿 ← 推荐最强模型', true),
    ('zhongshu', '📜 中书省', '章节规划',    false),
    ('menxia',   '🔍 门下省', '规划审议',    false),
    ('gongbu',   '🌍 工部',   '档案更新+审计',false),
    ('libu',     '📝 礼部',   '文风润色',    false),
    ('hubu',     '💰 户部',   '数值验算',    false),
    ('libu_hr',  '👥 吏部',   '群像调度',    false),
    ('xingbu',   '⚖️ 刑部',   '合规审查',    false),
  ];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfgs = ref.watch(llmConfigsProvider);
    return cfgs.when(
      data: (list) => ListView(children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.blueDim,
            border: const Border(left: BorderSide(color: AppColors.blue2, width: 2))),
          child: const Text('每个 Agent 可独立配置不同模型。兵部推荐最强；其余用快速模型可节省约80%成本。',
            style: TextStyle(fontSize: 12, color: AppColors.text2, height: 1.7))),
        ..._agents.map((a) {
          final cfg = list.firstWhere((c) => c.agentId == a.$1,
            orElse: () => LlmConfig(agentId: a.$1,
              baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat'));
          return Container(
            decoration: a.$4 ? const BoxDecoration(color: Color(0x08C8942A),
              border: Border(left: BorderSide(color: AppColors.gold, width: 2))) : null,
            child: ListTile(
              leading: Text(a.$2.split(' ')[0], style: const TextStyle(fontSize: 20)),
              title: Row(children: [
                Text(a.$2, style: const TextStyle(fontSize: 13)),
                if (a.$4) ...[const SizedBox(width: 6),
                  const AppBadge(label: '关键', color: AppColors.gold2, small: true)],
              ]),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.$3, style: const TextStyle(fontSize: 11, color: AppColors.text3)),
                Text(cfg.model, style: const TextStyle(
                  fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text2)),
              ]),
              trailing: const Icon(Icons.chevron_right, size: 16, color: AppColors.text3),
              onTap: () => showModalBottomSheet(context: context, isScrollControlled: true,
                builder: (_) => _AgentSheet(agentId: a.$1, name: a.$2, cfg: cfg, ref: ref))));
        }),
      ]),
      loading: () => const LoadingShimmer(),
      error:   (e, _) => EmptyState(icon: Icons.error_outline, title: '$e'));
  }
}

class _AgentSheet extends StatefulWidget {
  const _AgentSheet({super.key, required this.agentId, required this.name, required this.cfg, required this.ref});
  final String agentId, name; final LlmConfigModel cfg; final WidgetRef ref;
  @override State<_AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<_AgentSheet> {
  late final _urlCtrl   = TextEditingController(text: widget.cfg.baseUrl);
  late final _modelCtrl = TextEditingController(text: widget.cfg.model);
  final _keyCtrl  = TextEditingController();
  bool _showKey = false, _saving = false, _fetching = false;
  List<ModelInfo> _models = [];

  @override
  void dispose() { _urlCtrl.dispose(); _modelCtrl.dispose(); _keyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Text(widget.name, style: const TextStyle(fontFamily: 'NotoSerifSC',
          fontSize: 16, fontWeight: FontWeight.w700)),
        const Spacer(),
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('关闭', style: TextStyle(color: AppColors.text3))),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: LlmPresets.providers.map((p) => ActionChip(
        label: Text(p.$1, style: const TextStyle(fontSize: 10)),
        onPressed: () => setState(() { _urlCtrl.text = p.$2; _modelCtrl.text = p.$3; _models = []; }),
      )).toList()),
      const SizedBox(height: 10),
      TextField(controller: _urlCtrl,
        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
        decoration: const InputDecoration(labelText: 'Base URL')),
      const SizedBox(height: 8),
      if (_models.isNotEmpty)
        DropdownButtonFormField<String>(
          value: _models.any((m) => m.id == _modelCtrl.text) ? _modelCtrl.text : null,
          dropdownColor: AppColors.bg2,
          decoration: const InputDecoration(labelText: '选择模型'),
          items: _models.map((m) => DropdownMenuItem(value: m.id,
            child: Row(children: [
              Expanded(child: Text(m.displayName, style: const TextStyle(fontSize: 12))),
              if (m.chapterCostEstimate.isNotEmpty)
                Text(m.chapterCostEstimate, style: const TextStyle(
                  fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.jade2)),
            ]))).toList(),
          onChanged: (v) => setState(() => _modelCtrl.text = v ?? _modelCtrl.text))
      else
        TextField(controller: _modelCtrl,
          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
          decoration: InputDecoration(
            labelText: '模型名（或点图标搜索）',
            suffixIcon: IconButton(
              icon: _fetching
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5))
                : const Icon(Icons.search, size: 16),
              onPressed: _fetching ? null : _search))),
      const SizedBox(height: 8),
      TextField(controller: _keyCtrl, obscureText: !_showKey,
        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11),
        decoration: InputDecoration(
          labelText: 'API Key（留空保持现有）',
          suffixIcon: IconButton(
            icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 16),
            onPressed: () => setState(() => _showKey = !_showKey)))),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: _saving ? null : _save,
        child: _saving
          ? const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg0))
          : const Text('保存'))),
    ])));

  Future<void> _search() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _fetching = true);
    final key = _keyCtrl.text.trim().isNotEmpty ? _keyCtrl.text.trim()
      : await _kStorage.read(key: 'apikey_${widget.agentId}')
      ?? await _kStorage.read(key: 'apikey_default') ?? '';
    final list = await LlmClient.instance.fetchModels(baseUrl: url, apiKey: key);
    setState(() { _fetching = false; _models = list; });
    if (list.isEmpty && mounted) context.showError('未找到模型列表');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await widget.ref.read(llmConfigsProvider.notifier).save(
      agentId: widget.agentId, baseUrl: _urlCtrl.text.trim(),
      model: _modelCtrl.text.trim(), apiKey: _keyCtrl.text.trim(),
      temperature: widget.agentId == 'bingbu' ? 0.85 : 0.2);
    setState(() => _saving = false);
    if (mounted) ok ? Navigator.pop(context) : context.showError('连接测试失败');
  }
}

// ════════════════════════════════════════════
// Tab 3 — 统计
// ════════════════════════════════════════════
class _StatsTab extends StatefulWidget {
  const _StatsTab();
  @override State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  WritingStats? _stats;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final stats = await StatisticsManager.instance.getGlobalStats();
    if (mounted) setState(() => _stats = stats);
  }
  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return ListView(padding: const EdgeInsets.all(20), children: [
    const SectionLabel('创作统计'),
    const SizedBox(height: 12),
    if (s == null)
      const Center(child: CircularProgressIndicator())
    else ...[
    _bar('书籍总数',    '${s.totalBooks} 本',       AppColors.info),
    _bar('已写章节',   '${s.totalChapters} 章',     AppColors.jade2),
    _bar('总字数',     s.totalWordsLabel,            AppColors.blue2),
    _bar('平均章节字数', '${s.avgWordsPerChapter}字', AppColors.teal2),
    _bar('Token 消耗', s.tokenLabel,                AppColors.purple2),
    _bar('预估费用（真实）', s.costLabel,             AppColors.gold2),
    _bar('当前模型', s.currentModel,                 AppColors.accent),
    _bar('请求成功率', '${(s.successRate * 100).toStringAsFixed(1)}%', AppColors.jade2),
    ],
    const SizedBox(height: 24),
    const SectionLabel('每章成本参考'),
    const SizedBox(height: 8),
    Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bg2, border: Border.all(color: AppColors.line2)),
      child: const Column(children: [
        _CR('DeepSeek Chat V3',    '≈¥0.01~0.03/章'),
        _CR('通义千问 Plus',        '≈¥0.03~0.08/章'),
        _CR('豆包 Pro 128K',        '≈¥0.02~0.05/章'),
        Divider(color: AppColors.line2, height: 16),
        _CR('GPT-4o',              '≈¥1.5~4/章'),
        _CR('Claude 3.5 Sonnet',   '≈¥1~3/章'),
      ])),
    const SizedBox(height: 16),
    const SizedBox(height: 24),
    const SectionLabel('数据安全'),
    const SizedBox(height: 8),
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.infoDim,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withOpacity(.25))),
      child: const Text(
        '📌 建议：每完成10章备份一次。\n备份文件包含全部书籍、章节、档案、伏笔，可存入微信收藏/网盘。',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.7)),
    ),
                const SizedBox(height: 12),
            _BackupButtons(),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                CostTracker.instance.reset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已重置'))
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.crimson2,
                side: const BorderSide(color: AppColors.crimson2),
              ),
              child: const Text('重置统计'),
            ),
          ]);
  } // <--- 🌟 这扇门完美关上了 build 方法！

  // 独立出来的 _bar 工具方法
  Widget _bar(String l, String v, Color c) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.withOpacity(.08),
          border: Border(left: BorderSide(color: c, width: 2)),
        ),
        child: Row(children: [
          Text(l, style: const TextStyle(fontSize: 13, color: AppColors.text2)),
          const Spacer(),
          Text(v, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 16, fontWeight: FontWeight.w700, color: c)),
        ]),
      );
} // <--- 🌟 这扇门彻底关上了 _StatTabState 大房子！

// 彻底自由独立的 _CR 类
class _CR extends StatelessWidget {
  const _CR(this.l, this.v);
  final String l, v;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(fontSize: 12, color: AppColors.text2))),
          Text(v, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: AppColors.jade2)),
        ]),
      );
}
// Fix7: 备份/恢复按钮组
class _BackupButtons extends StatefulWidget {
  const _BackupButtons();
  @override State<_BackupButtons> createState() => _BackupButtonsState();
}
class _BackupButtonsState extends State<_BackupButtons> {
  bool _backing = false;
  String _dbSize = '计算中...';

  @override
  void initState() { super.initState(); _loadInfo(); }
  
  Future<void> _loadInfo() async {
    final info = await BackupManager.instance.getDatabaseInfo();
    if (mounted) setState(() => _dbSize = info.exists ? info.sizeLabel : '未知');
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Row(children: [
      const Icon(Icons.storage_outlined, size: 14, color: AppColors.textTertiary),
      const SizedBox(width: 6),
      Text('数据库大小：$_dbSize', style: const TextStyle(
        fontFamily: 'JetBrainsMono', fontSize: 11, color: AppColors.textTertiary)),
    ]),
    const SizedBox(height: 10),
    SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _backing ? null : _backup,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.info, foregroundColor: Colors.white),
      icon: _backing
        ? const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.backup_outlined, size: 18),
      label: Text(_backing ? '备份中...' : '📦 导出完整备份 (.db)'),
    )),
  ]);

  Future<void> _backup() async {
    setState(() => _backing = true);
    try {
      final result = await BackupManager.instance.exportDatabase();
      if (mounted) {
        result.success
          ? context.showSuccess(result.message ?? '备份成功')
          : context.showError(result.error ?? '备份失败');
      }
    } finally {
      if (mounted) setState(() => _backing = false);
    }
  }
}
}
// ════════════════════════════════════════════
// Fix7: 备份面板
// ════════════════════════════════════════════
class _BackupPanel extends StatefulWidget {
  const _BackupPanel();
  @override
  State<_BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends State<_BackupPanel> {
  bool    _exporting = false;
  String? _dbSize;

  @override
  void initState() {
    super.initState();
    _loadDbInfo();
  }

  Future<void> _loadDbInfo() async {
    final info = await BackupManager.instance.getDatabaseInfo();
    if (mounted) setState(() => _dbSize = info.exists ? info.sizeLabel : '数据库未找到');
  }


  // 完美修复的导出方法（已替换官方 SnackBar）
  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final result = await BackupManager.instance.exportDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.success ? (result.message ?? '备份成功') : (result.error ?? '备份失败')))
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // 完美修复的导入方法
  Future<void> _import() async {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceL1,
        title: const Text('恢复备份'),
        content: const Text(
            '恢复备份会覆盖当前所有数据！\n\n操作步骤：\n1. 将 .db 备份文件传到手机\n2. 用文件管理器找到该文件\n3. 复制路径粘帖到此处\n建议先导出当前数据备份再恢复。',
            style: TextStyle(fontSize: 13, height: 1.7)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceL1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🗄️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('完整数据备份', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('包含：所有书籍、章节、档案、伏笔、角色',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ])),
          if (_dbSize != null)
            Text(_dbSize!, style: const TextStyle(
              fontFamily: 'JetBrainsMono', fontSize: 10, color: AppColors.textTertiary)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: _exporting ? null : _export,
            icon: _exporting
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.upload_outlined, size: 16),
            label: Text(_exporting ? '导出中...' : '导出备份 (.db)'),
          )),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('恢复备份'),
          ),
        ]),
        const SizedBox(height: 8),
        const Text('导出的 .db 文件可保存到微信收藏、云盘等。恢复后需重启 App。',
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary, height: 1.5)),
      ]),
    );
  }

  
}
