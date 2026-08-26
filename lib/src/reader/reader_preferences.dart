import 'package:shared_preferences/shared_preferences.dart';

class ReaderPreferences {
  const ReaderPreferences({
    this.flow = 'paginated',
    this.pageTurnEffect = 'curl',
    this.columns = 1,
    this.margin = 24,
    this.fontSize = 18,
    this.lineHeight = 1.65,
    this.fontFamily = 'serif',
    this.fontWeight = 400,
    this.headingScale = 1.25,
    this.letterSpacing = 0,
    this.paragraphSpacing = 0.65,
    this.textIndent = 0,
    this.textAlign = 'start',
    this.writingMode = 'horizontal-tb',
    this.foreground = '#292b29',
    this.background = '#fbf8f1',
    this.preserveBookStyles = true,
    this.eInkMode = false,
    this.codeHighlight = true,
    this.backgroundImage = '',
    this.darkBackgroundImage = '',
    this.backgroundOpacity = 0.18,
    this.backgroundBlur = 0,
    this.backgroundFit = 'cover',
    this.importedFontName = '',
    this.importedFontData = '',
    this.txtChapterPattern = '',
    this.chineseConversion = 'original',
    this.tapZoneRatio = 0.28,
    this.swapTapZones = false,
    this.volumeKeyPaging = false,
    this.mouseWheelPaging = true,
    this.keepAwake = false,
    this.fullscreen = false,
    this.showHeader = true,
    this.showFooter = true,
    this.headerContent = 'title',
    this.footerContent = 'progress',
    this.customCss = '',
  });

  final String flow;
  final String pageTurnEffect;
  final int columns;
  final double margin;
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final int fontWeight;
  final double headingScale;
  final double letterSpacing;
  final double paragraphSpacing;
  final double textIndent;
  final String textAlign;
  final String writingMode;
  final String foreground;
  final String background;
  final bool preserveBookStyles;
  final bool eInkMode;
  final bool codeHighlight;
  final String backgroundImage;
  final String darkBackgroundImage;
  final double backgroundOpacity;
  final double backgroundBlur;
  final String backgroundFit;
  final String importedFontName;
  final String importedFontData;
  final String txtChapterPattern;
  final String chineseConversion;
  final double tapZoneRatio;
  final bool swapTapZones;
  final bool volumeKeyPaging;
  final bool mouseWheelPaging;
  final bool keepAwake;
  final bool fullscreen;
  final bool showHeader;
  final bool showFooter;
  final String headerContent;
  final String footerContent;
  final String customCss;

