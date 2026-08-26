import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:share_plus/share_plus.dart';

class ExcerptShareCardScreen extends StatefulWidget {
  const ExcerptShareCardScreen({
    super.key,
    required this.quote,
    required this.book,
    this.note,
  });
  final String quote;
  final String? note;
  final BookRecord? book;
  @override
  State<ExcerptShareCardScreen> createState() => _ExcerptShareCardScreenState();
}

class _ExcerptShareCardScreenState extends State<ExcerptShareCardScreen> {
  final _boundary = GlobalKey();
  _CardTemplate _template = _CardTemplate.leaf;
  String _font = 'serif';
  double _fontSize = 26;
  Color? _foregroundOverride;
  Color? _backgroundOverride;
  Color? _accentOverride;
  Uint8List? _backgroundImage;
  double _imageOpacity = .3;
  bool _busy = false;

  Future<Color?> _chooseColor(String title, Color selected) =>
      showDialog<Color>(
        context: context,
        builder: (context) {
          final strings = AppStrings.of(context);
          return AlertDialog(
            title: Text(title),
            content: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in const [
                  Color(0xff000000),
                  Color(0xffffffff),
                  Color(0xff22452d),
                  Color(0xff6e956f),
                  Color(0xfff5e6c8),
                  Color(0xff8d4e35),
                  Color(0xff1d3557),
                  Color(0xff457b9d),
                  Color(0xff6d597a),
                  Color(0xffe56b6f),
                  Color(0xfff4a261),
                  Color(0xff2a9d8f),
                ])
                  Semantics(
                    label: strings.colorChoice(color),
                    button: true,
                    selected: color == selected,
                    excludeSemantics: true,
                    onTap: () => Navigator.pop(context, color),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, color),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                            width: color == selected ? 4 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Future<void> _pickBackgroundImage() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    final file = picked.singleOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _backgroundImage = bytes);
  }

