import 'package:flutter/material.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';

Future<String?> showExcerptDialog(
  BuildContext context, {
  required String quote,
}) async {
  final strings = AppStrings.of(context);
  final controller = TextEditingController();
  final note = await showDialog<String?>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.text('保存书摘')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quote, maxLines: 5, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: strings.text('想法（可选）'),
              border: const OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.text('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(strings.text('保存')),
        ),
      ],
    ),
  );
  controller.dispose();
  return note;
}
