// lib/screens/style/style_screen.dart
// 写作风格设置 — 纯本地 prompt 注入，无需上传文件分析
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/db/database.dart';
import '../../widgets/common/widgets.dart';
import '../../core/utils/extensions.dart';

// ── Provider ─────────────────────────────────
final styleConfigProvider =
    AsyncNotifierProvider<StyleConfigNotifier, StyleConfig>(
  StyleConfigNotifier.new,
);

class StyleConfig {
  const StyleConfig({
    this.genreStyle = '',
    this.customPrompt = '',
    this.avoidWords = '',
    this.sentenceLength = 'medium',
    this.dialogueRatio = 'medium',
    this.poetic = false,
    this.enabled = false,
  });
  final String genreStyle, customPrompt, avoidWords;
  final String sentenceLength, dialogueRatio;
  final bool   poetic, enabled;

  StyleConfig copyWith({
    String? genreStyle, String? customPrompt, String? avoidWords,
    String? sentenceLength, String? dialogueRatio,
    bool? poetic, bool? enabled,
  }) => StyleConfig(
    genreStyle:     genreStyle     ?? this.genreStyle,
    customPrompt:   customPrompt   ?? this.customPrompt,
    avoidWords:     avoidWords     ?? this.avoidWords,
    sentenceLength: sentenceLength ?? this.sentenceLength,
    dialogueRatio:  dialogueRatio  ?? this.dialogueRatio,
    poetic:         poetic         ?? this.poetic,
    enabled:        enabled        ?? this.enabled,
  );

  String toPrompt() {
    if (!enabled) return '';
    final parts = <String>[];
    if (genreStyle.isNotEmpty) parts.add('风格参考：$genreStyle');
    parts.add(_sentenceLabel());
    parts.add(_dialogueLabel());
    if (poetic) parts.add('文字具有诗意感，善用比喻和意象');
    if (avoidWords.isNotEmpty) parts.add('避免使用：$avoidWords');
    if (customPrompt.isNotEmpty) parts.add(customPrompt);
    return parts.join('。');
  }

  String _sentenceLabel() => switch (sentenceLength) {
    'short'  => '句式简短有力，多用短句，节奏明快',
    'long'   => '句式舒展，多用长句，叙事流畅',
    _        => '长短句交替，节奏张弛有度',
  };

  String _dialogueLabel() => switch (dialogueRatio) {
    'high' => '对话占比较高，通过对话推动情节',
    'low'  => '叙事描写为主，对话简洁精炼',
    _      => '对话与叙述均衡',
  };
}

class StyleConfigNotifier extends AsyncNotifier<StyleConfig> {
  static const _key = 'style_config_v1';

  @override
  Future<StyleConfig> build() async {
    final raw = await AppDatabase.instance.getSetting(_key);
    if (raw == null) return const StyleConfig();
    try {
      final parts = raw.split('|');
      return StyleConfig(
        enabled:        parts[0] == '1',
        genreStyle:     parts.length > 1 ? parts[1] : '',
        sentenceLength: parts.length > 2 ? parts[2] : 'medium',
        dialogueRatio:  parts.length > 3 ? parts[3] : 'medium',
        poetic:         parts.length > 4 && parts[4] == '1',
        avoidWords:     parts.length > 5 ? parts[5] : '',
        customPrompt:   parts.length > 6 ? parts[6] : '',
      );
    } catch (_) {
      return const StyleConfig();
    }
  }

  Future<void> save(StyleConfig cfg) async {
    state = AsyncData(cfg);
    final encoded = [
      cfg.enabled ? '1' : '0',
      cfg.genreStyle,
      cfg.sentenceLength,
      cfg.dialogueRatio,
      cfg.poetic ? '1' : '0',
      cfg.avoidWords,
      cfg.customPrompt,
    ].join('|');
    await AppDatabase.instance.setSetting(_key, encoded);
  }
}

// 供 pipeline 读取当前风格 prompt
Future<String?> getStylePrompt() async {
  final raw = await AppDatabase.instance.getSetting('style_config_v1');
  if (raw == null) return null;
  try {
    final parts = raw.split('|');
    if (parts[0] != '1') return null;
    final cfg = StyleConfig(
      enabled:        true,
      genreStyle:     parts.length > 1 ? parts[1] : '',
      sentenceLength: parts.length > 2 ? parts[2] : 'medium',
      dialogueRatio:  parts.length > 3 ? parts[3] : 'medium',
      poetic:         parts.length > 4 && parts[4] == '1',
      avoidWords:     parts.length > 5 ? parts[5] : '',
      customPrompt:   parts.length > 6 ? parts[6] : '',
    );
    final prompt = cfg.toPrompt();
    return prompt.isEmpty ? null : prompt;
  } catch (_) {
    return null;
  }
}

// ════════════════════════════════════════════
// 风格设置页面
// ════════════════════════════════════════════
class StyleScreen extends ConsumerStatefulWidget {
  const StyleScreen({super.key});
  @override
  ConsumerState<StyleScreen> createState() => _StyleScreenState();
}