  ReaderPreferences copyWith({
    String? flow,
    String? pageTurnEffect,
    int? columns,
    double? margin,
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    int? fontWeight,
    double? headingScale,
    double? letterSpacing,
    double? paragraphSpacing,
    double? textIndent,
    String? textAlign,
    String? writingMode,
    String? foreground,
    String? background,
    bool? preserveBookStyles,
    bool? eInkMode,
    bool? codeHighlight,
    String? backgroundImage,
    String? darkBackgroundImage,
    double? backgroundOpacity,
    double? backgroundBlur,
    String? backgroundFit,
    String? importedFontName,
    String? importedFontData,
    String? txtChapterPattern,
    String? chineseConversion,
    double? tapZoneRatio,
    bool? swapTapZones,
    bool? volumeKeyPaging,
    bool? mouseWheelPaging,
    bool? keepAwake,
    bool? fullscreen,
    bool? showHeader,
    bool? showFooter,
    String? headerContent,
    String? footerContent,
    String? customCss,
  }) => ReaderPreferences(
    flow: flow ?? this.flow,
    pageTurnEffect: pageTurnEffect ?? this.pageTurnEffect,
    columns: columns ?? this.columns,
    margin: margin ?? this.margin,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    fontFamily: fontFamily ?? this.fontFamily,
    fontWeight: fontWeight ?? this.fontWeight,
    headingScale: headingScale ?? this.headingScale,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    textIndent: textIndent ?? this.textIndent,
    textAlign: textAlign ?? this.textAlign,
    writingMode: writingMode ?? this.writingMode,
    foreground: foreground ?? this.foreground,
    background: background ?? this.background,
    preserveBookStyles: preserveBookStyles ?? this.preserveBookStyles,
    eInkMode: eInkMode ?? this.eInkMode,
    codeHighlight: codeHighlight ?? this.codeHighlight,
    backgroundImage: backgroundImage ?? this.backgroundImage,
    darkBackgroundImage: darkBackgroundImage ?? this.darkBackgroundImage,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    backgroundBlur: backgroundBlur ?? this.backgroundBlur,
    backgroundFit: backgroundFit ?? this.backgroundFit,
    importedFontName: importedFontName ?? this.importedFontName,
    importedFontData: importedFontData ?? this.importedFontData,
    txtChapterPattern: txtChapterPattern ?? this.txtChapterPattern,
    chineseConversion: chineseConversion ?? this.chineseConversion,
    tapZoneRatio: tapZoneRatio ?? this.tapZoneRatio,
    swapTapZones: swapTapZones ?? this.swapTapZones,
    volumeKeyPaging: volumeKeyPaging ?? this.volumeKeyPaging,
    mouseWheelPaging: mouseWheelPaging ?? this.mouseWheelPaging,
    keepAwake: keepAwake ?? this.keepAwake,
    fullscreen: fullscreen ?? this.fullscreen,
    showHeader: showHeader ?? this.showHeader,
    showFooter: showFooter ?? this.showFooter,
    headerContent: headerContent ?? this.headerContent,
    footerContent: footerContent ?? this.footerContent,
    customCss: customCss ?? this.customCss,
  );

  static Future<ReaderPreferences> load() async {
    final values = await SharedPreferences.getInstance();
    return ReaderPreferences(
      flow: values.getString('leeef.reader.flow') ?? 'paginated',
      pageTurnEffect:
          values.getString('leeef.reader.page_turn_effect') ?? 'curl',
      columns: values.getInt('leeef.reader.columns') ?? 1,
      margin: values.getDouble('leeef.reader.margin') ?? 24,
      fontSize: values.getDouble('leeef.reader.font_size') ?? 18,
      lineHeight: values.getDouble('leeef.reader.line_height') ?? 1.65,
      fontFamily: values.getString('leeef.reader.font_family') ?? 'serif',
      fontWeight: values.getInt('leeef.reader.font_weight') ?? 400,
      headingScale: values.getDouble('leeef.reader.heading_scale') ?? 1.25,
      letterSpacing: values.getDouble('leeef.reader.letter_spacing') ?? 0,
      paragraphSpacing:
          values.getDouble('leeef.reader.paragraph_spacing') ?? 0.65,
      textIndent: values.getDouble('leeef.reader.text_indent') ?? 0,
      textAlign: values.getString('leeef.reader.text_align') ?? 'start',
      writingMode:
          values.getString('leeef.reader.writing_mode') ?? 'horizontal-tb',
      foreground: values.getString('leeef.reader.foreground') ?? '#292b29',
      background: values.getString('leeef.reader.background') ?? '#fbf8f1',
      preserveBookStyles:
          values.getBool('leeef.reader.preserve_book_styles') ?? true,
      eInkMode: values.getBool('leeef.reader.eink_mode') ?? false,
      codeHighlight: values.getBool('leeef.reader.code_highlight') ?? true,
      backgroundImage: values.getString('leeef.reader.background_image') ?? '',
      darkBackgroundImage:
          values.getString('leeef.reader.dark_background_image') ?? '',
      backgroundOpacity:
          values.getDouble('leeef.reader.background_opacity') ?? 0.18,
      backgroundBlur: values.getDouble('leeef.reader.background_blur') ?? 0,
      backgroundFit: values.getString('leeef.reader.background_fit') ?? 'cover',
      importedFontName:
          values.getString('leeef.reader.imported_font_name') ?? '',
      importedFontData:
          values.getString('leeef.reader.imported_font_data') ?? '',
      txtChapterPattern:
          values.getString('leeef.reader.txt_chapter_pattern') ?? '',
      chineseConversion:
          values.getString('leeef.reader.chinese_conversion') ?? 'original',
      tapZoneRatio: values.getDouble('leeef.reader.tap_zone_ratio') ?? 0.28,
      swapTapZones: values.getBool('leeef.reader.swap_tap_zones') ?? false,
      volumeKeyPaging:
          values.getBool('leeef.reader.volume_key_paging') ?? false,
      mouseWheelPaging:
          values.getBool('leeef.reader.mouse_wheel_paging') ?? true,
      keepAwake: values.getBool('leeef.reader.keep_awake') ?? false,
      fullscreen: values.getBool('leeef.reader.fullscreen') ?? false,
      showHeader: values.getBool('leeef.reader.show_header') ?? true,
      showFooter: values.getBool('leeef.reader.show_footer') ?? true,
      headerContent: values.getString('leeef.reader.header_content') ?? 'title',
      footerContent:
          values.getString('leeef.reader.footer_content') ?? 'progress',
      customCss: values.getString('leeef.reader.custom_css') ?? '',
    );
  }

