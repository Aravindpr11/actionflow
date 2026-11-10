import 'dart:convert';
import 'dart:typed_data';

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:action_flow/widgets/document_preview/pdf_view.dart';
import 'package:flutter/material.dart';

/// In-App Document Preview Modal Dialog
/// Supports PDF rendering, InteractiveViewer image zooming, text file viewing,
/// and graceful fallback for unsupported formats (Word, Excel) with direct download.
class DocumentPreviewDialog extends StatefulWidget {
  const DocumentPreviewDialog({
    super.key,
    required this.document,
    required this.organizationId,
    this.documentService,
  });

  final DocumentRecord document;
  final String organizationId;
  final DocumentService? documentService;

  static Future<void> show(
    BuildContext context, {
    required DocumentRecord doc,
    required String organizationId,
    DocumentService? documentService,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DocumentPreviewDialog(
        document: doc,
        organizationId: organizationId,
        documentService: documentService,
      ),
    );
  }

  @override
  State<DocumentPreviewDialog> createState() => _DocumentPreviewDialogState();
}

class _DocumentPreviewDialogState extends State<DocumentPreviewDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  Uint8List? _fileBytes;
  bool _isDownloading = false;

  DocumentService get _service =>
      widget.documentService ?? DocumentService.instance;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Check if document has bytes already cached in memory
      if (widget.document.fileBytes != null &&
          widget.document.fileBytes!.isNotEmpty) {
        _fileBytes = Uint8List.fromList(widget.document.fileBytes!);
      } else {
        // 2. Fetch binary bytes using authenticated document access flow
        final bytes = await _service.getDocumentBytes(
          documentId: widget.document.id,
          organizationId: widget.organizationId,
        );
        if (bytes.isEmpty) {
          throw StateError('Retrieved document bytes are empty.');
        }
        _fileBytes = Uint8List.fromList(bytes);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = DocumentService.formatDownloadError(e);
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
          content: Text('Downloading "${widget.document.fileName}"...'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final success = await _service.downloadAndSaveDocument(
        doc: widget.document,
        organizationId: widget.organizationId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Downloaded "${widget.document.fileName}".'
                  : 'Download cancelled.',
            ),
            backgroundColor: success
                ? const Color(0xFF16A34A)
                : const Color(0xFF64748B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${DocumentService.formatDownloadError(e)}'),
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

  IconData _getFileIcon() {
    if (widget.document.isPdf) return Icons.picture_as_pdf_rounded;
    if (widget.document.isImage) return Icons.image_rounded;
    if (widget.document.isWord) return Icons.description_rounded;
    if (widget.document.isExcel) return Icons.table_chart_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor() {
    if (widget.document.isPdf) return const Color(0xFFDC2626);
    if (widget.document.isImage) return const Color(0xFF7C3AED);
    if (widget.document.isWord) return const Color(0xFF2563EB);
    if (widget.document.isExcel) return const Color(0xFF16A34A);
    return const Color(0xFF64748B);
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
                          widget.document.title,
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
                          '${widget.document.fileName} • ${widget.document.formattedFileSize} • ${widget.document.category}',
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
                          widget.document.category,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: brandColor,
                          ),
                        ),
                      ),
                      if (dialogWidth >= 360 &&
                          widget.document.actionNumber != null &&
                          widget.document.actionNumber!.isNotEmpty) ...[
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
                            'Action: ${widget.document.actionNumber}',
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
              'Loading secure preview for "${widget.document.fileName}"...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Verifying organizational and department permissions...',
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
                'Unable to preview document',
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
                    onPressed: _loadDocument,
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
      return const Center(child: Text('Document is empty.'));
    }

    // A. PDF Preview
    if (widget.document.isPdf) {
      return PdfViewWidget(
        bytes: _fileBytes!,
        fileName: widget.document.fileName,
      );
    }

    // B. Image Formats (InteractiveViewer with Zoom & Pan)
    if (widget.document.isImage) {
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

    // C. Plain Text & CSV Preview
    if (widget.document.fileExtension == 'txt' ||
        widget.document.fileExtension == 'csv') {
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

    // D. Unsupported Formats (Word, Excel, etc.)
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
                'In-app preview is not supported for .${widget.document.fileExtension.toUpperCase()} files.\nDownload the document to view it in Microsoft Office or your preferred application.',
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
              label: Text('Download ${widget.document.fileName}'),
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
}
