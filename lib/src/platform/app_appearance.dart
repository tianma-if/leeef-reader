import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppAppearanceController extends ChangeNotifier {
  AppAppearanceController._();
  static final instance = AppAppearanceController._();
  Locale? locale;
  ThemeMode themeMode = ThemeMode.system;
  Color seedColor = const Color(0xFF356A45);
  Set<String> visibleNavigation = {
    'library',
    'notes',
    'search',
    'statistics',
    'settings',
  };
  String shelfStyle = 'comfortable';
  BoxFit coverFit = BoxFit.cover;

  Future<void> load() async {
    final values = await SharedPreferences.getInstance();
    final language = values.getString('leeef.appearance.locale');
    locale = language == null || language == 'system' ? null : Locale(language);
    themeMode = ThemeMode.values.firstWhere(
      (item) => item.name == values.getString('leeef.appearance.theme_mode'),
      orElse: () => ThemeMode.system,
    );
    seedColor = Color(
      values.getInt('leeef.appearance.seed_color') ?? 0xFF356A45,
    );
    visibleNavigation =
        (values.getStringList('leeef.appearance.navigation') ??
                ['library', 'notes', 'search', 'statistics', 'settings'])
            .toSet()
          ..addAll(const ['library', 'settings']);
    shelfStyle =
        values.getString('leeef.appearance.shelf_style') ?? 'comfortable';
    coverFit = values.getString('leeef.appearance.cover_fit') == 'contain'
        ? BoxFit.contain
        : BoxFit.cover;
    notifyListeners();
  }

  Future<void> setLocale(String language) async {
    locale = language == 'system' ? null : Locale(language);
    await (await SharedPreferences.getInstance()).setString(
      'leeef.appearance.locale',
      language,
    );
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await (await SharedPreferences.getInstance()).setString(
      'leeef.appearance.theme_mode',
      value.name,
    );
    notifyListeners();
  }

  Future<void> setSeedColor(Color value) async {
    seedColor = value;
    await (await SharedPreferences.getInstance()).setInt(
      'leeef.appearance.seed_color',
      value.toARGB32(),
    );
    notifyListeners();
  }

  Future<void> setNavigationVisible(String section, bool visible) async {
    if (visible) {
      visibleNavigation.add(section);
    } else if (section != 'library' && section != 'settings') {
      visibleNavigation.remove(section);
    }
    await (await SharedPreferences.getInstance()).setStringList(
      'leeef.appearance.navigation',
      visibleNavigation.toList(),
    );
    notifyListeners();
  }

  Future<void> setShelfStyle(String value) async {
    shelfStyle = value;
    await (await SharedPreferences.getInstance()).setString(
      'leeef.appearance.shelf_style',
      value,
    );
    notifyListeners();
  }

  Future<void> setCoverFit(BoxFit value) async {
    coverFit = value;
    await (await SharedPreferences.getInstance()).setString(
      'leeef.appearance.cover_fit',
      value == BoxFit.contain ? 'contain' : 'cover',
    );
    notifyListeners();
  }
}

