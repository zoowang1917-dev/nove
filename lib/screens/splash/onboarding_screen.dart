// lib/screens/splash/onboarding_screen.dart
// 首次启动：引导用户填写 API Key 后进入主界面
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/llm/llm_client.dart';
import '../../core/db/database.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pages = PageController();
  int   _page        = 0;
  int   _providerIdx = 0;
  final _keyCtrl     = TextEditingController();
  bool  _showKey     = false;
  bool  _testing     = false;
  bool  _saving      = false;
  String? _testResult; // 'ok' | 'fail' | null

  @override
  void dispose() {
    _pages.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: Column(children: [
          // 进度指示
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(children: List.generate(3, (i) => Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                color: i <= _page ? AppColors.gold2 : AppColors.line2,
              ),
            ))),
          ),

          Expanded(child: PageView(
            controller: _pages,
            physics:    const NeverScrollableScrollPhysics(),
            children: [
              _Page0Welcome(),
              _Page1Setup(
                providerIdx: _providerIdx,
                keyCtrl:     _keyCtrl,
                showKey:     _showKey,
                testResult:  _testResult,
                testing:     _testing,
                onProviderChanged: (i) => setState(() { _providerIdx = i; _testResult = null; }),
                onToggleShow:   () => setState(() => _showKey = !_showKey),
                onTest:         _test,
              ),
              _Page2Done(),
            ],
          )),

          // 底部按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: _buildButtons(),
          ),
        ]),
      ),
    );
  }

  Widget _buildButtons() {
    if (_page == 0) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _goTo(1),
          child: const Text('开始配置'),
        ),
      );
    }

    if (_page == 1) {
      return Column(children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_testing || _saving) ? null : _saveAndContinue,
            child: _saving
              ? const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg0)),
                  SizedBox(width: 8), Text('保存中...'),
                ])
              : const Text('保存并开始创作'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _skip,
          child: const Text('跳过，稍后在设置中配置',
            style: TextStyle(color: AppColors.text3, fontSize: 12)),
        ),
      ]);
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => context.go('/'),
        child: const Text('进入书库，开始创作！'),
      ),
    );
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _pages.animateToPage(page,
      duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  Future<void> _test() async {
    setState(() { _testing = true; _testResult = null; });
    final preset = LlmPresets.providers[_providerIdx];
    final ok = await LlmClient.instance.testConnection(
      baseUrl: preset.$2, model: preset.$3,
      apiKey:  _keyCtrl.text.trim(),
    );
    setState(() { _testing = false; _testResult = ok ? 'ok' : 'fail'; });
  }

  Future<void> _saveAndContinue() async {
    if (_keyCtrl.text.trim().isEmpty) {
      _goTo(2); // 允许空 Key 跳过
      return;
    }
    setState(() => _saving = true);
    try {
      final preset = LlmPresets.providers[_providerIdx];
      final ok = await ref.read(llmConfigsProvider.notifier).setDefault(
        baseUrl: preset.$2, model: preset.$3,
        apiKey:  _keyCtrl.text.trim(),
      );
      if (ok || _testResult == 'ok') {
        await AppDatabase.instance.setSetting('onboarding_done', '1');
        _goTo(2);
      } else {
        if (mounted) context.showError('连接测试未通过，请检查 API Key');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skip() async {
    await AppDatabase.instance.setSetting('onboarding_done', '1');
    if (mounted) context.go('/');
  }
}

// ── 第0页：欢迎 ──────────────────────────────
class _Page0Welcome extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          color:  AppColors.goldDim,
          border: Border.all(color: AppColors.gold, width: 1.5),
        ),
        child: const Center(child: Text('⚔️', style: TextStyle(fontSize: 40))),
      ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(.8,.8)),
      const SizedBox(height: 32),
      const Text('三省六部 × InkOS', style: TextStyle(
        fontFamily: 'NotoSerifSC', fontSize: 26, fontWeight: FontWeight.w900,
        color: AppColors.gold2, letterSpacing: 4,
      )).animate(delay: 200.ms).fadeIn().slideY(begin: .2),
      const SizedBox(height: 12),
      const Text('AI 网文创作助手', style: TextStyle(
        fontFamily: 'JetBrainsMono', fontSize: 12,
        color: AppColors.text3, letterSpacing: 3,
      )).animate(delay: 350.ms).fadeIn(),
      const SizedBox(height: 40),
      ...[
        ('⚔️ 兵部写手',  '流式输出，实时看到文字生成'),
        ('📜 三省审议',  '中书规划 → 门下审议 → 尚书派发'),
        ('🌍 六大真相档案', '角色/世界/伏笔自动追踪，防止崩文'),
        ('📱 完全本地',  '数据存手机，API Key 加密保存'),
      ].map((item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Text(item.$1, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text(item.$2, style: const TextStyle(
            fontSize: 13, color: AppColors.text2))),
        ]),
      ).animate(delay: 500.ms).fadeIn()).toList(),
    ]),
  );
}

