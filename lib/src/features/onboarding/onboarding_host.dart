import 'package:flutter/material.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingHost extends StatefulWidget {
  const OnboardingHost({required this.child, super.key});
  final Widget child;

  @override
  State<OnboardingHost> createState() => _OnboardingHostState();
}

class _OnboardingHostState extends State<OnboardingHost> {
  late final Future<bool> _completed = SharedPreferences.getInstance().then(
    (values) => values.getBool('leeef.onboarding.completed') ?? false,
  );
  bool _done = false;

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _completed,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return snapshot.data! || _done
          ? widget.child
          : _Onboarding(onDone: _finish);
    },
  );

  Future<void> _finish() async {
    await (await SharedPreferences.getInstance()).setBool(
      'leeef.onboarding.completed',
      true,
    );
    if (mounted) setState(() => _done = true);
  }
}

class _Onboarding extends StatefulWidget {
  const _Onboarding({required this.onDone});
  final Future<void> Function() onDone;
  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final _controller = PageController();
  int _page = 0;
  static const _items = [
    (
      Icons.local_library_outlined,
      '把书库带在身边',
      '导入 EPUB、PDF、TXT、MOBI、AZW3 和 FB2，并在四端继续阅读。',
    ),
    (Icons.sync_outlined, '离线优先，安全同步', '阅读进度、书摘、书签、目录与原文件通过增量日志合并。'),
    (
      Icons.auto_awesome_outlined,
      '让 AI 真正理解你的书库',
      '上下文翻译、总结、全文对话，以及经过确认的 MCP 管理操作。',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDone,
                child: Text(strings.text('跳过')),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _items.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Padding(
                    padding: const EdgeInsets.all(36),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.$1,
                          size: 92,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          strings.text(item.$2),
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          strings.text(item.$3),
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton.icon(
                onPressed: _page == _items.length - 1
                    ? widget.onDone
                    : () => _controller.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                      ),
                icon: Icon(
                  _page == _items.length - 1
                      ? Icons.check
                      : Icons.arrow_forward,
                ),
                label: Text(
                  strings.text(_page == _items.length - 1 ? '开始使用' : '下一步'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
