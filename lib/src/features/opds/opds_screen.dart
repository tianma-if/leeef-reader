import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/opds/opds_service.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OpdsScreen extends ConsumerStatefulWidget {
  const OpdsScreen({super.key});
  @override
  ConsumerState<OpdsScreen> createState() => _OpdsScreenState();
}

class _OpdsScreenState extends ConsumerState<OpdsScreen> {
  static const _catalogsKey = 'leeef.opds.catalogs';
  static const _storage = FlutterSecureStorage();
  var _catalogs = <_Catalog>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_catalogsKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as List;
    if (mounted) {
      setState(
        () => _catalogs = decoded
            .map(
              (item) =>
                  _Catalog.fromJson(Map<String, Object?>.from(item as Map)),
            )
            .toList(),
      );
    }
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setString(
        _catalogsKey,
        jsonEncode(_catalogs.map((item) => item.toJson()).toList()),
      );

  Future<void> _add() async {
    final strings = AppStrings.of(context);
    final title = TextEditingController();
    final url = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final result = await showDialog<_Catalog>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('添加 OPDS 目录')),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(labelText: strings.text('名称')),
              ),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'OPDS Feed URL'),
              ),
              TextField(
                controller: username,
                decoration: InputDecoration(labelText: strings.text('用户名（可选）')),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(labelText: strings.text('密码（可选）')),
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
              final uri = Uri.tryParse(url.text.trim());
              if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
              Navigator.pop(
                context,
                _Catalog(
                  title: title.text.trim().isEmpty
                      ? uri.host
                      : title.text.trim(),
                  url: uri.toString(),
                  username: username.text.trim(),
                ),
              );
            },
            child: Text(strings.text('保存')),
          ),
        ],
      ),
    );
    if (result != null) {
      await _storage.write(
        key: 'leeef.opds.password.${result.url}',
        value: password.text,
      );
      setState(() => _catalogs = [..._catalogs, result]);
      await _save();
    }
    title.dispose();
    url.dispose();
    username.dispose();
    password.dispose();
  }

  Future<void> _remove(_Catalog catalog) async {
    await _storage.delete(key: 'leeef.opds.password.${catalog.url}');
    setState(
      () => _catalogs = _catalogs
          .where((item) => item.url != catalog.url)
          .toList(),
    );
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('OPDS 目录')),
        actions: [
          IconButton(
            onPressed: _add,
            icon: const Icon(Icons.add),
            tooltip: strings.text('添加目录'),
          ),
        ],
      ),
      body: _catalogs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.public, size: 56),
                  const SizedBox(height: 12),
                  Text(strings.text('添加 OPDS 目录后即可浏览、搜索和下载')),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: Text(strings.text('添加目录')),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _catalogs.length,
              itemBuilder: (context, index) {
                final catalog = _catalogs[index];
                return ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(catalog.title),
                  subtitle: Text(catalog.url),
                  onTap: () async {
                    final password = await _storage.read(
                      key: 'leeef.opds.password.${catalog.url}',
                    );
                    if (!context.mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            _OpdsBrowser(catalog: catalog, password: password),
                      ),
                    );
                  },
                  trailing: IconButton(
                    onPressed: () => _remove(catalog),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: strings.text('删除目录'),
                  ),
                );
              },
            ),
    );
  }
}

class _OpdsBrowser extends ConsumerStatefulWidget {
  const _OpdsBrowser({required this.catalog, required this.password});
  final _Catalog catalog;
  final String? password;
  @override
  ConsumerState<_OpdsBrowser> createState() => _OpdsBrowserState();
}

class _OpdsBrowserState extends ConsumerState<_OpdsBrowser> {
  final _service = OpdsService();
  final _search = TextEditingController();
  OpdsFeed? _feed;
  Object? _error;
  var _loading = true;
  var _downloading = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load(Uri.parse(widget.catalog.url)));
  }

  @override
  void dispose() {
    _service.close();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(Uri uri, {bool append = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await _service.load(
        uri,
        username: widget.catalog.username,
        password: widget.password,
      );
      if (!mounted) return;
      setState(
        () => _feed = append && _feed != null
            ? OpdsFeed(
                title: _feed!.title,
                entries: [..._feed!.entries, ...next.entries],
                nextUri: next.nextUri,
              )
            : next,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(OpdsEntry entry) async {
    if (entry.navigationUri != null) await _load(entry.navigationUri!);
  }

  Future<void> _download(OpdsEntry entry) async {
    setState(() => _downloading = {..._downloading, entry.id});
    final temporary = await Directory.systemTemp.createTemp('leeef-opds-');
    try {
      final file = await _service.download(
        entry,
        temporary,
        username: widget.catalog.username,
        password: widget.password,
      );
      final importer = await ref.read(bookImportServiceProvider.future);
      final book = await importer.importFile(file);
      if (mounted) {
        final strings = AppStrings.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('《${book.title}》${strings.text('已导入书库')}')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        final strings = AppStrings.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.text('下载失败')}：$error')),
        );
      }
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      if (mounted) {
        setState(() => _downloading = {..._downloading}..remove(entry.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final query = _search.text.trim().toLowerCase();
    final entries = (_feed?.entries ?? const <OpdsEntry>[])
        .where(
          (entry) =>
              query.isEmpty ||
              entry.title.toLowerCase().contains(query) ||
              (entry.author?.toLowerCase().contains(query) ?? false),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(_feed?.title ?? widget.catalog.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              controller: _search,
              hintText: strings.text('搜索当前目录'),
              leading: const Icon(Icons.search),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_error != null)
            MaterialBanner(
              content: Text('${strings.text('目录加载失败')}：$_error'),
              actions: [
                TextButton(
                  onPressed: () => _load(Uri.parse(widget.catalog.url)),
                  child: Text(strings.text('重试')),
                ),
              ],
            ),
          if (_loading && _feed == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.builder(
                itemCount: entries.length + (_feed?.nextUri == null ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index == entries.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () => _load(_feed!.nextUri!, append: true),
                        child: Text(strings.text(_loading ? '加载中…' : '加载下一页')),
                      ),
                    );
                  }
                  final entry = entries[index];
                  final downloading = _downloading.contains(entry.id);
                  return ListTile(
                    leading: Icon(
                      entry.acquisitionUri == null
                          ? Icons.folder_outlined
                          : Icons.book_outlined,
                    ),
                    title: Text(entry.title),
                    subtitle: Text(
                      [
                        entry.author,
                        entry.summary,
                      ].whereType<String>().join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: entry.summary != null,
                    onTap: entry.navigationUri == null
                        ? null
                        : () => _open(entry),
                    trailing: entry.acquisitionUri == null
                        ? const Icon(Icons.chevron_right)
                        : downloading
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            onPressed: () => _download(entry),
                            icon: const Icon(Icons.download),
                            tooltip: strings.text('下载并导入'),
                          ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Catalog {
  const _Catalog({
    required this.title,
    required this.url,
    required this.username,
  });
  final String title;
  final String url;
  final String username;
  Map<String, Object?> toJson() => {
    'title': title,
    'url': url,
    'username': username,
  };
  factory _Catalog.fromJson(Map<String, Object?> json) => _Catalog(
    title: json['title']! as String,
    url: json['url']! as String,
    username: json['username'] as String? ?? '',
  );
}