class AppStrings {
  AppStrings(this.locale);
  final Locale locale;
  bool get _english => locale.languageCode == 'en';
  bool get _japanese => locale.languageCode == 'ja';
  static const _englishText = <String, String>{
    '跳过': 'Skip',
    '开始使用': 'Get started',
    '下一步': 'Next',
    '把书库带在身边': 'Take your library anywhere',
    '导入 EPUB、PDF、TXT、MOBI、AZW3 和 FB2，并在四端继续阅读。':
        'Import EPUB, PDF, TXT, MOBI, AZW3, and FB2, then keep reading across all four platforms.',
    '离线优先，安全同步': 'Offline first, safely synced',
    '阅读进度、书摘、书签、目录与原文件通过增量日志合并。':
        'Reading progress, excerpts, bookmarks, shelves, and original files merge through incremental logs.',
    '让 AI 真正理解你的书库': 'Let AI truly understand your library',
    '上下文翻译、总结、全文对话，以及经过确认的 MCP 管理操作。':
        'Contextual translation, summaries, full-text chat, and confirmed MCP management actions.',
    'AI 阅读助手': 'AI Reading Assistant',
    '章节总结': 'Chapter summary',
    '全书总结': 'Book summary',
    '回顾前文': 'Recap',
    '深入分析': 'Deep analysis',
    '思维导图': 'Mind map',
    '当前上下文': 'Current context',
    '正在载入…': 'Loading…',
    '询问当前书籍或整个书库…': 'Ask about this book or your whole library…',
    '请求失败': 'Request failed',
    '待确认的 AI 整理计划': 'AI organization plan awaiting confirmation',
    '审阅并执行': 'Review and apply',
    '确认 AI 整理计划': 'Confirm AI organization plan',
    '取消': 'Cancel',
    '确认执行': 'Confirm and apply',
    '阶段汇总': 'Period summary',
    '阅读时长': 'Reading time',
    '阅读天数': 'Reading days',
    '连续阅读': 'Reading streak',
    '阅读书籍': 'Books read',
    '书摘笔记': 'Notes and excerpts',
    '已读完': 'Finished',
    '近 7 日': 'Last 7 days',
    '近 30 日': 'Last 30 days',
    '周': 'Week',
    '月': 'Month',
    '年': 'Year',
    '全部': 'All',
    '设置': 'Settings',
    '语言': 'Language',
    '界面语言': 'Interface language',
    '明暗主题': 'Appearance',
    '浅色': 'Light',
    '深色': 'Dark',
    '主题色': 'Accent color',
    '导航与书架外观': 'Navigation and library appearance',
    '笔记': 'Notes',
    '统计': 'Statistics',
    '显示': 'Show ',
    '栏目': ' section',
    '跟随系统': 'System default',
    '简体中文': 'Simplified Chinese',
    '英语': 'English',
    '日语': 'Japanese',
    '完成': 'Done',
    '关闭': 'Close',
    '保存': 'Save',
    '应用': 'Apply',
    '删除': 'Delete',
    '编辑': 'Edit',
    '搜索': 'Search',
    '搜索书名、作者、书摘、笔记和书签':
        'Search titles, authors, excerpts, notes, and bookmarks',
    '输入关键词搜索整个书库': 'Enter keywords to search your library',
    '没有找到匹配内容': 'No matching content',
    '书籍': 'Books',
    '书摘与笔记': 'Excerpts and notes',
    '书签': 'Bookmarks',
    '书摘': 'Excerpt',
    '未知作者': 'Unknown author',
    '未知书籍': 'Unknown book',
    '未命名书签': 'Untitled bookmark',
    '请先下载这本书': 'Download this book first',
    '新建书架': 'New shelf',
    '所有标签': 'All tags',
    '管理标签': 'Manage tags',
    '全部状态': 'All statuses',
    '未开始': 'Not started',
    '阅读中': 'Reading',
    '最近更新': 'Recently updated',
    '标题': 'Title',
    '作者': 'Author',
    '阅读进度': 'Reading progress',
    '导入时间': 'Import date',
    '评分': 'Rating',
    '没有符合当前筛选条件的书籍。': 'No books match the current filters.',
    '开始你的书库': 'Start your library',
    '导入 EPUB、MOBI、AZW3、FB2、PDF 或 TXT。阅读进度和书摘会先保存在本地，联网后再安全同步。':
        'Import EPUB, MOBI, AZW3, FB2, PDF, or TXT. Progress and excerpts stay local first, then sync safely when online.',
    '导出': 'Export',
    '复制 Markdown': 'Copy Markdown',
    '导出 Markdown': 'Export Markdown',
    '导出 TXT': 'Export TXT',
    '导出 CSV': 'Export CSV',
    '按书合并章节导出': 'Export merged by book and chapter',
    '选中书中文字可创建书摘，阅读时也可添加书签。':
        'Select text in a book to create an excerpt, or add bookmarks while reading.',
    '全部书籍': 'All books',
    '全部类型': 'All types',
    '有笔记': 'With notes',
    '仅书摘': 'Excerpts only',
    '全部颜色': 'All colors',
    '黄色': 'Yellow',
    '绿色': 'Green',
    '蓝色': 'Blue',
    '粉色': 'Pink',
    '紫色': 'Purple',
    '棕色': 'Brown',
    '灰蓝': 'Blue gray',
    '最新优先': 'Newest first',
    '最早优先': 'Oldest first',
    '按书与章节': 'By book and chapter',
    '添加 OPDS 目录': 'Add OPDS catalog',
    '名称': 'Name',
    '用户名（可选）': 'Username (optional)',
    '密码（可选）': 'Password (optional)',
    'OPDS 目录': 'OPDS catalogs',
    '添加目录': 'Add catalog',
    '删除目录': 'Delete catalog',
    '添加 OPDS 目录后即可浏览、搜索和下载':
        'Add an OPDS catalog to browse, search, and download books.',
    '搜索当前目录': 'Search this catalog',
    '目录加载失败': 'Could not load catalog',
    '重试': 'Retry',
    '加载中…': 'Loading…',
    '加载下一页': 'Load next page',
    '下载并导入': 'Download and import',
    '已导入书库': 'Imported into library',
    '下载失败': 'Download failed',
    '系统朗读': 'System narration',
    '当前页面没有可朗读文字': 'No readable text on this page',
    '上一句': 'Previous sentence',
    '下一句': 'Next sentence',
    '暂停': 'Pause',
    '播放': 'Play',
    '停止': 'Stop',
    '语速': 'Rate',
    '音调': 'Pitch',
    '音量': 'Volume',
    '声音': 'Voice',
    '系统声音': 'System voice',
    '15 分钟后停止': 'Stop after 15 minutes',
    '30 分钟后停止': 'Stop after 30 minutes',
    '取消定时': 'Cancel timer',
    '添加用户 Prompt': 'Add user prompt',
    '编辑 Prompt': 'Edit prompt',
    'Prompt 内容': 'Prompt content',
    'Prompt 管理': 'Prompt manager',
    '恢复内置 Prompt': 'Restore built-in prompts',
    '添加 Prompt': 'Add prompt',
    '无法读取统计': 'Could not load statistics',
    '管理统计卡片': 'Manage dashboard cards',
    '近 12 周阅读热力图': 'Reading heatmap · last 12 weeks',
    '阅读最多': 'Most read',
    '已删除书籍': 'Deleted book',
    '阅读记录': 'Reading sessions',
    '这个时间范围内还没有阅读记录': 'No reading sessions in this period',
    '修改时长': 'Edit duration',
    '删除记录': 'Delete session',
    '拖动排序，移除后可随时重新添加': 'Drag to reorder. Removed cards can be added again.',
    '移除': 'Remove',
    '修改阅读时长': 'Edit reading duration',
    '分钟': 'Minutes',
    '阅读记录已删除': 'Reading session deleted',
    '撤销': 'Undo',
    '全部时间累计': 'All-time total',
    '与上一阶段持平': 'Same as the previous period',
    '上一阶段没有阅读记录': 'No reading in the previous period',
    '增加': 'Up',
    '减少': 'Down',
    '继续阅读': 'Continue reading',
    '今日随机书摘': 'Random excerpt today',
    '书摘分享卡片': 'Excerpt share card',
    '保存 PNG': 'Save PNG',
    '系统分享': 'Share',
    '叶绿': 'Leaf',
    '纸张': 'Paper',
    '夜色': 'Night',
    '系统': 'System',
    '衬线': 'Serif',
    '等宽': 'Monospace',
    '文字颜色': 'Text color',
    '背景颜色': 'Background color',
    '强调色': 'Accent color',
    '背景图片': 'Background image',
    '更换图片': 'Replace image',
    '移除背景图片': 'Remove background image',
    '图片浓度': 'Image opacity',
    '保存书摘卡片': 'Save excerpt card',
    '书摘卡片已保存': 'Excerpt card saved',
    '保存书摘': 'Save excerpt',
    '想法（可选）': 'Thoughts (optional)',
    '摘自': 'From',
    '上一页': 'Previous page',
    '下一页': 'Next page',
    '书内搜索': 'Search in book',
    '阅读设置': 'Reading settings',
    '添加书签': 'Add bookmark',
    '书名': 'Book title',
    '章节名': 'Chapter title',
    '页码': 'Page number',
    '当前时间': 'Current time',
    '页眉内容': 'Header content',
    '页脚内容': 'Footer content',
    '显示页眉': 'Show header',
    '显示页脚': 'Show footer',
    '左右点击区域互换': 'Swap left and right tap zones',
    '音量键翻页': 'Turn pages with volume keys',
    '鼠标滚轮翻页': 'Turn pages with mouse wheel',
    '阅读时屏幕常亮': 'Keep screen awake while reading',
    '沉浸全屏': 'Immersive fullscreen',
    '点击翻页区域宽度': 'Tap-zone width',
    '横向分页': 'Horizontal pages',
    '连续滚动': 'Continuous scroll',
    'PDF 阅读设置': 'PDF reading settings',
    '关键词': 'Keywords',
    '搜索中': 'Searching',
    '无结果': 'No results',
    '关闭搜索': 'Close search',
    '上一个结果': 'Previous result',
    '下一个结果': 'Next result',
    '书摘已保存': 'Excerpt saved',
    '书签已添加': 'Bookmark added',
    '朗读': 'Read aloud',
    '摘录': 'Excerpt',
    '更多选中文本操作': 'More selection actions',
    '复制': 'Copy',
    'Web 搜索': 'Search the web',
    '发送给 AI': 'Send to AI',
    '生成分享卡片': 'Create share card',
    '从选中内容朗读': 'Read from selection',
    'AI 上下文翻译': 'AI contextual translation',
    '基于全文对话': 'Chat with full text',
    '全文翻译': 'Translate full text',
    '无法打开书籍': 'Could not open book',
    '正在朗读': 'Reading aloud',
    '前进到下个位置': 'Go forward',
    '后退到上次位置': 'Go back',
    '前进到下个跳转位置': 'Go forward to the next jump',
    '后退到上次跳转位置': 'Go back to the previous jump',
    '目录': 'Table of contents',
    '选中文本': 'Selected text',
    '阅读样式': 'Reading style',
    '分页': 'Pages',
    '仿真': 'Page curl',
    '滑动': 'Slide',
    '无动画': 'No animation',
    '双栏': 'Two columns',
    '字体': 'Font',
    '系统字体': 'System font',
    '衬线字体': 'Serif',
    '无衬线字体': 'Sans serif',
    '等宽字体': 'Monospace',
    '字号': 'Font size',
    '行距': 'Line height',
    '边距': 'Margins',
    '字重': 'Font weight',
    '字距': 'Letter spacing',
    '段距': 'Paragraph spacing',
    '缩进': 'Indent',
    '首行缩进': 'First-line indent',
    '文本对齐': 'Text alignment',
    '左对齐': 'Align left',
    '起始对齐': 'Align to start',
    '居中': 'Center',
    '两端对齐': 'Justify',
    '排版方向': 'Writing direction',
    '横排': 'Horizontal',
    '竖排（从右到左）': 'Vertical (right to left)',
    '保留书籍原始 CSS': 'Preserve book CSS',
    '关闭后统一覆盖正文排版': 'When off, override body typography',
    '代码语法配色': 'Code syntax highlighting',
    '电子墨水屏模式': 'E-ink mode',
    '灰阶、高对比度并减少视觉效果': 'Grayscale, high contrast, and reduced visual effects',
    '使用灰阶高对比度并关闭背景效果':
        'Use grayscale high contrast and disable background effects',
    '日间': 'Day',
    '夜间': 'Night',
    '护眼': 'Eye comfort',
    '正文': 'Text',
    '背景填充': 'Background fit',
    '裁切填满': 'Cover',
    '拉伸填满': 'Fill',
    '完整显示': 'Contain',
    '覆盖': 'Cover',
    '拉伸': 'Fill',
    '模糊': 'Blur',
    '透明': 'Opacity',
    '选择日间背景图': 'Choose day background',
    '选择夜间背景图': 'Choose night background',
    '移除背景图': 'Remove day background',
    '移除夜间背景图': 'Remove night background',
    '导入字体': 'Import font',
    '导入字体文件': 'Import font file',
    '支持 TTF、OTF、WOFF、WOFF2': 'Supports TTF, OTF, WOFF, and WOFF2',
    '中文显示': 'Chinese conversion',
    '保持原文': 'Original',
    '转为简体': 'Convert to simplified',
    '转为繁体': 'Convert to traditional',
    '阅读交互与状态': 'Reading interaction and status',
    '点击翻页区域': 'Tap-zone width',
    '自定义 CSS': 'Custom CSS',
    '自定义 CSS 的大括号不匹配': 'Custom CSS has unmatched braces',
    '更多阅读操作': 'More reading actions',
    '复制当前章节正文': 'Copy current chapter',
    '基于当前章节对话': 'Chat with current chapter',
    '基于全书对话与总结': 'Chat with and summarize the full book',
    '当前章节正文已复制': 'Current chapter copied',
    '已复制选中文本': 'Selected text copied',
    '打开外部链接？': 'Open external link?',
    '打开': 'Open',
    '图片': 'Image',
    '搜索失败': 'Search failed',
    '这本书尚未下载到本机。': 'This book is not downloaded on this device.',
    '暂不支持此格式': 'Unsupported format',
    'TXT 章节切分规则': 'TXT chapter detection',
    '章节标题正则表达式': 'Chapter-title regular expression',
    '留空时使用内置的中文小说与 Chapter 规则':
        'Leave empty to use the built-in Chinese novel and Chapter rules',
    '正则表达式无效': 'Invalid regular expression',
    '衬线体': 'Serif',
    '无衬线体': 'Sans serif',
    '等宽体': 'Monospace',
    '已设置日间背景图': 'Day background selected',
    '已设置夜间背景图': 'Night background selected',
    '导入字体 · ': 'Imported font · ',
    '书架密度': 'Shelf density',
    '舒适封面': 'Comfortable covers',
    '紧凑封面': 'Compact covers',
    '封面填充': 'Cover fit',
    '裁切': 'Crop',
    '完整': 'Fit',
    '检查更新与变更日志': 'Updates and release notes',
    '从 GitHub Releases 获取最新版本和发布说明':
        'Get the latest version and notes from GitHub Releases',
    '检查': 'Check',
    '我的同步设备': 'My synced devices',
    '配对新设备，自动迁移配置、凭据和书库数据':
        'Pair a device and automatically transfer settings, credentials, and library data',
    '让其他设备加入': 'Let another device join',
    '从已有设备恢复': 'Restore from an existing device',
    '在另一台设备输入下面的配对码。两台设备需要连接同一个局域网。':
        'Enter this pairing code on the other device. Both devices must be on the same local network.',
    '配对码 5 分钟内有效且只能使用一次。':
        'The pairing code expires in 5 minutes and can be used only once.',
    '复制配对码': 'Copy pairing code',
    '配对码': 'Pairing code',
    '两台设备需要连接同一个局域网': 'Both devices must be on the same local network',
    '开始配对': 'Start pairing',
    '已添加设备': 'Device added',
    '设备配对完成，已恢复配置': 'Pairing complete; settings restored',
    '配置已传输，书库将在同步后端可用时继续同步':
        'Settings transferred; the library will continue syncing when the backend is available',
    '设备名称': 'Device name',
    '移除同步设备': 'Remove synced device',
    '移除后，该设备将不能再获取后续配置。':
        'After removal, this device will no longer receive future settings.',
    '如果设备已经丢失，还应在 S3/WebDAV 服务端更换访问凭据。':
        'If the device is lost, also rotate its S3/WebDAV credentials at the provider.',
    '设备已移除': 'Device removed',
    '尚未建立可信设备空间': 'Trusted devices are not set up yet',
    '配置、凭据和书库数据将在可信设备间加密同步':
        'Settings, credentials, and library data are encrypted between trusted devices',
    '设备配对后会自动迁移 S3/WebDAV、AI、TTS、OPDS 和阅读配置。':
        'Pairing automatically transfers S3/WebDAV, AI, TTS, OPDS, and reading settings.',
    '已绑定设备': 'Paired devices',
    '本机': 'This device',
    '最近同步': 'Last synced',
    '已移除': 'Removed',
    '刚刚': 'just now',
    '刷新': 'Refresh',
    '自动同步': 'Automatic sync',
    '网络恢复、应用回到前台及定时触发时同步':
        'Sync when the network returns, the app resumes, or a timer fires',
    '仅 Wi-Fi / 有线网络': 'Wi-Fi / wired network only',
    '开启后不会通过移动数据自动同步': 'Do not automatically sync over mobile data',
    '同步完成通知': 'Sync completion notifications',
    '后台同步结束后显示系统通知': 'Show a system notification after background sync',
    'HTTP/HTTPS 代理': 'HTTP/HTTPS proxy',
    '未启用': 'Disabled',
    '配置': 'Configure',
    '尚未配置': 'Not configured',
    '对话查询书库、总结、回顾、分析和生成思维导图':
        'Chat with your library, summarize, recap, analyze, and create mind maps',
    'AI Provider、Prompt 与 Tools': 'AI provider, prompts, and tools',
    'Claude/Gemini 原生协议、推理强度、助手 Prompt 和上下文工具开关':
        'Claude/Gemini protocols, reasoning effort, assistant prompt, and context tools',
    'AI Prompt 管理': 'AI prompt manager',
    '编辑内置 Prompt，添加或删除用户 Prompt':
        'Edit built-in prompts and add or remove your own',
    '检测 AI 模型': 'Test AI model',
    '发送最小翻译请求，验证 API、模型和密钥':
        'Send a minimal request to verify the API, model, and key',
    '检测': 'Test',
    'TTS 朗读服务': 'TTS service',
    '系统 TTS': 'System TTS',
    '阿里云智能语音': 'Alibaba Cloud Speech',
    '完整备份': 'Full backup',
    '导出数据库、操作日志、书籍和封面，并附带 SHA-256 完整性信息':
        'Export the database, operation log, books, and covers with SHA-256 integrity data',
    '恢复备份': 'Restore backup',
    '恢复': 'Restore',
    '先校验、再原子恢复；恢复的操作日志会重新参与同步':
        'Validate first, then restore atomically; restored operations will sync again',
    '存储统计与文件检查': 'Storage statistics and file check',
    '重新检查': 'Check again',
    '阅读字体管理': 'Reading font manager',
    '导入、替换或删除流式阅读器共用字体，并查看缓存占用':
        'Import, replace, or remove shared reader fonts and review cache use',
    '自定义书籍数据目录': 'Custom book data directory',
    '使用应用默认目录': 'Use the app default directory',
    '迁移': 'Move',
    '补算 MD5': 'Backfill MD5',
    '修复缺失状态': 'Repair missing status',
    '清理孤立缓存': 'Clear orphaned cache',
    '仅对信任的互动书籍开启；关闭可减少脚本风险':
        'Enable only for trusted interactive books; disabling reduces script risk',
    '重置新手引导与提示': 'Reset onboarding and tips',
    '下次启动时重新显示功能引导': 'Show feature guidance again on the next launch',
    '重置': 'Reset',
    '开发者选项': 'Developer options',
    '显示诊断日志和运行时信息': 'Show diagnostic logs and runtime information',
    '查看应用日志': 'View app logs',
    '日志自动滚动保留最近约 1 MB，可复制或清空':
        'Logs retain about the latest 1 MB and can be copied or cleared',
    '管理自定义目录，浏览、搜索、下载并导入电子书':
        'Manage catalogs, browse, search, download, and import ebooks',
    '同步方式': 'Sync method',
    '共享目录': 'Shared directory',
    'S3-compatible 对象存储': 'S3-compatible object storage',
    '检测 S3 能力': 'Test S3 capabilities',
    '验证签名、条件写入、上传、下载、列举和删除':
        'Verify signing, conditional writes, upload, download, listing, and deletion',
    '同步目录': 'Sync directory',
    '尚未选择，可使用共享目录或网络盘': 'Not selected; use a shared directory or network drive',
    '选择': 'Choose',
    'WebDAV 服务器': 'WebDAV server',
    '匿名访问': 'Anonymous access',
    '检测 WebDAV 能力': 'Test WebDAV capabilities',
    '验证目录、上传、下载、条件写入、列举和删除':
        'Verify directories, upload, download, conditional writes, listing, and deletion',
    '立即同步': 'Sync now',
    '离线失败不会丢失变更，恢复连接后可安全重试':
        'Offline failures preserve changes and can be safely retried later',
    '同步': 'Sync',
    '批量下载云端书籍': 'Download cloud books',
    '下载所有仅保留在同步后端、当前设备尚无副本的书籍':
        'Download every cloud-only book missing from this device',
    '全部下载': 'Download all',
    '复制结果': 'Copy result',
    '译文': 'Translation',
    '双语': 'Bilingual',
    '原文': 'Original',
    '术语表：原词 = 译词（每行一条）': 'Glossary: source = translation (one per line)',
    '开始翻译': 'Start translating',
    '翻译失败': 'Translation failed',
    'AI 模型连接正常': 'AI model connection succeeded',
    'Claude / Anthropic 原生': 'Native Claude / Anthropic',
    'Gemini 原生': 'Native Gemini',
    'MinIO、NAS 等兼容服务通常需要开启':
        'Usually required for compatible services such as MinIO and NAS',
    'Path-style 请求': 'Path-style requests',
    '与其他音频同时播放': 'Mix with other audio',
    '中': 'Medium',
    '书库中还没有文件': 'No files in the library yet',
    '书库整理写入 Tools': 'Library organization write tools',
    '书库查询 Tool': 'Library query tool',
    '书摘与笔记 Tool': 'Excerpts and notes tool',
    '书籍、书摘、书签和阅读进度会从所有同步设备删除。':
        'The book, excerpts, bookmarks, and progress will be deleted from every synced device.',
    '书籍不会被删除，只会移出这个书架。':
        'Books will not be deleted; they will only be removed from this shelf.',
    '书籍文件已替换': 'Book file replaced',
    '从云端重新下载': 'Download again from cloud',
    '低（更省）': 'Low (economical)',
    '停用': 'Disable',
    '分享文件': 'Share file',
    '删除书籍': 'Delete book',
    '删除会同步到其他设备。': 'Deletion will sync to other devices.',
    '只删除本机副本，书籍信息和云端文件会保留。之后可从同步后端重新下载。':
        'Only the local copy is removed. Metadata and the cloud file remain available for download.',
    '同步后端连接和读写能力正常': 'Sync backend connection and read/write checks passed',
    '应用日志': 'App logs',
    '开始迁移': 'Start migration',
    '引导与提示已重置，下次启动时生效': 'Onboarding and tips reset; takes effect next launch',
    '恢复完整备份？': 'Restore full backup?',
    '批量删除会通过同步日志传播到其他设备。':
        'Bulk deletion will propagate to other devices through the sync log.',
    '整理书架': 'Organize shelves',
    '新建标签': 'New tag',
    '日志为空': 'No logs',
    '日本語': 'Japanese',
    '暂停其他音频': 'Pause other audio',
    '替换文件': 'Replace file',
    '本地副本已释放': 'Local copy removed',
    '本地文件不存在': 'Local file does not exist',
    '本地文件明细': 'Local file details',
    '松开即可导入电子书': 'Drop to import ebooks',
    '查看发布页': 'View release page',
    '正在导入，请稍后重试': 'Import in progress; try again shortly',
    '没有符合筛选条件的书摘': 'No excerpts match the filters',
    '没有需要下载的云端书籍': 'No cloud books need downloading',
    '清空': 'Clear',
    '移动到文件夹': 'Move to folder',
    '编辑书摘': 'Edit excerpt',
    '编辑书签': 'Edit bookmark',
    '编辑书籍详情': 'Edit book details',
    '编辑详情与评分': 'Edit details and rating',
    '解散': 'Dissolve',
    '解散书架': 'Dissolve shelf',
    '设置标签': 'Set tags',
    '请先新建一个书架。': 'Create a shelf first.',
    '迁移本地书籍数据？': 'Move local book data?',
    '配置 AI 翻译': 'Configure AI translation',
    '配置 S3-compatible': 'Configure S3-compatible',
    '配置 TTS 服务': 'Configure TTS service',
    '配置 WebDAV': 'Configure WebDAV',
    '释放': 'Remove',
    '释放本地空间': 'Free local space',
    '重命名': 'Rename',
    '阅读历史 Tool': 'Reading history tool',
    '降低其他音频音量': 'Lower other audio',
    '顶层': 'Top level',
    '高': 'High',
    '与其他音频的混合方式': 'Audio mixing',
    '书籍操作': 'Book actions',
    '代理主机': 'Proxy host',
    '删除字体': 'Delete font',
    '取消选择': 'Clear selection',
    '同步目录 URL': 'Sync directory URL',
    '备注': 'Notes',
    '密码或应用密码': 'Password or app password',
    '对象前缀': 'Object prefix',
    '导出 Leeef 完整备份': 'Export full Leeef backup',
    '导出书摘与笔记': 'Export excerpts and notes',
    '导出所选': 'Export selected',
    '批量修改颜色': 'Change colors in bulk',
    '批量删除': 'Delete in bulk',
    '推理强度': 'Reasoning effort',
    '服务': 'Service',
    '标签名称': 'Tag name',
    '标记颜色': 'Highlight color',
    '模型': 'Model',
    '用户名': 'Username',
    '端口': 'Port',
    '简介': 'Description',
    '翻译 Prompt': 'Translation prompt',
    '请求协议': 'Request protocol',
    '选择 Leeef 书籍数据目录': 'Choose Leeef book data directory',
    '选择 Leeef 同步目录': 'Choose Leeef sync directory',
    '选择 Leeef 完整备份': 'Choose a full Leeef backup',
    '阅读助手 Prompt': 'Reading assistant prompt',
    '重命名书架': 'Rename shelf',
    '编辑标签': 'Edit tag',
    '升序': 'Ascending',
    '降序': 'Descending',
    '书籍已下载到本机': 'Book downloaded to this device',
    '云端尚无该书文件': 'The book file is not available in the cloud',
    '未评分': 'Not rated',
    '已复制到剪贴板': 'Copied to clipboard',
    '导出完成': 'Export complete',
    '数据库记录为本地可用，但文件已缺失': 'Marked as locally available, but the file is missing',
    '仅云端/元数据': 'Cloud / metadata only',
    '尚未导入字体': 'No font imported',
    '可导入 TTF、OTF、WOFF 或 WOFF2，所有流式阅读器共用':
        'Import TTF, OTF, WOFF, or WOFF2 for all reflowable readers',
    '替换字体': 'Replace font',
    '正在检查…': 'Checking…',
    '分享': 'Share',
    '拖入': 'Drag and drop',
    '导入': 'Import',
    '替换': 'Replace',
    '下载': 'Download',
    '读取标签': 'Load tags',
    '读取书架': 'Load shelves',
    '读取书库': 'Load library',
    '读取书架内容': 'Load shelf contents',
    '读取标签内容': 'Load tag contents',
    '读取进度': 'Load progress',
    '读取书摘': 'Load excerpts',
    '读取书签': 'Load bookmarks',
    '检查更新': 'Check for updates',
    '同步后端检测': 'Test sync backend',
    '备份': 'Backup',
    '批量下载': 'Bulk download',
  };
  static const _japaneseText = <String, String>{
    '跳过': 'スキップ',
    '开始使用': '始める',
    '下一步': '次へ',
    '把书库带在身边': 'ライブラリをいつでも手元に',
    '导入 EPUB、PDF、TXT、MOBI、AZW3 和 FB2，并在四端继续阅读。':
        'EPUB、PDF、TXT、MOBI、AZW3、FB2 を読み込み、4つのプラットフォームで続きを読めます。',
    '离线优先，安全同步': 'オフライン優先、安全に同期',
    '阅读进度、书摘、书签、目录与原文件通过增量日志合并。': '進捗、抜粋、しおり、本棚、原本ファイルを増分ログで統合します。',
    '让 AI 真正理解你的书库': 'AI がライブラリを本当に理解',
    '上下文翻译、总结、全文对话，以及经过确认的 MCP 管理操作。': '文脈翻訳、要約、全文対話、確認付き MCP 管理操作を利用できます。',
    'AI 阅读助手': 'AI 読書アシスタント',
    '章节总结': '章の要約',
    '全书总结': '本全体の要約',
    '回顾前文': 'これまでの振り返り',
    '深入分析': '詳しく分析',
    '思维导图': 'マインドマップ',
    '当前上下文': '現在のコンテキスト',
    '正在载入…': '読み込み中…',
    '询问当前书籍或整个书库…': 'この本またはライブラリ全体について質問…',
    '请求失败': 'リクエスト失敗',
    '待确认的 AI 整理计划': '確認待ちの AI 整理プラン',
    '审阅并执行': '確認して実行',
    '确认 AI 整理计划': 'AI 整理プランを確認',
    '取消': 'キャンセル',
    '确认执行': '確認して実行',
    '阶段汇总': '期間サマリー',
    '阅读时长': '読書時間',
    '阅读天数': '読書日数',
    '连续阅读': '連続読書',
    '阅读书籍': '読んだ本',
    '书摘笔记': '抜粋とノート',
    '已读完': '読了',
    '近 7 日': '直近7日',
    '近 30 日': '直近30日',
    '周': '週',
    '月': '月',
    '年': '年',
    '全部': 'すべて',
    '设置': '設定',
    '语言': '言語',
    '界面语言': '表示言語',
    '明暗主题': '外観モード',
    '浅色': 'ライト',
    '深色': 'ダーク',
    '主题色': 'テーマカラー',
    '导航与书架外观': 'ナビゲーションと本棚の外観',
    '笔记': 'ノート',
    '统计': '統計',
    '显示': '',
    '栏目': 'を表示',
    '跟随系统': 'システム設定',
    '简体中文': '簡体字中国語',
    '英语': '英語',
    '日语': '日本語',
    '完成': '完了',
    '关闭': '閉じる',
    '保存': '保存',
    '应用': '適用',
    '删除': '削除',
    '编辑': '編集',
    '搜索': '検索',
    '搜索书名、作者、书摘、笔记和书签': '書名、著者、抜粋、ノート、しおりを検索',
    '输入关键词搜索整个书库': 'キーワードを入力してライブラリを検索',
    '没有找到匹配内容': '一致する内容がありません',
    '书籍': '本',
    '书摘与笔记': '抜粋とノート',
    '书签': 'しおり',
    '书摘': '抜粋',
    '未知作者': '著者不明',
    '未知书籍': '不明な本',
    '未命名书签': '名称なしのしおり',
    '请先下载这本书': '先にこの本をダウンロードしてください',
    '新建书架': '本棚を作成',
    '所有标签': 'すべてのタグ',
    '管理标签': 'タグを管理',
    '全部状态': 'すべての状態',
    '未开始': '未読',
    '阅读中': '読書中',
    '最近更新': '最近更新',
    '标题': 'タイトル',
    '作者': '著者',
    '阅读进度': '読書進捗',
    '导入时间': '読み込み日',
    '评分': '評価',
    '没有符合当前筛选条件的书籍。': '現在の条件に一致する本はありません。',
    '开始你的书库': 'ライブラリを始めましょう',
    '导入 EPUB、MOBI、AZW3、FB2、PDF 或 TXT。阅读进度和书摘会先保存在本地，联网后再安全同步。':
        'EPUB、MOBI、AZW3、FB2、PDF、TXT を読み込めます。進捗と抜粋はまず端末に保存され、オンライン時に安全に同期されます。',
    '导出': 'エクスポート',
    '复制 Markdown': 'Markdown をコピー',
    '导出 Markdown': 'Markdown を書き出す',
    '导出 TXT': 'TXT を書き出す',
    '导出 CSV': 'CSV を書き出す',
    '按书合并章节导出': '本・章ごとにまとめて書き出す',
    '选中书中文字可创建书摘，阅读时也可添加书签。': '本文を選択して抜粋を作成したり、読書中にしおりを追加できます。',
    '全部书籍': 'すべての本',
    '全部类型': 'すべての種類',
    '有笔记': 'ノートあり',
    '仅书摘': '抜粋のみ',
    '全部颜色': 'すべての色',
    '黄色': '黄',
    '绿色': '緑',
    '蓝色': '青',
    '粉色': 'ピンク',
    '紫色': '紫',
    '棕色': '茶',
    '灰蓝': 'ブルーグレー',
    '最新优先': '新しい順',
    '最早优先': '古い順',
    '按书与章节': '本と章の順',
    '添加 OPDS 目录': 'OPDS カタログを追加',
    '名称': '名前',
    '用户名（可选）': 'ユーザー名（任意）',
    '密码（可选）': 'パスワード（任意）',
    'OPDS 目录': 'OPDS カタログ',
    '添加目录': 'カタログを追加',
    '删除目录': 'カタログを削除',
    '添加 OPDS 目录后即可浏览、搜索和下载': 'OPDS カタログを追加すると、閲覧・検索・ダウンロードできます。',
    '搜索当前目录': 'このカタログを検索',
    '目录加载失败': 'カタログを読み込めませんでした',
    '重试': '再試行',
    '加载中…': '読み込み中…',
    '加载下一页': '次のページを読み込む',
    '下载并导入': 'ダウンロードして読み込む',
    '已导入书库': 'ライブラリに読み込みました',
    '下载失败': 'ダウンロード失敗',
    '系统朗读': 'システム読み上げ',
    '当前页面没有可朗读文字': 'このページには読み上げ可能な文字がありません',
    '上一句': '前の文',
    '下一句': '次の文',
    '暂停': '一時停止',
    '播放': '再生',
    '停止': '停止',
    '语速': '速度',
    '音调': 'ピッチ',
    '音量': '音量',
    '声音': '音声',
    '系统声音': 'システム音声',
    '15 分钟后停止': '15分後に停止',
    '30 分钟后停止': '30分後に停止',
    '取消定时': 'タイマーを解除',
    '添加用户 Prompt': 'ユーザープロンプトを追加',
    '编辑 Prompt': 'プロンプトを編集',
    'Prompt 内容': 'プロンプト内容',
    'Prompt 管理': 'プロンプト管理',
    '恢复内置 Prompt': '組み込みプロンプトを復元',
    '添加 Prompt': 'プロンプトを追加',
    '无法读取统计': '統計を読み込めませんでした',
    '管理统计卡片': '統計カードを管理',
    '近 12 周阅读热力图': '直近12週間の読書ヒートマップ',
    '阅读最多': '最も読んだ本',
    '已删除书籍': '削除済みの本',
    '阅读记录': '読書記録',
    '这个时间范围内还没有阅读记录': 'この期間には読書記録がありません',
    '修改时长': '時間を変更',
    '删除记录': '記録を削除',
    '拖动排序，移除后可随时重新添加': 'ドラッグで並べ替えます。削除したカードは再追加できます。',
    '移除': '取り除く',
    '修改阅读时长': '読書時間を変更',
    '分钟': '分',
    '阅读记录已删除': '読書記録を削除しました',
    '撤销': '元に戻す',
    '全部时间累计': '全期間の累計',
    '与上一阶段持平': '前の期間と同じ',
    '上一阶段没有阅读记录': '前の期間に読書記録はありません',
    '增加': '増加',
    '减少': '減少',
    '继续阅读': '続きを読む',
    '今日随机书摘': '今日のランダム抜粋',
    '书摘分享卡片': '抜粋共有カード',
    '保存 PNG': 'PNG を保存',
    '系统分享': '共有',
    '叶绿': 'リーフ',
    '纸张': '紙',
    '夜色': 'ナイト',
    '系统': 'システム',
    '衬线': 'セリフ',
    '等宽': '等幅',
    '文字颜色': '文字色',
    '背景颜色': '背景色',
    '强调色': 'アクセント色',
    '背景图片': '背景画像',
    '更换图片': '画像を変更',
    '移除背景图片': '背景画像を削除',
    '图片浓度': '画像の濃さ',
    '保存书摘卡片': '抜粋カードを保存',
    '书摘卡片已保存': '抜粋カードを保存しました',
    '保存书摘': '抜粋を保存',
    '想法（可选）': 'メモ（任意）',
    '摘自': '出典',
    '上一页': '前のページ',
    '下一页': '次のページ',
    '书内搜索': '本の中を検索',
    '阅读设置': '読書設定',
    '添加书签': 'しおりを追加',
    '书名': '書名',
    '章节名': '章名',
    '页码': 'ページ番号',
    '当前时间': '現在時刻',
    '页眉内容': 'ヘッダー内容',
    '页脚内容': 'フッター内容',
    '显示页眉': 'ヘッダーを表示',
    '显示页脚': 'フッターを表示',
    '左右点击区域互换': '左右のタップ領域を入れ替える',
    '音量键翻页': '音量キーでページをめくる',
    '鼠标滚轮翻页': 'マウスホイールでページをめくる',
    '阅读时屏幕常亮': '読書中は画面を点灯',
    '沉浸全屏': '没入型フルスクリーン',
    '点击翻页区域宽度': 'タップ領域の幅',
    '横向分页': '横方向のページ',
    '连续滚动': '連続スクロール',
    'PDF 阅读设置': 'PDF 読書設定',
    '关键词': 'キーワード',
    '搜索中': '検索中',
    '无结果': '結果なし',
    '关闭搜索': '検索を閉じる',
    '上一个结果': '前の結果',
    '下一个结果': '次の結果',
    '书摘已保存': '抜粋を保存しました',
    '书签已添加': 'しおりを追加しました',
    '朗读': '読み上げ',
    '摘录': '抜粋',
    '更多选中文本操作': '選択テキストのその他の操作',
    '复制': 'コピー',
    'Web 搜索': 'Web 検索',
    '发送给 AI': 'AI に送る',
    '生成分享卡片': '共有カードを作成',
    '从选中内容朗读': '選択位置から読み上げ',
    'AI 上下文翻译': 'AI 文脈翻訳',
    '基于全文对话': '全文について対話',
    '全文翻译': '全文翻訳',
    '无法打开书籍': '本を開けません',
    '正在朗读': '読み上げ中',
    '前进到下个位置': '次の位置へ進む',
    '后退到上次位置': '前の位置へ戻る',
    '前进到下个跳转位置': '次のジャンプ位置へ進む',
    '后退到上次跳转位置': '前のジャンプ位置へ戻る',
    '目录': '目次',
    '选中文本': '選択テキスト',
    '阅读样式': '読書スタイル',
    '分页': 'ページ',
    '仿真': 'ページカール',
    '滑动': 'スライド',
    '无动画': 'アニメーションなし',
    '双栏': '2段組',
    '字体': 'フォント',
    '系统字体': 'システムフォント',
    '衬线字体': 'セリフ',
    '无衬线字体': 'サンセリフ',
    '等宽字体': '等幅',
    '字号': '文字サイズ',
    '行距': '行間',
    '边距': '余白',
    '字重': 'ウェイト',
    '字距': '文字間隔',
    '段距': '段落間隔',
    '缩进': 'インデント',
    '首行缩进': '先頭行インデント',
    '文本对齐': '文字揃え',
    '左对齐': '左揃え',
    '起始对齐': '開始位置に揃える',
    '居中': '中央揃え',
    '两端对齐': '両端揃え',
    '排版方向': '文字方向',
    '横排': '横書き',
    '竖排（从右到左）': '縦書き（右から左）',
    '保留书籍原始 CSS': '本の CSS を保持',
    '关闭后统一覆盖正文排版': 'オフにすると本文の書式を上書きします',
    '代码语法配色': 'コードのシンタックスハイライト',
    '电子墨水屏模式': '電子ペーパーモード',
    '灰阶、高对比度并减少视觉效果': 'グレースケール、高コントラスト、視覚効果を軽減',
    '使用灰阶高对比度并关闭背景效果': 'グレースケールの高コントラストを使い背景効果を無効化',
    '日间': '昼',
    '夜间': '夜',
    '护眼': '目に優しい',
    '正文': '本文',
    '背景填充': '背景の表示方法',
    '裁切填满': '切り抜いて全面表示',
    '拉伸填满': '引き伸ばして全面表示',
    '完整显示': '全体表示',
    '覆盖': 'カバー',
    '拉伸': '引き伸ばす',
    '模糊': 'ぼかし',
    '透明': '透明度',
    '选择日间背景图': '昼の背景画像を選択',
    '选择夜间背景图': '夜の背景画像を選択',
    '移除背景图': '昼の背景画像を削除',
    '移除夜间背景图': '夜の背景画像を削除',
    '导入字体': 'フォントを読み込む',
    '导入字体文件': 'フォントファイルを読み込む',
    '支持 TTF、OTF、WOFF、WOFF2': 'TTF、OTF、WOFF、WOFF2 に対応',
    '中文显示': '中国語表記変換',
    '保持原文': '原文のまま',
    '转为简体': '簡体字に変換',
    '转为繁体': '繁体字に変換',
    '阅读交互与状态': '読書操作と状態',
    '点击翻页区域': 'タップ領域の幅',
    '自定义 CSS': 'カスタム CSS',
    '自定义 CSS 的大括号不匹配': 'カスタム CSS の波括弧が一致しません',
    '更多阅读操作': 'その他の読書操作',
    '复制当前章节正文': '現在の章をコピー',
    '基于当前章节对话': '現在の章について対話',
    '基于全书对话与总结': '本全体について対話・要約',
    '当前章节正文已复制': '現在の章をコピーしました',
    '已复制选中文本': '選択テキストをコピーしました',
    '打开外部链接？': '外部リンクを開きますか？',
    '打开': '開く',
    '图片': '画像',
    '搜索失败': '検索失敗',
    '这本书尚未下载到本机。': 'この本は端末にダウンロードされていません。',
    '暂不支持此格式': '未対応の形式',
    'TXT 章节切分规则': 'TXT 章分割ルール',
    '章节标题正则表达式': '章タイトルの正規表現',
    '留空时使用内置的中文小说与 Chapter 规则': '空欄の場合は組み込みの中国語小説・Chapter ルールを使用',
    '正则表达式无效': '正規表現が無効です',
    '衬线体': 'セリフ',
    '无衬线体': 'サンセリフ',
    '等宽体': '等幅',
    '已设置日间背景图': '昼の背景画像を設定済み',
    '已设置夜间背景图': '夜の背景画像を設定済み',
    '导入字体 · ': '読み込みフォント · ',
    '书架密度': '本棚の密度',
    '舒适封面': 'ゆったり表示',
    '紧凑封面': 'コンパクト表示',
    '封面填充': '表紙の表示',
    '裁切': 'トリミング',
    '完整': '全体',
    '检查更新与变更日志': '更新とリリースノート',
    '从 GitHub Releases 获取最新版本和发布说明': 'GitHub Releases から最新版と説明を取得',
    '检查': '確認',
    '我的同步设备': '同期デバイス',
    '配对新设备，自动迁移配置、凭据和书库数据': '新しいデバイスをペアリングし、設定・認証情報・書庫データを自動移行',
    '让其他设备加入': '別のデバイスを追加',
    '从已有设备恢复': '既存のデバイスから復元',
    '在另一台设备输入下面的配对码。两台设备需要连接同一个局域网。':
        'もう一方のデバイスで次のペアリングコードを入力してください。両方を同じローカルネットワークに接続してください。',
    '配对码 5 分钟内有效且只能使用一次。': 'ペアリングコードは5分間有効で、一度だけ使用できます。',
    '复制配对码': 'コードをコピー',
    '配对码': 'ペアリングコード',
    '两台设备需要连接同一个局域网': '両方のデバイスを同じローカルネットワークに接続してください',
    '开始配对': 'ペアリング開始',
    '已添加设备': 'デバイスを追加しました',
    '设备配对完成，已恢复配置': 'ペアリングが完了し、設定を復元しました',
    '配置已传输，书库将在同步后端可用时继续同步': '設定を転送しました。同期バックエンドが利用可能になると書庫の同期を続行します',
    '设备名称': 'デバイス名',
    '移除同步设备': '同期デバイスを削除',
    '移除后，该设备将不能再获取后续配置。': '削除後、このデバイスは今後の設定を受信できません。',
    '如果设备已经丢失，还应在 S3/WebDAV 服务端更换访问凭据。':
        'デバイスを紛失した場合は、S3/WebDAV 側でもアクセス認証情報を変更してください。',
    '设备已移除': 'デバイスを削除しました',
    '尚未建立可信设备空间': '信頼済みデバイスはまだ設定されていません',
    '配置、凭据和书库数据将在可信设备间加密同步': '設定・認証情報・書庫データを信頼済みデバイス間で暗号化して同期します',
    '设备配对后会自动迁移 S3/WebDAV、AI、TTS、OPDS 和阅读配置。':
        'ペアリングすると、S3/WebDAV、AI、TTS、OPDS、読書設定が自動的に移行されます。',
    '已绑定设备': 'ペアリング済みデバイス',
    '本机': 'このデバイス',
    '最近同步': '最終同期',
    '已移除': '削除済み',
    '刚刚': 'たった今',
    '刷新': '更新',
    '自动同步': '自動同期',
    '网络恢复、应用回到前台及定时触发时同步': 'ネットワーク復帰時、アプリ復帰時、定期実行時に同期',
    '仅 Wi-Fi / 有线网络': 'Wi-Fi / 有線ネットワークのみ',
    '开启后不会通过移动数据自动同步': 'モバイルデータでは自動同期しません',
    '同步完成通知': '同期完了通知',
    '后台同步结束后显示系统通知': 'バックグラウンド同期後にシステム通知を表示',
    'HTTP/HTTPS 代理': 'HTTP/HTTPS プロキシ',
    '未启用': '無効',
    '配置': '設定',
    '尚未配置': '未設定',
    '对话查询书库、总结、回顾、分析和生成思维导图': 'ライブラリと対話し、要約・振り返り・分析・マインドマップ作成',
    'AI Provider、Prompt 与 Tools': 'AI プロバイダー、プロンプト、ツール',
    'Claude/Gemini 原生协议、推理强度、助手 Prompt 和上下文工具开关':
        'Claude/Gemini プロトコル、推論強度、プロンプト、コンテキストツール',
    'AI Prompt 管理': 'AI プロンプト管理',
    '编辑内置 Prompt，添加或删除用户 Prompt': '組み込みプロンプトの編集とユーザープロンプトの追加・削除',
    '检测 AI 模型': 'AI モデルをテスト',
    '发送最小翻译请求，验证 API、模型和密钥': 'API、モデル、キーを最小リクエストで確認',
    '检测': 'テスト',
    'TTS 朗读服务': 'TTS 読み上げサービス',
    '系统 TTS': 'システム TTS',
    '阿里云智能语音': 'Alibaba Cloud Speech',
    '完整备份': '完全バックアップ',
    '导出数据库、操作日志、书籍和封面，并附带 SHA-256 完整性信息':
        'データベース、操作ログ、本、表紙と SHA-256 整合性情報を書き出し',
    '恢复备份': 'バックアップを復元',
    '恢复': '復元',
    '先校验、再原子恢复；恢复的操作日志会重新参与同步': '検証後にアトミックに復元し、復元ログは再度同期',
    '存储统计与文件检查': 'ストレージ統計とファイル検査',
    '重新检查': '再検査',
    '阅读字体管理': '読書フォント管理',
    '导入、替换或删除流式阅读器共用字体，并查看缓存占用': 'リーダー共通フォントの読み込み・置換・削除とキャッシュ確認',
    '自定义书籍数据目录': 'カスタムブックデータフォルダ',
    '使用应用默认目录': 'アプリの既定フォルダを使用',
    '迁移': '移動',
    '补算 MD5': 'MD5 を補完',
    '修复缺失状态': '欠落状態を修復',
    '清理孤立缓存': '孤立キャッシュを消去',
    '仅对信任的互动书籍开启；关闭可减少脚本风险': '信頼できる対話型書籍のみで有効にします',
    '重置新手引导与提示': '初期ガイドとヒントをリセット',
    '下次启动时重新显示功能引导': '次回起動時に機能ガイドを再表示',
    '重置': 'リセット',
    '开发者选项': '開発者オプション',
    '显示诊断日志和运行时信息': '診断ログと実行時情報を表示',
    '查看应用日志': 'アプリログを表示',
    '日志自动滚动保留最近约 1 MB，可复制或清空': '最新約 1 MB のログを保持し、コピーまたは消去できます',
    '管理自定义目录，浏览、搜索、下载并导入电子书': 'カタログの管理、閲覧、検索、ダウンロード、読み込み',
    '同步方式': '同期方法',
    '共享目录': '共有フォルダ',
    'S3-compatible 对象存储': 'S3 互換オブジェクトストレージ',
    '检测 S3 能力': 'S3 機能をテスト',
    '验证签名、条件写入、上传、下载、列举和删除': '署名、条件付き書き込み、アップロード、ダウンロード、一覧、削除を確認',
    '同步目录': '同期フォルダ',
    '尚未选择，可使用共享目录或网络盘': '未選択。共有フォルダまたはネットワークドライブを利用',
    '选择': '選択',
    'WebDAV 服务器': 'WebDAV サーバー',
    '匿名访问': '匿名アクセス',
    '检测 WebDAV 能力': 'WebDAV 機能をテスト',
    '验证目录、上传、下载、条件写入、列举和删除': 'フォルダ、アップロード、ダウンロード、条件付き書き込み、一覧、削除を確認',
    '立即同步': '今すぐ同期',
    '离线失败不会丢失变更，恢复连接后可安全重试': 'オフライン時の失敗で変更は失われず、後で安全に再試行できます',
    '同步': '同期',
    '批量下载云端书籍': 'クラウドの本を一括ダウンロード',
    '下载所有仅保留在同步后端、当前设备尚无副本的书籍': 'この端末にないクラウドの本をすべてダウンロード',
    '全部下载': 'すべてダウンロード',
    '复制结果': '結果をコピー',
    '译文': '翻訳',
    '双语': '対訳',
    '原文': '原文',
    '术语表：原词 = 译词（每行一条）': '用語集：原語 = 訳語（1行に1件）',
    '开始翻译': '翻訳を開始',
    '翻译失败': '翻訳失敗',
    'AI 模型连接正常': 'AI モデルに接続できました',
    'Claude / Anthropic 原生': 'Claude / Anthropic ネイティブ',
    'Gemini 原生': 'Gemini ネイティブ',
    'MinIO、NAS 等兼容服务通常需要开启': 'MinIO や NAS などの互換サービスでは通常必要',
    'Path-style 请求': 'Path-style リクエスト',
    '与其他音频同时播放': '他の音声と同時再生',
    '中': '中',
    '书库中还没有文件': 'ライブラリにファイルがありません',
    '书库整理写入 Tools': 'ライブラリ整理書き込みツール',
    '书库查询 Tool': 'ライブラリ照会ツール',
    '书摘与笔记 Tool': '抜粋・ノートツール',
    '书籍、书摘、书签和阅读进度会从所有同步设备删除。': '本、抜粋、しおり、進捗がすべての同期端末から削除されます。',
    '书籍不会被删除，只会移出这个书架。': '本は削除されず、この本棚から外れるだけです。',
    '书籍文件已替换': '本のファイルを置き換えました',
    '从云端重新下载': 'クラウドから再ダウンロード',
    '低（更省）': '低（節約）',
    '停用': '無効化',
    '分享文件': 'ファイルを共有',
    '删除书籍': '本を削除',
    '删除会同步到其他设备。': '削除は他の端末にも同期されます。',
    '只删除本机副本，书籍信息和云端文件会保留。之后可从同步后端重新下载。': '端末のコピーだけを削除し、情報とクラウドファイルは保持します。',
    '同步后端连接和读写能力正常': '同期バックエンドの接続と読み書きは正常です',
    '应用日志': 'アプリログ',
    '开始迁移': '移行を開始',
    '引导与提示已重置，下次启动时生效': 'ガイドとヒントをリセットしました',
    '恢复完整备份？': '完全バックアップを復元しますか？',
    '批量删除会通过同步日志传播到其他设备。': '一括削除は同期ログで他の端末に反映されます。',
    '整理书架': '本棚を整理',
    '新建标签': '新規タグ',
    '日志为空': 'ログは空です',
    '日本語': '日本語',
    '暂停其他音频': '他の音声を一時停止',
    '替换文件': 'ファイルを置き換え',
    '本地副本已释放': 'ローカルコピーを削除しました',
    '本地文件不存在': 'ローカルファイルがありません',
    '本地文件明细': 'ローカルファイル詳細',
    '松开即可导入电子书': 'ドロップして電子書籍を読み込む',
    '查看发布页': 'リリースページを表示',
    '正在导入，请稍后重试': '読み込み中です。少し待ってから再試行してください',
    '没有符合筛选条件的书摘': '条件に合う抜粋がありません',
    '没有需要下载的云端书籍': 'ダウンロード必要なクラウドの本はありません',
    '清空': '消去',
    '移动到文件夹': 'フォルダへ移動',
    '编辑书摘': '抜粋を編集',
    '编辑书签': 'しおりを編集',
    '编辑书籍详情': '本の詳細を編集',
    '编辑详情与评分': '詳細と評価を編集',
    '解散': '解散',
    '解散书架': '本棚を解散',
    '设置标签': 'タグを設定',
    '请先新建一个书架。': '先に本棚を作成してください。',
    '迁移本地书籍数据？': 'ローカルの本データを移動しますか？',
    '配置 AI 翻译': 'AI 翻訳を設定',
    '配置 S3-compatible': 'S3-compatible を設定',
    '配置 TTS 服务': 'TTS サービスを設定',
    '配置 WebDAV': 'WebDAV を設定',
    '释放': '削除',
    '释放本地空间': 'ローカル容量を解放',
    '重命名': '名前を変更',
    '阅读历史 Tool': '読書履歴ツール',
    '降低其他音频音量': '他の音声を小さくする',
    '顶层': 'トップレベル',
    '高': '高',
    '与其他音频的混合方式': '他の音声とのミックス',
    '书籍操作': '本の操作',
    '代理主机': 'プロキシホスト',
    '删除字体': 'フォントを削除',
    '取消选择': '選択を解除',
    '同步目录 URL': '同期フォルダ URL',
    '备注': 'メモ',
    '密码或应用密码': 'パスワードまたはアプリパスワード',
    '对象前缀': 'オブジェクト接頭辞',
    '导出 Leeef 完整备份': 'Leeef 完全バックアップを書き出し',
    '导出书摘与笔记': '抜粋とノートを書き出し',
    '导出所选': '選択項目を書き出し',
    '批量修改颜色': '色を一括変更',
    '批量删除': '一括削除',
    '推理强度': '推論強度',
    '服务': 'サービス',
    '标签名称': 'タグ名',
    '标记颜色': 'ハイライト色',
    '模型': 'モデル',
    '用户名': 'ユーザー名',
    '端口': 'ポート',
    '简介': '説明',
    '翻译 Prompt': '翻訳プロンプト',
    '请求协议': 'リクエストプロトコル',
    '选择 Leeef 书籍数据目录': 'Leeef ブックデータフォルダを選択',
    '选择 Leeef 同步目录': 'Leeef 同期フォルダを選択',
    '选择 Leeef 完整备份': 'Leeef 完全バックアップを選択',
    '阅读助手 Prompt': '読書アシスタントプロンプト',
    '重命名书架': '本棚の名前を変更',
    '编辑标签': 'タグを編集',
    '升序': '昇順',
    '降序': '降順',
    '书籍已下载到本机': '本をこの端末にダウンロードしました',
    '云端尚无该书文件': 'クラウドにこの本のファイルがありません',
    '未评分': '未評価',
    '已复制到剪贴板': 'クリップボードにコピーしました',
    '导出完成': '書き出し完了',
    '数据库记录为本地可用，但文件已缺失': 'ローカル利用可と記録されていますが、ファイルがありません',
    '仅云端/元数据': 'クラウド / メタデータのみ',
    '尚未导入字体': 'フォント未読み込み',
    '可导入 TTF、OTF、WOFF 或 WOFF2，所有流式阅读器共用':
        'TTF、OTF、WOFF、WOFF2 をすべてのリフローリーダー用に読み込み',
    '替换字体': 'フォントを置き換え',
    '正在检查…': '確認中…',
    '分享': '共有',
    '拖入': 'ドラッグ＆ドロップ',
    '导入': '読み込み',
    '替换': '置き換え',
    '下载': 'ダウンロード',
    '读取标签': 'タグの読み込み',
    '读取书架': '本棚の読み込み',
    '读取书库': 'ライブラリの読み込み',
    '读取书架内容': '本棚内容の読み込み',
    '读取标签内容': 'タグ内容の読み込み',
    '读取进度': '進捗の読み込み',
    '读取书摘': '抜粋の読み込み',
    '读取书签': 'しおりの読み込み',
    '检查更新': '更新を確認',
    '同步后端检测': '同期バックエンドをテスト',
    '备份': 'バックアップ',
    '批量下载': '一括ダウンロード',
  };

