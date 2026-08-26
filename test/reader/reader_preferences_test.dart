import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/reader/reader_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'reader preferences persist layout, typography, theme, and CSS',
    () async {
      SharedPreferences.setMockInitialValues({});
      const preferences = ReaderPreferences(
        flow: 'scrolled',
        pageTurnEffect: 'none',
        columns: 2,
        margin: 36,
        fontSize: 22,
        lineHeight: 1.9,
        fontFamily: 'sans-serif',
        fontWeight: 500,
        headingScale: 1.5,
        letterSpacing: 0.8,
        paragraphSpacing: 1.1,
        textIndent: 2,
        textAlign: 'justify',
        writingMode: 'vertical-rl',
        foreground: '#eeeeee',
        background: '#000000',
        preserveBookStyles: false,
        eInkMode: true,
        codeHighlight: false,
        backgroundImage: 'data:image/png;base64,AA==',
        darkBackgroundImage: 'data:image/png;base64,AQ==',
        backgroundOpacity: .4,
        backgroundBlur: 8,
        backgroundFit: 'contain',
        importedFontName: 'reader.ttf',
        importedFontData: 'data:font/ttf;base64,AA==',
        txtChapterPattern: r'^Part \d+$',
        chineseConversion: 'traditional',
        tapZoneRatio: .35,
        swapTapZones: true,
        volumeKeyPaging: true,
        mouseWheelPaging: false,
        keepAwake: true,
        fullscreen: true,
        showHeader: false,
        showFooter: false,
        headerContent: 'chapter',
        footerContent: 'time',
        customCss: 'p { text-indent: 2em; }',
      );

      await preferences.save();
      final restored = await ReaderPreferences.load();

      expect(restored.flow, preferences.flow);
      expect(restored.pageTurnEffect, preferences.pageTurnEffect);
      expect(restored.columns, preferences.columns);
      expect(restored.margin, preferences.margin);
      expect(restored.fontSize, preferences.fontSize);
      expect(restored.lineHeight, preferences.lineHeight);
      expect(restored.fontFamily, preferences.fontFamily);
      expect(restored.fontWeight, preferences.fontWeight);
      expect(restored.headingScale, preferences.headingScale);
      expect(restored.letterSpacing, preferences.letterSpacing);
      expect(restored.paragraphSpacing, preferences.paragraphSpacing);
      expect(restored.textIndent, preferences.textIndent);
      expect(restored.textAlign, preferences.textAlign);
      expect(restored.writingMode, preferences.writingMode);
      expect(restored.foreground, preferences.foreground);
      expect(restored.background, preferences.background);
      expect(restored.preserveBookStyles, isFalse);
      expect(restored.eInkMode, isTrue);
      expect(restored.codeHighlight, isFalse);
      expect(restored.backgroundImage, preferences.backgroundImage);
      expect(restored.darkBackgroundImage, preferences.darkBackgroundImage);
      expect(restored.backgroundOpacity, preferences.backgroundOpacity);
      expect(restored.backgroundBlur, preferences.backgroundBlur);
      expect(restored.backgroundFit, preferences.backgroundFit);
      expect(restored.importedFontName, preferences.importedFontName);
      expect(restored.importedFontData, preferences.importedFontData);
      expect(restored.txtChapterPattern, preferences.txtChapterPattern);
      expect(restored.chineseConversion, preferences.chineseConversion);
      expect(restored.tapZoneRatio, preferences.tapZoneRatio);
      expect(restored.swapTapZones, isTrue);
      expect(restored.volumeKeyPaging, isTrue);
      expect(restored.mouseWheelPaging, isFalse);
      expect(restored.keepAwake, isTrue);
      expect(restored.fullscreen, isTrue);
      expect(restored.showHeader, isFalse);
      expect(restored.showFooter, isFalse);
      expect(restored.headerContent, preferences.headerContent);
      expect(restored.footerContent, preferences.footerContent);
      expect(restored.customCss, preferences.customCss);
    },
  );
}