// ── 第1页：API Key 配置 ──────────────────────
class _Page1Setup extends StatelessWidget {
  const _Page1Setup({super.key, 
    required this.providerIdx,
    required this.keyCtrl,
    required this.showKey,
    required this.testResult,
    required this.testing,
    required this.onProviderChanged,
    required this.onToggleShow,
    required this.onTest,
  });

  final int    providerIdx;
  final TextEditingController keyCtrl;
  final bool   showKey, testing;
  final String? testResult;
  final ValueChanged<int> onProviderChanged;
  final VoidCallback onToggleShow, onTest;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text('配置 LLM API', style: TextStyle(
        fontFamily: 'NotoSerifSC', fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('选择一个 AI 服务商，填入 API Key\n（推荐 DeepSeek：国内直连，每章约 ¥0.02）',
        style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.6)),
      const SizedBox(height: 24),

      // 供应商选择
      Wrap(spacing: 8, runSpacing: 8,
        children: LlmPresets.providers.asMap().entries.map((e) => GestureDetector(
          onTap: () => onProviderChanged(e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color:  providerIdx == e.key ? AppColors.goldDim : AppColors.bg2,
              border: Border.all(
                color: providerIdx == e.key ? AppColors.gold : AppColors.line2,
                width: providerIdx == e.key ? 1.5 : 1,
              ),
            ),
            child: Text(e.value.$1, style: TextStyle(
              fontSize: 12,
              color: providerIdx == e.key ? AppColors.gold2 : AppColors.text2,
              fontWeight: providerIdx == e.key ? FontWeight.w500 : FontWeight.w300,
            )),
          ),
        )).toList(),
      ),
      const SizedBox(height: 20),

      // Base URL 预览
      Container(
        padding: const EdgeInsets.all(12),
        color: AppColors.bg3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Base URL', style: TextStyle(
            fontFamily: 'JetBrainsMono', fontSize: 9, color: AppColors.text3, letterSpacing: 2)),
          const SizedBox(height: 4),
          Text(LlmPresets.providers[providerIdx].$2, style: const TextStyle(
            fontFamily: 'JetBrainsMono', fontSize: 10, color: AppColors.text2)),
        ]),
      ),
      const SizedBox(height: 16),

      // API Key 输入
      TextField(
        controller: keyCtrl,
        obscureText: !showKey,
        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
        decoration: InputDecoration(
          labelText: 'API Key',
          hintText:  'sk-... 或对应格式的密钥',
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: Icon(showKey ? Icons.visibility_off : Icons.visibility, size: 18),
              onPressed: onToggleShow,
            ),
            IconButton(
              icon: Icon(
                testResult == 'ok'   ? Icons.check_circle_outline
                : testResult == 'fail' ? Icons.cancel_outlined
                : Icons.wifi_tethering,
                size: 18,
                color: testResult == 'ok'   ? AppColors.jade2
                     : testResult == 'fail' ? AppColors.crimson2
                     : AppColors.text3,
              ),
              onPressed: testing ? null : onTest,
            ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        testResult == 'ok'   ? '✓ 连接成功，可以开始写作'
        : testResult == 'fail' ? '✗ 连接失败，请检查 Key 和网络'
        : '点击右侧图标测试连接（可选）',
        style: TextStyle(
          fontFamily: 'JetBrainsMono', fontSize: 10,
          color: testResult == 'ok'   ? AppColors.jade2
               : testResult == 'fail' ? AppColors.crimson2
               : AppColors.text3,
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        color: AppColors.bg3,
        child: const Row(children: [
          Icon(Icons.lock_outline, size: 14, color: AppColors.text3),
          SizedBox(width: 6),
          Expanded(child: Text(
            'Key 使用 Android Keystore / iOS Keychain 加密存储，不上传任何服务器',
            style: TextStyle(fontSize: 10, color: AppColors.text3, height: 1.5),
          )),
        ]),
      ),
    ],
  );
}

// ── 第2页：完成 ──────────────────────────────
class _Page2Done extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('🎉', style: TextStyle(fontSize: 64))
        .animate().scale(begin: const Offset(.5,.5), duration: 500.ms, curve: Curves.elasticOut),
      const SizedBox(height: 24),
      const Text('配置完成！', style: TextStyle(
        fontFamily: 'NotoSerifSC', fontSize: 24, fontWeight: FontWeight.w900,
        color: AppColors.gold2,
      )).animate(delay: 200.ms).fadeIn().slideY(begin: .2),
      const SizedBox(height: 16),
      const Text(
        '现在可以开始创作了\n\n'
        '1. 在书库创建第一本书\n'
        '2. 进入写作台下达指令\n'
        '3. 三省六部 AI 为你写作',
        style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.9),
        textAlign: TextAlign.center,
      ).animate(delay: 400.ms).fadeIn(),
    ]),
  );
}
