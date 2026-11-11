import 'dart:typed_data';

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/requests/models/request_models.dart';
import 'package:action_flow/features/requests/services/request_service.dart';
import 'package:action_flow/widgets/document_preview/pdf_view.dart';
import 'package:flutter/material.dart';

/// Interactive Preview Dialog for Request Attachments
/// Supports high-fidelity rendering for Images (JPEG, PNG, WEBP),
/// PDFs via [PdfViewWidget], and actionable download fallback for other files.
class RequestAttachmentPreviewDialog extends StatefulWidget {
  const RequestAttachmentPreviewDialog({
    super.key,
    required this.attachment,
    this.initialBytes,
  });

  final RequestAttachmentRecord attachment;
  final Uint8List? initialBytes;

  static Future<void> show(
    BuildContext context, {
    required RequestAttachmentRecord attachment,
    Uint8List? initialBytes,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => RequestAttachmentPreviewDialog(
        attachment: attachment,
        initialBytes: initialBytes,
      ),
    );
  }

  @override
  State<RequestAttachmentPreviewDialog> createState() =>
      _RequestAttachmentPreviewDialogState();
}

class _RequestAttachmentPreviewDialogState
    extends State<RequestAttachmentPreviewDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  Uint8List? _fileBytes;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (widget.initialBytes != null && widget.initialBytes!.isNotEmpty) {
      setState(() {
        _fileBytes = widget.initialBytes;
        _isLoading = false;
      });
      return;
    }

    try {
      final bytes = await RequestService.instance.getAttachmentBytes(
        widget.attachment.filePath,
      );
      if (mounted) {
        setState(() {
          _fileBytes = bytes;
          _isLoading = false;
        });
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
          content: Text('Downloading "${widget.attachment.fileName}"...'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final saved = await RequestService.instance.downloadAttachment(
        attachment: widget.attachment,
      );

      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Downloaded "${widget.attachment.fileName}" successfully.',
            ),
            backgroundColor: const Color(0xFF16A34A),
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

  IconData _getFileIcon() {
    if (widget.attachment.isPdf) return Icons.picture_as_pdf_rounded;
    if (widget.attachment.isImage) return Icons.image_rounded;
    final ext = widget.attachment.fileExtension;
    if (ext == 'doc' || ext == 'docx') return Icons.description_rounded;
    if (ext == 'xls' || ext == 'xlsx' || ext == 'csv') {
      return Icons.table_chart_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor() {
    if (widget.attachment.isPdf) return const Color(0xFFDC2626);
    if (widget.attachment.isImage) return const Color(0xFF7C3AED);
    final ext = widget.attachment.fileExtension;
    if (ext == 'doc' || ext == 'docx') return const Color(0xFF2563EB);
    if (ext == 'xls' || ext == 'xlsx' || ext == 'csv') {
      return const Color(0xFF16A34A);
    }
    return const Color(0xFF64748B);
  }

  Widget _buildContent(BuildContext context, bool isDark) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 16),
            Text(
              'Loading attachment preview...',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Color(0xFFDC2626),
              ),
              const SizedBox(height: 12),
              Text(
                'Unable to preview attachment',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadBytes,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _handleDownload,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Download File'),
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
        child: Text(
          'File content is empty.',
          style: TextStyle(color: AppTheme.textSecondary(context)),
        ),
      );
    }

    // 1. PDF Preview
    if (widget.attachment.isPdf) {
      return PdfViewWidget(
        bytes: _fileBytes!,
        fileName: widget.attachment.fileName,
      );
    }

    // 2. Image Preview (JPEG, PNG, WEBP)
    if (widget.attachment.isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            _fileBytes!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.broken_image_rounded,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to render image format.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 3. Fallback for Word, Excel, ZIP, etc.
    final iconColor = _getFileColor();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(_getFileIcon(), size: 54, color: iconColor),
            ),
            const SizedBox(height: 16),
            Text(
              widget.attachment.fileName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.attachment.formattedSize} • ${widget.attachment.contentType.isNotEmpty ? widget.attachment.contentType : 'Document File'}',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'In-browser preview is not supported for this file format.\nYou can download the file to inspect it on your device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              icon: _isDownloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_isDownloading ? 'Downloading...' : 'Download File'),
              onPressed: _isDownloading ? null : _handleDownload,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < 700;
    final dialogWidth = isMobile ? media.size.width * 0.95 : 820.0;
    final dialogHeight = isMobile ? media.size.height * 0.85 : 620.0;
    final iconColor = _getFileColor();

    return Dialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  border: Border(
                    bottom: BorderSide(color: AppTheme.cardBorder(context)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_getFileIcon(), size: 20, color: iconColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.attachment.fileName,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.attachment.formattedSize,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded, size: 20),
                      tooltip: 'Download File',
                      onPressed: _isDownloading ? null : _handleDownload,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Close Preview',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Content Area
              Expanded(
                child: Container(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5F9),
                  child: _buildContent(context, isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
