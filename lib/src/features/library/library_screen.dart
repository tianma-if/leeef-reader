import 'package:flutter/material.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;
        final content = const _EmptyLibrary();

        if (!useRail) {
          return Scaffold(
            appBar: AppBar(title: const Text('书库')),
            body: content,
            floatingActionButton: FloatingActionButton.extended(
              onPressed: null,
              icon: const Icon(Icons.add),
              label: const Text('导入书籍'),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: 0,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.local_library_outlined),
                  selectedIcon: Icon(Icons.local_library),
                  label: '书库',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.edit_note_outlined),
                  label: '笔记',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: '设置',
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: 0,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  const NavigationRailDestination(
                    icon: Icon(Icons.local_library_outlined),
                    selectedIcon: Icon(Icons.local_library),
                    label: Text('书库'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.edit_note_outlined),
                    label: Text('笔记'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    label: Text('设置'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Scaffold(
                  appBar: AppBar(title: const Text('书库')),
                  body: content,
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: null,
                    icon: const Icon(Icons.add),
                    label: const Text('导入书籍'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text('开始你的书库', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '导入 EPUB、PDF 或 TXT。阅读数据会先保存在本地，联网后再安全同步。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
