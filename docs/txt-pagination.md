# TXT 分页与留白修复依据

## 开源实现对照（2026-09-03）

- Readest 的 [TXT 转换器](https://github.com/readest/readest/blob/6e11bee80323698ab469271b6a2780cb4d8d6bda/apps/readest-app/src/utils/txt.ts) 将 TXT 按章节生成 EPUB；[Foliate 分页器](https://github.com/readest/foliate-js/blob/b1fe9d3eb945c6fae7528377d2601c6bf3683835/paginator.js) 的 `columnize` 使用实际容器尺寸、边距及 CSS `column-fill: auto`，由浏览器完成断行。尺寸变化触发重排，并用内容锚点恢复阅读位置。
- Anx Reader 的 [TXT 转换器](https://github.com/Anxcye/anx-reader/blob/b339b6900efbc8409e8621490bf33bacba050449/lib/service/convert_to_epub/txt/convert_from_txt.dart) 也生成 EPUB；[分页器](https://github.com/Anxcye/anx-reader/blob/b339b6900efbc8409e8621490bf33bacba050449/assets/foliate-js/src/paginator.js) 同样基于 CSS 多栏、容器测量和 `scrollToAnchor`，不是按字符类别估算每页字数。

## 本次应用范围

Leeef 的 EPUB 已使用 Foliate，但 TXT 使用 Flutter，已有进度、书签、书摘绑定原文 offset。本次不改变文件格式和定位协议，也不直接移植浏览器代码，而是采用同一原则：分页与显示必须由同一个排版引擎、同一套几何参数决定。

- 移除放大字宽、行高的经验系数。用 `TextPainter` 测量经过实际缩进、段距、繁简转换后的页面，通过有界搜索找到可容纳的原文范围。
- 以 Unicode grapheme 为搜索边界，避免拆开代理对、组合字符或复合 emoji；原文切片连续拼接必须等于原文。
- 页面顶部对齐；分页模式使用窗口扣除用户边距后的宽度，不再固定限制到 760。连续滚动模式保留原有阅读宽度。
- 分页、正文和翻页快照共享字号、缩放、字重、行距及边距。`SelectableText` 底层还保留 2px 光标和 1px 间隔，测量和快照也扣除这 3px。
- 字体样式从 Material 主题解析后关闭继承，避免正文进入 Scaffold 后才继承另一套 leading/strut 规则，导致测量高度与真实行高不同；原生回归同时比较测量高度与正文高度。
- 底部保留 48px 控件、12px 外边距、12px 正文间隔及系统安全区；控件隐藏时不撤销底部预留，避免悬停导致页容量反复变化。
- 窗口或字体变化时保留原文 offset，再映射到新页，而不是沿用旧页码。

## 回归约束

测试不仅验证“不溢出”，还验证非末页不能在下一个完整字符仍能容纳时提前结束。覆盖中英文、段距/缩进、复合 emoji、字体缩放、手机/桌面宽度、短末页顶部对齐、原文连续性、真实 `SelectableText` 内部无滚动溢出及百万字输入的有界测量。

若后续统一 TXT 与 EPUB 引擎，需单独设计原文 offset 与 EPUB CFI 的双向映射，并迁移验证已有进度、书签、书摘、TTS 和同步数据。
