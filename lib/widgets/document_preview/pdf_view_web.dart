import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Web implementation of the In-App PDF Viewer utilizing browser's native PDF renderer
class PdfViewWidget extends StatefulWidget {
  const PdfViewWidget({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;

  @override
  State<PdfViewWidget> createState() => _PdfViewWidgetState();
}

class _PdfViewWidgetState extends State<PdfViewWidget> {
  late final String _viewType;
  String? _blobUrl;

  @override
  void initState() {
    super.initState();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    _viewType = 'pdf-frame-$timestamp-${widget.fileName.hashCode}';

    try {
      final blob = web.Blob(
        [widget.bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'application/pdf'),
      );
      _blobUrl = web.URL.createObjectURL(blob);

      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) {
          final iframe = web.HTMLIFrameElement()
            ..src = '$_blobUrl#toolbar=1&navpanes=0'
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%';
          return iframe;
        },
      );
    } catch (e) {
      debugPrint('[PdfViewWidget] Failed to initialize PDF blob URL: $e');
    }
  }

  @override
  void dispose() {
    if (_blobUrl != null) {
      try {
        web.URL.revokeObjectURL(_blobUrl!);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_blobUrl == null) {
      return const Center(
        child: Text('Unable to render PDF in browser.'),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}

