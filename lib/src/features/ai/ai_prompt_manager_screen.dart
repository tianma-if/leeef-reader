import 'package:flutter/material.dart';
import 'package:leeef_reader/src/ai/ai_prompt_registry.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:uuid/uuid.dart';

class AiPromptManagerScreen extends StatefulWidget {
  const AiPromptManagerScreen({super.key});

  @override
  State<AiPromptManagerScreen> createState() => _AiPromptManagerScreenState();
}

class _AiPromptManagerScreenState extends State<AiPromptManagerScreen> {
  static const _registry = AiPromptRegistry();
  List<AiPrompt>? _prompts;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final prompts = await _registry.load();
    if (mounted) setState(() => _prompts = prompts);
  }

  Future<void> _edit([AiPrompt? original]) async {
    final strings = AppStrings.of(context);
    final title = TextEditingController(text: original?.title);
    final content = TextEditingController(text: original?.content);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.text(original == null ? '添加用户 Prompt' : '编辑 Prompt'),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: InputDecoration(labelText: strings.text('名称')),
              ),
              TextField(
                controller: content,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: strings.text('Prompt 内容'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.text('取消')),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty || content.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, (title.text.trim(), content.text.trim()));
            },
            child: Text(strings.text('保存')),
          ),
        ],
      ),
    );
    title.dispose();
    content.dispose();
    if (result == null) return;
    final prompts = [...?_prompts];
    final updated = AiPrompt(
      id: original?.id ?? const Uuid().v4(),
      title: result.$1,
      content: result.$2,
      builtIn: original?.builtIn ?? false,
    );
    final index = prompts.indexWhere((item) => item.id == updated.id);
    if (index < 0) {
      prompts.add(updated);
    } else {
      prompts[index] = updated;
    }
    await _registry.save(prompts);
    if (mounted) setState(() => _prompts = prompts);
  }

  Future<void> _delete(AiPrompt prompt) async {
    final prompts = [...?_prompts]..removeWhere((item) => item.id == prompt.id);
    await _registry.save(prompts);
    if (mounted) setState(() => _prompts = prompts);
  }

  Future<void> _reset() async {
    await _registry.reset();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('Prompt 管理')),
        actions: [
          IconButton(
            tooltip: strings.text('恢复内置 Prompt'),
            onPressed: _reset,
            icon: const Icon(Icons.restore),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: Text(strings.text('添加 Prompt')),
      ),
      body: _prompts == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: _prompts!.length,
              itemBuilder: (context, index) {
                final prompt = _prompts![index];
                return ListTile(
                  leading: Icon(
                    prompt.builtIn ? Icons.auto_awesome : Icons.person,
                  ),
                  title: Text(prompt.title),
                  subtitle: Text(
                    prompt.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _edit(prompt),
                  trailing: prompt.builtIn
                      ? const Icon(Icons.edit_outlined)
                      : IconButton(
                          tooltip: strings.text('删除'),
                          onPressed: () => _delete(prompt),
                          icon: const Icon(Icons.delete_outline),
                        ),
                );
              },
            ),
    );
  }
}
