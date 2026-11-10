import 'dart:typed_data';
import '../app_file_picker_service.dart';

Future<AppPickedFile?> pickPlatformFile({
  required List<String> allowedExtensions,
}) async {
  throw UnsupportedError('File picking is not supported on this platform.');
}

Future<List<AppPickedFile>> pickPlatformMultipleFiles({
  required List<String> allowedExtensions,
}) async {
  throw UnsupportedError('File picking is not supported on this platform.');
}

Future<bool> savePlatformFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('File saving is not supported on this platform.');
}

