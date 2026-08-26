import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/ai/configured_translation_provider.dart';
import 'package:leeef_reader/src/ai/ai_prompt_registry.dart';
import 'package:leeef_reader/src/ai/ai_tool_registry.dart';
import 'package:leeef_reader/src/ai/full_translation.dart';
import 'package:leeef_reader/src/ai/llm_assistant_provider.dart';
import 'package:leeef_reader/src/ai/llm_translation_provider.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({
    super.key,
    this.title = 'AI 阅读助手',
    this.contextText,
  });
  final String title;
  final String? contextText;
  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final _controller = TextEditingController();
  final _messages = <AiChatMessage>[];
  String _context = '';
  bool _sending = false;
  Object? _error;
  String? _systemPrompt;
  List<AiPrompt> _prompts = AiPromptRegistry.defaults;
  bool _writeToolsEnabled = false;
  AiToolPermissions _toolPermissions = const AiToolPermissions();
  AiToolPlan? _pendingPlan;

  @override
  void initState() {
    super.initState();
    unawaited(_loadContext());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final preferences = await SharedPreferences.getInstance();
    _systemPrompt = preferences.getString(aiAssistantPromptPreferenceKey);
    final libraryEnabled =
        preferences.getBool(aiLibraryToolPreferenceKey) ?? true;
    final notesEnabled = preferences.getBool(aiNotesToolPreferenceKey) ?? true;
    final historyEnabled =
        preferences.getBool(aiHistoryToolPreferenceKey) ?? true;
    _writeToolsEnabled =
        preferences.getBool(aiWriteToolsPreferenceKey) ?? false;
    _toolPermissions = AiToolPermissions(
      library: libraryEnabled,
      notes: notesEnabled,
      history: historyEnabled,
      write: _writeToolsEnabled,
    );
    _systemPrompt =
        '${_systemPrompt ?? ''}\n\n${AiToolRegistry.systemInstructions(_toolPermissions)}';
    _prompts = await const AiPromptRegistry().load();
    if (widget.contextText != null) {
      if (mounted) setState(() => _context = widget.contextText!);
      return;
    }
    final repository = await ref.read(libraryRepositoryProvider.future);
    final context = StringBuffer();
    if (libraryEnabled) {
      final books = await repository.listBooks();
      context.writeln('书库共有 ${books.length} 本书。');
      for (final book in books.take(100)) {
        context.writeln(
          '- id=${book.id}；${book.title}${book.author == null ? '' : ' / ${book.author}'}，评分 ${book.rating ?? '未评分'}',
        );
      }
      final shelves = await repository.watchBookshelves().first;
      context.writeln('\n书架目录：');
      for (final shelf in shelves) {
        context.writeln(
          '- id=${shelf.id}；${shelf.name}；parentId=${shelf.parentId ?? 'root'}',
        );
      }
    }
    if (notesEnabled) {
      final excerpts = await repository.listExcerpts();
      context.writeln('\n最近书摘：');
      for (final excerpt in excerpts.reversed.take(50)) {
        context.writeln(
          '- id=${excerpt.id}；bookId=${excerpt.bookId}；locator=${excerpt.locator}；${excerpt.quote}${excerpt.note == null ? '' : '（${excerpt.note}）'}',
        );
      }
    }
    if (historyEnabled) {
      final sessions = await repository.watchReadingSessions().first;
      context.writeln('\n最近阅读记录：');
      for (final session in sessions.take(30)) {
        context.writeln(
          '- ${session.bookId}：${session.startedAt.toLocal()}，${session.durationSeconds} 秒',
        );
      }
    }
    if (mounted) setState(() => _context = context.toString());
  }

  Future<void> _send([String? prompt]) async {
    final text = (prompt ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(AiChatMessage(role: 'user', content: text));
      _controller.clear();
      _sending = true;
      _error = null;
    });
    LlmAssistantProvider? provider;
    try {
      provider = await loadConfiguredAssistantProvider();
      var workingMessages = List<AiChatMessage>.from(_messages);
      var answer = await provider.complete(
        messages: _messages,
        context: _context,
        systemPrompt: _systemPrompt,
      );
      AiToolPlan? plan;
      for (var toolRound = 0; toolRound < 4; toolRound++) {
        plan = AiToolPlan.parse(answer);
        if (plan == null) break;
        if (!_toolPermissions.allows(plan)) {
          throw StateError('AI 请求了已关闭的工具：${plan.tool}');
        }
        if (!plan.isReadOnly) break;
        if (toolRound == 3) {
          throw StateError('AI 连续请求工具次数过多，请缩小问题范围后重试。');
        }
        final result = await const AiToolRegistry().executeRead(
          plan,
          await ref.read(libraryRepositoryProvider.future),
        );
        workingMessages = [
          ...workingMessages,
          AiChatMessage(role: 'assistant', content: answer),
          AiChatMessage(
            role: 'user',
            content:
                'Leeef tool result for ${plan.tool}: ${jsonEncode(result)}\nUse this result to continue answering. Call another read tool only if required.',
          ),
        ];
        answer = await provider.complete(
          messages: workingMessages,
          context: _context,
          systemPrompt: _systemPrompt,
        );
      }
      if (mounted) {
        setState(() {
          _pendingPlan = plan?.isReadOnly == false ? plan : null;
          final visible = plan == null
              ? answer
              : answer
                    .replaceAll(
                      RegExp(
                        r'```leeef-tool\s*[\s\S]*?```',
                        caseSensitive: false,
                      ),
                      '',
                    )
                    .trim();
          _messages.add(
            AiChatMessage(
              role: 'assistant',
              content: visible.isEmpty ? '已生成待确认的整理计划。' : visible,
            ),
          );
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      provider?.close();
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reviewAndApplyPlan() async {
    final plan = _pendingPlan;
    if (plan == null || _sending) return;
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('确认 AI 整理计划')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              '${plan.summary}\n\n工具：${plan.tool}\n参数：\n${const JsonEncoder.withIndent('  ').convert(plan.arguments)}',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.text('确认执行')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sending = true);
    try {
      final result = await const AiToolRegistry().execute(
        plan,
        await ref.read(libraryRepositoryProvider.future),
      );
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(allExcerptsProvider);
      ref.invalidate(bookshelvesProvider);
      if (mounted) {
        setState(() {
          _pendingPlan = null;
          _messages.add(
            AiChatMessage(
              role: 'assistant',
              content: '计划已执行：${jsonEncode(result)}',
            ),
          );
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title == 'AI 阅读助手' ? strings.text('AI 阅读助手') : widget.title,
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final chat = Column(
            children: [
              if (_messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final prompt in _prompts)
                        ActionChip(
                          label: Text(
                            prompt.builtIn
                                ? strings.text(prompt.title)
                                : prompt.title,
                          ),
                          onPressed: () => _send(prompt.content),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final mine = message.role == 'user';
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 680),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(message.content),
                      ),
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '${strings.text('请求失败')}：$_error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_pendingPlan case final plan?)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.rule_folder_outlined),
                    title: Text(strings.text('待确认的 AI 整理计划')),
                    subtitle: Text(plan.summary),
                    trailing: FilledButton.tonal(
                      onPressed: _sending ? null : _reviewAndApplyPlan,
                      child: Text(strings.text('审阅并执行')),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: strings.text('询问当前书籍或整个书库…'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 900) return chat;
          return Row(
            children: [
              Expanded(flex: 2, child: chat),
              VerticalDivider(width: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.text('当前上下文'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _context.isEmpty ? strings.text('正在载入…') : _context,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class FullTranslationScreen extends StatefulWidget {
  const FullTranslationScreen({
    super.key,
    required this.title,
    required this.sourceText,
  });
  final String title;
  final String sourceText;
  @override
  State<FullTranslationScreen> createState() => _FullTranslationScreenState();
}

class _FullTranslationScreenState extends State<FullTranslationScreen> {
  final _glossary = TextEditingController();
  LlmTranslationProvider? _provider;
  FullTranslationController? _translation;
  TranslationDisplayMode _mode = TranslationDisplayMode.bilingual;
  String _target = '简体中文';
  String _output = '';
  double _progress = 0;
  bool _running = false;
  Object? _error;

  @override
  void dispose() {
    _translation?.cancel();
    _provider?.close();
    _glossary.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _translation?.cancel();
    _provider?.close();
    setState(() {
      _running = true;
      _error = null;
      _output = '';
      _progress = 0;
    });
    try {
      _provider = await loadConfiguredTranslationProvider();
      _translation = FullTranslationController(provider: _provider!);
      final glossary = <String, String>{};
      for (final line in _glossary.text.split('\n')) {
        final parts = line.split(RegExp(r'\s*(?:=|→)\s*'));
        if (parts.length >= 2 && parts.first.isNotEmpty) {
          glossary[parts.first] = parts.sublist(1).join('=');
        }
      }
      final result = await _translation!.translate(
        text: widget.sourceText,
        targetLanguage: _target,
        mode: _mode,
        glossary: glossary,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _output = progress.output;
              _progress = progress.fraction;
            });
          }
        },
      );
      if (mounted) setState(() => _output = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} · ${strings.text('全文翻译')}'),
        actions: [
          IconButton(
            onPressed: _output.isEmpty
                ? null
                : () => Clipboard.setData(ClipboardData(text: _output)),
            icon: const Icon(Icons.copy),
            tooltip: strings.text('复制结果'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _target,
                  items: const ['简体中文', '繁體中文', 'English', '日本語']
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: _running
                      ? null
                      : (value) => setState(() => _target = value!),
                ),
                SegmentedButton<TranslationDisplayMode>(
                  segments: [
                    ButtonSegment(
                      value: TranslationDisplayMode.translated,
                      label: Text(strings.text('译文')),
                    ),
                    ButtonSegment(
                      value: TranslationDisplayMode.bilingual,
                      label: Text(strings.text('双语')),
                    ),
                    ButtonSegment(
                      value: TranslationDisplayMode.original,
                      label: Text(strings.text('原文')),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _running
                      ? null
                      : (value) => setState(() => _mode = value.single),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _glossary,
                    enabled: !_running,
                    decoration: InputDecoration(
                      labelText: strings.text('术语表：原词 = 译词（每行一条）'),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _running ? () => _translation?.cancel() : _start,
                  icon: Icon(_running ? Icons.stop : Icons.translate),
                  label: Text(strings.text(_running ? '取消' : '开始翻译')),
                ),
              ],
            ),
          ),
          if (_running || _progress > 0)
            LinearProgressIndicator(value: _progress),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('${strings.text('翻译失败')}：$_error'),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                _output.isEmpty
                    ? strings.fullTranslationIntro(widget.sourceText.length)
                    : _output,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
