import 'dart:convert';

class ReadingLocation {
  const ReadingLocation({
    required this.locator,
    required this.progress,
    this.chapterTitle,
    this.page,
  }) : assert(progress >= 0 && progress <= 1);

  factory ReadingLocation.fromJson(Map<String, Object?> json) {
    final progress = (json['progress'] as num).toDouble();
    if (progress < 0 || progress > 1) {
      throw FormatException('Reading progress must be between 0 and 1.');
    }
    return ReadingLocation(
      locator: json['locator']! as String,
      progress: progress,
      chapterTitle: json['chapterTitle'] as String?,
      page: json['page'] as int?,
    );
  }

  final String locator;
  final double progress;
  final String? chapterTitle;
  final int? page;

  Map<String, Object?> toJson() => {
    'locator': locator,
    'progress': progress,
    'chapterTitle': chapterTitle,
    'page': page,
  };

  String encode() => jsonEncode(toJson());
}
