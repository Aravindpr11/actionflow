import 'dart:typed_data';

import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:flutter/material.dart';

/// Reusable Document Upload Dialog for both Manager and Staff Portals
class DocumentUploadDialog extends StatefulWidget {
  const DocumentUploadDialog({
    super.key,
    required this.organizationId,
    required this.userId,
    required this.userName,
    this.departmentId,
    this.departmentName,
    this.actions = const [],
    this.customFilePicker,
    this.onDocumentUploaded,
    this.documentService,
  });

  final String organizationId;
  final String userId;
  final String userName;
  final String? departmentId;
  final String? departmentName;
  final List<ActionRecord> actions;
  final Future<AppPickedFile?> Function()? customFilePicker;
  final void Function(DocumentRecord doc)? onDocumentUploaded;
  final DocumentService? documentService;

  static Future<DocumentRecord?> show(
    BuildContext context, {
    required String organizationId,
    required String userId,
    required String userName,
    String? departmentId,
    String? departmentName,
    List<ActionRecord> actions = const [],
    Future<AppPickedFile?> Function()? customFilePicker,
    void Function(DocumentRecord doc)? onDocumentUploaded,
    DocumentService? documentService,
  }) {
    return showDialog<DocumentRecord>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DocumentUploadDialog(
        organizationId: organizationId,
        userId: userId,
        userName: userName,
        departmentId: departmentId,
        departmentName: departmentName,
        actions: actions,
        customFilePicker: customFilePicker,
        onDocumentUploaded: onDocumentUploaded,
        documentService: documentService,
      ),
    );
  }

  @override
  State<DocumentUploadDialog> createState() => _DocumentUploadDialogState();
}

