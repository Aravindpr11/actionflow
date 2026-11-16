import 'dart:convert';
import 'dart:math';
import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of creating an external share token
class ExternalTokenCreationResult {
  const ExternalTokenCreationResult({
    required this.token,
    required this.record,
  });

  /// The 32-byte hex raw plaintext token (displayed only once to manager)
  final String token;

  /// The persisted token metadata record with SHA-256 tokenHash
  final DocumentExternalToken record;

  String get rawToken => token;
}

/// Result of verifying an external share token
class ExternalTokenVerificationResult {
  const ExternalTokenVerificationResult({
    required this.success,
    this.document,
    this.tokenRecord,
    this.error,
    this.isRevoked = false,
    this.isExpired = false,
    this.isInvalid = false,
  });

  final bool success;
  final DocumentRecord? document;
  final DocumentExternalToken? tokenRecord;
  final String? error;
  final bool isRevoked;
  final bool isExpired;
  final bool isInvalid;

  bool get isValid => success && !isRevoked && !isExpired && !isInvalid;

  dynamic operator [](String key) {
    switch (key) {
      case 'success':
        return success;
      case 'document':
        return document;
      case 'token':
      case 'tokenRecord':
        return tokenRecord;
      case 'error':
        return error;
      case 'isRevoked':
        return isRevoked;
      case 'isExpired':
        return isExpired;
      case 'isInvalid':
        return isInvalid;
      default:
        return null;
    }
  }
}

/// In-memory Mock Document Store for test execution and offline mode
class MockDocumentStore {
  MockDocumentStore._() {
    _initializeSeedDocuments();
  }

  static final MockDocumentStore instance = MockDocumentStore._();

  final List<DocumentRecord> documents = [];
  final List<DocumentShare> shares = [];
  final List<DocumentExternalToken> externalTokens = [];

  void reset() {
    documents.clear();
    shares.clear();
    externalTokens.clear();
    _initializeSeedDocuments();
  }

