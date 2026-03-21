// lib/core/llm/llm_client.dart
// 直连任意 OpenAI 兼容 API，无需中间服务器
import 'dart:async';
import 'dart:isolate';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/statistics_manager.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import '../db/database.dart';

// ── LLM 配置 ─────────────────────────────────
class LlmConfig {
  const LlmConfig({
    required this.agentId,
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.temperature = 0.7,
    this.maxTokens = 4096,
  });
  final String  agentId;
  final String  baseUrl;
  final String  model;
  final String? apiKey;
  final double  temperature;
  final int     maxTokens;

  LlmConfig copyWith({String? apiKey, double? temperature, int? maxTokens}) =>
      LlmConfig(
        agentId:     agentId,
        baseUrl:     baseUrl,
        model:       model,
        apiKey:      apiKey ?? this.apiKey,
        temperature: temperature ?? this.temperature,
        maxTokens:   maxTokens ?? this.maxTokens,
      );

  Map<String, dynamic> toMap() => {
    'agent_id':   agentId,
    'base_url':   baseUrl,
    'model':      model,
    'temperature': temperature,
    'max_tokens': maxTokens,
  };
}

// 预置供应商
class LlmPresets {
  static const providers = [
    ('DeepSeek',   'https://api.deepseek.com/v1',                        'deepseek-chat'),
    ('通义千问',   'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus'),
    ('豆包',       'https://ark.cn-beijing.volces.com/api/v3',           'doubao-pro-128k'),
    ('文心一言',   'https://qianfan.baidubce.com/v2',                    'ernie-4.0-8k'),
    ('MiniMax',    'https://api.minimax.chat/v1',                        'abab6.5s-chat'),
    ('GPT-4o',     'https://api.openai.com/v1',                          'gpt-4o'),
    ('Claude',     'https://api.anthropic.com/v1',                       'claude-3-5-sonnet-20241022'),
    ('Gemini',     'https://generativelanguage.googleapis.com/v1beta/openai/', 'gemini-1.5-pro'),
  ];
}

// ── LLM 客户端（单例）────────────────────────
class LlmClient {
  LlmClient._();
  static final LlmClient instance = LlmClient._();

  // 内存缓存（避免每次调用都读 Keystore 磁盘）
  final _configCache = <String, LlmConfig>{};
  final _keyCache    = <String, String>{};
  void invalidateCache() { _configCache.clear(); _keyCache.clear(); }

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  final _log = Logger();

  // ── 获取 Agent 配置 ──────────────────────
  Future<LlmConfig> getConfig(String agentId) async {
    // 内存缓存命中直接返回
    if (_configCache.containsKey(agentId)) return _configCache[agentId]!;

    final row = await AppDatabase.instance.getLlmConfig(agentId);
    if (row == null) return _defaultConfig(agentId);

    // API Key 从安全存储读取（带内存缓存）
    final key = _keyCache[agentId]
              ?? _keyCache['default']
              ?? await _storage.read(key: 'apikey_$agentId')
              ?? await _storage.read(key: 'apikey_default');
    if (key != null) _keyCache[agentId] = key;

    final config = LlmConfig(
      agentId:     agentId,
      baseUrl:     row['base_url'] as String,
      model:       row['model'] as String,
      apiKey:      key,
      temperature: (row['temperature'] as num).toDouble(),
      maxTokens:   row['max_tokens'] as int,
    );
    _configCache[agentId] = config;
    return config;
  }

  Future<void> saveConfig(LlmConfig cfg, {String? apiKey}) async {
    invalidateCache(); // 配置变更，清空缓存
    await AppDatabase.instance.saveLlmConfig(cfg.toMap());
    if (apiKey != null && apiKey.isNotEmpty) {
      await _storage.write(key: 'apikey_${cfg.agentId}', value: apiKey);
    }
  }

  Future<void> saveDefaultKey(String baseUrl, String apiKey) async {
    await _storage.write(key: 'apikey_default', value: apiKey);
    await AppDatabase.instance.saveDefaultLlm(baseUrl: baseUrl);
  }

