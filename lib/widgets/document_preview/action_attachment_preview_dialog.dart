import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/widgets/document_preview/pdf_view.dart';
import 'package:excel_plus/excel_plus.dart' hide Border;

/// In-App Action Attachment Preview Modal Dialog.
///
/// Features:
/// - In-app PDF rendering via [PdfViewWidget] utilizing browser native iframe or platform stub.
/// - In-app interactive zoom & pan for images (PNG, JPG, JPEG, WEBP).
/// - In-app selectable monospace view for plain text (TXT) and CSV files.
/// - Clear, informative explanation for office formats (DOC, DOCX, XLS, XLSX) with working download button.
/// - Strict authorization check: verifies user's role on the action before fetching bytes or displaying contents.
/// - Private Storage: bucket remains private; access utilizes short-lived signed URLs.
class ActionAttachmentPreviewDialog extends StatefulWidget {
  const ActionAttachmentPreviewDialog({
    super.key,
    required this.action,
    required this.fileName,
    this.currentUserId,
    this.isWorker = false,
    this.actionService,
    this.initialBytes,
  });

  final ActionRecord action;
  final String fileName;
  final String? currentUserId;
  final bool isWorker;
  final ActionService? actionService;
  final Uint8List? initialBytes;

  static Future<void> show(
    BuildContext context, {
    required ActionRecord action,
    required String fileName,
    String? currentUserId,
    bool isWorker = false,
    ActionService? actionService,
    Uint8List? initialBytes,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ActionAttachmentPreviewDialog(
        action: action,
        fileName: fileName,
        currentUserId: currentUserId,
        isWorker: isWorker,
        actionService: actionService,
        initialBytes: initialBytes,
      ),
    );
  }

  @override
  State<ActionAttachmentPreviewDialog> createState() =>
      _ActionAttachmentPreviewDialogState();
}

