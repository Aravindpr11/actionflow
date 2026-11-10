import 'dart:typed_data';
import 'file_picker/file_picker_stub.dart'
    if (dart.library.js_interop) 'file_picker/file_picker_web.dart'
    if (dart.library.io) 'file_picker/file_picker_io.dart' as impl;

/// Representation of a file picked from any platform (Web, Desktop, Mobile)
class AppPickedFile {
  AppPickedFile({
    required this.name,
    required this.bytes,
    int? size,
  }) : size = size ?? bytes.length;

  /// The raw file name including extension (e.g. Audit_Report.pdf)
  final String name;

  /// The size in bytes
  final int size;

  /// The binary content
  final Uint8List bytes;

  /// Lowercase extension without dot (e.g. 'pdf', 'xlsx')
  String get extension {
    final dot = name.lastIndexOf('.');
    return dot != -1 ? name.substring(dot + 1).toLowerCase() : '';
  }

  /// Human-readable formatted file size
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Abstract handler definition for test mocking
typedef FilePickerHandler = Future<AppPickedFile?> Function({
  required List<String> allowedExtensions,
});

/// Abstract handler definition for test mocking multiple file picking
typedef MultipleFilePickerHandler = Future<List<AppPickedFile>> Function({
  required List<String> allowedExtensions,
});

/// Abstract handler definition for test mocking file saving/download
typedef FileSaverHandler = Future<bool> Function({
  required String fileName,
  required Uint8List bytes,
  String mimeType,
});

/// Cross-platform device file picker providing robust native picking on Web, Desktop, and Mobile.
class AppFilePicker {
  AppFilePicker._();

  /// Test override hook allowing tests to inject mock picked files without platform dependencies
  static FilePickerHandler? testOverride;

  /// Test override hook allowing tests to inject mock multiple picked files without platform dependencies
  static MultipleFilePickerHandler? multiTestOverride;

  /// Test override hook allowing tests to inject mock save behavior without platform dependencies
  static FileSaverHandler? saveTestOverride;

  /// Supported extensions for HSSE documents
  static const List<String> defaultAllowedExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'png',
    'jpg',
    'jpeg',
    'webp',
    'csv',
    'txt',
  ];

  /// Opens the native device/browser file picker and reads the selected file's bytes.
  /// Returns `null` if the user cancels selection.
  static Future<AppPickedFile?> pickSingleFile({
    List<String> allowedExtensions = defaultAllowedExtensions,
  }) async {
    if (testOverride != null) {
      return testOverride!(allowedExtensions: allowedExtensions);
    }
    return impl.pickPlatformFile(allowedExtensions: allowedExtensions);
  }

  /// Opens the native device/browser file picker and reads multiple selected files.
  /// Returns empty list if the user cancels selection.
  static Future<List<AppPickedFile>> pickMultipleFiles({
    List<String> allowedExtensions = defaultAllowedExtensions,
  }) async {
    if (multiTestOverride != null) {
      return multiTestOverride!(allowedExtensions: allowedExtensions);
    }
    return impl.pickPlatformMultipleFiles(allowedExtensions: allowedExtensions);
  }

  /// Saves or downloads a file to the client platform.
  /// On Web: downloads the bytes through a native browser Blob and Anchor click.
  /// On Desktop / Mobile: opens the native save dialog and writes the bytes.
  /// Returns `true` if saved or downloaded, or `false` if cancelled.
  static Future<bool> saveFile({
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
    if (saveTestOverride != null) {
      return saveTestOverride!(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
    }
    return impl.savePlatformFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
  }
}
