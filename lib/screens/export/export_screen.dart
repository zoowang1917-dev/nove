// lib/screens/export/export_screen.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/db/database.dart';
import '../../providers/providers.dart';
import '../../widgets/common/widgets.dart';
import '../../core/utils/extensions.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key, required this.bookId});
  final String bookId;
  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _exporting = false;
  String? _lastPath;
  String _filter = 'all'; // all | approved | pending

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(bookDetailProvider(widget.bookId));
    final chapters  = ref.watch(chaptersProvider(widget.bookId));

    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(title: const Text('导出')),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // 书籍信息卡
        bookAsync.when(
          data: (book) => book == null
            ? const SizedBox()
            : Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bg2,
                  border: Border.all(color: AppColors.line2),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(book.title, style: const TextStyle(
                    fontFamily: 'NotoSerifSC', fontSize: 18,
                    fontWeight: FontWeight.w700, color: AppColors.text1)),
                  const SizedBox(height: 6),
                  Text(
                    '${book.currentChapter} 章 · ${book.totalWords.wordCountLabel}',
                    style: const TextStyle(fontFamily: 'JetBrainsMono',
                      fontSize: 11, color: AppColors.text3),
                  ),
                ]),
              ),
          loading: () => const SizedBox(),
          error:   (_, __) => const SizedBox(),
        ),
        const SizedBox(height: 20),

        // 导出范围
        const SectionLabel('导出范围'),
        const SizedBox(height: 8),
        chapters.when(
          data: (list) {
            final filtered = _getFiltered(list);
            return Column(children: [
              _FilterChip('全部章节', 'all', list.length),
              _FilterChip('已通过审核', 'approved',
                list.where((c) => c.status == 'approved').length),
              _FilterChip('包含待审章节', 'pending',
                list.where((c) => c.status != 'approved').length),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                color: AppColors.bg3,
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.text3),
                  const SizedBox(width: 8),
                  Text('将导出 ${filtered.length} 章 · 约 ${_totalWords(filtered).wordCountLabel}',
                    style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                ]),
              ),
            ]);
          },
          loading: () => const LoadingShimmer(count: 2),
          error:   (e, _) => EmptyState(icon: Icons.error_outline, title: '$e'),
        ),
        const SizedBox(height: 24),

        // 导出格式
        const SectionLabel('导出格式'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.goldDim,
            border: Border.all(color: AppColors.gold.withOpacity(.4)),
          ),
          child: const Row(children: [
            Text('📄', style: TextStyle(fontSize: 20)),
            SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('纯文本 TXT', style: TextStyle(fontSize: 13, color: AppColors.text1)),
              Text('UTF-8 编码，可直接投稿', style: TextStyle(fontSize: 11, color: AppColors.text3)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),

        // 导出按钮
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _exporting ? null : () => _export(context),
            icon: _exporting
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg0))
              : const Icon(Icons.file_download_outlined, size: 18),
            label: Text(_exporting ? '导出中...' : '导出 TXT'),
          ),
        ),

        // 已导出文件
        if (_lastPath != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.jadeDim,
              border: Border.all(color: AppColors.jade2.withOpacity(.4)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_outline, color: AppColors.jade2, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '已保存到：$_lastPath',
                style: const TextStyle(fontSize: 12, color: AppColors.jade2),
              )),
              TextButton(
                onPressed: _share,
                child: const Text('分享', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  List<dynamic> _getFiltered(List chapters) => switch (_filter) {
    'approved' => chapters.where((c) => c.status == 'approved').toList(),
    'pending'  => chapters.where((c) => c.status != 'approved').toList(),
    _          => chapters,
  };

  int _totalWords(List chapters) {
    int total = 0;
    for (final c in chapters) total += (c.wordCount as int? ?? 0);
    return total;
  }

  Widget _FilterChip(String label, String value, int count) =>
    GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:  _filter == value ? AppColors.goldDim : AppColors.bg2,
          border: Border.all(color: _filter == value ? AppColors.gold : AppColors.line2),
        ),
        child: Row(children: [
          Icon(
            _filter == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 16,
            color: _filter == value ? AppColors.gold2 : AppColors.text3,
          ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
            fontSize: 13,
            color: _filter == value ? AppColors.text1 : AppColors.text2,
          )),
          const Spacer(),
          Text('$count 章', style: const TextStyle(
            fontFamily: 'JetBrainsMono', fontSize: 10, color: AppColors.text3)),
        ]),
      ),
    );

  Future<void> _export(BuildContext context) async {
    setState(() => _exporting = true);
    try {
      final db      = AppDatabase.instance;
      final book    = await db.getBook(widget.bookId);
      final rows    = await db.getChapters(widget.bookId);

      // 过滤
      final chapters = switch (_filter) {
        'approved' => rows.where((r) => r['status'] == 'approved').toList(),
        'pending'  => rows.where((r) => r['status'] != 'approved').toList(),
        _          => rows,
      };

      if (chapters.isEmpty) {
        if (mounted) context.showError('没有可导出的章节');
        return;
      }

      // 拼装文本
      final title  = book?['title'] as String? ?? '未知书名';
      final buffer = StringBuffer();
      buffer.writeln(title);
      buffer.writeln('=' * 20);
      buffer.writeln();

      for (final ch in chapters) {
        final chTitle   = ch['title'] as String? ?? '第${ch['chapter_no']}章';
        final content   = ch['content'] as String? ?? '';
        buffer.writeln(chTitle);
        buffer.writeln();
        buffer.writeln(content);
        buffer.writeln();
        buffer.writeln();
      }

      // 保存文件
      final dir  = await getApplicationDocumentsDirectory();
      final safe = title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final file = File('${dir.path}/${safe}_export.txt');
      await file.writeAsString(buffer.toString(), encoding: utf8);

      setState(() => _lastPath = file.path);
      if (mounted) context.showSuccess('导出成功，共 ${chapters.length} 章');
    } catch (e) {
      if (mounted) context.showError('导出失败: $e');
    } finally {
      setState(() => _exporting = false);
    }
  }

  Future<void> _share() async {
    if (_lastPath == null) return;
    await Share.shareXFiles([XFile(_lastPath!)], subject: '小说导出');
  }
}