  Future<void> save() async {
    final values = await SharedPreferences.getInstance();
    await Future.wait([
      values.setString('leeef.reader.flow', flow),
      values.setString('leeef.reader.page_turn_effect', pageTurnEffect),
      values.setInt('leeef.reader.columns', columns),
      values.setDouble('leeef.reader.margin', margin),
      values.setDouble('leeef.reader.font_size', fontSize),
      values.setDouble('leeef.reader.line_height', lineHeight),
      values.setString('leeef.reader.font_family', fontFamily),
      values.setInt('leeef.reader.font_weight', fontWeight),
      values.setDouble('leeef.reader.heading_scale', headingScale),
      values.setDouble('leeef.reader.letter_spacing', letterSpacing),
      values.setDouble('leeef.reader.paragraph_spacing', paragraphSpacing),
      values.setDouble('leeef.reader.text_indent', textIndent),
      values.setString('leeef.reader.text_align', textAlign),
      values.setString('leeef.reader.writing_mode', writingMode),
      values.setString('leeef.reader.foreground', foreground),
      values.setString('leeef.reader.background', background),
      values.setBool('leeef.reader.preserve_book_styles', preserveBookStyles),
      values.setBool('leeef.reader.eink_mode', eInkMode),
      values.setBool('leeef.reader.code_highlight', codeHighlight),
      values.setString('leeef.reader.background_image', backgroundImage),
      values.setString(
        'leeef.reader.dark_background_image',
        darkBackgroundImage,
      ),
      values.setDouble('leeef.reader.background_opacity', backgroundOpacity),
      values.setDouble('leeef.reader.background_blur', backgroundBlur),
      values.setString('leeef.reader.background_fit', backgroundFit),
      values.setString('leeef.reader.imported_font_name', importedFontName),
      values.setString('leeef.reader.imported_font_data', importedFontData),
      values.setString('leeef.reader.txt_chapter_pattern', txtChapterPattern),
      values.setString('leeef.reader.chinese_conversion', chineseConversion),
      values.setDouble('leeef.reader.tap_zone_ratio', tapZoneRatio),
      values.setBool('leeef.reader.swap_tap_zones', swapTapZones),
      values.setBool('leeef.reader.volume_key_paging', volumeKeyPaging),
      values.setBool('leeef.reader.mouse_wheel_paging', mouseWheelPaging),
      values.setBool('leeef.reader.keep_awake', keepAwake),
      values.setBool('leeef.reader.fullscreen', fullscreen),
      values.setBool('leeef.reader.show_header', showHeader),
      values.setBool('leeef.reader.show_footer', showFooter),
      values.setString('leeef.reader.header_content', headerContent),
      values.setString('leeef.reader.footer_content', footerContent),
      values.setString('leeef.reader.custom_css', customCss),
    ]);
  }
}
