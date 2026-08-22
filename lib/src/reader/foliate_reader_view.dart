import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:leeef_reader/src/reader/foliate_reader_engine.dart';

class FoliateReaderView extends StatefulWidget {
  const FoliateReaderView({
    required this.engine,
    super.key,
    this.onWebViewCreated,
  });

  final FoliateReaderEngine engine;
  final void Function(InAppWebViewController controller)? onWebViewCreated;

  @override
  State<FoliateReaderView> createState() => _FoliateReaderViewState();
}

class _FoliateReaderViewState extends State<FoliateReaderView> {
  late final Future<void> _initialization = widget.engine.initialize();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('阅读器启动失败：${snapshot.error}'));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(widget.engine.readerUri.toString()),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            supportZoom: false,
            transparentBackground: true,
            mediaPlaybackRequiresUserGesture: true,
            allowFileAccess: false,
            allowFileAccessFromFileURLs: false,
            allowUniversalAccessFromFileURLs: false,
          ),
          onWebViewCreated: (controller) {
            widget.engine.attach(controller);
            widget.onWebViewCreated?.call(controller);
          },
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame ?? false) {
              // A main-frame error will also surface as a bridge timeout to the
              // command caller. The WebView keeps its native error page here.
            }
          },
        );
      },
    );
  }
}