  // ── 非流式调用 ───────────────────────────
  Future<LlmResponse> chat(
    String agentId,
    List<Map<String, String>> messages, {
    bool jsonMode = false,
    double? temperature,
  }) async {
    final cfg     = await getConfig(agentId);
    final url     = Uri.parse('${cfg.baseUrl}/chat/completions');
    final headers = _headers(cfg.apiKey, baseUrl: cfg.baseUrl);
    final body    = jsonEncode({
      'model':       cfg.model,
      'messages':    messages,
      'temperature': temperature ?? cfg.temperature,
      'max_tokens':  cfg.maxTokens,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    });

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final resp = await http.post(url, headers: headers, body: body)
            .timeout(const Duration(minutes: 5));

        if (resp.statusCode == 429) {
          if (attempt < 2) {
            await Future.delayed(Duration(seconds: (attempt + 1) * 3));
            continue;
          }
          throw LlmException('请求频率超限（429），请稍后重试');
        }
        if (resp.statusCode != 200) {
          final msg = resp.body.length > 300
              ? resp.body.substring(0, 300) : resp.body;
          throw LlmException('HTTP ${resp.statusCode}: $msg');
        }

        final data    = jsonDecode(resp.body) as Map<String, dynamic>;
        final content = (data['choices'] as List).first['message']['content'] as String;
        final usage   = data['usage'] as Map<String, dynamic>? ?? {};
        final inputT  = usage['prompt_tokens']     as int? ?? 0;
        final outputT = usage['completion_tokens'] as int? ?? 0;
        final tokens  = inputT + outputT;
        // 记录到统计中台
        Future.microtask(() => StatisticsManager.instance.record(
          inputTokens: inputT, outputTokens: outputT, model: cfg.model));
        return LlmResponse(content: content, tokensUsed: tokens);

      } on LlmException {
        rethrow;
      } catch (e) {
        if (attempt == 2) {
          _log.e('LLM [$agentId] 所有重试失败: $e');
          throw LlmException('网络错误: $e');
        }
        _log.w('LLM [$agentId] attempt ${attempt + 1} 失败，重试: $e');
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    throw LlmException('LLM [$agentId] 未知错误');
  }