class _ActionAttachmentPreviewDialogState
    extends State<ActionAttachmentPreviewDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  Uint8List? _fileBytes;
  bool _isDownloading = false;
  Excel? _excelWorkbook;
  String? _selectedSheetName;
  bool _excelDecodeFailed = false;

  ActionService get _service => widget.actionService ?? ActionService.instance;

  String get _cleanFileName =>
      ActionService.sanitizeAttachmentFileName(widget.fileName);

  String get _fileExtension {
    final name = _cleanFileName.toLowerCase();
    final dotIdx = name.lastIndexOf('.');
    if (dotIdx != -1 && dotIdx < name.length - 1) {
      return name.substring(dotIdx + 1);
    }
    return '';
  }

  bool get _isPdf => _fileExtension == 'pdf';
  bool get _isImage =>
      _fileExtension == 'png' ||
      _fileExtension == 'jpg' ||
      _fileExtension == 'jpeg' ||
      _fileExtension == 'webp';
  bool get _isText => _fileExtension == 'txt' || _fileExtension == 'csv';
  bool get _isWord => _fileExtension == 'doc' || _fileExtension == 'docx';
  bool get _isExcel => _fileExtension == 'xls' || _fileExtension == 'xlsx';

  IconData _getFileIcon() {
    if (_isPdf) return Icons.picture_as_pdf_rounded;
    if (_isImage) return Icons.image_rounded;
    if (_isText) return Icons.article_rounded;
    if (_isWord) return Icons.description_rounded;
    if (_isExcel) return Icons.table_chart_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor() {
    if (_isPdf) return const Color(0xFFDC2626);
    if (_isImage) return const Color(0xFF7C3AED);
    if (_isText) return const Color(0xFF0284C7);
    if (_isWord) return const Color(0xFF2563EB);
    if (_isExcel) return const Color(0xFF16A34A);
    return const Color(0xFF64748B);
  }

  @override
  void initState() {
    super.initState();
    _loadAttachment();
  }

  Future<void> _loadAttachment() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _excelWorkbook = null;
      _selectedSheetName = null;
      _excelDecodeFailed = false;
    });

    try {
      // 1. If test or caller injected initial bytes directly
      if (widget.initialBytes != null && widget.initialBytes!.isNotEmpty) {
        _fileBytes = widget.initialBytes;
      } else {
        // 2. Fetch authenticated bytes using ActionService
        final res = await _service.getActionAttachmentBytes(
          action: widget.action,
          fileName: widget.fileName,
          userId: widget.currentUserId,
          isManager: !widget.isWorker,
        );

        if (!res.success) {
          throw Exception(res.error ?? 'Failed to retrieve attachment file.');
        }

        if (res.bytes == null || res.bytes!.isEmpty) {
          throw StateError('Retrieved attachment content is empty.');
        }

        _fileBytes = res.bytes;
      }

      if (_fileBytes != null && _isExcel) {
        try {
          final decoded = Excel.decodeBytes(_fileBytes!);
          if (decoded.tables.isNotEmpty) {
            _excelWorkbook = decoded;
            _selectedSheetName =
                decoded.getDefaultSheet() ?? decoded.tables.keys.first;
            _excelDecodeFailed = false;
          } else {
            _excelDecodeFailed = true;
          }
        } catch (e) {
          debugPrint('[ActionAttachmentPreviewDialog] Excel decode error: $e');
          _excelDecodeFailed = true;
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _handleDownload() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading "$_cleanFileName"...'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final res = await _service.downloadActionAttachment(
        action: widget.action,
        fileName: widget.fileName,
        userId: widget.currentUserId,
        isManager: !widget.isWorker,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.success
                  ? 'Downloaded "$_cleanFileName" successfully.'
                  : (res.error ?? 'Download failed.'),
            ),
            backgroundColor: res.success
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxAvailableWidth = (media.size.width - 32.0).clamp(260.0, 960.0);
    final dialogWidth =
        (media.size.width * 0.92).clamp(260.0, maxAvailableWidth);
    final maxAvailableHeight = (media.size.height - 48.0).clamp(300.0, 780.0);
    final dialogHeight =
        (media.size.height * 0.85).clamp(280.0, maxAvailableHeight);
    final brandColor = _getFileColor();
    final isCompactHeader = dialogWidth < 420;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppTheme.cardBg(context),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // =================================================================
            // 1. HEADER
            // =================================================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.headerBg(context),
                border: Border(
                  bottom: BorderSide(color: AppTheme.cardBorder(context)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_getFileIcon(), color: brandColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _cleanFileName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Action: ${widget.action.displayId} • Verified HSSE Evidence',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isCompactHeader)
                    IconButton(
                      key: const Key('action_preview_dialog_download_btn'),
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 20),
                      tooltip: 'Download',
                      onPressed: _isDownloading ? null : _handleDownload,
                    )
                  else
                    FilledButton.tonalIcon(
                      key: const Key('action_preview_dialog_download_btn'),
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Download'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      onPressed: _isDownloading ? null : _handleDownload,
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('action_preview_dialog_close_btn'),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // =================================================================
            // 2. VIEWER VIEWPORT
            // =================================================================
            Expanded(
              child: Container(
                width: double.infinity,
                color: AppTheme.containerBg(context),
                child: _buildViewerContent(context),
              ),
            ),

            // =================================================================
            // 3. FOOTER
            // =================================================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.headerBg(context),
                border: Border(
                  top: BorderSide(color: AppTheme.cardBorder(context)),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: brandColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: brandColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          _fileExtension.toUpperCase().isEmpty
                              ? 'ATTACHMENT'
                              : _fileExtension.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: brandColor,
                          ),
                        ),
                      ),
                      if (dialogWidth >= 360) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF1565C0).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.action.department.isNotEmpty
                                ? widget.action.department
                                : 'HSSE Action',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1565C0),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  if (dialogWidth < 360)
                    IconButton(
                      icon: const Icon(Icons.download_rounded, size: 20),
                      tooltip: 'Download',
                      onPressed: _isDownloading ? null : _handleDownload,
                    )
                  else
                    FilledButton.icon(
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Download'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                      ),
                      onPressed: _isDownloading ? null : _handleDownload,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewerContent(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF1565C0),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading secure preview for "$_cleanFileName"...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Verifying action attachment permissions...',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_person_outlined,
                  size: 48,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Unable to preview attachment',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry Preview'),
                    onPressed: _loadAttachment,
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Download Instead'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                    ),
                    onPressed: _handleDownload,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_fileBytes == null || _fileBytes!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'Document is empty or could not be decoded.',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    // 1. PDF Preview
    if (_isPdf) {
      return PdfViewWidget(
        bytes: _fileBytes!,
        fileName: _cleanFileName,
      );
    }

    // 2. Image Formats (JPG, JPEG, PNG, WEBP)
    if (_isImage) {
      return InteractiveViewer(
        panEnabled: true,
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: Image.memory(
            _fileBytes!,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => Center(
              child: Text(
                'Failed to decode image data: $err',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
      );
    }

    // 3. Plain Text & CSV Preview
    if (_isText) {
      final textContent = utf8.decode(_fileBytes!, allowMalformed: true);
      return Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: SelectableText(
            textContent,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ),
      );
    }

    // 4. Excel Spreadsheet Table Preview (.XLSX / .XLS)
    if (_isExcel &&
        !_excelDecodeFailed &&
        _excelWorkbook != null &&
        _selectedSheetName != null) {
      return _buildExcelPreview(context);
    }

    // 5. Unsupported Office Formats (Word, Excel fallback) & Others
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getFileColor().withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(_getFileIcon(), size: 48, color: _getFileColor()),
            ),
            const SizedBox(height: 12),
            Text(
              'In-App Preview Unavailable',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Text(
                _isWord || _isExcel
                    ? 'In-app preview is not supported for .${_fileExtension.toUpperCase()} files.\nDownload the document to view it in Microsoft Office or your preferred application.'
                    : 'In-app preview is not supported for .${_fileExtension.toUpperCase()} files.\nDownload the file to view it on your device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text('Download $_cleanFileName'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: _handleDownload,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExcelPreview(BuildContext context) {
    final workbook = _excelWorkbook!;
    final sheetNames = workbook.tables.keys.toList();
    final currentSheet = workbook.tables[_selectedSheetName];

    if (currentSheet == null) {
      return Center(
        child: Text(
          'Selected sheet "$_selectedSheetName" not found.',
          style: TextStyle(color: AppTheme.textSecondary(context)),
        ),
      );
    }

    final rows = currentSheet.rows;
    final maxRowsToDisplay = rows.length > 100 ? 100 : rows.length;
    final maxColsInRows = rows.fold<int>(
      0,
      (prev, r) => r.length > prev ? r.length : prev,
    );
    final colCount = (currentSheet.maxColumns > 0
            ? currentSheet.maxColumns
            : maxColsInRows)
        .clamp(1, 26);

    String getColHeader(int idx) {
      if (idx < 26) {
        return String.fromCharCode(65 + idx);
      }
      final first = String.fromCharCode(65 + (idx ~/ 26) - 1);
      final second = String.fromCharCode(65 + (idx % 26));
      return '$first$second';
    }

    return Column(
      key: const Key('action_preview_excel_container'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sheet selector toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.headerBg(context),
            border: Border(
              bottom: BorderSide(color: AppTheme.cardBorder(context)),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.table_chart_rounded,
                size: 16,
                color: Color(0xFF16A34A),
              ),
              const SizedBox(width: 8),
              Text(
                'Sheets (${sheetNames.length}):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: sheetNames.map((name) {
                      final isSelected = name == _selectedSheetName;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: Key('excel_sheet_chip_$name'),
                          label: Text(
                            name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textPrimary(context),
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFF16A34A),
                          backgroundColor: AppTheme.cardBg(context),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedSheetName = name);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Spreadsheet table viewport
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    'Sheet "$_selectedSheetName" is empty.',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                )
              : Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Table(
                          key: const Key('action_preview_excel_table'),
                          columnWidths: const {
                            0: FixedColumnWidth(48),
                          },
                          defaultColumnWidth: const IntrinsicColumnWidth(),
                          border: TableBorder.all(
                            color: AppTheme.cardBorder(context).withValues(alpha: 0.6),
                            width: 1,
                          ),
                          children: [
                            // Column headers row (#, A, B, C...)
                            TableRow(
                              decoration: const BoxDecoration(
                                color: Color(0xFF1E293B),
                              ),
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    '#',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                ...List.generate(colCount, (colIdx) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      getColHeader(colIdx),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                            // Data rows
                            ...List.generate(maxRowsToDisplay, (rowIdx) {
                              final rowCells = rows[rowIdx];
                              final isEven = rowIdx.isEven;
                              return TableRow(
                                decoration: BoxDecoration(
                                  color: isEven
                                      ? AppTheme.cardBg(context)
                                      : AppTheme.containerBg(context),
                                ),
                                children: [
                                  // Row number
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 6,
                                    ),
                                    alignment: Alignment.center,
                                    color: AppTheme.headerBg(context),
                                    child: Text(
                                      '${rowIdx + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSecondary(context),
                                      ),
                                    ),
                                  ),
                                  // Data Cells
                                  ...List.generate(colCount, (colIdx) {
                                    final cell = colIdx < rowCells.length
                                        ? rowCells[colIdx]
                                        : null;
                                    final valStr = cell?.value?.toString() ?? '';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      alignment: Alignment.centerLeft,
                                      constraints: const BoxConstraints(
                                        minWidth: 80,
                                        maxWidth: 280,
                                      ),
                                      child: SelectableText(
                                        valStr,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textPrimary(context),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),

        // Spreadsheet footer status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.headerBg(context),
            border: Border(
              top: BorderSide(color: AppTheme.cardBorder(context)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${maxRowsToDisplay > 0 ? '1-$maxRowsToDisplay' : '0'} of ${rows.length} rows • $colCount columns',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              if (rows.length > 100)
                Text(
                  'Preview limited to first 100 rows. Download to view complete workbook.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

