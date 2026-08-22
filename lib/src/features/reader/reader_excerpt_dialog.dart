import 'package:flutter/material.dart';

Future<String?> showExcerptDialog(
  BuildContext context, {
  required String quote,
}) async {
  final controller = TextEditingController();
  final note = await showDialog<String?>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('保存书摘'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quote, maxLines: 5, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '想法（可选）',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return note;
}