  String text(String chinese) => _english
      ? _englishText[chinese] ?? chinese
      : _japanese
      ? _japaneseText[chinese] ?? chinese
      : chinese;
  String get library => _english
      ? 'Library'
      : _japanese
      ? 'ライブラリ'
      : '书库';
  String get notes => _english
      ? 'Notes'
      : _japanese
      ? 'ノート'
      : '笔记';
  String get search => _english
      ? 'Search'
      : _japanese
      ? '検索'
      : '搜索';
  String get statistics => _english
      ? 'Statistics'
      : _japanese
      ? '統計'
      : '统计';
  String get settings => _english
      ? 'Settings'
      : _japanese
      ? '設定'
      : '设置';
  String get importBook => _english
      ? 'Import books'
      : _japanese
      ? '本を読み込む'
      : '导入书籍';
  String duration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (_english) return hours > 0 ? '${hours}h ${minutes}m' : '$minutes min';
    if (_japanese) return hours > 0 ? '$hours 時間 $minutes 分' : '$minutes 分';
    return hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分钟';
  }

  String daysCount(int value) => _english
      ? '$value days'
      : _japanese
      ? '$value 日'
      : '$value 天';

  String booksCount(int value) => _english
      ? '$value books'
      : _japanese
      ? '$value 冊'
      : '$value 本';

  String itemsCount(int value) => _english
      ? '$value items'
      : _japanese
      ? '$value 件'
      : '$value 条';

  String continueBook(String title) => _english
      ? 'Continue reading “$title”'
      : _japanese
      ? '『$title』の続きを読む'
      : '继续阅读《$title》';

  String pageNumber(int page) => _english
      ? 'Page $page'
      : _japanese
      ? '$page ページ'
      : '第 $page 页';

  String colorChoice(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    final hex = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    return _english
        ? 'Color #$hex'
        : _japanese
        ? '色 #$hex'
        : '颜色 #$hex';
  }

  String fullTranslationIntro(int characters) => _english
      ? 'The source has $characters characters. Choose a target language, '
            'display mode, and glossary, then start.'
      : _japanese
      ? '原文は $characters 文字です。対象言語、表示方法、用語集を設定して開始してください。'
      : '原文共 $characters 字符。设置目标语言、显示方式和术语表后开始。';

  String failure(String action, Object error) => _english
      ? '${text(action)} failed: $error'
      : _japanese
      ? '${text(action)}に失敗しました：$error'
      : '${text(action)}失败：$error';

  String unsupportedFiles(String source) => _english
      ? 'Files from ${text(source)} do not contain a supported ebook format'
      : _japanese
      ? '${text(source)}のファイルに対応する電子書籍形式がありません'
      : '$source的文件中没有支持的电子书格式';

  String dissolveShelf(String name) => _english
      ? 'Dissolve “$name”?'
      : _japanese
      ? '「$name」を解散しますか？'
      : '解散“$name”？';

  String moveShelf(String name) => _english
      ? 'Move “$name”'
      : _japanese
      ? '「$name」を移動'
      : '移动“$name”';

  String chooseNewBookFile(String title) => _english
      ? 'Choose a new file for “$title”'
      : _japanese
      ? '『$title』の新しいファイルを選択'
      : '选择《$title》的新文件';

  String freeLocalCopy(String title) => _english
      ? 'Free local space used by “$title”?'
      : _japanese
      ? '『$title』のローカル容量を解放しますか？'
      : '释放《$title》的本地空间？';

  String addBookToShelf(String title) => _english
      ? 'Add “$title” to shelves'
      : _japanese
      ? '『$title』を本棚に追加'
      : '将《$title》加入书架';

  String setBookTags(String title) => _english
      ? 'Set tags for “$title”'
      : _japanese
      ? '『$title』のタグを設定'
      : '为《$title》设置标签';

  String deleteBookTitle(String title) => _english
      ? 'Delete “$title”?'
      : _japanese
      ? '『$title』を削除しますか？'
      : '删除《$title》？';

  String deleteExcerpts(int count) => _english
      ? 'Delete $count excerpts?'
      : _japanese
      ? '$count 件の抜粋を削除しますか？'
      : '删除 $count 条书摘？';

  String deleteNamed(String label) => _english
      ? 'Delete $label?'
      : _japanese
      ? '$labelを削除しますか？'
      : '删除$label？';

  String migrationTarget(String path) => _english
      ? 'Books and covers will be copied and database pointers verified before old copies are removed.\n\nTarget: $path'
      : _japanese
      ? '本と表紙をコピーし、データベース参照を検証してから古いコピーを削除します。\n\n移動先：$path'
      : '书籍和封面会先复制并校验数据库指针，成功后再删除旧副本。\n\n目标：$path';

  String migrationCompleted(int count) => _english
      ? 'Data directory migration complete: $count books moved. Restart the app to switch databases.'
      : _japanese
      ? 'データフォルダの移行が完了し、$count 冊を移動しました。アプリを再起動してください。'
      : '数据目录迁移完成，共迁移 $count 本书；请重启应用以切换数据库';

  String backupCompleted(int books, int files) => _english
      ? 'Backed up $books books and $files files'
      : _japanese
      ? '$books 冊の本と $files 個のファイルをバックアップしました'
      : '已备份 $books 本书和 $files 个文件';

  String restoreCompleted(int books, int files) => _english
      ? 'Restored $books books and $files files'
      : _japanese
      ? '$books 冊の本と $files 個のファイルを復元しました'
      : '已恢复 $books 本书和 $files 个文件';

  String importCompleted(int imported, int failed, String? firstFailure) {
    if (_english) {
      return failed == 0
          ? 'Imported $imported books'
          : 'Imported $imported; $failed failed: $firstFailure';
    }
    if (_japanese) {
      return failed == 0
          ? '$imported 冊を読み込みました'
          : '$imported 冊を読み込み、$failed 冊が失敗：$firstFailure';
    }
    return failed == 0
        ? '已导入 $imported 本书'
        : '导入 $imported 本，失败 $failed 本：$firstFailure';
  }

  String bookSemantics(
    String title,
    String? author, {
    required bool cloudOnly,
  }) {
    final resolvedAuthor = author ?? text('未知作者');
    if (_english) {
      return '$title, $resolvedAuthor${cloudOnly ? ', cloud only' : ''}';
    }
    if (_japanese) {
      return '$title、$resolvedAuthor${cloudOnly ? '、クラウドのみ' : ''}';
    }
    return '$title，$resolvedAuthor${cloudOnly ? '，仅云端' : ''}';
  }

  String storageFileSummary(String path, String bookBytes, String coverBytes) =>
      _english
      ? '$path\nBook $bookBytes · Cover $coverBytes'
      : _japanese
      ? '$path\n本 $bookBytes · 表紙 $coverBytes'
      : '$path\n书籍 $bookBytes · 封面 $coverBytes';

  String cacheUsage(String size) => _english
      ? 'Cache usage $size'
      : _japanese
      ? 'キャッシュ使用量 $size'
      : '缓存占用 $size';

  String updateTitle(bool available, String version) => _english
      ? available
            ? 'Version $version is available'
            : 'You are up to date'
      : _japanese
      ? available
            ? '新バージョン $version があります'
            : '最新バージョンです'
      : available
      ? '发现新版本 $version'
      : '已是最新版本';

  String updateDetails(String current, String latest, String notes) => _english
      ? 'Current version: $current\nLatest version: $latest\n\n$notes'
      : _japanese
      ? '現在のバージョン：$current\n最新バージョン：$latest\n\n$notes'
      : '当前版本：$current\n最新版本：$latest\n\n$notes';

  String storageSummary({
    required String bookBytes,
    required String coverBytes,
    required String orphanBytes,
    required int localBooks,
    required int missingBooks,
    required int md5Missing,
  }) => _english
      ? 'Books $bookBytes · Covers $coverBytes · Cleanable $orphanBytes\n'
            'Local $localBooks · Missing $missingBooks · MD5 pending $md5Missing'
      : _japanese
      ? '本 $bookBytes · 表紙 $coverBytes · 消去可能 $orphanBytes\n'
            'ローカル $localBooks 冊 · 欠落 $missingBooks 冊 · MD5 未計算 $md5Missing 冊'
      : '书籍 $bookBytes · 封面 $coverBytes · 可清理 $orphanBytes\n'
            '本地 $localBooks 本 · 缺失 $missingBooks 本 · 待补 MD5 $md5Missing 本';

  String searchResults(String query, int count) => _english
      ? '$count results for “$query”'
      : _japanese
      ? '「$query」の検索結果（$count 件）'
      : '“$query”的结果（$count）';

  String stageSummary({
    required String duration,
    required String comparison,
    required int activeBooks,
    required int finishedBooks,
    required int notes,
  }) => _english
      ? 'Read $duration this period; $comparison. $activeBooks active books, '
            '$finishedBooks finished in total, and $notes new excerpts or notes.'
      : _japanese
      ? 'この期間は $duration 読み、$comparison。$activeBooks 冊を読み、累計 '
            '$finishedBooks 冊を読了、抜粋・ノートを $notes 件追加しました。'
      : '本阶段阅读 $duration，$comparison。阅读 $activeBooks 本，累计完成 '
            '$finishedBooks 本，新增 $notes 条书摘或笔记。';
  static AppStrings of(BuildContext context) =>
      AppStrings(Localizations.localeOf(context));
}
