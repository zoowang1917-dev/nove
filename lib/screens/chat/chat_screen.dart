// lib/screens/chat/chat_screen.dart
// 豆包式 AI 助手对话 — 选择书籍上下文，多种对话模式
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_colors.dart';
import '../../core/llm/llm_client.dart';
import '../../core/db/database.dart';
import '../../core/utils/extensions.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';

// ── 对话模式定义 ─────────────────────────────
enum ChatMode {
  general,    // 通用聊天
  plotAdvice, // 剧情顾问
  charAnalysis,// 角色分析
  worldBuild, // 世界观问答
  rewrite,    // 片段改写
  debug,      // 逻辑漏洞排查
}

extension ChatModeX on ChatMode {
  String get label => switch (this) {
    ChatMode.general      => '💬 自由聊天',
    ChatMode.plotAdvice   => '📖 剧情顾问',
    ChatMode.charAnalysis => '👤 角色分析',
    ChatMode.worldBuild   => '🌍 世界观问答',
    ChatMode.rewrite      => '✏️ 片段改写',
    ChatMode.debug        => '🔍 逻辑漏洞排查',
  };

  String get systemPrompt => switch (this) {
    ChatMode.general      => '你是一个友善的创作助手，帮助用户讨论小说创作的各种问题。',
    ChatMode.plotAdvice   =>
      '你是资深网文编辑，专注于剧情结构设计。基于用户提供的书籍档案和情节，'
      '给出具体可执行的剧情建议。重点关注：爽点设计、矛盾冲突、伏笔回收时机、读者期待管理。',
    ChatMode.charAnalysis =>
      '你是人物塑造专家。分析角色的行为逻辑、成长弧线和心理动机。'
      '指出角色扁平化、工具人化、口吻不一致等问题，给出具体改善建议。',
    ChatMode.worldBuild   =>
      '你是世界观构建顾问。帮助用户完善设定体系，检查内部逻辑一致性，'
      '挖掘设定的故事潜力。注意：设定要服务情节，而非成为作者的独角戏。',
    ChatMode.rewrite      =>
      '你是文字润色师。用户提供原文片段，你给出更优的改写版本。'
      '改写方向：去AI味（淡淡/微微/缓缓等禁用）、加强动作感、提升画面感、优化节奏。',
    ChatMode.debug        =>
      '你是严格的逻辑审查官。分析用户描述的情节，找出：'
      '时间线矛盾、地理位置问题、角色信息越界、能力设定前后矛盾、伏笔遗漏等逻辑漏洞。'
      '用清单格式列出问题并给出修复建议。',
  };
}

