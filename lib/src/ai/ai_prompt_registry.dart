import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AiPrompt {
  const AiPrompt({
    required this.id,
    required this.title,
    required this.content,
    required this.builtIn,
  });

  final String id;
  final String title;
  final String content;
  final bool builtIn;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'builtIn': builtIn,
  };

  factory AiPrompt.fromJson(Map<String, dynamic> json) => AiPrompt(
    id: json['id'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    builtIn: json['builtIn'] == true,
  );
}

class AiPromptRegistry {
  const AiPromptRegistry();

  static const _key = 'leeef.ai.prompt_registry';
  static const defaults = [
    AiPrompt(
      id: 'summary',
      title: '章节总结',
      content: '总结当前上下文，列出核心观点和关键细节。',
      builtIn: true,
    ),
    AiPrompt(
      id: 'book-summary',
      title: '全书总结',
      content: '总结整本书的结构、核心主题、关键论点或情节，并给出值得回顾的章节。',
      builtIn: true,
    ),
    AiPrompt(
      id: 'recap',
      title: '回顾前文',
      content: '帮我回顾前文，说明人物、概念和未解决的问题。',
      builtIn: true,
    ),
    AiPrompt(
      id: 'analysis',
      title: '深入分析',
      content: '分析当前内容的论证、主题、隐含假设和可能的不同解释。',
      builtIn: true,
    ),
    AiPrompt(
      id: 'mind-map',
      title: '思维导图',
      content: '用缩进式 Markdown 生成一份思维导图。',
      builtIn: true,
    ),
  ];

  Future<List<AiPrompt>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return defaults;
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((item) => AiPrompt.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on Object {
      return defaults;
    }
  }

  Future<void> save(List<AiPrompt> prompts) async {
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(prompts.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> reset() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}