class _DocumentUploadDialogState extends State<DocumentUploadDialog> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  String _selectedCategory = DocumentCategory.auditChecklists;
  String? _selectedActionId;
  bool _isSubmitting = false;
  bool _isPickingFile = false;
  String? _validationMsg;
  String? _uploadError;
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  int? _selectedFileSize;

  DocumentService get _service =>
      widget.documentService ?? DocumentService.instance;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeviceFile() async {
    setState(() {
      _isPickingFile = true;
      _validationMsg = null;
    });

    try {
      AppPickedFile? picked;
      if (widget.customFilePicker != null) {
        picked = await widget.customFilePicker!();
      } else {
        picked = await AppFilePicker.pickSingleFile(
          allowedExtensions: const [
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
          ],
        );
      }

      if (picked == null) {
        setState(() => _isPickingFile = false);
        return;
      }

      final bytes = picked.bytes;
      final size = picked.size;
      final name = picked.name;

      final err = DocumentService.validateFile(
        fileName: name,
        fileSize: size,
      );

      setState(() {
        _isPickingFile = false;
        if (err != null) {
          _selectedFileBytes = null;
          _selectedFileName = null;
          _selectedFileSize = null;
          _validationMsg = err;
        } else {
          _selectedFileBytes = bytes;
          _selectedFileName = name;
          _selectedFileSize = size;
          _validationMsg = null;

          if (_titleCtrl.text.trim().isEmpty) {
            final dotIdx = name.lastIndexOf('.');
            final baseName = dotIdx != -1 ? name.substring(0, dotIdx) : name;
            _titleCtrl.text =
                baseName.replaceAll('_', ' ').replaceAll('-', ' ');
          }
        }
      });
    } catch (e) {
      setState(() {
        _isPickingFile = false;
        _selectedFileBytes = null;
        _selectedFileName = null;
        _selectedFileSize = null;
        _validationMsg = 'Failed to select file: $e';
      });
    }
  }

  void _clearSelectedFile() {
    setState(() {
      _selectedFileBytes = null;
      _selectedFileName = null;
      _selectedFileSize = null;
      _validationMsg = null;
      _uploadError = null;
    });
  }

  Future<void> _handleSubmit() async {
    if (_selectedFileBytes == null ||
        _selectedFileName == null ||
        _titleCtrl.text.trim().isNotEmpty != true ||
        _isSubmitting) {
      return;
    }

    final fName = _selectedFileName!;
    final tName = _titleCtrl.text.trim().isNotEmpty
        ? _titleCtrl.text.trim()
        : fName;

    setState(() {
      _isSubmitting = true;
      _uploadError = null;
    });

    try {
      String? actionNum;
      if (_selectedActionId != null && widget.actions.isNotEmpty) {
        final match = widget.actions.where((a) => a.id == _selectedActionId);
        if (match.isNotEmpty) {
          actionNum = match.first.actionNumber.isNotEmpty
              ? match.first.actionNumber
              : match.first.id;
        }
      }

      final uploadedDoc = await _service.uploadDocument(
        organizationId: widget.organizationId,
        title: tName,
        fileName: fName,
        fileBytes: _selectedFileBytes!,
        description: _descCtrl.text.trim(),
        category: _selectedCategory,
        actionId: _selectedActionId,
        actionNumber: actionNum,
        departmentId: widget.departmentId,
        userId: widget.userId,
        userName: widget.userName,
      );

      if (mounted) {
        Navigator.of(context).pop(uploadedDoc);
        widget.onDocumentUploaded?.call(uploadedDoc);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uploadedDoc.isPersisted
                  ? 'Document "$tName" uploaded and saved permanently.'
                  : 'Document "$tName" uploaded to preview store.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _uploadError = DocumentService.formatUploadError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayError = _validationMsg ?? _uploadError;
    final canSubmit = _selectedFileBytes != null &&
        _selectedFileBytes!.isNotEmpty &&
        _titleCtrl.text.trim().isNotEmpty &&
        !_isSubmitting &&
        _validationMsg == null;

    final media = MediaQuery.of(context);
    final dialogWidth = media.size.width < 560
        ? media.size.width * 0.92
        : 520.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppTheme.cardBg(context),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.upload_file_rounded,
              color: Color(0xFF1565C0),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upload Document',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                if (widget.departmentName != null &&
                    widget.departmentName!.isNotEmpty)
                  Text(
                    'Department: ${widget.departmentName}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select a document to upload to secure enterprise storage. Maximum file size is 25 MB.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 16),

                // File Picker Area
                if (_selectedFileBytes == null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.containerBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _validationMsg != null &&
                                _selectedFileName == null
                            ? Colors.red.shade400
                            : AppTheme.cardBorder(context),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF1565C0).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 32,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const Key('documents_choose_file_button'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                          ),
                          icon: _isPickingFile
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.folder_open_rounded, size: 18),
                          label: Text(
                            _isPickingFile
                                ? 'Browsing...'
                                : 'Choose File from Device',
                          ),
                          onPressed: _isPickingFile ? null : _pickDeviceFile,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Supported: PDF, DOC, DOCX, XLS, XLSX, PNG, JPG, CSV, TXT',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.containerBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF16A34A)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF16A34A).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.insert_drive_file_rounded,
                            color: Color(0xFF16A34A),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFileName!,
                                key: const Key('documents_selected_file_name'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    '${((_selectedFileSize ?? 0) / 1024).toStringAsFixed(1)} KB',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16A34A)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Ready to upload',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!_isSubmitting) ...[
                          TextButton.icon(
                            key: const Key('documents_change_file_button'),
                            icon: const Icon(Icons.sync_rounded, size: 16),
                            label: const Text(
                              'Change',
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed: _pickDeviceFile,
                          ),
                          IconButton(
                            key: const Key('documents_remove_file_button'),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: 'Remove selected file',
                            onPressed: _clearSelectedFile,
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Document Title
                TextField(
                  controller: _titleCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Document Title *',
                    hintText: 'e.g. Site Safety Standard Operating Procedure',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Category Dropdown
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: DocumentCategory.all.map((c) {
                    return DropdownMenuItem(value: c, child: Text(c));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
                const SizedBox(height: 14),

                // Action Link Dropdown (if any actions available)
                if (widget.actions.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _selectedActionId,
                    decoration: InputDecoration(
                      labelText: 'Link to Action (Optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'None (General Repository Document)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...widget.actions.map((a) {
                        final actLabel = a.actionNumber.isNotEmpty ? a.actionNumber : a.id;
                        return DropdownMenuItem<String?>(
                          value: a.id,
                          child: Text(
                            '$actLabel - ${a.subject.length > 25 ? '${a.subject.substring(0, 25)}...' : a.subject}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) =>
                        setState(() => _selectedActionId = val),
                  ),
                  const SizedBox(height: 14),
                ],

                // Description TextField
                TextField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Description / Notes',
                    hintText: 'Brief summary of procedures or guidelines...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                // Validation / Submission Error Message
                if (displayError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    key: const Key('documents_validation_error'),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: Colors.red.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayError,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('documents_submit_upload_button'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1565C0),
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.cloud_upload_outlined, size: 18),
          label: Text(_isSubmitting ? 'Uploading...' : 'Upload Document'),
          onPressed: canSubmit ? _handleSubmit : null,
        ),
      ],
    );
  }
}