// ── ChatMessage 模型 ─────────────────────────
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.isStreaming = false,
  });
  final String   role;
  final String   content;
  final DateTime createdAt;
  final bool     isStreaming;

  bool get isUser      => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
    role:      m['role'] as String,
    content:   m['content'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

// ════════════════════════════════════════════
// 主屏幕
// ════════════════════════════════════════════
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl   = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _sessionId   = const Uuid().v4();

  String?          _selectedBookId;
  ChatMode         _mode       = ChatMode.general;
  List<ChatMessage> _messages  = [];
  bool             _streaming  = false;
  String           _streamBuf  = '';

  @override
  void initState() { super.initState(); _loadHistory(); }
  @override
  void dispose()   { _inputCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _loadHistory() async {
    final rows = await AppDatabase.instance.getChatHistory(_sessionId);
    setState(() {
      _messages = rows.reversed
        .map((r) => ChatMessage.fromMap(r))
        .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(booksProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: _buildAppBar(books),
      body: Column(children: [
        // 模式选择器
        _ModeBar(
          current: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        // 消息列表
        Expanded(child: _messages.isEmpty && !_streaming
          ? _EmptyState(mode: _mode, onSuggest: _sendSuggestion)
          : ListView.builder(
              controller:  _scrollCtrl,
              padding:     const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount:   _messages.length + (_streaming ? 1 : 0),
              itemBuilder: (_, i) {
                if (_streaming && i == _messages.length) {
                  return _AssistantBubble(text: _streamBuf, isStreaming: true);
                }
                final msg = _messages[i];
                return msg.isUser
                  ? _UserBubble(msg: msg)
                  : _AssistantBubble(text: msg.content, isStreaming: false);
              },
            )),
        // 输入栏
        _InputBar(
          ctrl:       _inputCtrl,
          streaming:  _streaming,
          onSend:     _send,
          onStop:     _stop,
          bookCount:  _selectedBookId != null ? 1 : 0,
        ),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar(List<Book> books) => AppBar(
    title: const Text('AI 创作助手'),
    actions: [
      // 书籍选择
      if (books.isNotEmpty)
        PopupMenuButton<String?>(
          icon: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              _selectedBookId != null ? Icons.auto_stories : Icons.auto_stories_outlined,
              size: 18,
              color: _selectedBookId != null ? AppColors.gold2 : AppColors.text3,
            ),
            const SizedBox(width: 4),
            Text(
              _selectedBookId != null
                ? (books.firstWhere((b) => b.id == _selectedBookId,
                    orElse: () => books.first).title.truncate(6))
                : '无书籍',
              style: TextStyle(
                fontSize: 11,
                color: _selectedBookId != null ? AppColors.gold2 : AppColors.text3,
              ),
            ),
            const Icon(Icons.expand_more, size: 16, color: AppColors.text3),
          ]),
          color: AppColors.bg2,
          shape: const RoundedRectangleBorder(),
          onSelected: (id) => setState(() => _selectedBookId = id),
          itemBuilder: (_) => [
            const PopupMenuItem<String?>(
              value: null,
              child: Text('不使用书籍上下文', style: TextStyle(color: AppColors.text3)),
            ),
            ...books.map((b) => PopupMenuItem<String>(
              value: b.id,
              child: Row(children: [
                const Icon(Icons.book_outlined, size: 16, color: AppColors.text2),
                const SizedBox(width: 8),
                Text(b.title, style: const TextStyle(fontSize: 13)),
              ]),
            )),
          ],
        ),
      // 清空对话
      IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        tooltip: '清空对话',
        onPressed: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.bg2,
            title: const Text('清空对话'),
            content: const Text('确定清空本次对话？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
              TextButton(
                onPressed: () async {
                  await AppDatabase.instance.clearChatSession(_sessionId);
                  setState(() { _messages = []; _streamBuf = ''; });
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('清空', style: TextStyle(color: AppColors.crimson2))),
            ],
          ),
        ),
      ),
    ],
  );

  // 快捷发送建议内容
  void _sendSuggestion(String text) {
    _inputCtrl.text = text;
    _send();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _streaming) return;
    _inputCtrl.clear();

    // 添加用户消息
    final userMsg = ChatMessage(
      role: 'user', content: text, createdAt: DateTime.now());
    setState(() { _messages.add(userMsg); _streaming = true; _streamBuf = ''; });
    await AppDatabase.instance.insertChatMsg(
      sessionId: _sessionId, role: 'user', content: text,
      bookId: _selectedBookId, mode: _mode.name);
    _scrollToBottom();

    // 构建上下文
    final systemPrompt = await _buildSystemPrompt();
    final history = _buildHistory();

    // 流式请求
    final buf = StringBuffer();
    try {
      await for (final token in LlmClient.instance.stream('zhongshu', [
        {'role': 'system', 'content': systemPrompt},
        ...history,
        {'role': 'user', 'content': text},
      ])) {
        if (!_streaming) break; // 被停止
        buf.write(token);
        setState(() => _streamBuf = buf.toString());
        _scrollToBottom();
      }

      // 保存助手消息
      final reply = buf.toString().trim();
      if (reply.isNotEmpty) {
        final assistantMsg = ChatMessage(
          role: 'assistant', content: reply, createdAt: DateTime.now());
        setState(() { _messages.add(assistantMsg); });
        await AppDatabase.instance.insertChatMsg(
          sessionId: _sessionId, role: 'assistant', content: reply,
          bookId: _selectedBookId, mode: _mode.name);
      }
    } catch (e) {
      setState(() { _messages.add(ChatMessage(
        role: 'assistant',
        content: '⚠️ ${e.toString().replaceAll("LlmException: ", "")}',
        createdAt: DateTime.now()));
      });
    } finally {
      setState(() { _streaming = false; _streamBuf = ''; });
      _scrollToBottom();
    }
  }

  void _stop() => setState(() => _streaming = false);

  Future<String> _buildSystemPrompt() async {
    final base = _mode.systemPrompt;
    if (_selectedBookId == null) return base;

    // 注入书籍档案（RAG：将相关档案注入 prompt）
    final db      = AppDatabase.instance;
    final book    = await db.getBook(_selectedBookId!);
    final archives = await db.getAllArchives(_selectedBookId!);

    final title   = book?['title'] as String? ?? '未命名';
    final genre   = book?['genre'] as String? ?? '';
    final world   = (archives['world']?.toString() ?? '').take300;
    final chars   = (archives['characters']?.toString() ?? '').take300;
    final hooks   = await db.getHooks(_selectedBookId!);
    final openHooks = hooks.where((h) => h['status'] == 'OPEN').take(5).toList();
    final hookText = openHooks.map((h) =>
      '• ${h['description']}（${h['current_age']}章未收）').join('\n');

    return '''$base

## 当前书籍：$title（$genre）

### 世界状态摘要
$world

### 角色圣经摘要
$chars

### 待回收伏笔（${openHooks.length}条）
${hookText.isEmpty ? '（暂无）' : hookText}

请基于以上档案信息回答用户问题，保持与档案的一致性。''';
  }

  List<Map<String, String>> _buildHistory() {
    // 取最近10轮对话作为上下文
    final recent = _messages.reversed.take(20).toList().reversed.toList();
    return recent.map((m) => {'role': m.role, 'content': m.content}).toList();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

// 字符串扩展：安全截取
extension _StrX on String {
  String get take300 => length > 300 ? substring(0, 300) + '...' : this;
}

// ════════════════════════════════════════════
// 模式选择栏
// ════════════════════════════════════════════
class _ModeBar extends StatelessWidget {
  const _ModeBar({super.key, required this.current, required this.onChanged});
  final ChatMode current;
  final ValueChanged<ChatMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line1))),
    child: SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection:  Axis.horizontal,
        padding:          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount:        ChatMode.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final m       = ChatMode.values[i];
          final active  = m == current;
          return GestureDetector(
            onTap: () => onChanged(m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color:  active ? AppColors.goldDim : AppColors.bg2,
                border: Border.all(color: active ? AppColors.gold : AppColors.line2),
              ),
              child: Text(m.label, style: TextStyle(
                fontSize: 11,
                color: active ? AppColors.gold2 : AppColors.text3,
                fontWeight: active ? FontWeight.w500 : FontWeight.w300,
              )),
            ),
          );
        },
      ),
    ),
  );
}

