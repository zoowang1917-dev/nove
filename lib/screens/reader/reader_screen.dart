// lib/screens/reader/reader_screen.dart
// 沉浸式阅读器：阅读视角审阅 AI 生成内容
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../platform/platform_service.dart';
import '../../platform/local_db.dart';

// ── 阅读器设置 Provider ───────────────────────
final readerSettingsProvider = StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
  (ref) => ReaderSettingsNotifier(),
);

class ReaderSettings {
  const ReaderSettings({
    this.fontSize    = 17.0,
    this.lineHeight  = 1.9,
    this.brightness  = 0.5,
    this.bgMode      = ReaderBgMode.dark,
    this.fontFamily  = 'NotoSerifSC',
  });
  final double       fontSize;
  final double       lineHeight;
  final double       brightness;
  final ReaderBgMode bgMode;
  final String       fontFamily;

  ReaderSettings copyWith({
    double? fontSize, double? lineHeight, double? brightness,
    ReaderBgMode? bgMode, String? fontFamily,
  }) => ReaderSettings(
    fontSize:   fontSize   ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    brightness: brightness ?? this.brightness,
    bgMode:     bgMode     ?? this.bgMode,
    fontFamily: fontFamily ?? this.fontFamily,
  );
}

enum ReaderBgMode { dark, sepia, light }

class ReaderSettingsNotifier extends StateNotifier<ReaderSettings> {
  ReaderSettingsNotifier() : super(const ReaderSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ReaderSettings(
      fontSize:   prefs.getDouble('reader_fontSize')   ?? 17.0,
      lineHeight: prefs.getDouble('reader_lineHeight') ?? 1.9,
      bgMode:     ReaderBgMode.values[prefs.getInt('reader_bgMode') ?? 0],
    );
  }

  Future<void> update(ReaderSettings s) async {
    state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('reader_fontSize',   s.fontSize);
    await prefs.setDouble('reader_lineHeight', s.lineHeight);
    await prefs.setInt('reader_bgMode', s.bgMode.index);
  }

  void adjustFontSize(double delta) => update(state.copyWith(
    fontSize: (state.fontSize + delta).clamp(13.0, 26.0),
  ));
}