  // ── 流式调用（SSE）— 加 WakelockPlus 防息屏 + LineSplitter 精确解析
  Stream<String> stream(
    String agentId,
    List<Map<String, String>> messages, {
    double? temperature,
  }) async* {
    final cfg         = await getConfig(agentId);
    final effectiveKey = cfg.apiKey ?? _keyCache['default'];
    if (effectiveKey == null || effectiveKey.isEmpty) {
      throw LlmException('[$agentId] 未配置 API Key，请前往「设置」页面填写');
    }

    // 开启唤醒锁 — 防止 8 分钟长连接期间系统息屏杀后台
    await WakelockPlus.enable();
    int outputTokenCount = 0;

    try {
      final url     = Uri.parse('${cfg.baseUrl}/chat/completions');
      final headers = {
        ..._headers(effectiveKey, baseUrl: cfg.baseUrl),
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      };
      final body = jsonEncode({
        'model':       cfg.model,
        'messages':    messages,
        'temperature': temperature ?? cfg.temperature,
        'max_tokens':  cfg.maxTokens,
        'stream':      true,
        'stream_options': {'include_usage': true},  // 请求最终 Token 统计
      });

      final request = http.Request('POST', url)
        ..headers.addAll(headers)
        ..body = body;

      final response = await request.send()
          .timeout(const Duration(minutes: 10));

      if (response.statusCode != 200) {
        final err = await response.stream.bytesToString();
        throw LlmException('HTTP ${response.statusCode}: ${err.length > 200 ? err.substring(0,200) : err}');
      }

      // 用 LineSplitter 精确按行分割 SSE（比手动 split 更可靠）
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(minutes: 10), onTimeout: (sink) => sink.close())) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        try {
          final json    = jsonDecode(payload) as Map<String, dynamic>;
          // 提取 Token 使用量（流式最后一包）
          final usage   = json['usage'] as Map<String, dynamic>?;
          if (usage != null) {
            final input  = usage['prompt_tokens']     as int? ?? 0;
            final output = usage['completion_tokens'] as int? ?? 0;
            await StatisticsManager.instance.record(
              inputTokens: input, outputTokens: output, model: cfg.model);
          }
          final delta   = (json['choices'] as List?)?.first?['delta'];
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            outputTokenCount++;
            yield content;
          }
        } catch (_) {}
      }
    } catch (e) {
      _log.e('LLM [$agentId] stream error: $e');
      // 记录错误统计
      await StatisticsManager.instance.record(
        inputTokens: 0, outputTokens: outputTokenCount,
        model: cfg.model, isError: true);
      rethrow;
    } finally {
      // 无论成功或失败，务必释放唤醒锁
      await WakelockPlus.disable();
    }
  }

  // ── 连接测试 ─────────────────────────────
  Future<bool> testConnection({
    required String baseUrl,
    required String model,
    required String apiKey,
  }) async {
    try {
      final url  = Uri.parse('$baseUrl/chat/completions');
      final resp = await http.post(url,
        headers: _headers(apiKey.isEmpty ? null : apiKey, baseUrl: baseUrl),
        body: jsonEncode({
          'model': model,
          'messages': [{'role': 'user', 'content': '回复OK'}],
          'max_tokens': 5,
        }),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _headers(String? apiKey, {String? baseUrl}) {
    final isAnthropic = baseUrl != null &&
        baseUrl.contains('anthropic.com');
    return {
      'Content-Type': 'application/json',
      if (apiKey != null && apiKey.isNotEmpty)
        if (isAnthropic) ...{
          'x-api-key':          apiKey,
          'anthropic-version':  '2023-06-01',
        } else
          'Authorization': 'Bearer $apiKey',
    };
  }

  LlmConfig _defaultConfig(String agentId) => LlmConfig(
    agentId:  agentId,
    baseUrl:  'https://api.deepseek.com/v1',
    model:    'deepseek-chat',
    temperature: agentId == 'bingbu' ? 0.85 : 0.3,
  );
}

class LlmResponse {
  const LlmResponse({required this.content, this.tokensUsed = 0});
  final String content;
  final int    tokensUsed;
}

class LlmException implements Exception {
  const LlmException(this.message);
  final String message;
  @override
  String toString() => 'LlmException: $message';
}

// ════════════════════════════════════════════
// 模型自动发现（RikkaHub 式：GET /v1/models）
// ════════════════════════════════════════════
extension LlmModelDiscovery on LlmClient {
  /// 拉取供应商支持的全部模型（OpenAI 标准 /v1/models 接口）
  Future<List<ModelInfo>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    try {
      final url  = Uri.parse('$baseUrl/models');
      final resp = await http.get(url,
        headers: _headers(apiKey.isEmpty ? null : apiKey, baseUrl: baseUrl),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (data['data'] as List? ?? []);
      return list
        .map((m) => ModelInfo.fromJson(m as Map<String, dynamic>))
        .where((m) => m.id.isNotEmpty)
        .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
    } catch (_) {
      return [];
    }
  }
}

class ModelInfo {
  const ModelInfo({
    required this.id,
    this.contextLength,
    this.priceInput,
    this.priceOutput,
    this.owned,
  });
  final String  id;
  final int?    contextLength;
  final double? priceInput;   // 元/1K tokens
  final double? priceOutput;
  final String? owned;

  factory ModelInfo.fromJson(Map<String, dynamic> m) => ModelInfo(
    id:            m['id'] as String? ?? '',
    contextLength: (m['context_length'] ?? m['max_tokens']) as int?,
    priceInput:    (m['pricing']?['input'] as num?)?.toDouble(),
    priceOutput:   (m['pricing']?['output'] as num?)?.toDouble(),
    owned:         m['owned_by'] as String?,
  );

  String get displayName {
    // 常见模型友好名称映射
    const aliases = {
      'deepseek-chat':              'DeepSeek Chat (V3)',
      'deepseek-reasoner':          'DeepSeek R1 推理',
      'deepseek-coder':             'DeepSeek Coder',
      'qwen-plus':                  '通义千问 Plus',
      'qwen-turbo':                 '通义千问 Turbo',
      'qwen-max':                   '通义千问 Max',
      'qwen-long':                  '通义千问 Long (1M ctx)',
      'gpt-4o':                     'GPT-4o',
      'gpt-4o-mini':                'GPT-4o Mini',
      'gpt-4-turbo':                'GPT-4 Turbo',
      'claude-3-5-sonnet-20241022': 'Claude 3.5 Sonnet',
      'claude-3-5-haiku-20241022':  'Claude 3.5 Haiku',
      'gemini-1.5-pro':             'Gemini 1.5 Pro',
      'gemini-1.5-flash':           'Gemini 1.5 Flash',
      'doubao-pro-128k':            '豆包 Pro 128K',
      'doubao-lite-128k':           '豆包 Lite 128K',
    };
    return aliases[id] ?? id;
  }

  String get ctxLabel {
    if (contextLength == null) return '';
    if (contextLength! >= 1000000) return '${(contextLength! / 1000000).toStringAsFixed(0)}M';
    if (contextLength! >= 1000)    return '${(contextLength! / 1000).toStringAsFixed(0)}K';
    return '$contextLength';
  }

  // 估算每章写作成本（约 6000 tokens 输入 + 4000 tokens 输出）
  String get chapterCostEstimate {
    if (priceInput == null || priceOutput == null) return '';
    final cost = priceInput! * 6 + priceOutput! * 4;
    if (cost < 0.001) return '<¥0.01/章';
    if (cost < 0.1)   return '≈¥${cost.toStringAsFixed(3)}/章';
    return '≈¥${cost.toStringAsFixed(2)}/章';
  }
}

// ════════════════════════════════════════════
// Token 成本追踪器
// ════════════════════════════════════════════
class CostTracker {
  CostTracker._();
  static final CostTracker instance = CostTracker._();

  int _totalTokens = 0;
  double _estimatedCost = 0;

  void record(int tokens, {double pricePerK = 0.001}) {
    _totalTokens    += tokens;
    _estimatedCost  += tokens / 1000 * pricePerK;
  }

  int    get totalTokens    => _totalTokens;
  double get estimatedCost  => _estimatedCost;
  String get costLabel      => _estimatedCost < 0.01
    ? '<¥0.01'
    : '≈¥${_estimatedCost.toStringAsFixed(2)}';

  void reset() { _totalTokens = 0; _estimatedCost = 0; }
}
