import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/ai/ai_prompt_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('prompt registry supplies defaults and persists user edits', () async {
    SharedPreferences.setMockInitialValues({});
    const registry = AiPromptRegistry();

    final defaults = await registry.load();
    expect(defaults, hasLength(5));
    expect(defaults.every((item) => item.builtIn), isTrue);

    final customized = [
      ...defaults,
      const AiPrompt(
        id: 'custom',
        title: '人物关系',
        content: '整理人物关系并引用依据。',
        builtIn: false,
      ),
    ];
    await registry.save(customized);
    final restored = await registry.load();
    expect(restored.last.title, '人物关系');
    expect(restored.last.builtIn, isFalse);

    await registry.reset();
    expect(await registry.load(), hasLength(5));
  });
}