// ════════════════════════════════════════════
// 消息气泡
// ════════════════════════════════════════════
class _UserBubble extends StatelessWidget {
  const _UserBubble({super.key, required this.msg});
  final ChatMessage msg;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16, left: 48),
    child: Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.goldDim,
          borderRadius: BorderRadius.only(
            topLeft:     Radius.circular(12),
            topRight:    Radius.circular(2),
            bottomLeft:  Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: Text(msg.content, style: const TextStyle(
          fontSize: 14, color: AppColors.text1, height: 1.6)),
      ),
    ),
  );
}

class _AssistantBubble extends StatefulWidget {
  const _AssistantBubble({super.key, required this.text, required this.isStreaming});
  final String text;
  final bool   isStreaming;
  @override State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cur;
  @override
  void initState() {
    super.initState();
    _cur = AnimationController(vsync: this, duration: 600.ms)..repeat(reverse: true);
  }
  @override
  void dispose() { _cur.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16, right: 48),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 头像
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: AppColors.bg3, border: Border.all(color: AppColors.line2)),
        child: const Center(child: Text('⚔️', style: TextStyle(fontSize: 14))),
      ),
      const SizedBox(width: 8),
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.only(
            topLeft:     Radius.circular(2),
            topRight:    Radius.circular(12),
            bottomLeft:  Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: widget.text.isEmpty
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 4),
              FadeTransition(opacity: _cur,
                child: Container(width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.gold2, shape: BoxShape.circle))),
              const SizedBox(width: 4),
              FadeTransition(opacity: ReverseAnimation(_cur),
                child: Container(width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.gold2, shape: BoxShape.circle))),
              const SizedBox(width: 4),
              FadeTransition(opacity: _cur,
                child: Container(width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.gold2, shape: BoxShape.circle))),
            ])
          : RichText(text: TextSpan(
              style: const TextStyle(
                fontFamily: 'NotoSerifSC', fontSize: 14,
                color: AppColors.text1, height: 1.75),
              children: [
                TextSpan(text: widget.text),
                if (widget.isStreaming) WidgetSpan(child: FadeTransition(
                  opacity: _cur,
                  child: Container(width: 2, height: 15,
                    margin: const EdgeInsets.only(left: 2),
                    color: AppColors.gold2))),
              ],
            )),
      )),
    ]),
  );
}

