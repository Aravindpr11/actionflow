import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../app_file_picker_service.dart';

Future<AppPickedFile?> pickPlatformFile({
  required List<String> allowedExtensions,
}) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );

  if (files.isEmpty) {
    return null;
  }

  final file = files.first;
  Uint8List? bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (_) {
    if (file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (_) {}
    }
  }

  final fileSize = bytes?.length ?? (await file.length()) ?? 0;

  return AppPickedFile(
    name: file.name,
    size: fileSize,
    bytes: bytes ?? Uint8List(0),
  );
}

Future<List<AppPickedFile>> pickPlatformMultipleFiles({
  required List<String> allowedExtensions,
}) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );

  if (files.isEmpty) {
    return [];
  }

  final List<AppPickedFile> results = [];
  for (final file in files) {
    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (file.path != null) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (_) {}
      }
    }
    final fileSize = bytes?.length ?? (await file.length()) ?? 0;
    results.add(
      AppPickedFile(
        name: file.name,
        size: fileSize,
        bytes: bytes ?? Uint8List(0),
      ),
    );
  }
  return results;
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

  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
  );
  return uri != null;
}