  Future<Uint8List> _capture() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('无法生成分享卡片。');
    return data.buffer.asUint8List();
  }

  Future<void> _save() async {
    if (_busy) return;
    final strings = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      await FilePicker.saveFile(
        dialogTitle: strings.text('保存书摘卡片'),
        fileName: 'leeef-quote.png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
        bytes: await _capture(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.text('书摘卡片已保存'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    final sourceLabel = AppStrings.of(context).text('摘自');
    setState(() => _busy = true);
    final directory = await Directory.systemTemp.createTemp('leeef-card-');
    try {
      final file = File('${directory.path}/leeef-quote.png');
      await file.writeAsBytes(await _capture());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '$sourceLabel《${widget.book?.title ?? 'Leeef Reader'}》',
        ),
      );
    } finally {
      Future<void>.delayed(const Duration(minutes: 1), () async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = switch (_template) {
      _CardTemplate.leaf => (
        const Color(0xffeaf4e7),
        const Color(0xff22452d),
        const Color(0xff6e956f),
      ),
      _CardTemplate.paper => (
        const Color(0xfffff9ec),
        const Color(0xff3b3126),
        const Color(0xffaa7c48),
      ),
      _CardTemplate.night => (
        const Color(0xff101715),
        const Color(0xffe8f1ed),
        const Color(0xff72b68c),
      ),
    };
    final background = _backgroundOverride ?? colors.$1;
    final foreground = _foregroundOverride ?? colors.$2;
    final accent = _accentOverride ?? colors.$3;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('书摘分享卡片')),
        actions: [
          IconButton(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_alt),
            tooltip: strings.text('保存 PNG'),
          ),
          IconButton(
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.share),
            tooltip: strings.text('系统分享'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: RepaintBoundary(
              key: _boundary,
              child: Container(
                width: 560,
                constraints: const BoxConstraints(minHeight: 420),
                padding: const EdgeInsets.all(44),
                decoration: BoxDecoration(
                  color: background,
                  image: _backgroundImage == null
                      ? null
                      : DecorationImage(
                          image: MemoryImage(_backgroundImage!),
                          fit: BoxFit.cover,
                          opacity: _imageOpacity,
                        ),
                  gradient:
                      _backgroundImage == null &&
                          _backgroundOverride == null &&
                          _template == _CardTemplate.leaf
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colors.$1, const Color(0xffcfe4d1)],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(blurRadius: 18, color: Colors.black26),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.eco, color: accent, size: 34),
                    const SizedBox(height: 34),
                    Text(
                      '“${widget.quote}”',
                      style: TextStyle(
                        color: foreground,
                        fontSize: _fontSize,
                        height: 1.6,
                        fontFamily: _font == 'system' ? null : _font,
                      ),
                    ),
                    if (widget.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          widget.note!,
                          style: TextStyle(
                            color: foreground.withValues(alpha: .75),
                            fontSize: 17,
                          ),
                        ),
                      ),
                    const SizedBox(height: 40),
                    Divider(color: accent),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '《${widget.book?.title ?? strings.text('未知书籍')}》${widget.book?.author == null ? '' : ' · ${widget.book!.author}'}',
                            style: TextStyle(color: foreground, fontSize: 16),
                          ),
                        ),
                        Text(
                          'Leeef Reader',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SegmentedButton<_CardTemplate>(
            segments: [
              ButtonSegment(
                value: _CardTemplate.leaf,
                label: Text(strings.text('叶绿')),
              ),
              ButtonSegment(
                value: _CardTemplate.paper,
                label: Text(strings.text('纸张')),
              ),
              ButtonSegment(
                value: _CardTemplate.night,
                label: Text(strings.text('夜色')),
              ),
            ],
            selected: {_template},
            onSelectionChanged: (value) => setState(() {
              _template = value.single;
              _foregroundOverride = null;
              _backgroundOverride = null;
              _accentOverride = null;
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(width: 60, child: Text(strings.text('字体'))),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _font,
                  items: [
                    DropdownMenuItem(
                      value: 'system',
                      child: Text(strings.text('系统')),
                    ),
                    DropdownMenuItem(
                      value: 'serif',
                      child: Text(strings.text('衬线')),
                    ),
                    DropdownMenuItem(
                      value: 'monospace',
                      child: Text(strings.text('等宽')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _font = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.format_color_text),
                label: Text(strings.text('文字颜色')),
                onPressed: () async {
                  final value = await _chooseColor(
                    strings.text('文字颜色'),
                    foreground,
                  );
                  if (value != null) {
                    setState(() => _foregroundOverride = value);
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.format_color_fill),
                label: Text(strings.text('背景颜色')),
                onPressed: () async {
                  final value = await _chooseColor(
                    strings.text('背景颜色'),
                    background,
                  );
                  if (value != null) {
                    setState(() => _backgroundOverride = value);
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.color_lens_outlined),
                label: Text(strings.text('强调色')),
                onPressed: () async {
                  final value = await _chooseColor(strings.text('强调色'), accent);
                  if (value != null) setState(() => _accentOverride = value);
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  strings.text(_backgroundImage == null ? '背景图片' : '更换图片'),
                ),
                onPressed: _pickBackgroundImage,
              ),
              if (_backgroundImage != null)
                IconButton(
                  tooltip: strings.text('移除背景图片'),
                  onPressed: () => setState(() => _backgroundImage = null),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          if (_backgroundImage != null)
            Row(
              children: [
                SizedBox(width: 60, child: Text(strings.text('图片浓度'))),
                Expanded(
                  child: Slider(
                    value: _imageOpacity,
                    min: .05,
                    max: .85,
                    onChanged: (value) => setState(() => _imageOpacity = value),
                  ),
                ),
              ],
            ),
          Row(
            children: [
              SizedBox(width: 60, child: Text(strings.text('字号'))),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 18,
                  max: 38,
                  onChanged: (value) => setState(() => _fontSize = value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _CardTemplate { leaf, paper, night }