  void _initializeSeedDocuments() {
    final now = DateTime.now();
    documents.addAll([
      DocumentRecord(
        id: 'doc-seed-001',
        organizationId: 'SOBHA-001',
        title: 'HSSE Manual 2026',
        description: 'Comprehensive Health, Safety, Security and Environment procedures manual (v4.2).',
        category: DocumentCategory.hsseManuals,
        fileName: 'HSSE_Manual_2026_v4.2.pdf',
        filePath: 'SOBHA-001/doc-seed-001/HSSE_Manual_2026_v4.2.pdf',
        fileSize: 2400000, // 2.4 MB
        fileType: 'application/pdf',
        storageBucket: 'documents',
        createdByName: 'M. Ali (Safety Lead)',
        createdBy: 'usr-ali-01',
        actionId: 'AF-1042',
        actionNumber: 'AF-1042',
        isArchived: false,
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now.subtract(const Duration(days: 20)),
        sharedInternalCount: 2,
        sharedExternalCount: 1,
        sharedWithUserIds: ['staff-uuid-001', 'staff-uuid-002'],
      ),
      DocumentRecord(
        id: 'doc-seed-002',
        organizationId: 'SOBHA-001',
        title: 'Site Audit Checklist',
        description: 'Standard inspection and compliance verification checklist template.',
        category: DocumentCategory.auditChecklists,
        fileName: 'Site_Audit_Checklist_Template.xlsx',
        filePath: 'SOBHA-001/doc-seed-002/Site_Audit_Checklist_Template.xlsx',
        fileSize: 540000, // 540 KB
        fileType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        storageBucket: 'documents',
        createdByName: 'R. Kumar (Compliance Mgr)',
        createdBy: 'usr-kumar-01',
        actionId: 'AF-1048',
        actionNumber: 'AF-1048',
        isArchived: false,
        createdAt: now.subtract(const Duration(days: 25)),
        updatedAt: now.subtract(const Duration(days: 15)),
        sharedInternalCount: 1,
        sharedExternalCount: 0,
        sharedWithUserIds: ['staff-uuid-001'],
      ),
      DocumentRecord(
        id: 'doc-seed-003',
        organizationId: 'SOBHA-001',
        title: 'Incident Protocol',
        description: 'Emergency response, escalation path, and notification guidelines.',
        category: DocumentCategory.incidentReports,
        fileName: 'Emergency_Incident_Protocol.pdf',
        filePath: 'SOBHA-001/doc-seed-003/Emergency_Incident_Protocol.pdf',
        fileSize: 1800000, // 1.8 MB
        fileType: 'application/pdf',
        storageBucket: 'documents',
        createdByName: 'M. Ali (Safety Lead)',
        createdBy: 'usr-ali-01',
        actionId: 'AF-1053',
        actionNumber: 'AF-1053',
        isArchived: false,
        createdAt: now.subtract(const Duration(days: 18)),
        updatedAt: now.subtract(const Duration(days: 5)),
        sharedInternalCount: 3,
        sharedExternalCount: 2,
        sharedWithUserIds: ['staff-uuid-001', 'staff-uuid-002', 'staff-uuid-003'],
      ),
      DocumentRecord(
        id: 'doc-seed-004',
        organizationId: 'SOBHA-001',
        title: 'PPE Matrix & Policy',
        description: 'Personal Protective Equipment standard requirements by work zone and site.',
        category: DocumentCategory.policies,
        fileName: 'PPE_Requirements_Matrix_2026.pdf',
        filePath: 'SOBHA-001/doc-seed-004/PPE_Requirements_Matrix_2026.pdf',
        fileSize: 1100000, // 1.1 MB
        fileType: 'application/pdf',
        storageBucket: 'documents',
        createdByName: 'Safety Operations',
        createdBy: 'usr-ops-01',
        isArchived: false,
        createdAt: now.subtract(const Duration(days: 45)),
        updatedAt: now.subtract(const Duration(days: 10)),
        sharedInternalCount: 0,
        sharedExternalCount: 0,
      ),
    ]);

    // Initial seed shares
    shares.addAll([
      DocumentShare(
        id: 'share-001',
        documentId: 'doc-seed-001',
        userId: 'staff-uuid-001',
        userName: 'Staff Alice',
        userEmail: 'alice@sobha.com',
        organizationId: 'SOBHA-001',
        permission: 'view',
        sharedBy: 'usr-ali-01',
        sharedByName: 'M. Ali',
        createdAt: now.subtract(const Duration(days: 10)),
      ),
      DocumentShare(
        id: 'share-002',
        documentId: 'doc-seed-001',
        userId: 'staff-uuid-002',
        userName: 'Staff Bob',
        userEmail: 'bob@sobha.com',
        organizationId: 'SOBHA-001',
        permission: 'download',
        sharedBy: 'usr-ali-01',
        sharedByName: 'M. Ali',
        createdAt: now.subtract(const Duration(days: 10)),
      ),
      DocumentShare(
        id: 'share-003',
        documentId: 'doc-seed-002',
        userId: 'staff-uuid-001',
        userName: 'Staff Alice',
        userEmail: 'alice@sobha.com',
        organizationId: 'SOBHA-001',
        permission: 'view',
        sharedBy: 'usr-kumar-01',
        sharedByName: 'R. Kumar',
        createdAt: now.subtract(const Duration(days: 8)),
      ),
      DocumentShare(
        id: 'share-004',
        documentId: 'doc-seed-003',
        userId: 'staff-uuid-001',
        userName: 'Staff Alice',
        userEmail: 'alice@sobha.com',
        organizationId: 'SOBHA-001',
        permission: 'download',
        sharedBy: 'usr-ali-01',
        sharedByName: 'M. Ali',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      DocumentShare(
        id: 'share-005',
        documentId: 'doc-seed-003',
        userId: 'staff-uuid-002',
        userName: 'Staff Bob',
        userEmail: 'bob@sobha.com',
        organizationId: 'SOBHA-001',
        permission: 'view',
        sharedBy: 'usr-ali-01',
        sharedByName: 'M. Ali',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      DocumentShare(
        id: 'share-006',
        documentId: 'doc-seed-003',
        userId: 'staff-uuid-003',
        userName: 'Staff Charlie',
        userEmail: 'charlie@sobha.com',
        organizationId: 'SOBHA-001',
        permission: 'view',
        sharedBy: 'usr-ali-01',
        sharedByName: 'M. Ali',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
    ]);
  }
}

/// A bounded [OutputMemoryStream] that enforces strict byte limits during decompression.
/// Prevents memory exhaustion or decompression bombs by aborting decompression
/// the instant written bytes exceed [maxBytes].
class BoundedOutputMemoryStream extends OutputMemoryStream {
  final int maxBytes;

  BoundedOutputMemoryStream({required this.maxBytes, super.size});

  void _checkLimit(int additional) {
    if (length + additional > maxBytes) {
      throw ArchiveException(
        'Decompression limit exceeded: attempted to decompress ${length + additional} bytes (max: $maxBytes bytes). Possible zip bomb.',
      );
    }
  }

  @override
  void writeByte(int value) {
    _checkLimit(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final len = length ?? bytes.length;
    _checkLimit(len);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _checkLimit(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _checkLimit(count);
    super.writeBackReference(distance, count);
  }
}

/// Service managing Document storage, metadata, permissions, and sharing
class DocumentService {
  DocumentService({SupabaseClient? client}) : _clientOverride = client;

  static final DocumentService instance = DocumentService();

  /// Explicitly enabled by unit tests that exercise the in-memory store.
  /// The application never falls back to mock documents when Supabase fails.
  static bool allowInMemoryStoreForTests = false;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _client => _clientOverride ?? SupabaseConfig.clientOrNull;

  bool get isReady =>
      _client != null && (_clientOverride != null || SupabaseConfig.isInitialized);

  void _requirePersistenceOrTestStore() {
    if (!isReady && !allowInMemoryStoreForTests) {
      throw StateError(
        'Document storage is unavailable because the Supabase client is not initialized.',
      );
    }
  }

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool _isValidUuid(String? id) => id != null && _uuidRegex.hasMatch(id.trim());

  static String _resolveEffectiveOrgId(String orgId) {
    if (allowInMemoryStoreForTests) {
      return orgId;
    }
    if (orgId == 'SOBHA-001') {
      return '00000000-0000-0000-0000-000000000001';
    }
    return orgId;
  }

  static bool isOrgMatch(String? orgA, String? orgB) {
    if (orgA == null || orgB == null) return false;
    if (orgA == orgB) return true;
    final isA = orgA == 'SOBHA-001' || orgA == '00000000-0000-0000-0000-000000000001';
    final isB = orgB == 'SOBHA-001' || orgB == '00000000-0000-0000-0000-000000000001';
    return isA && isB;
  }

  static bool _isOrgMatch(String? orgA, String? orgB) => isOrgMatch(orgA, orgB);

  /// Checks if a storage bucket exists on the Supabase backend
  Future<bool> checkBucketExists({String bucket = 'documents'}) async {
    final client = _client;
    if (!isReady || client == null) return false;
    try {
      final res = await client.storage.getBucket(bucket);
      return res.id.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Max allowed file size: 25 MB
  static const int maxFileSize = 25 * 1024 * 1024;

  /// Supported file extensions
  static const Set<String> supportedExtensions = {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'rtf',
    'png',
    'jpg',
    'jpeg',
    'webp',
    'csv',
    'txt',
  };

  /// Maximum number of entries permitted in an OpenXML ZIP archive (zip bomb protection).
  static const int maxZipEntries = 1000;

  /// Maximum total uncompressed size permitted across all entries in an OpenXML ZIP archive (100 MB).
  static const int maxTotalDecompressedSize = 100 * 1024 * 1024;

  /// Maximum uncompressed size permitted for any single entry in an OpenXML ZIP archive (50 MB).
  static const int maxSingleEntrySize = 50 * 1024 * 1024;

  /// Maximum uncompressed size permitted for [Content_Types].xml (512 KB).
  static const int maxContentTypesSize = 512 * 1024;

  /// Scans [bytes] up to [maxScan] length to check if [pattern] sequence exists.
  static bool _containsSubsequence(List<int> bytes, List<int> pattern, [int maxScan = 65536]) {
    final limit = min(bytes.length, maxScan);
    if (pattern.isEmpty || limit < pattern.length) return false;
    for (int i = 0; i <= limit - pattern.length; i++) {
      bool match = true;
      for (int j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  /// Inspects a ZIP archive's package structure to verify OpenXML document contents
  /// with comprehensive zip bomb, path traversal, entry limits, and content-type enforcement.
  /// All decompression occurs strictly in-memory without any filesystem extraction.
  /// Enforces early central directory parsing, entry count bounds, declared uncompressed limits,
  /// required document parts (word/document.xml or xl/workbook.xml), package relationships (_rels/.rels),
  /// and stream-bounded manifest decompression that aborts the instant byte limits are exceeded.
  ///
  /// Note on Validation Scope:
  /// This performs deep OpenXML package integrity and signature validation (ZIP container safety,
  /// Central Directory limits, path traversal defense, stream-bounded manifest inspection,
  /// required document/workbook XML part verification, and relationship package structure).
  /// It verifies container authenticity and protects against disguised/malicious files,
  /// strictly distinguishing package signature validation from full Office document rendering/semantic parsing.
  /// Returns null if valid for the given [expectedType] ('docx' or 'xlsx'),
  /// or a descriptive error message if invalid.
  static String? _validateOpenXmlPackage(List<int> bytes, String expectedType) {
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4B ||
        bytes[2] != 0x03 ||
        bytes[3] != 0x04) {
      return 'File validation error: Content does not match expected OpenXML ZIP container.';
    }

    // Step 1: Early Central Directory inspection via ZipDirectory
    // Parses central directory headers without decompressing or allocating entries in memory.
    final zipDir = ZipDirectory();
    try {
      zipDir.read(InputMemoryStream(bytes));
      if (zipDir.filePosition < 0 || zipDir.fileHeaders.isEmpty) {
        return 'File validation error: Corrupt or malformed ZIP container for .$expectedType file.';
      }
    } catch (_) {
      return 'File validation error: Corrupt or malformed ZIP container for .$expectedType file.';
    }

    // Step 2: Earliest entry count check (checked as early as possible before processing files)
    final entryCount = max(zipDir.totalCentralDirectoryEntries, zipDir.fileHeaders.length);
    if (entryCount > maxZipEntries) {
      return 'File validation error: ZIP archive contains excessive entries ($entryCount > $maxZipEntries), possible zip bomb.';
    }

    // Step 3: Inspect declared uncompressed sizes and path traversal on all headers before decompression
    int totalDeclaredSize = 0;
    bool hasContentTypesHeader = false;
    bool hasWordDocument = false;
    bool hasWordPart = false;
    bool hasExcelWorkbook = false;
    bool hasExcelPart = false;

    for (final header in zipDir.fileHeaders) {
      // Enforce individual entry declared size limits and guard against integer overflows
      if (header.uncompressedSize < 0 || header.uncompressedSize > maxSingleEntrySize) {
        return 'File validation error: ZIP entry (${header.filename}) uncompressed size exceeds safety limit (${header.uncompressedSize} bytes).';
      }

      totalDeclaredSize += header.uncompressedSize;
      if (totalDeclaredSize > maxTotalDecompressedSize) {
        return 'File validation error: ZIP archive total uncompressed size exceeds safety limit (${(totalDeclaredSize / (1024 * 1024)).toStringAsFixed(1)} MB > 100 MB), possible zip bomb.';
      }

      // Path traversal protection: normalize slashes, reject '..' segments, absolute roots, or drive letters
      final normalized = header.filename.replaceAll('\\', '/');
      if (normalized.startsWith('/') ||
          RegExp(r'^[a-zA-Z]:').hasMatch(normalized) ||
          normalized.split('/').any((seg) => seg == '..')) {
        return 'File validation error: Path traversal sequence detected in ZIP entry (${header.filename}).';
      }

      if (normalized == '[Content_Types].xml' || normalized.endsWith('/[Content_Types].xml')) {
        hasContentTypesHeader = true;
      }
      if (normalized == 'word/document.xml' || normalized.endsWith('/word/document.xml')) {
        hasWordDocument = true;
      }
      if (normalized.startsWith('word/') || normalized.contains('/word/')) {
        hasWordPart = true;
      }
      if (normalized == 'xl/workbook.xml' || normalized.endsWith('/xl/workbook.xml')) {
        hasExcelWorkbook = true;
      }
      if (normalized.startsWith('xl/') || normalized.contains('/xl/')) {
        hasExcelPart = true;
      }
    }

    // Step 4: Strict package structure validation
    if (!hasContentTypesHeader) {
      return expectedType == 'docx'
          ? 'File validation error: File is a generic ZIP archive, not a valid Word (.docx) document.'
          : 'File validation error: File is a generic ZIP archive, not a valid Excel (.xlsx) spreadsheet.';
    }

    // Reject archives containing conflicting Word and Excel package structures
    if (hasWordPart && hasExcelPart) {
      return 'File validation error: Archive contains conflicting Word and Excel package structures.';
    }

    // Step 5: Decode archive container safely to inspect [Content_Types].xml
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
      if (archive.files.isEmpty) {
        return 'File validation error: Corrupt or malformed ZIP container for .$expectedType file.';
      }
    } catch (_) {
      return 'File validation error: Corrupt or malformed ZIP container for .$expectedType file.';
    }

    ArchiveFile? contentTypesFile;
    for (final file in archive.files) {
      final norm = file.name.replaceAll('\\', '/');
      if (norm == '[Content_Types].xml' || norm.endsWith('/[Content_Types].xml')) {
        contentTypesFile = file;
        break;
      }
    }

    if (contentTypesFile == null) {
      return expectedType == 'docx'
          ? 'File validation error: File is a generic ZIP archive, not a valid Word (.docx) document.'
          : 'File validation error: File is a generic ZIP archive, not a valid Excel (.xlsx) spreadsheet.';
    }

    // Enforce declared size ceiling on [Content_Types].xml before decompression
    if (contentTypesFile.size < 0 || contentTypesFile.size > maxContentTypesSize) {
      return 'File validation error: [Content_Types].xml uncompressed size exceeds safety limit (${contentTypesFile.size} bytes).';
    }

    // Step 6: Controlled bounded decompression of [Content_Types].xml
    // Decompresses strictly in-memory into BoundedOutputMemoryStream.
    // If actual decompressed output exceeds maxContentTypesSize (512 KB), decompression aborts immediately.
    final boundedOut = BoundedOutputMemoryStream(maxBytes: maxContentTypesSize);
    try {
      contentTypesFile.decompress(boundedOut);
    } catch (e) {
      return 'File validation error: ZIP decompression limit exceeded during processing, possible zip bomb.';
    }

    final contentBytes = boundedOut.getBytes();
    if (contentBytes.isEmpty) {
      return 'File validation error: [Content_Types].xml is empty or corrupt.';
    }

    final contentStr = utf8.decode(contentBytes, allowMalformed: true);
    final hasWordContentType = contentStr.contains('wordprocessingml');
    final hasExcelContentType = contentStr.contains('spreadsheetml');

    if (hasWordContentType && hasExcelContentType) {
      return 'File validation error: Archive contains conflicting Word and Excel package structures.';
    }

    if (expectedType == 'docx') {
      if ((hasExcelPart || hasExcelContentType) && (!hasWordPart && !hasWordContentType)) {
        return 'File validation error: Content is an Excel spreadsheet (.xlsx) renamed as a Word (.docx) document.';
      }
      if (!hasWordPart || !hasWordDocument) {
        return 'File validation error: File is a generic ZIP archive, not a valid Word (.docx) document.';
      }
      if (!hasWordContentType) {
        return 'File validation error: [Content_Types].xml does not define WordprocessingML content type.';
      }
    } else if (expectedType == 'xlsx') {
      if ((hasWordPart || hasWordContentType) && (!hasExcelPart && !hasExcelContentType)) {
        return 'File validation error: Content is a Word document (.docx) renamed as an Excel (.xlsx) spreadsheet.';
      }
      if (!hasExcelPart || !hasExcelWorkbook) {
        return 'File validation error: File is a generic ZIP archive, not a valid Excel (.xlsx) spreadsheet.';
      }
      if (!hasExcelContentType) {
        return 'File validation error: [Content_Types].xml does not define SpreadsheetML content type.';
      }
    }

    return null;
  }

  /// Validates file type, size, and optional magic-byte content. Returns null if valid, or an error string if invalid.
  static String? validateFile({
    required String fileName,
    required int fileSize,
    List<int>? fileBytes,
  }) {
    if (fileName.trim().isEmpty) {
      return 'File name cannot be empty.';
    }

    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) {
      return 'File must have a valid extension (e.g. .pdf, .docx, .xlsx).';
    }

    final ext = fileName.substring(dotIndex + 1).toLowerCase();
    if (!supportedExtensions.contains(ext)) {
      return 'Unsupported file format (.$ext). Supported formats: PDF, DOC, DOCX, XLS, XLSX, RTF, PNG, JPG, JPEG, WEBP, CSV, TXT.';
    }

    if (fileSize <= 0) {
      return 'File cannot be empty.';
    }

    if (fileSize > maxFileSize) {
      return 'File size (${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB) exceeds the maximum allowed limit of 25 MB.';
    }

    // Magic-byte signature verification when file content is available
    if (fileBytes != null && fileBytes.isNotEmpty) {
      // 1. Blacklist check: Executable binaries (MZ for Windows PE, ELF for Linux, Mach-O for Mac)
      if (fileBytes.length >= 2 && fileBytes[0] == 0x4D && fileBytes[1] == 0x5A) {
        return 'Security Violation: Executable file disguised as .$ext is not permitted.';
      }
      if (fileBytes.length >= 4 &&
          fileBytes[0] == 0x7F &&
          fileBytes[1] == 0x45 &&
          fileBytes[2] == 0x4C &&
          fileBytes[3] == 0x46) {
        return 'Security Violation: Executable ELF binary disguised as .$ext is not permitted.';
      }
      if (fileBytes.length >= 4 &&
          ((fileBytes[0] == 0xCA && fileBytes[1] == 0xFE && fileBytes[2] == 0xBA && fileBytes[3] == 0xBE) ||
           (fileBytes[0] == 0xCF && fileBytes[1] == 0xFA && fileBytes[2] == 0xED && fileBytes[3] == 0xFE))) {
        return 'Security Violation: Executable Mach-O binary disguised as .$ext is not permitted.';
      }

      // 2. Specific format magic byte validation
      switch (ext) {
        case 'pdf':
          // PDF must start with %PDF (0x25, 0x50, 0x44, 0x46)
          if (fileBytes.length < 4 ||
              fileBytes[0] != 0x25 ||
              fileBytes[1] != 0x50 ||
              fileBytes[2] != 0x44 ||
              fileBytes[3] != 0x46) {
            return 'File validation error: Content does not match expected PDF signature.';
          }
          break;
        case 'png':
          // PNG magic: 0x89, 0x50, 0x4E, 0x47
          if (fileBytes.length < 4 ||
              fileBytes[0] != 0x89 ||
              fileBytes[1] != 0x50 ||
              fileBytes[2] != 0x4E ||
              fileBytes[3] != 0x47) {
            return 'File validation error: Content does not match expected PNG signature.';
          }
          break;
        case 'jpg':
        case 'jpeg':
          // JPEG magic: 0xFF, 0xD8, 0xFF
          if (fileBytes.length < 3 ||
              fileBytes[0] != 0xFF ||
              fileBytes[1] != 0xD8 ||
              fileBytes[2] != 0xFF) {
            return 'File validation error: Content does not match expected JPEG signature.';
          }
          break;
        case 'webp':
          // WebP magic: 'RIFF' at 0..3 and 'WEBP' at 8..11 (if length >= 12)
          if (fileBytes.length < 4 ||
              fileBytes[0] != 0x52 ||
              fileBytes[1] != 0x49 ||
              fileBytes[2] != 0x46 ||
              fileBytes[3] != 0x46) {
            return 'File validation error: Content does not match expected WEBP signature.';
          }
          if (fileBytes.length >= 12 &&
              (fileBytes[8] != 0x57 ||
               fileBytes[9] != 0x45 ||
               fileBytes[10] != 0x42 ||
               fileBytes[11] != 0x50)) {
            return 'File validation error: RIFF container does not contain valid WEBP header.';
          }
          break;
        case 'docx':
          final openXmlDocxErr = _validateOpenXmlPackage(fileBytes, 'docx');
          if (openXmlDocxErr != null) {
            return openXmlDocxErr;
          }
          break;
        case 'xlsx':
          final openXmlXlsxErr = _validateOpenXmlPackage(fileBytes, 'xlsx');
          if (openXmlXlsxErr != null) {
            return openXmlXlsxErr;
          }
          break;
        case 'doc':
          if (fileBytes.length >= 2 && fileBytes[0] == 0x50 && fileBytes[1] == 0x4B) {
            return 'File validation error: ZIP archive or OpenXML file disguised as legacy Word (.doc) document is not permitted.';
          }
          final isRtf = fileBytes.length >= 5 &&
              fileBytes[0] == 0x7B &&
              fileBytes[1] == 0x5C &&
              fileBytes[2] == 0x72 &&
              fileBytes[3] == 0x74 &&
              fileBytes[4] == 0x66; // '{\rtf'
          if (isRtf) {
            return 'File validation error: RTF content disguised as legacy Word (.doc) document is not permitted. Please use the .rtf extension.';
          }
          final isOle = fileBytes.length >= 4 &&
              fileBytes[0] == 0xD0 &&
              fileBytes[1] == 0xCF &&
              fileBytes[2] == 0x11 &&
              fileBytes[3] == 0xE0;
          if (isOle) {
            final hasWordDocUtf16 = _containsSubsequence(fileBytes, const [
              0x57, 0x00, 0x6F, 0x00, 0x72, 0x00, 0x64, 0x00,
              0x44, 0x00, 0x6F, 0x00, 0x63, 0x00, 0x75, 0x00,
              0x6D, 0x00, 0x65, 0x00, 0x6E, 0x00, 0x74, 0x00
            ]); // 'WordDocument' in UTF-16LE
            final hasWordDocAscii = _containsSubsequence(
              fileBytes,
              const [0x57, 0x6F, 0x72, 0x64, 0x44, 0x6F, 0x63, 0x75, 0x6D, 0x65, 0x6E, 0x74],
            );
            final hasWorkbookUtf16 = _containsSubsequence(fileBytes, const [
              0x57, 0x00, 0x6F, 0x00, 0x72, 0x00, 0x6B, 0x00,
              0x62, 0x00, 0x6F, 0x00, 0x6F, 0x00, 0x6B, 0x00
            ]); // 'Workbook' in UTF-16LE
            final hasWorkbookAscii = _containsSubsequence(
              fileBytes,
              const [0x57, 0x6F, 0x72, 0x6B, 0x62, 0x6F, 0x6F, 0x6B],
            );
            final hasBookUtf16 = _containsSubsequence(fileBytes, const [
              0x42, 0x00, 0x6F, 0x00, 0x6F, 0x00, 0x6B, 0x00
            ]); // 'Book' in UTF-16LE
            final hasBookAscii = _containsSubsequence(fileBytes, const [0x42, 0x6F, 0x6F, 0x6B]);

            final hasWord = hasWordDocUtf16 || hasWordDocAscii;
            final hasExcel = hasWorkbookUtf16 || hasWorkbookAscii || hasBookUtf16 || hasBookAscii;

            if (hasExcel && !hasWord) {
              return 'File validation error: Content is an Excel spreadsheet (.xls) renamed as a Word (.doc) document.';
            }
            if (!hasWord) {
              return 'File validation error: Content does not match expected Word (.doc) document signature.';
            }
          } else {
            return 'File validation error: Content does not match expected Word (.doc) document signature.';
          }
          break;
        case 'rtf':
          final isRtf = fileBytes.length >= 5 &&
              fileBytes[0] == 0x7B &&
              fileBytes[1] == 0x5C &&
              fileBytes[2] == 0x72 &&
              fileBytes[3] == 0x74 &&
              fileBytes[4] == 0x66; // '{\rtf'
          if (!isRtf) {
            return 'File validation error: Content does not match expected RTF signature.';
          }
          break;
        case 'xls':
          if (fileBytes.length >= 2 && fileBytes[0] == 0x50 && fileBytes[1] == 0x4B) {
            return 'File validation error: ZIP archive or OpenXML file disguised as legacy Excel (.xls) spreadsheet is not permitted.';
          }
          final isBiffBof = fileBytes.length >= 2 &&
              fileBytes[0] == 0x09 &&
              (fileBytes[1] == 0x08 || fileBytes[1] == 0x04 || fileBytes[1] == 0x02 || fileBytes[1] == 0x00);
          final isOleXls = fileBytes.length >= 4 &&
              fileBytes[0] == 0xD0 &&
              fileBytes[1] == 0xCF &&
              fileBytes[2] == 0x11 &&
              fileBytes[3] == 0xE0;
          if (isOleXls) {
            final hasWordDocUtf16 = _containsSubsequence(fileBytes, const [
              0x57, 0x00, 0x6F, 0x00, 0x72, 0x00, 0x64, 0x00,
              0x44, 0x00, 0x6F, 0x00, 0x63, 0x00, 0x75, 0x00,
              0x6D, 0x00, 0x65, 0x00, 0x6E, 0x00, 0x74, 0x00
            ]);
            final hasWordDocAscii = _containsSubsequence(
              fileBytes,
              const [0x57, 0x6F, 0x72, 0x64, 0x44, 0x6F, 0x63, 0x75, 0x6D, 0x65, 0x6E, 0x74],
            );
            final hasWorkbookUtf16 = _containsSubsequence(fileBytes, const [
              0x57, 0x00, 0x6F, 0x00, 0x72, 0x00, 0x6B, 0x00,
              0x62, 0x00, 0x6F, 0x00, 0x6F, 0x00, 0x6B, 0x00
            ]);
            final hasWorkbookAscii = _containsSubsequence(
              fileBytes,
              const [0x57, 0x6F, 0x72, 0x6B, 0x62, 0x6F, 0x6F, 0x6B],
            );
            final hasBookUtf16 = _containsSubsequence(fileBytes, const [
              0x42, 0x00, 0x6F, 0x00, 0x6F, 0x00, 0x6B, 0x00
            ]);
            final hasBookAscii = _containsSubsequence(fileBytes, const [0x42, 0x6F, 0x6F, 0x6B]);

            final hasWord = hasWordDocUtf16 || hasWordDocAscii;
            final hasExcel = hasWorkbookUtf16 || hasWorkbookAscii || hasBookUtf16 || hasBookAscii;

            if (hasWord && !hasExcel) {
              return 'File validation error: Content is a Word document (.doc) renamed as an Excel (.xls) spreadsheet.';
            }
            if (!hasExcel) {
              return 'File validation error: Content does not match expected Excel (.xls) spreadsheet signature.';
            }
          } else if (!isBiffBof) {
            return 'File validation error: Content does not match expected Excel (.xls) spreadsheet signature.';
          }
          break;
        case 'txt':
        case 'csv':
          // Plain text / CSV files must not start with binary executable or archive signatures
          if (fileBytes.length >= 4 &&
              ((fileBytes[0] == 0x50 && fileBytes[1] == 0x4B && fileBytes[2] == 0x03 && fileBytes[3] == 0x04) ||
               (fileBytes[0] == 0x25 && fileBytes[1] == 0x50 && fileBytes[2] == 0x44 && fileBytes[3] == 0x46) ||
               (fileBytes[0] == 0x89 && fileBytes[1] == 0x50 && fileBytes[2] == 0x4E && fileBytes[3] == 0x47))) {
            return 'File validation error: Binary file disguised as plain text / CSV is not permitted.';
          }
          // Must not contain null bytes in the scanned sample (first 1024 bytes)
          final sampleLimit = min(fileBytes.length, 1024);
          for (int i = 0; i < sampleLimit; i++) {
            if (fileBytes[i] == 0x00) {
              return 'File validation error: Binary control characters detected in plain text / CSV file.';
            }
          }
          break;
      }
    }

    return null;
  }

  /// Determines MIME type from file extension
  static String resolveMimeType(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1) return 'application/octet-stream';
    final ext = fileName.substring(dotIndex + 1).toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'rtf':
        return 'application/rtf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'csv':
        return 'text/csv';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  /// Generates a cryptographically strong 32-character hex token
  static String generateSecureToken() {
    final rand = Random.secure();
    final values = List<int>.generate(32, (i) => rand.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Formats storage errors with clear, actionable diagnostics for managers
  static String formatStorageError(dynamic error) {
    if (error is StorageException) {
      final code = error.statusCode;
      final msg = error.message;
      if (code == '404' || msg.toLowerCase().contains('bucket not found')) {
        return 'Storage bucket "documents" not found on the backend ($msg). '
            'Please ensure the storage bucket exists and migration 20261021000001_documents_system_and_sharing.sql has been initialized in your environment.';
      } else if (code == '403' || code == '401') {
        return 'Storage permission denied ($code: $msg). '
            'Ensure the user is authorized to upload to the organization storage bucket.';
      }
      return 'Failed to upload file to storage: $msg (Status: $code)';
    }
    final errStr = error.toString();
    if (errStr.toLowerCase().contains('bucket not found') || errStr.contains('404')) {
      return 'Storage bucket "documents" not found on the backend ($errStr). '
          'Please ensure the storage bucket exists and migration 20261021000001_documents_system_and_sharing.sql has been initialized in your environment.';
    }
    return 'Failed to upload file to storage: $error';
  }

  /// Formats document upload errors with actionable diagnostics for user feedback
  static String formatUploadError(dynamic error) {
    if (error is StorageException) {
      final code = error.statusCode;
      final msg = error.message;
      if (code == '403' || code == '401' || msg.toLowerCase().contains('access denied') || msg.toLowerCase().contains('permission denied')) {
        return 'Storage access denied ($code): You do not have permission to upload files to this organization storage bucket.';
      } else if (code == '404' || msg.toLowerCase().contains('bucket not found')) {
        return 'Storage bucket "documents" not found on the backend.';
      }
      return 'Storage upload failed ($code): $msg';
    }
    final str = error.toString();
    if (str.contains('42501') || str.toLowerCase().contains('permission denied')) {
      return 'Upload permission denied: You do not have permission to upload documents to this organization.';
    }
    if (str.toLowerCase().contains('socket') ||
        str.toLowerCase().contains('clientexception') ||
        str.toLowerCase().contains('failed host lookup') ||
        str.toLowerCase().contains('network')) {
      return 'Network error connecting to storage. Please check your internet connection.';
    }
    return str.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
  }

  /// Formats download, preview, and storage retrieval errors with clear diagnostics
  static String formatDownloadError(dynamic error) {
    if (error is StorageException) {
      final code = error.statusCode;
      final msg = error.message;
      if (code == '403' || code == '401' || msg.toLowerCase().contains('access denied')) {
        return 'Access denied: You do not have permission to view or download this document ($code: $msg).';
      } else if (code == '404' || msg.toLowerCase().contains('not found')) {
        return 'Document file not found in storage. It may have been deleted or archived.';
      }
      return 'Storage error ($code): $msg';
    }
    final str = error.toString();
    if (str.contains('42501') ||
        str.toLowerCase().contains('permission denied') ||
        str.contains('PGRST116')) {
      return 'Access denied: You do not have permission to view or download this document.';
    }
    if (str.toLowerCase().contains('not found')) {
      return 'Document not found or no longer available.';
    }
    if (str.toLowerCase().contains('socket') ||
        str.toLowerCase().contains('clientexception') ||
        str.toLowerCase().contains('failed host lookup') ||
        str.toLowerCase().contains('network')) {
      return 'Network error connecting to storage. Please check your internet connection.';
    }
    return str.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
  }

  // ===========================================================================
  // 1. FETCH DOCUMENTS
  // ===========================================================================

  /// Fetches documents for an organization, with optional category, actionId, and search query.
  Future<List<DocumentRecord>> fetchDocuments({
    required String organizationId,
    String? category,
    String? actionId,
    String? departmentId,
    String? searchQuery,
    String? currentUserId,
    String? userRole,
  }) async {
    _requirePersistenceOrTestStore();
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    final client = _client;

    if (isReady && client != null) {
      try {
        dynamic query = client
            .from('documents')
            .select('*')
            .eq('organization_id', effectiveOrgId)
            .eq('is_archived', false);

        if (category != null && category.isNotEmpty && category != 'All') {
          query = query.eq('category', category);
        }

        if (actionId != null && actionId.isNotEmpty) {
          query = query.eq('action_id', actionId);
        }

        if (departmentId != null && departmentId.isNotEmpty) {
          query = query.eq('department_id', departmentId);
        }

        final response = await query.order('created_at', ascending: false);
        if (response is List) {
          final docs = response.map((json) => DocumentRecord.fromJson(json as Map<String, dynamic>)).toList();

          // Enrich documents with active internal shares info from document_shares
          try {
            final sharesRes = await client
                .from('document_shares')
                .select('document_id, user_id, shared_by, shared_by_name, created_at')
                .eq('organization_id', effectiveOrgId);
            if (sharesRes.isNotEmpty) {
              final Map<String, List<String>> sharedRecipients = {};
              final Map<String, List<String>> sharedSenders = {};
              final Map<String, String> senderNames = {};
              final Map<String, DateTime> shareTimestamps = {};
              for (final s in sharesRes) {
                final dId = s['document_id']?.toString() ?? '';
                final uId = s['user_id']?.toString() ?? '';
                final sBy = s['shared_by']?.toString() ?? '';
                final sName = s['shared_by_name']?.toString() ?? '';
                final sAt = s['created_at'] != null ? DateTime.tryParse(s['created_at'].toString()) : null;
                if (dId.isNotEmpty && uId.isNotEmpty) {
                  sharedRecipients.putIfAbsent(dId, () => []).add(uId);
                }
                if (dId.isNotEmpty && sBy.isNotEmpty) {
                  sharedSenders.putIfAbsent(dId, () => []).add(sBy);
                  if (currentUserId != null && uId == currentUserId) {
                    senderNames[dId] = sName;
                    if (sAt != null) shareTimestamps[dId] = sAt;
                  }
                }
              }
              for (int i = 0; i < docs.length; i++) {
                final docId = docs[i].id;
                final recipients = sharedRecipients[docId] ?? [];
                final senders = sharedSenders[docId] ?? [];
                docs[i] = docs[i].copyWith(
                  sharedWithUserIds: recipients,
                  sharedByUserIds: senders,
                  sharedInternalCount: recipients.length,
                  sharedByUserName: senderNames[docId],
                  sharedAt: shareTimestamps[docId],
                );
              }
            }
          } catch (sharesErr) {
            debugPrint('[DocumentService] fetchDocuments shares enrichment note: $sharesErr');
          }

          if (searchQuery != null && searchQuery.trim().isNotEmpty) {
            final q = searchQuery.trim().toLowerCase();
            return docs.where((d) =>
              d.title.toLowerCase().contains(q) ||
              d.fileName.toLowerCase().contains(q) ||
              d.description.toLowerCase().contains(q) ||
              (d.actionNumber != null && d.actionNumber!.toLowerCase().contains(q))
            ).toList();
          }
          return docs;
        }
      } catch (e) {
        debugPrint('[DocumentService] fetchDocuments Supabase error: $e');
        rethrow;
      }
    }

    // Fallback: Mock Document Store
    var docs = MockDocumentStore.instance.documents
        .where((d) => _isOrgMatch(d.organizationId, organizationId) && !d.isArchived)
        .toList();

    if (category != null && category.isNotEmpty && category != 'All') {
      docs = docs.where((d) => d.category.toLowerCase() == category.toLowerCase()).toList();
    }

    if (actionId != null && actionId.isNotEmpty) {
      docs = docs.where((d) => d.actionId == actionId || d.actionNumber == actionId).toList();
    }

    if (departmentId != null && departmentId.isNotEmpty) {
      docs = docs.where((d) => d.departmentId == departmentId).toList();
    }

    if (currentUserId != null &&
        (userRole?.toLowerCase() == 'worker' ||
            userRole?.toLowerCase() == 'staff')) {
      final uid = currentUserId.trim();
      docs = docs.where((d) {
        final isOwner = d.isOwnedBy(uid);
        final isShared = d.isSharedWith(uid) ||
            MockDocumentStore.instance.shares
                .any((s) => s.documentId == d.id && s.userId == uid);
        final isSharedByMe = d.isSharedBy(uid) ||
            MockDocumentStore.instance.shares
                .any((s) => s.documentId == d.id && s.sharedBy == uid);
        final isPolicy = d.category == DocumentCategory.hsseManuals ||
            d.category == DocumentCategory.policies ||
            d.category.toLowerCase().contains('polic') ||
            d.category.toLowerCase().contains('manual') ||
            d.category.toLowerCase().contains('guide');
        final isAction = actionId != null &&
            (d.actionId == actionId || d.actionNumber == actionId);

        // Department check: if document belongs to another department,
        // it is only accessible if explicitly shared, authored, or linked:
        if (departmentId != null &&
            departmentId.isNotEmpty &&
            d.departmentId != null &&
            d.departmentId!.isNotEmpty &&
            d.departmentId != departmentId) {
          if (!isShared && !isOwner && !isSharedByMe && !isAction) {
            return false;
          }
        }

        return isOwner || isShared || isSharedByMe || isPolicy || isAction;
      }).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      docs = docs.where((d) =>
        d.title.toLowerCase().contains(q) ||
        d.fileName.toLowerCase().contains(q) ||
        d.description.toLowerCase().contains(q) ||
        (d.actionNumber != null && d.actionNumber!.toLowerCase().contains(q))
      ).toList();
    }

    docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return docs;
  }

  // ===========================================================================
  // 2. UPLOAD DOCUMENT
  // ===========================================================================

  /// Uploads a document file and saves its metadata
  Future<DocumentRecord> uploadDocument({
    required String organizationId,
    required String title,
    required String fileName,
    required List<int> fileBytes,
    String description = '',
    String category = DocumentCategory.general,
    String? actionId,
    String? actionNumber,
    String? departmentId,
    required String userId,
    required String userName,
  }) async {
    // 1. Strict Validation
    final validationError = validateFile(
      fileName: fileName,
      fileSize: fileBytes.length,
      fileBytes: fileBytes,
    );
    if (validationError != null) {
      throw ArgumentError(validationError);
    }
    _requirePersistenceOrTestStore();

    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    final sanitizedTitle = title.trim().isEmpty ? fileName : title.trim();
    final fileType = resolveMimeType(fileName);
    final now = DateTime.now();
    final documentId = 'doc-${now.millisecondsSinceEpoch}-${Random().nextInt(9999)}';
    final storagePath = '$effectiveOrgId/$documentId/$fileName';

    final client = _client;
    final currentAuthUid = client?.auth.currentUser?.id;
    final effectiveUserId = (currentAuthUid != null && _isValidUuid(currentAuthUid))
        ? currentAuthUid
        : (_isValidUuid(userId) ? userId : null);

    // Resolve departmentId:
    // 1. If explicit valid UUID was passed (e.g. from linked action), use it.
    // 2. If actionId is provided but departmentId was omitted, attempt lookup from linked action.
    // 3. If genuinely general repository document (no action), only ordinary staff auto-inherit
    //    their department to preserve staff department isolation. Managers and Admins retain
    //    department_id = NULL so general documents remain organization-wide.
    String? resolvedDeptId = _isValidUuid(departmentId) ? departmentId : null;

    if (resolvedDeptId == null && isReady && client != null) {
      if (actionId != null && _isValidUuid(actionId)) {
        try {
          final actionRow = await client
              .from('actions')
              .select('department_id')
              .eq('id', actionId)
              .maybeSingle();
          if (actionRow != null && actionRow['department_id'] != null) {
            final actDept = actionRow['department_id'].toString();
            if (_isValidUuid(actDept)) resolvedDeptId = actDept;
          }
        } catch (e) {
          debugPrint('[DocumentService] linked action department lookup note: $e');
        }
      }

      if (resolvedDeptId == null && effectiveUserId != null) {
        try {
          final profileRow = await client
              .from('profiles')
              .select('department_id, roles(code)')
              .eq('id', effectiveUserId)
              .maybeSingle();
          if (profileRow != null) {
            final roleData = profileRow['roles'];
            String? roleCode;
            if (roleData is Map) {
              roleCode = roleData['code']?.toString().toLowerCase();
            } else if (roleData is List && roleData.isNotEmpty && roleData.first is Map) {
              roleCode = roleData.first['code']?.toString().toLowerCase();
            }
            final isStaff = roleCode == 'staff' || roleCode == 'worker';
            if (isStaff && profileRow['department_id'] != null) {
              final staffDept = profileRow['department_id'].toString();
              if (_isValidUuid(staffDept)) resolvedDeptId = staffDept;
            }
          }
        } catch (e) {
          debugPrint('[DocumentService] profile department lookup note: $e');
        }
      }
    }
    final effectiveDepartmentId = _isValidUuid(resolvedDeptId) ? resolvedDeptId : null;

    if (isReady && client != null) {
      // A. Upload to Supabase Storage
      try {
        await client.storage.from('documents').uploadBinary(
          storagePath,
          Uint8List.fromList(fileBytes),
          fileOptions: FileOptions(
            contentType: fileType,
            upsert: false,
          ),
        );
      } catch (storageErr) {
        throw Exception(formatStorageError(storageErr));
      }

      // B. Persist metadata in database if storage succeeded
      try {
        final insertData = {
          'id': documentId,
          'organization_id': effectiveOrgId,
          'title': sanitizedTitle,
          'description': description.trim(),
          'category': category,
          'file_name': fileName,
          'file_path': storagePath,
          'file_size': fileBytes.length,
          'file_type': fileType,
          'storage_bucket': 'documents',
          'action_id': actionId,
          'action_number': actionNumber,
          'department_id': ?effectiveDepartmentId,
          'created_by': ?effectiveUserId,
          'created_by_name': userName,
          'ownership_status': 'verified',
          'is_archived': false,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };

        final response = await client.from('documents').insert(insertData).select().single();
        final doc = DocumentRecord.fromJson(response).copyWith(isPersisted: true);
        // Also keep in sync with mock store for seamless fallback/caching
        MockDocumentStore.instance.documents.removeWhere((d) => d.id == doc.id);
        MockDocumentStore.instance.documents.insert(0, doc.copyWith(fileBytes: fileBytes));
        return doc;
      } catch (dbErr) {
        // Rollback storage file on DB error to prevent orphaned objects
        try {
          await client.storage.from('documents').remove([storagePath]);
        } catch (cleanupErr) {
          debugPrint('[DocumentService] Warning: Failed to clean up orphaned storage object "$storagePath": $cleanupErr');
        }
        throw Exception('Failed to save document metadata: $dbErr');
      }
    }

    // Mock Store implementation (offline / testing)
    final record = DocumentRecord(
      id: documentId,
      organizationId: organizationId,
      title: sanitizedTitle,
      description: description.trim(),
      category: category,
      fileName: fileName,
      filePath: storagePath,
      fileSize: fileBytes.length,
      fileType: fileType,
      storageBucket: 'documents',
      actionId: actionId,
      actionNumber: actionNumber,
      departmentId: effectiveDepartmentId ?? departmentId,
      createdBy: userId,
      createdByName: userName,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
      fileBytes: fileBytes,
      isPersisted: false,
    );

    MockDocumentStore.instance.documents.insert(0, record);
    return record;
  }

  // ===========================================================================
  // 3. EDIT METADATA
  // ===========================================================================

  /// Updates document metadata (title, description, category, linked action)
  Future<DocumentRecord> updateDocumentMetadata({
    required String documentId,
    required String organizationId,
    required String title,
    String description = '',
    String category = DocumentCategory.general,
    String? actionId,
    String? actionNumber,
    String? departmentId,
    String? currentUserId,
    String? userRole,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError('Document title cannot be empty.');
    }
    _requirePersistenceOrTestStore();

    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    final effectiveDepartmentId = _isValidUuid(departmentId) ? departmentId : null;
    final client = _client;
    if (isReady && client != null) {
      try {
        final updateData = {
          'title': cleanTitle,
          'description': description.trim(),
          'category': category,
          'action_id': actionId,
          'action_number': actionNumber,
          'department_id': ?effectiveDepartmentId,
          'updated_at': DateTime.now().toIso8601String(),
        };

        final response = await client
            .from('documents')
            .update(updateData)
            .eq('id', documentId)
            .eq('organization_id', effectiveOrgId)
            .select()
            .single();

        final updated = DocumentRecord.fromJson(response);
        final idx = MockDocumentStore.instance.documents.indexWhere((d) => d.id == documentId);
        if (idx != -1) {
          MockDocumentStore.instance.documents[idx] = updated.copyWith(
            fileBytes: MockDocumentStore.instance.documents[idx].fileBytes,
          );
        }
        return updated;
      } catch (e) {
        throw Exception('Failed to update document metadata: $e');
      }
    }

    // Mock update
    final idx = MockDocumentStore.instance.documents.indexWhere(
      (d) => d.id == documentId && _isOrgMatch(d.organizationId, organizationId),
    );
    if (idx == -1) {
      throw StateError('Document not found in organization.');
    }

    final existing = MockDocumentStore.instance.documents[idx];

    // Authorization check matching documents_org_update RLS and enforce_document_immutability:
    // Anonymous or unauthenticated callers are strictly prohibited
    if (currentUserId == null || currentUserId.trim().isEmpty) {
      throw StateError('Authentication required. Anonymous or unauthenticated document updates are strictly prohibited.');
    }

    final isOwner = existing.createdBy == currentUserId;
    final isEditRecipient = MockDocumentStore.instance.shares.any(
      (s) => s.documentId == documentId && s.userId == currentUserId && s.permission == 'edit',
    );
    final isAdmin = userRole != null &&
        (userRole.toLowerCase() == 'admin' ||
         userRole.toLowerCase() == 'company_admin' ||
         userRole.toLowerCase() == 'platform_admin' ||
         userRole.toLowerCase() == 'service_role');

    if (!isOwner && !isEditRecipient && !isAdmin) {
      throw StateError('User does not have permission to edit this document.');
    }

    final updated = existing.copyWith(
      title: cleanTitle,
      description: description.trim(),
      category: category,
      actionId: actionId,
      actionNumber: actionNumber,
      clearAction: actionId == null || actionId.isEmpty,
      departmentId: departmentId ?? existing.departmentId,
      updatedAt: DateTime.now(),
    );

    MockDocumentStore.instance.documents[idx] = updated;
    return updated;
  }

  // ===========================================================================
  // 4. DELETE DOCUMENT
  // ===========================================================================

  /// Deletes a document: removes both storage object and database record
  Future<void> deleteDocument({
    required String documentId,
    required String organizationId,
    required String userId,
    String? userRole,
    String? userName,
  }) async {
    _requirePersistenceOrTestStore();
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    final client = _client;
    String? filePath;

    // Check existing document
    final docInMock = MockDocumentStore.instance.documents.firstWhere(
      (d) => d.id == documentId && _isOrgMatch(d.organizationId, organizationId),
      orElse: () => DocumentRecord(
        id: '',
        organizationId: '',
        title: '',
        fileName: '',
        filePath: '',
        fileSize: 0,
        fileType: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    if (docInMock.id.isNotEmpty) {
      filePath = docInMock.filePath;
      final isStaff = userRole?.toLowerCase() == 'staff' || userRole?.toLowerCase() == 'worker';
      final isOwner = docInMock.isOwnedBy(userId) ||
          (userName != null &&
              userName.isNotEmpty &&
              docInMock.createdByName.toLowerCase() == userName.toLowerCase());
      if (isStaff && !isOwner) {
        throw ArgumentError('Staff members can only delete documents they authored.');
      }
    }

    if (isReady && client != null) {
      try {
        // Fetch path and ownership from DB if not known
        if (filePath == null) {
          final res = await client
              .from('documents')
              .select('file_path, created_by, created_by_name')
              .eq('id', documentId)
              .eq('organization_id', effectiveOrgId)
              .maybeSingle();
          if (res != null) {
            filePath = res['file_path']?.toString();
            final isStaff = userRole?.toLowerCase() == 'staff' ||
                userRole?.toLowerCase() == 'worker';
            final createdBy = res['created_by']?.toString();
            final createdByName = res['created_by_name']?.toString();
            final isOwner = (createdBy != null && createdBy == userId) ||
                (userName != null &&
                    userName.isNotEmpty &&
                    createdByName != null &&
                    createdByName.toLowerCase() == userName.toLowerCase());
            if (isStaff && !isOwner) {
              throw ArgumentError(
                'Staff members can only delete documents they authored.',
              );
            }
          }
        }

        // 1. Delete storage object
        if (filePath != null && filePath.isNotEmpty) {
          await client.storage.from('documents').remove([filePath]);
        }

        // 2. Delete database record (cascades to shares & tokens)
        await client
            .from('documents')
            .delete()
            .eq('id', documentId)
            .eq('organization_id', effectiveOrgId);
      } catch (e) {
        if (e is ArgumentError) rethrow;
        throw Exception('Failed to delete document: $e');
      }
    }

    // Clean up mock store
    MockDocumentStore.instance.documents.removeWhere(
      (d) => d.id == documentId && _isOrgMatch(d.organizationId, organizationId),
    );
    MockDocumentStore.instance.shares.removeWhere((s) => s.documentId == documentId);
    MockDocumentStore.instance.externalTokens.removeWhere((t) => t.documentId == documentId);
  }

  // ===========================================================================
  // 5. VIEW & DOWNLOAD (SIGNED URL / BYTES)
  // ===========================================================================

  /// Generates a secure, short-lived signed download URL (e.g. 5 minutes)
  Future<String> getDownloadUrl({
    required String documentId,
    required String organizationId,
    int expiresInSeconds = 300,
  }) async {
    _requirePersistenceOrTestStore();
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    final client = _client;
    if (isReady && client != null) {
      try {
        final res = await client
            .from('documents')
            .select('file_path, storage_bucket')
            .eq('id', documentId)
            .eq('organization_id', effectiveOrgId)
            .single();

        final path = res['file_path']?.toString() ?? '';
        final bucket = res['storage_bucket']?.toString() ?? 'documents';
        if (path.isEmpty) throw StateError('File path is empty');

        final signedUrl = await client.storage
            .from(bucket)
            .createSignedUrl(path, expiresInSeconds);
        return signedUrl;
      } catch (e) {
        debugPrint('[DocumentService] getDownloadUrl error: $e');
        rethrow;
      }
    }

    // Mock fallback: data URL or simulated secure link
    return 'https://actionflow.enterprise/storage/signed/$organizationId/$documentId?expires=${DateTime.now().add(Duration(seconds: expiresInSeconds)).millisecondsSinceEpoch}';
  }

  /// Retrieves document binary bytes (for preview, tests, or direct download)
  Future<List<int>> getDocumentBytes({
    required String documentId,
    required String organizationId,
  }) async {
    _requirePersistenceOrTestStore();
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    final client = _client;
    if (isReady && client != null) {
      try {
        final res = await client
            .from('documents')
            .select('file_path, storage_bucket')
            .eq('id', documentId)
            .eq('organization_id', effectiveOrgId)
            .single();

        final path = res['file_path']?.toString() ?? '';
        final bucket = res['storage_bucket']?.toString() ?? 'documents';
        final bytes = await client.storage.from(bucket).download(path);
        return bytes;
      } catch (e) {
        debugPrint('[DocumentService] getDocumentBytes storage error: $e');
        rethrow;
      }
    }

    final doc = MockDocumentStore.instance.documents.firstWhere(
      (d) => d.id == documentId,
      orElse: () => throw StateError('Document not found.'),
    );

    if (doc.fileBytes != null && doc.fileBytes!.isNotEmpty) {
      return doc.fileBytes!;
    }

    // Default simulated bytes (plain text sample)
    return utf8.encode('ActionFlow Enterprise Document Content: ${doc.title} (${doc.fileName})');
  }

  /// Downloads the document binary and invokes the platform file saver to save it on the user's filesystem.
  Future<bool> downloadAndSaveDocument({
    required DocumentRecord doc,
    required String organizationId,
  }) async {
    final List<int> bytes;
    if (doc.fileBytes != null && doc.fileBytes!.isNotEmpty) {
      bytes = doc.fileBytes!;
    } else {
      bytes = await getDocumentBytes(
        documentId: doc.id,
        organizationId: organizationId,
      );
    }
    if (bytes.isEmpty) {
      throw StateError('Retrieved document bytes are empty.');
    }
    return AppFilePicker.saveFile(
      fileName: doc.fileName,
      bytes: Uint8List.fromList(bytes),
      mimeType: doc.fileType,
    );
  }

  // ===========================================================================
  // 6. INTERNAL SHARING
  // ===========================================================================

  /// Shares a document with one or more internal users
  Future<dynamic> shareDocumentInternal({
    required String documentId,
    required String organizationId,
    List<Map<String, String>>? users,
    String? userId,
    String? userName,
    String? userEmail,
    required String sharedBy,
    required String sharedByName,
    String permission = 'view',
    String? callerRole,
    String? callerDepartmentId,
    String? recipientDepartmentId,
    String? recipientRole,
    bool? recipientIsActive,
    String? recipientOrganizationId,
    Set<String>? allowedDepartmentIds,
  }) async {
    _requirePersistenceOrTestStore();
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    final client = _client;
    final now = DateTime.now();
    final newShares = <DocumentShare>[];

    // Client-side rule validation matching DB trigger enforce_document_share_department_isolation
    if (recipientIsActive == false) {
      throw ArgumentError('Share recipient is inactive or does not exist.');
    }
    if (recipientOrganizationId != null &&
        recipientOrganizationId.isNotEmpty &&
        !_isOrgMatch(recipientOrganizationId, organizationId) &&
        !_isOrgMatch(recipientOrganizationId, effectiveOrgId)) {
      throw ArgumentError('Recipient belongs to a different organization.');
    }

    final isStaff = callerRole?.toLowerCase() == 'worker' || callerRole?.toLowerCase() == 'staff';
    final docMatch = MockDocumentStore.instance.documents.where((d) => d.id == documentId).toList();
    if (docMatch.isNotEmpty) {
      final doc = docMatch.first;
      final rRole = recipientRole?.toLowerCase() ?? '';
      final isRecipientManager = rRole.contains('manager') ||
          rRole.contains('admin') ||
          rRole.contains('director') ||
          rRole.contains('lead') ||
          rRole.contains('head');

      if (isStaff) {
        if (!isRecipientManager) {
          // Staff sharing with another Staff member: must be document author
          if (doc.createdBy != null &&
              doc.createdBy!.isNotEmpty &&
              doc.createdBy != sharedBy &&
              doc.createdBy != sharedBy.trim()) {
            throw ArgumentError('Staff members can only share documents they authored.');
          }
          // Staff sharing with another Staff member: strictly same department
          if (callerDepartmentId != null &&
              callerDepartmentId.isNotEmpty &&
              recipientDepartmentId != null &&
              recipientDepartmentId.isNotEmpty &&
              callerDepartmentId != recipientDepartmentId) {
            throw ArgumentError('Department Isolation Violation: Staff members cannot share documents outside their own department.');
          }
          if (doc.departmentId != null &&
              doc.departmentId!.isNotEmpty &&
              recipientDepartmentId != null &&
              recipientDepartmentId.isNotEmpty &&
              recipientDepartmentId != doc.departmentId) {
            throw ArgumentError('Department Isolation Violation: Staff member cannot receive shares for documents outside their own department.');
          }
        }
      } else {
        // Caller is Manager or Admin
        if (!isRecipientManager) {
          // Manager sharing with Staff member:
          // Check if recipient department is within manager's authorized scope
          final isScopeAllowed = allowedDepartmentIds != null &&
              allowedDepartmentIds.isNotEmpty &&
              recipientDepartmentId != null &&
              allowedDepartmentIds.contains(recipientDepartmentId);
          final isSameDept = (callerDepartmentId != null &&
                  callerDepartmentId.isNotEmpty &&
                  callerDepartmentId == recipientDepartmentId) ||
              (doc.departmentId != null &&
                  doc.departmentId!.isNotEmpty &&
                  doc.departmentId == recipientDepartmentId);

          if (!isScopeAllowed && !isSameDept) {
            throw ArgumentError('Department Isolation Violation: Staff member cannot receive shares for documents outside their own department.');
          }
        }
      }
    }

    final targetUsers = <Map<String, String>>[];
    if (users != null) targetUsers.addAll(users);
    if (userId != null && userId.trim().isNotEmpty) {
      targetUsers.add({
        'id': userId.trim(),
        'name': userName ?? '',
        'email': userEmail ?? '',
      });
    }

    if (targetUsers.isEmpty) {
      throw ArgumentError('Share recipient is inactive or does not exist.');
    }


    for (final u in targetUsers) {
      final uId = u['id'] ?? '';
      final uName = u['name'] ?? '';
      final uEmail = u['email'] ?? '';
      if (uId.isEmpty) continue;

      final currentAuthUid = client?.auth.currentUser?.id;
      final effectiveSharedBy = _isValidUuid(sharedBy)
          ? sharedBy
          : (currentAuthUid != null && _isValidUuid(currentAuthUid) ? currentAuthUid : null);

      final share = DocumentShare(
        id: 'share-${now.millisecondsSinceEpoch}-${Random().nextInt(9999)}',
        documentId: documentId,
        userId: uId,
        userName: uName,
        userEmail: uEmail,
        organizationId: effectiveOrgId,
        permission: permission,
        sharedBy: effectiveSharedBy ?? sharedBy,
        sharedByName: sharedByName,
        createdAt: now,
      );

      if (isReady && client != null) {
        try {
          final shareMap = <String, dynamic>{
            'id': share.id,
            'document_id': share.documentId,
            'user_id': share.userId,
            'user_name': share.userName,
            'user_email': share.userEmail,
            'organization_id': effectiveOrgId,
            'permission': share.permission,
            'shared_by': ?effectiveSharedBy,
            'shared_by_name': share.sharedByName,
            'created_at': share.createdAt.toIso8601String(),
          };
          await client.from('document_shares').upsert(
            shareMap,
            onConflict: 'document_id, user_id',
          );
        } catch (e) {
          debugPrint('[DocumentService] shareDocumentInternal Supabase error: $e');
          rethrow;
        }
      }

      // Sync mock store
      MockDocumentStore.instance.shares.removeWhere(
        (s) => s.documentId == documentId && s.userId == uId,
      );
      MockDocumentStore.instance.shares.add(share);
      newShares.add(share);
    }

    // Update document shared internal count
    _updateMockCounts(documentId);
    if (userId != null && newShares.isNotEmpty) {
      return newShares.first;
    }
    return newShares;
  }

  /// Revokes internal access for a user
  Future<void> revokeDocumentInternalShare({
    required String documentId,
    String? userId,
    String? shareId,
    required String organizationId,
  }) async {
    _requirePersistenceOrTestStore();
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    String effectiveUserId = userId ?? '';
    if (effectiveUserId.isEmpty && shareId != null) {
      final s = MockDocumentStore.instance.shares.firstWhere(
        (sh) => sh.id == shareId,
        orElse: () => DocumentShare(
          id: '',
          documentId: '',
          userId: '',
          organizationId: '',
          createdAt: DateTime.now(),
        ),
      );
      effectiveUserId = s.userId;
    }

    final client = _client;
    if (isReady && client != null) {
      try {
        var query = client.from('document_shares').delete().eq('document_id', documentId);
        if (effectiveUserId.isNotEmpty) {
          query = query.eq('user_id', effectiveUserId);
        } else if (shareId != null) {
          query = query.eq('id', shareId);
        }
        await query.eq('organization_id', effectiveOrgId);
      } catch (e) {
        debugPrint('[DocumentService] revokeDocumentInternalShare Supabase error: $e');
        rethrow;
      }
    }

    MockDocumentStore.instance.shares.removeWhere(
      (s) => s.documentId == documentId && (
        (effectiveUserId.isNotEmpty && s.userId == effectiveUserId) ||
        (shareId != null && s.id == shareId)
      ),
    );

    _updateMockCounts(documentId);
  }

  /// Fetches internal shares for a document
  Future<List<DocumentShare>> fetchInternalShares(String documentId) async {
    _requirePersistenceOrTestStore();
    final client = _client;
    if (isReady && client != null) {
      try {
        final res = await client
            .from('document_shares')
            .select('*')
            .eq('document_id', documentId);
        return (res as List).map((json) => DocumentShare.fromJson(json as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('[DocumentService] fetchInternalShares error: $e');
        rethrow;
      }
    }

    return MockDocumentStore.instance.shares
        .where((s) => s.documentId == documentId)
        .toList();
  }

  /// Alias for fetching internal shares with organization context
  Future<List<DocumentShare>> fetchDocumentShares({
    required String documentId,
    required String organizationId,
  }) => fetchInternalShares(documentId);

  /// Fetches IDs of documents that were shared with the specified user ID
  Future<List<String>> fetchDocumentIdsSharedWith({
    required String organizationId,
    required String userId,
  }) async {
    _requirePersistenceOrTestStore();
    final client = _client;
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);

    if (isReady && client != null) {
      try {
        final res = await client
            .from('document_shares')
            .select('document_id')
            .eq('organization_id', effectiveOrgId)
            .eq('user_id', userId);
        return res
            .map((r) => r['document_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
      } catch (e) {
        debugPrint('[DocumentService] fetchDocumentIdsSharedWith error: $e');
      }
    }

    return MockDocumentStore.instance.shares
        .where((s) => s.userId == userId)
        .map((s) => s.documentId)
        .toSet()
        .toList();
  }

  /// Fetches IDs of documents that were explicitly shared by the specified user ID
  Future<List<String>> fetchDocumentIdsSharedBy({
    required String organizationId,
    required String userId,
  }) async {
    _requirePersistenceOrTestStore();
    final client = _client;
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);

    if (isReady && client != null) {
      try {
        final res = await client
            .from('document_shares')
            .select('document_id')
            .eq('organization_id', effectiveOrgId)
            .eq('shared_by', userId);
        return res
            .map((r) => r['document_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
      } catch (e) {
        debugPrint('[DocumentService] fetchDocumentIdsSharedBy error: $e');
      }
    }

    return MockDocumentStore.instance.shares
        .where((s) => s.sharedBy == userId)
        .map((s) => s.documentId)
        .toSet()
        .toList();
  }

  // ===========================================================================
  // 7. EXTERNAL SHARING & TOKEN GENERATION
  // ===========================================================================

  /// Generates a secure, expiring token to share a document with an external recipient
  Future<ExternalTokenCreationResult> createExternalShareToken({
    required String documentId,
    required String organizationId,
    required String recipientEmail,
    String externalRecipientId = '',
    String recipientName = '',
    required String createdBy,
    String createdByName = '',
    int expiresInDays = 7,
    String permission = 'view',
  }) async {
    _requirePersistenceOrTestStore();
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    final rawToken = generateSecureToken();
    final tokenHash = DocumentExternalToken.computeHash(rawToken);
    final now = DateTime.now();
    final expiresAt = now.add(Duration(days: expiresInDays));

    final client = _client;
    final currentAuthUid = client?.auth.currentUser?.id;
    final effectiveCreatedBy = _isValidUuid(createdBy)
        ? createdBy
        : (currentAuthUid != null && _isValidUuid(currentAuthUid) ? currentAuthUid : null);

    final record = DocumentExternalToken(
      id: 'dext-${now.millisecondsSinceEpoch}-${Random().nextInt(9999)}',
      documentId: documentId,
      externalRecipientId: externalRecipientId,
      recipientName: recipientName,
      recipientEmail: recipientEmail,
      organizationId: effectiveOrgId,
      tokenHash: tokenHash,
      rawToken: rawToken,
      permission: permission,
      expiresAt: expiresAt,
      isRevoked: false,
      accessCount: 0,
      createdBy: effectiveCreatedBy ?? createdBy,
      createdAt: now,
    );

    if (isReady && client != null) {
      try {
        final insertData = <String, dynamic>{
          'id': record.id,
          'document_id': record.documentId,
          'token_hash': record.tokenHash,
          'recipient_email': record.recipientEmail,
          'recipient_name': record.recipientName,
          'organization_id': effectiveOrgId,
          'permission': record.permission,
          'expires_at': record.expiresAt.toIso8601String(),
          'created_by': ?effectiveCreatedBy,
          if (createdByName.isNotEmpty) 'created_by_name': createdByName,
          'is_revoked': false,
          'access_count': 0,
          'created_at': record.createdAt.toIso8601String(),
        };
        await client.from('document_external_tokens').insert(insertData);
      } catch (e) {
        debugPrint('[DocumentService] createExternalShareToken Supabase error: $e');
        rethrow;
      }
    }

    MockDocumentStore.instance.externalTokens.add(record);
    _updateMockCounts(documentId);
    return ExternalTokenCreationResult(token: rawToken, record: record);
  }

  /// Revokes an external share token
  Future<void> revokeExternalShareToken({
    required String tokenId,
    required String organizationId,
    String? documentId,
    String? revokedBy,
    String? reason,
  }) async {
    _requirePersistenceOrTestStore();
    final effectiveOrgId = _resolveEffectiveOrgId(organizationId);
    final client = _client;
    final currentAuthUid = client?.auth.currentUser?.id;
    final effectiveRevokedBy = _isValidUuid(revokedBy)
        ? revokedBy
        : (currentAuthUid != null && _isValidUuid(currentAuthUid) ? currentAuthUid : null);

    if (isReady && client != null) {
      try {
        await client
            .from('document_external_tokens')
            .update({
              'is_revoked': true,
              'revoked_at': DateTime.now().toIso8601String(),
              'revoked_by': ?effectiveRevokedBy,
              'revocation_reason': ?reason,
            })
            .eq('id', tokenId)
            .eq('organization_id', effectiveOrgId);
      } catch (e) {
        debugPrint('[DocumentService] revokeExternalShareToken error: $e');
      }
    }

    final idx = MockDocumentStore.instance.externalTokens.indexWhere((t) => t.id == tokenId);
    if (idx != -1) {
      final t = MockDocumentStore.instance.externalTokens[idx];
      MockDocumentStore.instance.externalTokens[idx] = DocumentExternalToken(
        id: t.id,
        documentId: t.documentId,
        externalRecipientId: t.externalRecipientId,
        recipientName: t.recipientName,
        recipientEmail: t.recipientEmail,
        organizationId: t.organizationId,
        tokenHash: t.tokenHash,
        rawToken: t.rawToken,
        permission: t.permission,
        expiresAt: t.expiresAt,
        isRevoked: true,
        accessCount: t.accessCount,
        lastAccessedAt: t.lastAccessedAt,
        createdBy: t.createdBy,
        createdAt: t.createdAt,
      );
      _updateMockCounts(t.documentId);
    }
  }

  /// Fetches all active/revoked external tokens for a document
  Future<List<DocumentExternalToken>> fetchExternalShares(String documentId) async {
    _requirePersistenceOrTestStore();
    final client = _client;
    if (isReady && client != null) {
      try {
        final res = await client
            .from('document_external_tokens')
            .select('*')
            .eq('document_id', documentId)
            .order('created_at', ascending: false);
        return (res as List).map((json) => DocumentExternalToken.fromJson(json as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('[DocumentService] fetchExternalShares error: $e');
        rethrow;
      }
    }

    return MockDocumentStore.instance.externalTokens
        .where((t) => t.documentId == documentId)
        .toList();
  }

  /// Alias for fetching external tokens with organization context
  Future<List<DocumentExternalToken>> fetchDocumentExternalTokens({
    required String documentId,
    required String organizationId,
  }) => fetchExternalShares(documentId);

  /// Verifies an external raw token and retrieves authorized document metadata
  Future<ExternalTokenVerificationResult> verifyExternalTokenAndGetDocument(String rawToken) async {
    _requirePersistenceOrTestStore();
    final trimmed = rawToken.trim();
    if (trimmed.isEmpty) {
      return const ExternalTokenVerificationResult(
        success: false,
        error: 'Token is missing or invalid.',
        isInvalid: true,
      );
    }

    final tokenHash = DocumentExternalToken.computeHash(trimmed);
    final client = _client;

    if (isReady && client != null) {
      try {
        final tokenRes = await client
            .from('document_external_tokens')
            .select('*, documents(*)')
            .eq('token_hash', tokenHash)
            .maybeSingle();

        if (tokenRes == null) {
          return const ExternalTokenVerificationResult(
            success: false,
            error: 'Invalid or nonexistent document access token.',
            isInvalid: true,
          );
        }

        final token = DocumentExternalToken.fromJson(tokenRes);
        if (token.isRevoked) {
          return ExternalTokenVerificationResult(
            success: false,
            error: 'Access to this document has been revoked by the organization manager.',
            tokenRecord: token,
            isRevoked: true,
          );
        }

        if (token.isExpired) {
          return ExternalTokenVerificationResult(
            success: false,
            error: 'This document access token has expired.',
            tokenRecord: token,
            isExpired: true,
          );
        }

        // Increment access counter
        await client.from('document_external_tokens').update({
          'access_count': token.accessCount + 1,
          'last_accessed_at': DateTime.now().toIso8601String(),
        }).eq('id', token.id);

        final docData = tokenRes['documents'] as Map<String, dynamic>?;
        if (docData == null) {
          return const ExternalTokenVerificationResult(
            success: false,
            error: 'Linked document not found.',
            isInvalid: true,
          );
        }

        final document = DocumentRecord.fromJson(docData);
        return ExternalTokenVerificationResult(
          success: true,
          document: document,
          tokenRecord: token,
        );
      } catch (e) {
        debugPrint('[DocumentService] verifyExternalToken error: $e');
        rethrow;
      }
    }

    // Mock verification
    final token = MockDocumentStore.instance.externalTokens.firstWhere(
      (t) => t.tokenHash == tokenHash,
      orElse: () => DocumentExternalToken(
        id: '',
        documentId: '',
        externalRecipientId: '',
        recipientName: '',
        recipientEmail: '',
        organizationId: '',
        tokenHash: '',
        expiresAt: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );

    if (token.id.isEmpty) {
      return const ExternalTokenVerificationResult(
        success: false,
        error: 'Invalid or nonexistent document access token.',
        isInvalid: true,
      );
    }

    if (token.isRevoked) {
      return ExternalTokenVerificationResult(
        success: false,
        error: 'Access to this document has been revoked by the organization manager.',
        tokenRecord: token,
        isRevoked: true,
      );
    }

    if (token.isExpired) {
      return ExternalTokenVerificationResult(
        success: false,
        error: 'This document access token has expired.',
        tokenRecord: token,
        isExpired: true,
      );
    }

    // Increment mock access count
    final tokenIdx = MockDocumentStore.instance.externalTokens.indexWhere((t) => t.id == token.id);
    DocumentExternalToken accessedToken = token;
    if (tokenIdx != -1) {
      accessedToken = DocumentExternalToken(
        id: token.id,
        documentId: token.documentId,
        externalRecipientId: token.externalRecipientId,
        recipientName: token.recipientName,
        recipientEmail: token.recipientEmail,
        organizationId: token.organizationId,
        tokenHash: token.tokenHash,
        rawToken: token.rawToken,
        permission: token.permission,
        expiresAt: token.expiresAt,
        isRevoked: token.isRevoked,
        accessCount: token.accessCount + 1,
        lastAccessedAt: DateTime.now(),
        createdBy: token.createdBy,
        createdAt: token.createdAt,
      );
      MockDocumentStore.instance.externalTokens[tokenIdx] = accessedToken;
    }

    final doc = MockDocumentStore.instance.documents.firstWhere(
      (d) => d.id == token.documentId,
      orElse: () => DocumentRecord(
        id: '',
        organizationId: '',
        title: '',
        fileName: '',
        filePath: '',
        fileSize: 0,
        fileType: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (doc.id.isEmpty) {
      return const ExternalTokenVerificationResult(
        success: false,
        error: 'Linked document not found.',
        isInvalid: true,
      );
    }

    return ExternalTokenVerificationResult(
      success: true,
      document: doc,
      tokenRecord: accessedToken,
    );
  }
  void _updateMockCounts(String documentId) {
    final idx = MockDocumentStore.instance.documents.indexWhere((d) => d.id == documentId);
    if (idx != -1) {
      final internalShares = MockDocumentStore.instance.shares.where((s) => s.documentId == documentId).toList();
      final extShares = MockDocumentStore.instance.externalTokens.where((t) => t.documentId == documentId && !t.isRevoked).toList();
      final senders = internalShares.map((s) => s.sharedBy).where((id) => id.isNotEmpty).toSet().toList();
      MockDocumentStore.instance.documents[idx] = MockDocumentStore.instance.documents[idx].copyWith(
        sharedInternalCount: internalShares.length,
        sharedExternalCount: extShares.length,
        sharedWithUserIds: internalShares.map((s) => s.userId).toList(),
        sharedByUserIds: senders,
        sharedByUserName: internalShares.isNotEmpty ? internalShares.last.sharedByName : null,
        sharedAt: internalShares.isNotEmpty ? internalShares.last.createdAt : null,
      );
    }
  }
}
