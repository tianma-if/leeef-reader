import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leeef_reader/src/ai/configured_translation_provider.dart';
import 'package:leeef_reader/src/ai/llm_translation_provider.dart';
import 'package:leeef_reader/src/ai/translation_provider.dart';

Future<void> showTranslationSheet(
  BuildContext context, {
  required String text,
  required String contextText,
}) async {
  if (text.trim().isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) =>
        _TranslationResult(text: text, contextText: contextText),
  );
}

class _TranslationResult extends StatefulWidget {
  const _TranslationResult({required this.text, required this.contextText});

  final String text;
  final String contextText;

  @override
  State<_TranslationResult> createState() => _TranslationResultState();
}

class _TranslationResultState extends State<_TranslationResult> {
  String _targetLanguage = '简体中文';
  String? _translation;
  Object? _error;
  bool _loading = true;
  TranslationCancellationToken? _cancellationToken;

  @override
  void initState() {
    super.initState();
    _translate();
  }

  Future<void> _translate() async {
    _cancellationToken?.cancel();
    final cancellationToken = TranslationCancellationToken();
    _cancellationToken = cancellationToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    LlmTranslationProvider? provider;
    try {
      provider = await loadConfiguredTranslationProvider();
      final result = await provider.translate(
        TranslationRequest(
          text: widget.text,
          context: widget.contextText,
          targetLanguage: _targetLanguage,
        ),
        cancellationToken: cancellationToken,
      );
      if (mounted) setState(() => _translation = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      provider?.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cancellationToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('AI 上下文翻译', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              DropdownButton<String>(
                value: _targetLanguage,
                items: const [
                  DropdownMenuItem(value: '简体中文', child: Text('简体中文')),
                  DropdownMenuItem(value: '繁體中文', child: Text('繁體中文')),
                  DropdownMenuItem(value: 'English', child: Text('English')),
                  DropdownMenuItem(value: '日本語', child: Text('日本語')),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        _targetLanguage = value;
                        _translate();
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(widget.text, maxLines: 4, overflow: TextOverflow.ellipsis),
          const Divider(height: 28),
          if (_loading)
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  TextButton(
                    onPressed: () => _cancellationToken?.cancel(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            )
          else if (_error case final error?) ...[
            Text('翻译失败：$error'),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: _translate, child: const Text('重试')),
          ] else if (_translation case final translation?) ...[
            SelectableText(translation),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '复制译文',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: translation)),
                icon: const Icon(Icons.copy),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
