import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import '../app_file_picker_service.dart';

Future<AppPickedFile?> pickPlatformFile({
  required List<String> allowedExtensions,
}) async {
  final completer = Completer<AppPickedFile?>();

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = false
    ..style.display = 'none';

  if (allowedExtensions.isNotEmpty) {
    input.accept = allowedExtensions.map((e) => '.$e').join(',');
  }

  bool isCompleted = false;

  void completeWith(AppPickedFile? file) {
    if (!isCompleted) {
      isCompleted = true;
      input.remove();
      if (!completer.isCompleted) {
        completer.complete(file);
      }
    }
  }

  void onLoadEnd(web.FileReader reader, web.File file, web.Event e) {
    final res = reader.result;
    if (res != null) {
      final byteBuffer = (res as JSArrayBuffer).toDart;
      final bytes = byteBuffer.asUint8List();
      completeWith(
        AppPickedFile(
          name: file.name,
          size: file.size,
          bytes: bytes,
        ),
      );
    } else {
      completeWith(null);
    }
  }

  void onChange(web.Event event) {
    final files = input.files;
    if (files == null || files.length == 0) {
      completeWith(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      completeWith(null);
      return;
    }

    final reader = web.FileReader();

    reader.addEventListener(
      'loadend',
      ((web.Event e) => onLoadEnd(reader, file, e)).toJS,
    );
    reader.addEventListener(
      'error',
      ((web.Event e) => completeWith(null)).toJS,
    );

    reader.readAsArrayBuffer(file);
  }

  void onCancel(web.Event event) {
    completeWith(null);
  }

  input.addEventListener('change', onChange.toJS);
  input.addEventListener('cancel', onCancel.toJS);

  final body = web.document.body;
  if (body != null) {
    body.appendChild(input);
  }

  input.click();

  return completer.future;
}

Future<List<AppPickedFile>> pickPlatformMultipleFiles({
  required List<String> allowedExtensions,
}) async {
  final completer = Completer<List<AppPickedFile>>();

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..style.display = 'none';

  if (allowedExtensions.isNotEmpty) {
    input.accept = allowedExtensions.map((e) => '.$e').join(',');
  }

  bool isCompleted = false;

  void completeWith(List<AppPickedFile> files) {
    if (!isCompleted) {
      isCompleted = true;
      input.remove();
      if (!completer.isCompleted) {
        completer.complete(files);
      }
    }
  }

  void onChange(web.Event event) async {
    final fileList = input.files;
    if (fileList == null || fileList.length == 0) {
      completeWith([]);
      return;
    }

    final List<AppPickedFile> results = [];
    int pending = fileList.length;

    for (int i = 0; i < fileList.length; i++) {
      final file = fileList.item(i);
      if (file == null) {
        pending--;
        if (pending == 0) completeWith(results);
        continue;
      }

      final reader = web.FileReader();

      reader.addEventListener(
        'loadend',
        ((web.Event e) {
          final res = reader.result;
          if (res != null) {
            final byteBuffer = (res as JSArrayBuffer).toDart;
            results.add(
              AppPickedFile(
                name: file.name,
                size: file.size,
                bytes: byteBuffer.asUint8List(),
              ),
            );
          }
          pending--;
          if (pending == 0) {
            completeWith(results);
          }
        }).toJS,
      );

      reader.addEventListener(
        'error',
        ((web.Event e) {
          pending--;
          if (pending == 0) {
            completeWith(results);
          }
        }).toJS,
      );

      reader.readAsArrayBuffer(file);
    }
  }

  void onCancel(web.Event event) {
    completeWith([]);
  }

  input.addEventListener('change', onChange.toJS);
  input.addEventListener('cancel', onCancel.toJS);

  final body = web.document.body;
  if (body != null) {
    body.appendChild(input);
  }

  input.click();

  return completer.future;
}

Future<bool> savePlatformFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  if (bytes.isEmpty) {
    throw ArgumentError('File bytes cannot be empty.');
  }
  if (fileName.trim().isEmpty) {
    throw ArgumentError('File name cannot be empty.');
  }

  try {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';

    final body = web.document.body;
    if (body != null) {
      body.appendChild(anchor);
    }
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (e) {
    throw StateError('Browser file download failed: $e');
  }
}