// ════════════════════════════════════════════
// 阅读器屏幕
// ════════════════════════════════════════════
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.bookId,
    this.initialChapter = 1,
  });
  final String bookId;
  final int    initialChapter;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with SingleTickerProviderStateMixin {

  late final PageController _pageCtrl;
  bool _showUI = true;
  int  _currentChapter = 1;
  late AnimationController _uiAnim;
  late Animation<double>   _uiFade;

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.initialChapter;
    _pageCtrl = PageController(initialPage: _currentChapter - 1);
    _uiAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _uiFade = CurvedAnimation(parent: _uiAnim, curve: Curves.easeOut);
    _uiAnim.value = 1.0;

    // 进入阅读模式
    platform.enterReadingMode();
  }


  // 从阅读器直接编辑当前章节
  void _editChapterFromReader(BuildContext ctx, Chapter chapter) {
    final ctrl      = TextEditingController(text: chapter.content);
    final titleCtrl = TextEditingController(text: chapter.title);
    bool saving     = false;

    showModalBottomSheet(
      context: ctx, isScrollControlled: true,
      backgroundColor: AppColors.surfaceL1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx2).size.height * 0.90,
            child: Column(children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(children: [
                  const Icon(Icons.edit_outlined, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Text('编辑章节',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                          TextButton(
          onPressed: saving ? null : () async {
            setState(() => saving = true);
            try {
              if (titleCtrl.text.trim() != chapter.title) {
                await ref.read(tasksProvider(widget.bookId).notifier)
                    .updateChapterTitle(chapter.id, titleCtrl.text.trim());
              }
              await ref.read(tasksProvider(widget.bookId).notifier)
                  .updateChapterContent(chapter.id, ctrl.text);
              if (ctx2.mounted) {
                Navigator.pop(ctx2);
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已保存')));
              }
            } finally {
              if (ctx2.mounted) setState(() => saving = false);
            }
          },
          child: saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
        ),

                  IconButton(
                    onPressed: () => Navigator.pop(ctx2),
                    icon: const Icon(Icons.close, size: 20)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '章节标题',
                    prefixIcon: Icon(Icons.title, size: 18))),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ValueListenableBuilder(
                  valueListenable: ctrl,
                  builder: (_, v, __) {
                    final cnt = RegExp(r'[\u4e00-\u9fa5]').allMatches(v.text).length;
                    return Row(children: [
                      Text('$cnt 字',
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 11, color: AppColors.textTertiary)),
                    ]);
                  }),
              ),
              const SizedBox(height: 4),
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: ctrl,
                  maxLines:   null,
                  expands:    true,
                  style: const TextStyle(
                    fontFamily: 'NotoSerifSC',
                    fontSize:   15, height: 1.85,
                    color:      AppColors.textPrimary),
                  decoration: const InputDecoration(
                    border:         InputBorder.none,
                    filled:         false,
                    contentPadding: EdgeInsets.all(4)),
                ),
              )),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _uiAnim.dispose();
    platform.exitReadingMode();
    // 保存阅读进度
    // ignore: discarded_futures
    LocalDb.instance.saveReadingProgress(widget.bookId, _currentChapter, 0);
    super.dispose();
  }

  void _toggleUI() {
    setState(() => _showUI = !_showUI);
    if (_showUI) _uiAnim.forward(); else _uiAnim.reverse();
    platform.hapticLight();
  }

  @override
  Widget build(BuildContext context) {
    final chapters = ref.watch(chaptersProvider(widget.bookId));
    final settings = ref.watch(readerSettingsProvider);
    final bg       = _bgColor(settings.bgMode);
    final textColor = _textColor(settings.bgMode);

    return Scaffold(
      backgroundColor: bg,
      body: chapters.when(
        data: (list) {
          if (list.isEmpty) return const Center(
            child: Text('暂无章节', style: TextStyle(color: AppColors.text3)),
          );
          return GestureDetector(
            onTap: _toggleUI,
            child: Stack(
              children: [
                // ── 正文翻页 ────────────────────────
                PageView.builder(
                  controller: _pageCtrl,
                  itemCount:  list.length,
                  onPageChanged: (i) {
                    setState(() => _currentChapter = list[i].chapterNo);
                    // ignore: discarded_futures
                    LocalDb.instance.saveReadingProgress(widget.bookId, list[i].chapterNo, 0);
                  },
                  itemBuilder: (_, i) => _ChapterPage(
                    chapter:   list[i],
                    settings:  settings,
                    textColor: textColor,
                    bg:        bg,
                  ),
                ),

                // ── 顶部栏（点击显隐）──────────────
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: FadeTransition(
                    opacity: _uiFade,
                    child: _ReaderTopBar(
                      chapterTitle:   list.length >= _currentChapter
                        ? list[_currentChapter - 1].title : '',
                      onBack:         () => context.pop(),
                      bgMode:         settings.bgMode,
                    ),
                  ),
                ),

                // ── 底部工具栏 ──────────────────────
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: FadeTransition(
                    opacity: _uiFade,
                    child: _ReaderBottomBar(
                      chapters:       list,
                      currentChapter: _currentChapter,
                      pageCtrl:       _pageCtrl,
                      settings:       settings,
                      onSettingsChanged: (s) =>
                        ref.read(readerSettingsProvider.notifier).update(s),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
        error:   (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  Color _bgColor(ReaderBgMode mode) => switch (mode) {
    ReaderBgMode.dark  => const Color(0xFF0E1014),
    ReaderBgMode.sepia => const Color(0xFF1E1A14),
    ReaderBgMode.light => const Color(0xFFF5F0E8),
  };

  Color _textColor(ReaderBgMode mode) => switch (mode) {
    ReaderBgMode.dark  => const Color(0xFFB8B0A0),
    ReaderBgMode.sepia => const Color(0xFFBBAA88),
    ReaderBgMode.light => const Color(0xFF282420),
  };
}

// ── 章节页内容 ────────────────────────────────
class _ChapterPage extends StatelessWidget {
  const _ChapterPage({super.key, 
    required this.chapter,
    required this.settings,
    required this.textColor,
    required this.bg,
  });
  final Chapter       chapter;
  final ReaderSettings settings;
  final Color         textColor;
  final Color         bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24, MediaQuery.of(context).padding.top + 56, 24,
          MediaQuery.of(context).padding.bottom + 80,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节标题
            Text(
              chapter.title,
              style: TextStyle(
                fontFamily: settings.fontFamily,
                fontSize:   settings.fontSize + 3,
                fontWeight: FontWeight.w700,
                color:      textColor,
                height:     1.4,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            // 正文（首行缩进）
            ..._buildParagraphs(chapter.content, settings, textColor),
            const SizedBox(height: 40),
            // 字数行
            Text(
              '本章 ${chapter.wordCount} 字',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize:   11,
                color:      textColor.withOpacity(0.3),
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildParagraphs(String content, ReaderSettings s, Color color) {
    final paragraphs = content.split('\n')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

    return paragraphs.map((para) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '\u3000\u3000$para',  // 中文首行两格缩进
        style: TextStyle(
          fontFamily: s.fontFamily,
          fontSize:   s.fontSize,
          color:      color,
          height:     s.lineHeight,
          letterSpacing: 0.8,
        ),
      ),
    )).toList();
  }
}

// ── 顶部栏 ────────────────────────────────────
class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({super.key, 
    required this.chapterTitle,
    required this.onBack,
    required this.bgMode,
  });
  final String      chapterTitle;
  final VoidCallback onBack;
  final ReaderBgMode bgMode;

  @override
  Widget build(BuildContext context) {
    final isDark = bgMode != ReaderBgMode.light;
    return Container(
      padding: EdgeInsets.fromLTRB(
        8, MediaQuery.of(context).padding.top + 4, 8, 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [
            (isDark ? Colors.black : Colors.white).withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new,
              color: isDark ? AppColors.text2 : const Color(0xFF444444), size: 18),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              chapterTitle,
              style: TextStyle(
                fontFamily: 'NotoSerifSC',
                fontSize: 14,
                color: isDark ? AppColors.text2 : const Color(0xFF444444),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

// ── 底部工具栏 ────────────────────────────────
class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({super.key, 
    required this.chapters,
    required this.currentChapter,
    required this.pageCtrl,
    required this.settings,
    required this.onSettingsChanged,
  });
  final List<Chapter>              chapters;
  final int                        currentChapter;
  final PageController             pageCtrl;
  final ReaderSettings             settings;
  final ValueChanged<ReaderSettings> onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = settings.bgMode != ReaderBgMode.light;
    final barBg  = isDark
        ? Colors.black.withOpacity(0.85)
        : Colors.white.withOpacity(0.92);
    final iconColor = isDark ? AppColors.text1 : const Color(0xFF333333);

    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [barBg, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          SliderTheme(
            data: SliderThemeData(
              trackHeight:      2,
              thumbShape:       const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:     const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: AppColors.gold2,
              inactiveTrackColor: AppColors.line2,
              thumbColor:       AppColors.gold2,
              overlayColor:     AppColors.goldDim,
            ),
            child: Slider(
              value:   (currentChapter - 1).toDouble(),
              min:     0,
              max:     (chapters.length - 1).toDouble(),
              onChanged: (v) => pageCtrl.jumpToPage(v.round()),
            ),
          ),
          // 工具行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BarBtn(icon: Icons.format_size,     color: iconColor, onTap: () => _showFontSheet(context)),
              _BarBtn(icon: Icons.brightness_4_outlined, color: iconColor, onTap: () => _cycleBgMode()),
              _BarBtn(icon: Icons.format_list_numbered, color: iconColor, onTap: () => _showChapterSheet(context)),
              Text(
                '$currentChapter / ${chapters.length}',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono', fontSize: 11,
                  color: iconColor.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _cycleBgMode() {
    final modes = ReaderBgMode.values;
    final next  = modes[(settings.bgMode.index + 1) % modes.length];
    onSettingsChanged(settings.copyWith(bgMode: next));
  }

  void _showFontSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg1,
      builder: (_) => _FontSettings(settings: settings, onChanged: onSettingsChanged),
    );
  }

  void _showChapterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg1,
      builder: (_) => _ChapterList(chapters: chapters, currentChapter: currentChapter, pageCtrl: pageCtrl),
    );
  }
}

class _BarBtn extends StatelessWidget {
  const _BarBtn({super.key, required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, color: color, size: 22),
    onPressed: onTap,
  );
}

class _FontSettings extends StatelessWidget {
  const _FontSettings({super.key, required this.settings, required this.onChanged});
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('字体设置', style: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 16, color: AppColors.text1)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton(
            onPressed: () => onChanged(settings.copyWith(fontSize: (settings.fontSize - 1).clamp(13, 26))),
            child: const Text('A−'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('${settings.fontSize.toInt()}px',
              style: const TextStyle(fontFamily: 'JetBrainsMono', color: AppColors.text1)),
          ),
          OutlinedButton(
            onPressed: () => onChanged(settings.copyWith(fontSize: (settings.fontSize + 1).clamp(13, 26))),
            child: const Text('A+'),
          ),
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('行距', style: TextStyle(color: AppColors.text2, fontSize: 12)),
          const SizedBox(width: 12),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              activeTrackColor: AppColors.gold2,
              inactiveTrackColor: AppColors.line2,
              thumbColor: AppColors.gold2,
            ),
            child: SizedBox(
              width: 200,
              child: Slider(
                value: settings.lineHeight,
                min: 1.5, max: 2.5, divisions: 10,
                onChanged: (v) => onChanged(settings.copyWith(lineHeight: v)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({super.key, required this.chapters, required this.currentChapter, required this.pageCtrl});
  final List<Chapter> chapters;
  final int currentChapter;
  final PageController pageCtrl;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text('目录', style: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 16, color: AppColors.text1)),
      ),
      SizedBox(
        height: 360,
        child: ListView.separated(
          itemCount: chapters.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.line1),
          itemBuilder: (_, i) {
            final ch = chapters[i];
            final isCurrent = ch.chapterNo == currentChapter;
            return ListTile(
              dense: true,
              leading: Text('${ch.chapterNo}',
                style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11,
                  color: isCurrent ? AppColors.gold2 : AppColors.text3)),
              title: Text(ch.title,
                style: TextStyle(fontSize: 13,
                  color: isCurrent ? AppColors.gold2 : AppColors.text1,
                  fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w300)),
              onTap: () {
                pageCtrl.jumpToPage(i);
                Navigator.pop(context);
              },
            );
          },
        ),
      ),
    ]);
  }
}