// ════════════════════════════════════════════
// 空状态 — 快捷提问
// ════════════════════════════════════════════
class _EmptyState extends ConsumerWidget {
  const _EmptyState({super.key, required this.mode, required this.onSuggest});
  final ChatMode mode;
  final ValueChanged<String> onSuggest;

  static const _suggestions = {
    ChatMode.general:      [
      '帮我想一个引人入胜的开头', '我的主角设定有什么问题？',
      '如何让读者对我的书上瘾？', '网文爽点设计的技巧是什么？',
    ],
    ChatMode.plotAdvice:   [
      '我的剧情卡住了，帮我设计下一个转折点',
      '这章的矛盾冲突不够强，怎么加强？',
      '如何设计一个让读者难以预测的反转？',
      '主角的成长弧线应该如何规划？',
    ],
    ChatMode.charAnalysis: [
      '分析一下我的主角性格是否立体', '我的反派动机合理吗？',
      '配角总是工具人，怎么改？', '如何让多个角色有不同的说话风格？',
    ],
    ChatMode.worldBuild:   [
      '帮我完善修炼体系的内部逻辑', '我的世界地图设定有什么漏洞？',
      '如何自然地向读者展示世界观？', '门派/国家/势力体系如何设计？',
    ],
    ChatMode.rewrite:      [
      '帮我改写这段文字，去掉AI味', '这段战斗场景节奏太慢，帮我优化',
      '这段对话太平，帮我加强张力', '帮我把这段叙述改成更有画面感的文字',
    ],
    ChatMode.debug:        [
      '检查一下这个情节的逻辑漏洞', '这两章之间有时间线矛盾吗？',
      '角色A怎么知道这个秘密的？说不通', '检查我的能力设定是否前后矛盾',
    ],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tips = _suggestions[mode] ?? _suggestions[ChatMode.general]!;
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('⚔️', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(mode.label, style: const TextStyle(
          fontFamily: 'NotoSerifSC', fontSize: 18, fontWeight: FontWeight.w700,
          color: AppColors.text1)),
        const SizedBox(height: 6),
        Text(
          mode == ChatMode.general
            ? '选择书籍后 AI 将基于档案回答问题'
            : '选择书籍后 AI 会结合你的档案给出更精准建议',
          style: const TextStyle(fontSize: 12, color: AppColors.text3),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const Align(alignment: Alignment.centerLeft, child: Text('快捷提问',
          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9,
            color: AppColors.text3, letterSpacing: 2))),
        const SizedBox(height: 8),
        ...tips.map((tip) => GestureDetector(
          onTap: () => onSuggest(tip),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bg2,
              border: Border.all(color: AppColors.line2)),
            child: Row(children: [
              Expanded(child: Text(tip, style: const TextStyle(
                fontSize: 13, color: AppColors.text2))),
              const Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.text3),
            ]),
          ),
        )),
      ]),
    ));
  }
}

// ════════════════════════════════════════════
// 输入栏
// ════════════════════════════════════════════
class _InputBar extends StatelessWidget {
  const _InputBar({super.key, 
    required this.ctrl,
    required this.streaming,
    required this.onSend,
    required this.onStop,
    required this.bookCount,
  });
  final TextEditingController ctrl;
  final bool      streaming;
  final VoidCallback onSend, onStop;
  final int       bookCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    decoration: const BoxDecoration(
      color: AppColors.bg1,
      border: Border(top: BorderSide(color: AppColors.line1))),
    child: SafeArea(top: false, child: Row(children: [
      Expanded(child: TextField(
        controller: ctrl,
        enabled:    !streaming,
        maxLines:   4, minLines: 1,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: bookCount > 0
            ? '基于书籍档案提问...'
            : '直接提问或选择书籍获得精准建议...',
          hintStyle: const TextStyle(fontSize: 13),
        ),
        onSubmitted: (_) => onSend(),
      )),
      const SizedBox(width: 8),
      if (streaming)
        IconButton.outlined(
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded, color: AppColors.crimson2),
          style: IconButton.styleFrom(
            side: const BorderSide(color: AppColors.crimson2),
            shape: const RoundedRectangleBorder()),
        )
      else
        ElevatedButton(
          onPressed: onSend,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
          child: const Icon(Icons.send_rounded, size: 18),
        ),
    ])),
  );
}