class _StyleScreenState extends ConsumerState<StyleScreen> {
  final _genreCtrl   = TextEditingController();
  final _avoidCtrl   = TextEditingController();
  final _customCtrl  = TextEditingController();
  String _sentLen    = 'medium';
  String _dialRatio  = 'medium';
  bool   _poetic     = false;
  bool   _enabled    = false;
  bool   _loaded     = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = ref.read(styleConfigProvider).valueOrNull ?? const StyleConfig();
    _genreCtrl.text  = cfg.genreStyle;
    _avoidCtrl.text  = cfg.avoidWords;
    _customCtrl.text = cfg.customPrompt;
    _sentLen         = cfg.sentenceLength;
    _dialRatio       = cfg.dialogueRatio;
    _poetic          = cfg.poetic;
    _enabled         = cfg.enabled;
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _genreCtrl.dispose();
    _avoidCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  StyleConfig _current() => StyleConfig(
    genreStyle:     _genreCtrl.text.trim(),
    avoidWords:     _avoidCtrl.text.trim(),
    customPrompt:   _customCtrl.text.trim(),
    sentenceLength: _sentLen,
    dialogueRatio:  _dialRatio,
    poetic:         _poetic,
    enabled:        _enabled,
  );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(
      backgroundColor: AppColors.bg0,
      body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
    );

    final preview = _current().toPrompt();

    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('写作风格'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: AppColors.gold2)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // 开关
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color:  AppColors.bg2,
            border: Border.all(color: _enabled ? AppColors.gold : AppColors.line2),
          ),
          child: Row(children: [
            Text(
              _enabled ? '⚡ 风格注入已开启' : '风格注入已关闭',
              style: TextStyle(
                fontSize: 13,
                color: _enabled ? AppColors.gold2 : AppColors.text3,
              ),
            ),
            const Spacer(),
            Switch(
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              activeColor: AppColors.gold2,
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // 说明
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.blueDim,
            border: const Border(left: BorderSide(color: AppColors.blue2, width: 2)),
          ),
          child: const Text(
            '风格配置会注入到兵部写手的系统 Prompt 中。\n'
            '设置越具体，写作越贴近你的期望风格。',
            style: TextStyle(fontSize: 12, color: AppColors.text2, height: 1.7),
          ),
        ),
        const SizedBox(height: 20),

        // 风格参考
        const SectionLabel('风格参考作者 / 作品'),
        const SizedBox(height: 8),
        TextField(
          controller: _genreCtrl,
          decoration: const InputDecoration(
            hintText: '例：天蚕土豆早期风格、遮天前期、冰火人物塑造',
          ),
        ),
        const SizedBox(height: 16),

        // 句式长短
        const SectionLabel('句式风格'),
        const SizedBox(height: 8),
        _RadioGroup(
          options: const [
            ('short',  '短句为主', '节奏快，爽文感强'),
            ('medium', '长短交替', '张弛有度（推荐）'),
            ('long',   '长句为主', '叙事感，文学性强'),
          ],
          value: _sentLen,
          onChanged: (v) => setState(() => _sentLen = v),
        ),
        const SizedBox(height: 16),

        // 对话比例
        const SectionLabel('对话比例'),
        const SizedBox(height: 8),
        _RadioGroup(
          options: const [
            ('low',    '叙述为主', '描写细腻，节奏沉稳'),
            ('medium', '均衡',     '描写与对话各半（推荐）'),
            ('high',   '对话为主', '读感轻快，角色鲜活'),
          ],
          value: _dialRatio,
          onChanged: (v) => setState(() => _dialRatio = v),
        ),
        const SizedBox(height: 16),

        // 诗意开关
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: AppColors.bg2, border: Border.all(color: AppColors.line2)),
          child: Row(children: [
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('诗意笔触', style: TextStyle(fontSize: 13)),
                Text('善用比喻、意象，文字富有画面感', style: TextStyle(fontSize: 11, color: AppColors.text3)),
              ],
            )),
            Switch(
              value: _poetic,
              onChanged: (v) => setState(() => _poetic = v),
              activeColor: AppColors.gold2,
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // 避免词汇
        const SectionLabel('避免使用的词汇 / 句式'),
        const SizedBox(height: 8),
        TextField(
          controller: _avoidCtrl,
          decoration: const InputDecoration(
            hintText: '例：淡淡、微微、不禁、感受到，用逗号分隔',
          ),
        ),
        const SizedBox(height: 16),

        // 自定义 prompt
        const SectionLabel('自定义风格指令（直接注入）'),
        const SizedBox(height: 8),
        TextField(
          controller: _customCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '例：每章战斗场景不超过 800 字，重点刻画主角心理变化...',
          ),
        ),
        const SizedBox(height: 24),

        // 预览
        if (preview.isNotEmpty) ...[
          const SectionLabel('注入 Prompt 预览'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bg2,
              border: Border.all(color: AppColors.line2),
            ),
            child: Text(
              preview,
              style: const TextStyle(
                fontFamily: 'NotoSerifSC',
                fontSize: 12,
                color: AppColors.text2,
                height: 1.7,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _save,
            child: const Text('保存风格配置'),
          ),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  Future<void> _save() async {
    await ref.read(styleConfigProvider.notifier).save(_current());
    if (mounted) context.showSuccess('风格配置已保存');
  }
}

class _RadioGroup extends StatelessWidget {
  const _RadioGroup({super.key, 
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<(String, String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: options.map((opt) {
        final selected = value == opt.$1;
        return GestureDetector(
          onTap: () => onChanged(opt.$1),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:  selected ? AppColors.goldDim : AppColors.bg2,
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.line2,
              ),
            ),
            child: Row(children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 16,
                color: selected ? AppColors.gold2 : AppColors.text3,
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(opt.$2, style: TextStyle(
                    fontSize: 13,
                    color: selected ? AppColors.text1 : AppColors.text2,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w300,
                  )),
                  Text(opt.$3, style: const TextStyle(
                    fontSize: 11, color: AppColors.text3)),
                ],
              )),
            ]),
          ),
        );
      }).toList(),
    );
  }
}
