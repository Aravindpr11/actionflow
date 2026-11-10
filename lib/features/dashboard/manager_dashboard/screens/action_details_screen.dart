import 'dart:async';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

import '../../../users/data/mock_people_store.dart';
import '../../../users/models/person.dart';
import '../../../users/models/team.dart';

import 'package:action_flow/models/organization.dart';

import '../models/action_record.dart';
import '../models/manager_context.dart';
import 'add_action_screen.dart';
import 'manager_action_update_screen.dart';

import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/services/auth_service.dart';
import 'package:action_flow/services/notification_service.dart';
import 'package:action_flow/widgets/document_preview/action_attachment_preview_dialog.dart';

enum _ForwardMode { entireAction, subTask }

class ActionDetailsScreen extends StatefulWidget {
  const ActionDetailsScreen({
    required this.action,
    this.onUpdateAction,
    this.isWorker = false,
    this.currentUserId,
    this.managerContext,
    super.key,
  });

  final ActionRecord action;
  final VoidCallback? onUpdateAction;
  final bool isWorker;
  final String? currentUserId;
  final ManagerContext? managerContext;

  @override
  State<ActionDetailsScreen> createState() => _ActionDetailsScreenState();
}

class _ActionDetailsScreenState extends State<ActionDetailsScreen> {
  late ActionRecord _action;
  late List<String> _attachments;
  late List<String> _history;
  late List<_CommentItem> _comments;
  final TextEditingController _commentController = TextEditingController();
  int _selectedTabIndex = 0;
  List<ActionRecord> _relatedActions = [];

  void _persistUpdate() {
    widget.onUpdateAction?.call();
    if (_action.id.isNotEmpty && _action.id.contains('-')) {
      ActionService.instance.updateAction(_action).catchError((e) {
        debugPrint('[ActionDetailsScreen] Supabase action update error: $e');
        return _action;
      });
    }
  }

  Future<void> _handleOpenUpdateScreen() async {
    final updated = await Navigator.of(context).push<ActionRecord>(
      MaterialPageRoute(
        builder: (_) => ManagerActionUpdateScreen(
          action: _action,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _action = updated;
        _attachments = List<String>.from(updated.attachments);
        _history = List<String>.from(updated.history);
      });
      widget.onUpdateAction?.call();
    }
  }

  Future<void> _loadRelatedActions() async {
    final orgId = _action.organizationId.isNotEmpty
        ? _action.organizationId
        : Organization.sobhaId;
    try {
      final all = await ActionService.instance.fetchManagerActions(
        organizationId: orgId,
      );
      if (mounted) {
        setState(() {
          _relatedActions = all.where((a) {
            if (a.id == _action.id) return false;
            return a.department == _action.department || a.site == _action.site;
          }).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _action = widget.action;
    _attachments = List<String>.from(_action.attachments);
    _history = List<String>.from(_action.history);
    _comments = [];
    _loadRelatedActions();

    // Seed existing message fields into comments tab
    if (_action.workerMessage.isNotEmpty) {
      _comments.add(
        _CommentItem(
          author: _action.assignedTo,
          role: 'Assignee / Staff',
          type: _action.messageType.isNotEmpty
              ? _action.messageType
              : 'Progress Update',
          message: _action.workerMessage,
          subject: _action.workerMessageSubject,
          time: 'Previous update',
          isWorker: true,
        ),
      );
    }
    if (_action.managerMessage.isNotEmpty) {
      _comments.add(
        _CommentItem(
          author: 'Manager',
          role: 'Operations Lead',
          type: 'Review Feedback',
          message: _action.managerMessage,
          time: 'Latest review',
          isWorker: false,
        ),
      );
    }
    if (_action.remarks.isNotEmpty) {
      _comments.add(
        _CommentItem(
          author: 'Safety Officer',
          role: 'HSSE Team',
          type: 'Safety Remarks',
          message: _action.remarks,
          time: _action.dateRaised.isNotEmpty ? _action.dateRaised : 'Recorded',
          isWorker: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _handleAddComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final timeStr =
        '${now.day.toString().padLeft(2, '0')} ${_monthName(now.month)} ${now.year} • ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final authorName = widget.isWorker
        ? (_action.assignedTo.isNotEmpty ? _action.assignedTo : 'R. Kumar')
        : 'Current User';
    final roleName = widget.isWorker ? 'Assignee / Staff' : 'Manager / Lead';

    setState(() {
      _comments.insert(
        0,
        _CommentItem(
          author: authorName,
          role: roleName,
          type: widget.isWorker ? 'Staff Note' : 'Safety Note',
          message: text,
          time: timeStr,
          isWorker: widget.isWorker,
        ),
      );
      _history.insert(0, '$timeStr: Added a note.');
      _commentController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Note posted successfully.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF1565C0),
      ),
    );
  }

  bool get _canShowUpdateAction {
    if (_action.isClosed) return false;
    if (widget.isWorker) return true;
    final userProfile = AuthService.instance.currentProfileData?.userProfile;
    final uid = widget.currentUserId ?? widget.managerContext?.authUserId ?? userProfile?.id;
    final uname = widget.managerContext?.profile.name ?? userProfile?.name;
    if (uid == null && uname == null) return false;
    return (_action.assignedToId != null && _action.assignedToId == uid) ||
        (_action.assignedTo.isNotEmpty && _action.assignedTo == uname) ||
        _action.assignees.any((a) =>
            (uid != null && a.profileId == uid) ||
            (uname != null && a.profileName == uname));
  }

  bool get _canUploadEvidence {
    if (!widget.isWorker || (widget.managerContext?.isManager == true)) {
      return true;
    }
    final userProfile = AuthService.instance.currentProfileData?.userProfile;
    final staffId = widget.currentUserId ?? userProfile?.id;
    final staffName = userProfile?.name;
    final staffEmail = userProfile?.email;

    final isCreator = _action.isCreator(staffId, staffName, staffEmail);
    final isPrimaryOwner =
        _action.isAuthorizedPrimaryOwner(staffId, staffName, staffEmail);
    final isDirectAssignee =
        (_action.assignedToId != null && _action.assignedToId == staffId) ||
            (_action.assignedTo.isNotEmpty && _action.assignedTo == staffName) ||
            _action.assignees.any((a) =>
                (staffId != null && a.profileId == staffId) ||
                (staffName != null && a.profileName == staffName));
    final isContributor =
        _action.isForwardedTo(staffId, staffName, staffEmail);

    return isCreator || isPrimaryOwner || isDirectAssignee || isContributor;
  }

  void _handleUploadEvidence() {
    if (!_canUploadEvidence) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unauthorized: You do not have permission to upload evidence for this action.',
          ),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final List<AppPickedFile> selectedFiles = [];
        bool isUploading = false;
        String? validationError;
        int uploadingIndex = 0;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final totalBytes =
                selectedFiles.fold<int>(0, (int sum, AppPickedFile f) => sum + f.size);
            final formattedTotalSize = totalBytes < 1024 * 1024
                ? '${(totalBytes / 1024).toStringAsFixed(1)} KB'
                : '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

            return AlertDialog(
              backgroundColor: AppTheme.cardBg(dialogCtx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    color: AppTheme.primaryAccent(dialogCtx),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Upload Action Evidence',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(dialogCtx),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select documents or images from your computer (Max 10MB per file):',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary(dialogCtx),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isUploading
                            ? null
                            : () async {
                                final picked =
                                    await AppFilePicker.pickMultipleFiles(
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
                                if (picked.isEmpty) return;
                                const maxSizeBytes = 10 * 1024 * 1024;
                                final oversized = picked
                                    .where((f) => f.size > maxSizeBytes)
                                    .toList();
                                if (oversized.isNotEmpty) {
                                  setDialogState(() {
                                    validationError =
                                        'File "${oversized.first.name}" exceeds 10MB limit (${oversized.first.formattedSize}).';
                                  });
                                  return;
                                }
                                setDialogState(() {
                                  for (final f in picked) {
                                    if (!selectedFiles
                                        .any((e) => e.name == f.name)) {
                                      selectedFiles.add(f);
                                    }
                                  }
                                  validationError = null;
                                });
                              },
                        icon: Icon(
                          selectedFiles.isNotEmpty
                              ? Icons.add_circle_outline_rounded
                              : Icons.file_upload_outlined,
                          color: const Color(0xFF1565C0),
                          size: 18,
                        ),
                        label: Text(
                          selectedFiles.isEmpty
                              ? 'Choose Files from Computer'
                              : 'Add More Files...',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color(0xFF1565C0),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    if (selectedFiles.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Selected Files (${selectedFiles.length})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(dialogCtx),
                            ),
                          ),
                          Text(
                            'Total: $formattedTotalSize',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(dialogCtx),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          color: AppTheme.inputFill(dialogCtx),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.inputBorder(dialogCtx),
                          ),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: selectedFiles.length,
                          separatorBuilder: (_, index) => Divider(
                            height: 1,
                            color: AppTheme.inputBorder(dialogCtx),
                          ),
                          itemBuilder: (ctx, idx) {
                            final file = selectedFiles[idx];
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: Icon(
                                Icons.insert_drive_file_outlined,
                                size: 18,
                                color: AppTheme.primaryAccent(dialogCtx),
                              ),
                              title: Text(
                                file.name,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.textPrimary(dialogCtx),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                file.formattedSize,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary(dialogCtx),
                                ),
                              ),
                              trailing: isUploading
                                  ? (uploadingIndex == idx
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : null)
                                  : IconButton(
                                      icon: const Icon(Icons.close, size: 16),
                                      color: const Color(0xFFDC2626),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        setDialogState(() {
                                          selectedFiles.removeAt(idx);
                                        });
                                      },
                                    ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUploading
                      ? null
                      : () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary(dialogCtx)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: (isUploading || selectedFiles.isEmpty)
                      ? null
                      : () async {
                          setDialogState(() {
                            isUploading = true;
                            validationError = null;
                            uploadingIndex = 0;
                          });

                          final userProfile = AuthService.instance.currentProfileData?.userProfile;
                          final uploaderName = widget.isWorker
                              ? (userProfile?.name ?? 'Staff')
                              : 'Manager';
                          final uploaderRole =
                              widget.isWorker ? 'Staff' : 'Manager';
                          final nowStr = _formatCurrentDate();

                          int uploadedCount = 0;
                          for (int i = 0; i < selectedFiles.length; i++) {
                            setDialogState(() {
                              uploadingIndex = i;
                            });
                            final file = selectedFiles[i];
                            final uploadRes = await ActionService.instance
                                .uploadActionAttachment(
                              action: _action,
                              fileName: file.name,
                              bytes: file.bytes,
                            );

                            if (!uploadRes.success) {
                              setDialogState(() {
                                isUploading = false;
                                validationError =
                                    'Failed to upload "${file.name}": ${uploadRes.error ?? "Storage error"}';
                              });
                              return;
                            }

                            uploadedCount++;
                            final clean =
                                ActionService.sanitizeAttachmentFileName(
                                    file.name);
                            if (uploadRes.updatedAction != null) {
                              _action = uploadRes.updatedAction!;
                              _attachments = List.of(
                                uploadRes.updatedAction!.attachments,
                              );
                              _history = List.of(
                                uploadRes.updatedAction!.history,
                              );
                            } else {
                              if (!_attachments.contains(clean)) {
                                _attachments.add(clean);
                              }
                              _history.insert(
                                0,
                                '$nowStr: Evidence file "$clean" uploaded by $uploaderName ($uploaderRole).',
                              );
                              _action = _action.copyWith(
                                attachments: _attachments,
                                history: _history,
                              );
                            }
                          }

                          if (!mounted || !dialogCtx.mounted) return;
                          Navigator.of(dialogCtx).pop();

                          setState(() {});
                          widget.onUpdateAction?.call();

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Successfully uploaded $uploadedCount evidence file(s).',
                              ),
                              backgroundColor: const Color(0xFF16A34A),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  icon: isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(
                    isUploading
                        ? 'Uploading (${uploadingIndex + 1}/${selectedFiles.length})...'
                        : 'Upload ${selectedFiles.isEmpty ? "" : "(${selectedFiles.length})"}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleAddFollowUp() async {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    final notesController = TextEditingController();
    bool isSaving = false;
    String? errorText;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg(dialogCtx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Color(0xFF7C3AED),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Schedule Follow-Up',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(dialogCtx),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Follow-Up Date is a review checkpoint date to monitor progress before the target due date.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(dialogCtx),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Checkpoint Date *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(dialogCtx),
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 730),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.inputFill(dialogCtx),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.inputBorder(dialogCtx),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event,
                              size: 18,
                              color: Color(0xFF7C3AED),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${selectedDate.day.toString().padLeft(2, '0')} ${_monthName(selectedDate.month)} ${selectedDate.year}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary(dialogCtx),
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              'Change',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Review Notes / Agenda (Optional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(dialogCtx),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary(dialogCtx),
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g., Review milestone progress, inspect physical barricades...',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary(dialogCtx),
                        ),
                        filled: true,
                        fillColor: AppTheme.inputFill(dialogCtx),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppTheme.inputBorder(dialogCtx),
                          ),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary(dialogCtx)),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() {
                            isSaving = true;
                            errorText = null;
                          });
                          final res = await ActionService.instance.addFollowUp(
                            actionId: _action.id,
                            followUpDate: selectedDate,
                            notes: notesController.text.trim(),
                          );
                          if (!mounted) return;
                          if (res.success) {
                            final reloaded = await ActionService.instance
                                .fetchActionById(_action.id);
                            if (mounted) {
                              setState(() {
                                if (reloaded != null) {
                                  _action = reloaded;
                                  _history = List<String>.from(
                                    reloaded.history,
                                  );
                                }
                              });
                            }
                            if (dialogCtx.mounted) {
                              Navigator.of(dialogCtx).pop();
                            }
                            final formatted =
                                '${selectedDate.day.toString().padLeft(2, '0')} ${_monthName(selectedDate.month)} ${selectedDate.year}';
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Follow-up review scheduled for $formatted',
                                  ),
                                  backgroundColor: const Color(0xFF1565C0),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              widget.onUpdateAction?.call();
                            }
                          } else {
                            setDialogState(() {
                              isSaving = false;
                              errorText =
                                  res.error ?? 'Failed to schedule follow-up';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Schedule'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleApproveAndCloseAction() async {
    if (_action.percentComplete < 100) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.cardBg(dialogCtx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFEA580C),
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                'Action Incomplete',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.textPrimary(dialogCtx),
                ),
              ),
            ],
          ),
          content: Text(
            'This action is currently at ${_action.percentComplete}% progress. Only actions at 100% completion can be approved for formal closure.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppTheme.textSecondary(dialogCtx),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!_action.allRequiredAssigneesCompleted) {
      final incomplete = _action.assignees
          .where((a) => a.isRequired && !a.workCompleted)
          .toList();
      final names = incomplete
          .map((a) => a.profileName.isNotEmpty ? a.profileName : 'Assignee')
          .join(', ');
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.cardBg(dialogCtx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.group_off_rounded,
                color: Color(0xFFEA580C),
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                'Required Assignees Incomplete',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.textPrimary(dialogCtx),
                ),
              ),
            ],
          ),
          content: Text(
            'All required assignees must complete their assigned work before the Action can be formally closed. The following required assignee(s) have not completed their work: $names.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppTheme.textSecondary(dialogCtx),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final commentCtrl = TextEditingController();
    bool confirmedVerification = false;
    String? errorText;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg(dialogCtx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF16A34A),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Approve & Close Action',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(dialogCtx),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Action #${_action.displayId} • Retained permanently in register',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary(dialogCtx),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.containerBg(dialogCtx),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.cardBorder(dialogCtx),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _action.subject,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppTheme.textPrimary(dialogCtx),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Assignee: ${_action.assignedTo}  •  Site: ${_action.site}  •  Completion: ${_action.percentComplete}%',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textSecondary(dialogCtx),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Manager Closure & Verification Comments *',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: commentCtrl,
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter compliance verification and closure notes...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted(dialogCtx),
                          ),
                          filled: true,
                          fillColor: AppTheme.inputFill(dialogCtx),
                          errorText: errorText,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      CheckboxListTile(
                        value: confirmedVerification,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          'I verify this action has been fully inspected and completed according to HSSE requirements.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(dialogCtx),
                          ),
                        ),
                        onChanged: (val) {
                          setDialogState(() {
                            confirmedVerification = val ?? false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary(dialogCtx)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final comment = commentCtrl.text.trim();
                    if (comment.isEmpty) {
                      setDialogState(() {
                        errorText =
                            'Verification comment is required for closure.';
                      });
                      return;
                    }
                    if (!confirmedVerification) {
                      setDialogState(() {
                        errorText =
                            'Please verify completion checkbox before closing.';
                      });
                      return;
                    }

                    Navigator.of(dialogCtx).pop();

                    final now = DateTime.now();
                    final timeStr =
                        '${now.day.toString().padLeft(2, '0')} ${_monthName(now.month)} ${now.year}';
                    try {
                      if (_action.id.isNotEmpty && _action.id.contains('-')) {
                        final updated = await ActionService.instance
                            .approveAndCloseAction(
                              actionId: _action.id,
                              closureComment: comment,
                            );
                        if (mounted) {
                          setState(() {
                            _action = updated;
                            _history = List<String>.from(updated.history);
                          });
                        }
                      } else {
                        setState(() {
                          _action = _action.copyWith(
                            status: 'Closed',
                            percentComplete: 100,
                            closedAt: now,
                            closureComment: comment,
                          );
                          _history.insert(
                            0,
                            '$timeStr: Action Approved & Closed: $comment',
                          );
                        });
                        _persistUpdate();
                      }
                    } catch (e) {
                      debugPrint('[ActionDetailsScreen] Closure error: $e');
                      setState(() {
                        _action = _action.copyWith(
                          status: 'Closed',
                          percentComplete: 100,
                          closedAt: now,
                          closureComment: comment,
                        );
                        _history.insert(
                          0,
                          '$timeStr: Action Approved & Closed: $comment',
                        );
                      });
                      _persistUpdate();
                    }

                    if (mounted) {
                      widget.onUpdateAction?.call();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Action approved and closed. Retained permanently in register.',
                          ),
                          backgroundColor: Color(0xFF16A34A),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                  ),
                  label: const Text('Approve & Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleRequestMoreInformation() async {
    final commentCtrl = TextEditingController();
    String targetStatus = 'In Progress';
    String? errorText;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg(dialogCtx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.assignment_return_rounded,
                      color: Color(0xFFD97706),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Request More Information',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(dialogCtx),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Return action for revision or additional evidence',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary(dialogCtx),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Target Reverted Status',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: targetStatus,
                        dropdownColor: AppTheme.cardBg(dialogCtx),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.inputFill(dialogCtx),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'In Progress',
                            child: Text('In Progress'),
                          ),
                          DropdownMenuItem(
                            value: 'Open',
                            child: Text('Open / Pending Action'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => targetStatus = val);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Reason & Information Needed *',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: commentCtrl,
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Specify what additional proof or rework is required...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted(dialogCtx),
                          ),
                          filled: true,
                          fillColor: AppTheme.inputFill(dialogCtx),
                          errorText: errorText,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary(dialogCtx)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final comment = commentCtrl.text.trim();
                    if (comment.isEmpty) {
                      setDialogState(() {
                        errorText = 'Please provide details on what information is needed.';
                      });
                      return;
                    }

                    Navigator.of(dialogCtx).pop();

                    final now = DateTime.now();
                    final timeStr =
                        '${now.day.toString().padLeft(2, '0')} ${_monthName(now.month)} ${now.year}';

                    try {
                      if (_action.id.isNotEmpty && _action.id.contains('-')) {
                        final updated = await ActionService.instance
                            .requestMoreInformation(
                              actionId: _action.id,
                              comments: comment,
                              targetStatus: targetStatus,
                            );
                        if (mounted) {
                          setState(() {
                            _action = updated;
                            _history = List<String>.from(updated.history);
                          });
                        }
                      } else {
                        setState(() {
                          _action = _action.copyWith(
                            status: targetStatus,
                            managerMessage: comment,
                          );
                          _history.insert(
                            0,
                            '$timeStr: Reverted to $targetStatus: $comment',
                          );
                        });
                        _persistUpdate();
                      }
                    } catch (e) {
                      debugPrint(
                        '[ActionDetailsScreen] Request info error: $e',
                      );
                      setState(() {
                        _action = _action.copyWith(
                          status: targetStatus,
                          managerMessage: comment,
                        );
                        _history.insert(
                          0,
                          '$timeStr: Reverted to $targetStatus: $comment',
                        );
                      });
                      _persistUpdate();
                    }

                    if (mounted) {
                      widget.onUpdateAction?.call();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Action returned to $targetStatus for revision.',
                          ),
                          backgroundColor: const Color(0xFFD97706),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text('Return for Revision'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleStatusUpdate() {
    if (widget.onUpdateAction != null) {
      widget.onUpdateAction!();
      return;
    }

    // Default status picker dialog if no custom callback is attached
    final statuses = const ['Open', 'In Progress', 'Pending Review', 'Closed'];
    showDialog(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          backgroundColor: AppTheme.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Update Action Status',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(ctx),
            ),
          ),
          children: statuses.map((st) {
            final isCurrent = _action.status == st;
            return SimpleDialogOption(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _action = _action.copyWith(
                    status: st,
                    percentComplete: st == 'Closed'
                        ? 100
                        : (st == 'In Progress'
                              ? (_action.percentComplete < 30
                                    ? 40
                                    : _action.percentComplete)
                              : _action.percentComplete),
                  );
                  _history.insert(
                    0,
                    '${_formatCurrentDate()}: Status changed to $st.',
                  );
                });
                _persistUpdate();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Action ${_action.id} status set to $st'),
                    backgroundColor: _statusColor(st),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _statusColor(st),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      st,
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrent
                            ? AppTheme.primaryAccent(ctx)
                            : AppTheme.textPrimary(ctx),
                      ),
                    ),
                    if (isCurrent) ...[
                      const Spacer(),
                      Icon(
                        Icons.check_rounded,
                        color: AppTheme.primaryAccent(ctx),
                        size: 18,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  static String _monthName(int m) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return m >= 1 && m <= 12 ? months[m] : '';
  }

  static String _formatCurrentDate() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')} ${_monthName(now.month)} ${now.year}';
  }

  (String name, String role, String department) _getPersonDetails(
    String name, {
    ActionPersonReference? ref,
    bool isAssigner = false,
  }) {
    final effectiveName = name.trim().isNotEmpty
        ? name.trim()
        : (ref?.name.trim() ?? '');

    if (effectiveName.isEmpty) {
      return (
        'Unspecified',
        'Unspecified',
        _action.department.isNotEmpty ? _action.department : 'Operations',
      );
    }

    // 1. Look up in MockPeopleStore directory
    final matches = MockPeopleStore.instance.people
        .where(
          (p) => p.name.trim().toLowerCase() == effectiveName.toLowerCase(),
        )
        .toList();
    if (matches.isNotEmpty) {
      final p = matches.first;
      final roleText = p.type == PersonType.externalWorker
          ? 'External Staff'
          : (p.role == UserRole.departmentManager ||
                  p.role.name.toLowerCase().contains('manager') ||
                  p.designation.toLowerCase().contains('manager')
              ? 'Manager'
              : (p.role == UserRole.admin ||
                      p.designation.toLowerCase().contains('admin')
                  ? 'Administrator'
                  : 'Staff'));
      final deptText = p.department.isNotEmpty
          ? p.department
          : (p.company.isNotEmpty
                ? p.company
                : (_action.department.isNotEmpty
                      ? _action.department
                      : 'Operations'));
      return (p.name, roleText, deptText);
    }

    // 2. Look up in ActionPersonReference
    if (ref != null) {
      final roleText = ref.type == PersonType.externalWorker
          ? 'External Staff'
          : (ref.designation.toLowerCase().contains('manager')
              ? 'Manager'
              : (ref.designation.toLowerCase().contains('admin')
                  ? 'Administrator'
                  : 'Staff'));
      final deptText = ref.department.isNotEmpty
          ? ref.department
          : (ref.company.isNotEmpty
                ? ref.company
                : (_action.department.isNotEmpty
                      ? _action.department
                      : 'Operations'));
      return (ref.name, roleText, deptText);
    }

    // 3. Fallback
    final roleText = effectiveName == 'Unspecified' ? 'Unspecified' : 'Staff';
    final deptText = _action.department.isNotEmpty
        ? _action.department
        : 'Operations';
    return (effectiveName, roleText, deptText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.headerBg(context),
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0x1A0F172A),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary(context),
            size: 22,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
        titleSpacing: 4,
        title: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 240) {
              return Text(
                _action.displayId,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              );
            }
            return Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.actionIdBg(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.actionIdBorder(context)),
                  ),
                  child: Text(
                    _action.displayId,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.actionIdText(context),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _action.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          // Theme Toggle
          const ThemeToggleButton(size: 34),
          const SizedBox(width: 4),

          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Action summary copied to clipboard.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: Icon(
              Icons.share_outlined,
              color: AppTheme.textSecondary(context),
              size: 20,
            ),
            tooltip: 'Share',
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: AppTheme.textSecondary(context),
              size: 20,
            ),
            onSelected: (val) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$val action triggered.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'Export PDF',
                child: Row(
                  children: [
                    Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 18,
                      color: Color(0xFF475569),
                    ),
                    SizedBox(width: 10),
                    Text('Export as PDF'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'Print',
                child: Row(
                  children: [
                    Icon(
                      Icons.print_outlined,
                      size: 18,
                      color: Color(0xFF475569),
                    ),
                    SizedBox(width: 10),
                    Text('Print Details'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'Audit Log',
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 18,
                      color: Color(0xFF475569),
                    ),
                    SizedBox(width: 10),
                    Text('Verify Compliance'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // 1. TOP ACTION SUMMARY HERO CARD
              _buildTopHeroCard(context),
              const SizedBox(height: 16),

              // 2. TAB NAVIGATION BAR
              _buildTabBar(),
              const SizedBox(height: 16),

              // 3. ANIMATED ACTIVE TAB CONTENT
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: anim,
                      curve: Curves.easeOut,
                    ),
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0.015, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: anim,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey('tab_content_$_selectedTabIndex'),
                  child: _buildActiveTabContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TOP ACTION HERO CARD (HEADER + CIRCULAR PROGRESS + QUICK INFO + BUTTONS)
  // ===========================================================================

  Widget _buildClosedBanner(BuildContext context) {
    final closedDate = _action.closedAt != null
        ? '${_action.closedAt!.day.toString().padLeft(2, '0')} ${_monthName(_action.closedAt!.month)} ${_action.closedAt!.year}'
        : 'Recorded';
    final closedBy =
        _action.closedByName != null && _action.closedByName!.isNotEmpty
        ? _action.closedByName!
        : 'Unspecified';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF16A34A).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFF16A34A),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Action Closed & Retained',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Audit Retained',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Closed by: $closedBy • Date: $closedDate\n'
                  'Verification: ${_action.closureComment.isNotEmpty ? _action.closureComment : "Verified compliant with HSSE standards."}\n'
                  'This action and all its progress history are permanently retained in the register.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadyForReviewBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFD97706).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD97706).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFD97706),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.rate_review_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Ready for Manager Review (100% Complete)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Awaiting Closure',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Work is 100% complete and awaiting manager closure verification. Review the evidence and history, then Approve & Close or Request More Information.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _handleApproveAndCloseAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 15,
                      ),
                      label: const Text(
                        'Approve & Close',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _handleRequestMoreInformation,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD97706),
                        side: const BorderSide(color: Color(0xFFD97706)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      icon: const Icon(
                        Icons.assignment_return_rounded,
                        size: 15,
                      ),
                      label: const Text(
                        'Request More Information',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeroCard(BuildContext context) {
    final statusColor = _statusColor(_action.status);
    final priorityColor = _priorityColor(_action.priority);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: AppTheme.isDark(context)
            ? []
            : const [
                BoxShadow(
                  color: Color(0x060F172A),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_action.isClosed) ...[
                _buildClosedBanner(context),
                const SizedBox(height: 14),
              ] else if (_action.isReadyForReview) ...[
                _buildReadyForReviewBanner(context),
                const SizedBox(height: 14),
              ],
              // 1. Meta Badges Row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.actionIdBg(context),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppTheme.actionIdBorder(context),
                      ),
                    ),
                    child: Text(
                      _action.id,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.actionIdText(context),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.isDark(context)
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.cardBorder(context)),
                    ),
                    child: Text(
                      _action.section.isNotEmpty
                          ? _action.section
                          : (_action.category.isNotEmpty
                                ? _action.category
                                : 'HSSE Action'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                  _badge(
                    _action.priority,
                    priorityColor,
                    icon: _priorityIcon(_action.priority),
                  ),
                  _badge(_action.status, statusColor),
                ],
              ),
              const SizedBox(height: 14),

              // 2. Action Subject & Circular Progress Indicator
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _action.subject,
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Department: ${_action.department.isNotEmpty ? _action.department : 'General'}  •  Site: ${_action.site.isNotEmpty ? _action.site : 'Main'}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    _buildCircularCompletionIndicator(),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _action.subject,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_action.department.isNotEmpty ? _action.department : 'General'} • ${_action.site.isNotEmpty ? _action.site : 'Main'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _buildCircularCompletionIndicator(),
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              Divider(color: AppTheme.dividerColor(context), height: 1),
              const SizedBox(height: 16),

              // 3. Quick Info Strip
              _buildQuickInfoGrid(constraints),
              const SizedBox(height: 18),

              // 4. Action Buttons Toolbar
              _buildActionButtonsToolbar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCircularCompletionIndicator() {
    final percent = _action.percentComplete.clamp(0, 100);
    final color = _statusColor(_action.status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.isDark(context)
            ? const Color(0xFF1E293B)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: percent / 100.0,
                  strokeWidth: 5.5,
                  backgroundColor: AppTheme.progressTrackBg(context),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Completion',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _action.status,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickInfoGrid(BoxConstraints constraints) {
    final (assignedByName, _, _) = _getPersonDetails(
      _action.assignedBy,
      isAssigner: true,
    );
    final (assignedToName, _, _) = _getPersonDetails(
      _action.assignedTo,
      ref: _action.primaryAssignee,
      isAssigner: false,
    );

    final double itemWidth;
    if (constraints.maxWidth < 360) {
      itemWidth = constraints.maxWidth;
    } else if (constraints.maxWidth < 640) {
      itemWidth = (constraints.maxWidth - 12) / 2;
    } else if (constraints.maxWidth < 960) {
      itemWidth = (constraints.maxWidth - 24) / 3;
    } else {
      itemWidth = (constraints.maxWidth - 48) / 5;
    }

    final items = <(IconData, String, String, Color)>[
      (
        Icons.person_add_alt_1_outlined,
        'Assigned By',
        assignedByName,
        const Color(0xFF0D9488),
      ),
      (
        Icons.person_outline_rounded,
        'Assigned To',
        assignedToName,
        const Color(0xFF1565C0),
      ),
      (
        Icons.location_on_outlined,
        'Project / Site',
        _action.site.isNotEmpty ? _action.site : 'Not specified',
        const Color(0xFF0284C7),
      ),
      (
        Icons.event_outlined,
        'Target Date',
        _action.targetDate.isNotEmpty ? _action.targetDate : 'Not set',
        const Color(0xFFEA580C),
      ),
      (
        Icons.calendar_month_outlined,
        'Next Follow-up',
        _action.nextFollowUpDate.isNotEmpty
            ? _action.nextFollowUpDate
            : (_action.followUp.isNotEmpty && _action.followUp != '-'
                  ? _action.followUp
                  : 'Not scheduled'),
        const Color(0xFF7C3AED),
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items.map((info) {
        return SizedBox(
          width: itemWidth,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.isDark(context)
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: info.$4.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(info.$1, size: 16, color: info.$4),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButtonsToolbar() {
    if (widget.isWorker) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: widget.onUpdateAction ?? _handleStatusUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(Icons.edit_note_rounded, size: 17),
            label: const Text(
              'Submit Update',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _showForwardActionDialog,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryAccent(context),
              side: BorderSide(color: AppTheme.cardBorder(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            ),
            icon: const Icon(Icons.shortcut_rounded, size: 17),
            label: const Text(
              'Forward Action',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _handleUploadEvidence,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryAccent(context),
              side: BorderSide(color: AppTheme.cardBorder(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            ),
            icon: const Icon(Icons.upload_file_rounded, size: 17),
            label: const Text(
              'Upload Evidence',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _selectedTabIndex = 5);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary(context),
              side: BorderSide(color: AppTheme.cardBorder(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
            label: const Text(
              'Add Safety Remark',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_action.isClosed) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: const Color(0xFF16A34A).withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: Color(0xFF16A34A),
                ),
                SizedBox(width: 6),
                Text(
                  'Closed (Read-Only)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          if (_action.isReadyForReview) ...[
            ElevatedButton.icon(
              onPressed: _handleApproveAndCloseAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text(
                'Approve & Close',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _handleRequestMoreInformation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.assignment_return_rounded, size: 17),
              label: const Text(
                'Request More Info',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          if (_canShowUpdateAction) ...[
            ElevatedButton.icon(
              onPressed: _handleOpenUpdateScreen,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: Text(
                widget.isWorker ? 'Submit Update' : 'Update Action',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
        OutlinedButton.icon(
          onPressed: _showForwardActionDialog,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryAccent(context),
            side: BorderSide(color: AppTheme.cardBorder(context)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          ),
          icon: const Icon(Icons.shortcut_rounded, size: 17),
          label: const Text(
            'Forward Action',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _handleAddFollowUp,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryAccent(context),
            side: BorderSide(color: AppTheme.cardBorder(context)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          ),
          icon: const Icon(Icons.add_alarm_rounded, size: 17),
          label: const Text(
            'Add Follow-up',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _handleEditAction,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSecondary(context),
            side: BorderSide(color: AppTheme.cardBorder(context)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          ),
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text(
            'Edit Action',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Future<void> _handleEditAction() async {
    if (_action.isClosed) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF16A34A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Closed Action (Read-Only)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'This action has been approved and closed. In accordance with enterprise HSE governance and audit compliance retention standards, closed actions cannot be edited or modified.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    final updated = await Navigator.of(context).push<ActionRecord>(
      MaterialPageRoute(
        builder: (_) => AddActionScreen(
          actionId: _action.id,
          existingAction: _action,
          managerContext: widget.managerContext,
          isEmbedded: false,
          onSaved: (saved) {
            if (mounted) {
              setState(() {
                _action = saved;
              });
              widget.onUpdateAction?.call();
            }
          },
        ),
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _action = updated;
      });
      widget.onUpdateAction?.call();
    }
  }

  // ===========================================================================
  // FORWARD ACTION & SUB-TASK DIALOGS
  // ===========================================================================

  void _showForwardActionDialog() {
    _ForwardMode selectedMode = _ForwardMode.entireAction;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg(dialogCtx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.isDark(dialogCtx)
                          ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.shortcut_rounded,
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
                          'Forward Action — ${_action.id}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(dialogCtx),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select forwarding or delegation mode',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(dialogCtx),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Divider(
                        color: AppTheme.dividerColor(dialogCtx),
                        height: 16,
                      ),
                      _buildForwardModeOption(
                        title: 'Forward Action / Add Contributor',
                        description: 'Add a supporting team member to collaborate. Main ownership remains with the current owner.',
                        icon: Icons.person_add_alt_1_rounded,
                        iconColor: const Color(0xFF1565C0),
                        isSelected: selectedMode == _ForwardMode.entireAction,
                        onTap: () {
                          setDialogState(() {
                            selectedMode = _ForwardMode.entireAction;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildForwardModeOption(
                        title: 'Forward as Sub-task',
                        description: 'Keep main action ownership and delegate a weighted sub-task to a team member.',
                        icon: Icons.account_tree_rounded,
                        iconColor: const Color(0xFF7C3AED),
                        isSelected: selectedMode == _ForwardMode.subTask,
                        onTap: () {
                          setDialogState(() {
                            selectedMode = _ForwardMode.subTask;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary(dialogCtx)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    if (selectedMode == _ForwardMode.entireAction) {
                      _showForwardEntireActionDialog();
                    } else {
                      _showForwardSubTaskDialog();
                    }
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('Continue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildForwardModeOption({
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? (AppTheme.isDark(context)
                    ? const Color(0xFF1E3A8A).withValues(alpha: 0.35)
                    : const Color(0xFFEFF6FF))
              : (AppTheme.isDark(context)
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1565C0)
                : AppTheme.cardBorder(context),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? (AppTheme.isDark(context)
                                ? const Color(0xFF60A5FA)
                                : const Color(0xFF1565C0))
                          : AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1565C0)
                      : AppTheme.cardBorder(context),
                  width: isSelected ? 6 : 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showForwardEntireActionDialog() async {
    final orgId = _action.organizationId.isNotEmpty
        ? _action.organizationId
        : (widget.managerContext?.organizationId ?? Organization.sobhaId);
    final userProfile = AuthService.instance.currentProfileData?.userProfile;
    final callerId = widget.currentUserId ?? userProfile?.id;
    final callerName = userProfile != null ? userProfile.name.toLowerCase().trim() : '';

    final userRole = userProfile?.role.toLowerCase().trim() ?? '';
    final isCallerManager = widget.managerContext?.isManager == true ||
        userRole == 'manager' ||
        userRole == 'departmentmanager' ||
        userRole == 'department_manager' ||
        userRole == 'admin' ||
        userRole == 'company_admin' ||
        userRole == 'platform_admin';
    final isCallerStaff = widget.isWorker || !isCallerManager;

    List<ActionPersonReference> eligible = await ActionService.instance
        .fetchEligibleAssignees(
          organizationId: orgId,
          departmentId: _action.departmentId,
          siteId: _action.siteId,
          actionTeamId: _action.teamId,
          callerUserId: callerId,
          managerScopes: widget.managerContext?.scopes,
        );

    // Fallback to MockPeopleStore ONLY if offline test environment (when Supabase client is null)
    if (eligible.isEmpty && ActionService.instance.client == null) {
      eligible = MockPeopleStore.instance.people
          .where((p) => p.isActive)
          .map(
            (p) => ActionPersonReference(
              personId: p.id,
              name: p.name,
              type: p.type,
              email: p.email,
              phone: p.phone,
              designation: p.designation,
              department: p.department,
              site: p.site,
              company: p.company,
              role: p.role == UserRole.departmentManager ? 'manager' : 'staff',
              teamIds: p.teamIds,
              departmentId: p.departmentId,
              siteId: p.siteId,
            ),
          )
          .toList();
    }

    // Filter out current owner, invalid UUIDs, 'Unassigned', existing contributors, and caller
    final ownerId = _action.assignedToId ?? '';
    final ownerName = _action.assignedTo.toLowerCase().trim();

    eligible = eligible.where((p) {
      if (!p.isValidUuid || p.personId.toLowerCase() == 'unassigned') {
        return false;
      }
      if (p.name.trim().toLowerCase() == 'unassigned') return false;
      if (ownerId.isNotEmpty && p.personId == ownerId) return false;
      if (p.name.toLowerCase().trim() == ownerName) return false;
      if (callerId != null && callerId.isNotEmpty && p.personId == callerId) return false;
      if (callerName.isNotEmpty && p.name.toLowerCase().trim() == callerName) return false;
      // Filter out existing contributors
      if (_action.contributors.any(
        (c) =>
            c.profileId == p.personId ||
            c.profileName.toLowerCase().trim() == p.name.toLowerCase().trim(),
      )) {
        return false;
      }
      // If caller is Staff (worker), can only add other Staff (Staff -> Manager blocked)
      if (isCallerStaff && p.isManager) {
        return false;
      }
      return true;
    }).toList();

    if (!mounted) return;

    if (eligible.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('No Eligible Contributors'),
          content: const Text(
            'There are no additional eligible users available to add as a contributor for this action.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    ActionPersonReference selectedPerson = eligible.first;
    final reasonController = TextEditingController();
    bool isSaving = false;
    String? errorText;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg(dialogCtx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.isDark(dialogCtx)
                          ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
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
                          'Add Contributor — ${_action.id}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(dialogCtx),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Forward action to a collaborator without transferring ownership',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(dialogCtx),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Current Owner summary
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.isDark(dialogCtx)
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.cardBorder(dialogCtx),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              size: 20,
                              color: Color(0xFF1565C0),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ACTION OWNER (REMAINS RESPONSIBLE)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textSecondary(dialogCtx),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    _action.assignedTo,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary(dialogCtx),
                                    ),
                                  ),
                                  Text(
                                    'Adding a contributor forwards this action for shared contribution. Primary ownership does not change.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary(dialogCtx),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'Select Contributor *',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPerson.personId,
                        isExpanded: true,
                        dropdownColor: AppTheme.cardBg(dialogCtx),
                        style: TextStyle(
                          color: AppTheme.textPrimary(dialogCtx),
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                          fillColor: AppTheme.inputFill(dialogCtx),
                          filled: true,
                        ),
                        items: eligible.map((person) {
                          return DropdownMenuItem<String>(
                            value: person.personId,
                            child: Text(
                              '${person.name} — ${person.designation} (${person.department.isNotEmpty ? person.department : "Operations"})',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary(dialogCtx),
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedPerson = eligible.firstWhere(
                                (p) => p.personId == val,
                              );
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'Collaboration Notes (Optional)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        style: TextStyle(
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g., Forwarding to assist with scaffolding inspection...',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary(dialogCtx),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                          filled: true,
                          fillColor: AppTheme.inputFill(dialogCtx),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary(dialogCtx)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() {
                            isSaving = true;
                            errorText = null;
                          });

                          if (!selectedPerson.isValidUuid ||
                              selectedPerson.personId.toLowerCase() ==
                                  'unassigned') {
                            setDialogState(() {
                              isSaving = false;
                              errorText =
                                  'Cannot add contributor: invalid user ID ("${selectedPerson.personId}"). A valid user UUID is required.';
                            });
                            return;
                          }

                          final res = await ActionService.instance
                              .addContributor(
                                actionId: _action.id,
                                contributorProfileId: selectedPerson.personId,
                                notes: reasonController.text.trim(),
                                addedBy: callerId ?? '',
                                addedByName: userProfile?.name ?? '',
                              );

                          if (!mounted) return;

                          if (res.success) {
                            final reloaded = await ActionService.instance
                                .fetchActionById(_action.id);
                            if (mounted) {
                              setState(() {
                                if (reloaded != null) {
                                  _action = reloaded;
                                  _history = List<String>.from(
                                    reloaded.history,
                                  );
                                } else {
                                  final newContrib = ActionContributorRecord(
                                    id: 'contrib_${DateTime.now().millisecondsSinceEpoch}',
                                    actionId: _action.id,
                                    profileId: selectedPerson.personId,
                                    profileName: selectedPerson.name,
                                    profileEmail: selectedPerson.email,
                                    notes: reasonController.text.trim(),
                                    createdAt: DateTime.now(),
                                  );
                                  _action = _action.copyWith(
                                    contributors: [
                                      ..._action.contributors,
                                      newContrib,
                                    ],
                                    history: [
                                      '${_formatCurrentDate()}: Contributor ${selectedPerson.name} added.',
                                      ..._action.history,
                                    ],
                                  );
                                  _history = List<String>.from(_action.history);
                                }
                              });
                              _persistUpdate();
                              MockPeopleStore.instance.addNotification(
                                TeamNotification(
                                  id: 'NTF-${DateTime.now().millisecondsSinceEpoch}',
                                  managerId: selectedPerson.personId,
                                  teamId: _action.department,
                                  title: 'Added as Contributor',
                                  message:
                                      '${_action.assignedTo} added you as a contributor to Action ${_action.id}.',
                                ),
                              );
                            }

                            if (dialogCtx.mounted) {
                              Navigator.of(dialogCtx).pop();
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Contributor ${selectedPerson.name} added. Owner remains ${_action.assignedTo}.',
                                  ),
                                  backgroundColor: const Color(0xFF1565C0),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              widget.onUpdateAction?.call();
                            }
                          } else {
                            setDialogState(() {
                              isSaving = false;
                              errorText =
                                  res.error ?? 'Failed to add contributor';
                            });
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(isSaving ? 'Adding...' : 'Add Contributor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showForwardSubTaskDialog() async {
    final orgId = _action.organizationId.isNotEmpty
        ? _action.organizationId
        : (widget.managerContext?.organizationId ?? Organization.sobhaId);
    final userProfile = AuthService.instance.currentProfileData?.userProfile;
    final callerId = widget.currentUserId ?? userProfile?.id;
    final callerName = userProfile != null ? userProfile.name.toLowerCase().trim() : '';

    final userRole = userProfile?.role.toLowerCase().trim() ?? '';
    final isCallerManager = widget.managerContext?.isManager == true ||
        userRole == 'manager' ||
        userRole == 'departmentmanager' ||
        userRole == 'department_manager' ||
        userRole == 'admin' ||
        userRole == 'company_admin' ||
        userRole == 'platform_admin';
    final isCallerStaff = widget.isWorker || !isCallerManager;

    List<ActionPersonReference> eligible = await ActionService.instance
        .fetchEligibleAssignees(
          organizationId: orgId,
          departmentId: _action.departmentId,
          siteId: _action.siteId,
          actionTeamId: _action.teamId,
          callerUserId: callerId,
          managerScopes: widget.managerContext?.scopes,
        );

    // Fallback to MockPeopleStore ONLY if offline test environment
    if (eligible.isEmpty && ActionService.instance.client == null) {
      eligible = MockPeopleStore.instance.people
          .where((p) => p.isActive)
          .map(
            (p) => ActionPersonReference(
              personId: p.id,
              name: p.name,
              type: p.type,
              email: p.email,
              phone: p.phone,
              designation: p.designation,
              department: p.department,
              site: p.site,
              company: p.company,
              role: p.role == UserRole.departmentManager ? 'manager' : 'staff',
              teamIds: p.teamIds,
              departmentId: p.departmentId,
              siteId: p.siteId,
            ),
          )
          .toList();
    }

    eligible = eligible.where((p) {
      if (!p.isValidUuid || p.personId.toLowerCase() == 'unassigned') {
        return false;
      }
      if (p.name.trim().toLowerCase() == 'unassigned') return false;
      if (callerId != null && callerId.isNotEmpty && p.personId == callerId) return false;
      if (callerName.isNotEmpty && p.name.toLowerCase().trim() == callerName) return false;
      // If caller is Staff, can only delegate to other Staff (Staff -> Manager blocked)
      if (isCallerStaff && p.isManager) return false;
      return true;
    }).toList();

    if (!mounted) return;

    if (eligible.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('No Eligible Staff Members'),
          content: const Text(
            'There are no eligible team members available to delegate this sub-task.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    ActionPersonReference selectedStaff = eligible.first;
    final titleController = TextEditingController();
    final instructionController = TextEditingController();
    final remarksController = TextEditingController();
    int selectedWeight = 20;

    DateTime dueDate = DateTime.now().add(const Duration(days: 7));
    String dueDateStr =
        '${dueDate.day.toString().padLeft(2, '0')} ${_monthName(dueDate.month)} ${dueDate.year}';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg(dialogCtx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.isDark(dialogCtx)
                          ? const Color(0xFF581C87).withValues(alpha: 0.3)
                          : const Color(0xFFFAF5FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.account_tree_rounded,
                      color: Color(0xFF7C3AED),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delegate Sub-task — ${_action.id}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(dialogCtx),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Assign child sub-task under parent action',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(dialogCtx),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sub-task Title *',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: titleController,
                        style: TextStyle(
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'e.g., Fabricate scaffolding support brackets',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary(dialogCtx),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: AppTheme.inputFill(dialogCtx),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'Detailed Instruction *',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: instructionController,
                        maxLines: 3,
                        style: TextStyle(
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Provide specific requirements, safety checks, or deliverables...',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary(dialogCtx),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                          filled: true,
                          fillColor: AppTheme.inputFill(dialogCtx),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'Assign Staff *',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStaff.personId,
                        isExpanded: true,
                        dropdownColor: AppTheme.cardBg(dialogCtx),
                        style: TextStyle(
                          color: AppTheme.textPrimary(dialogCtx),
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                          fillColor: AppTheme.inputFill(dialogCtx),
                          filled: true,
                        ),
                        items: eligible.map((person) {
                          return DropdownMenuItem<String>(
                            value: person.personId,
                            child: Text(
                              '${person.name} (${person.designation})',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary(dialogCtx),
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedStaff = eligible.firstWhere(
                                (p) => p.personId == val,
                              );
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Due Date',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(dialogCtx),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: dueDate,
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now().add(
                                        const Duration(days: 365),
                                      ),
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        dueDate = picked;
                                        dueDateStr =
                                            '${picked.day.toString().padLeft(2, '0')} ${_monthName(picked.month)} ${picked.year}';
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppTheme.inputBorder(dialogCtx),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      color: AppTheme.inputFill(dialogCtx),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.event_outlined,
                                          size: 16,
                                          color: AppTheme.textSecondary(
                                            dialogCtx,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            dueDateStr,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary(
                                                dialogCtx,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Progress Weight',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(dialogCtx),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<int>(
                                  initialValue: selectedWeight,
                                  dropdownColor: AppTheme.cardBg(dialogCtx),
                                  style: TextStyle(
                                    color: AppTheme.textPrimary(dialogCtx),
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppTheme.inputBorder(dialogCtx),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: AppTheme.inputBorder(dialogCtx),
                                      ),
                                    ),
                                    fillColor: AppTheme.inputFill(dialogCtx),
                                    filled: true,
                                  ),
                                  items: [10, 20, 25, 30, 50].map((w) {
                                    return DropdownMenuItem<int>(
                                      value: w,
                                      child: Text(
                                        '$w% Weight',
                                        style: TextStyle(
                                          color: AppTheme.textPrimary(
                                            dialogCtx,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setDialogState(() {
                                        selectedWeight = val;
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'Remarks / Additional Notes (Optional)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: remarksController,
                        style: TextStyle(
                          color: AppTheme.textPrimary(dialogCtx),
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g., Priority for morning shift team',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary(dialogCtx),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: AppTheme.inputFill(dialogCtx),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppTheme.inputBorder(dialogCtx),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary(dialogCtx)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final title = titleController.text.trim();
                    final instruction = instructionController.text.trim();
                    if (title.isEmpty || instruction.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please enter sub-task title and instruction.',
                          ),
                          backgroundColor: Color(0xFFDC2626),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }

                    final subTaskId =
                        'ST-${_action.id.replaceAll('AF-', '').replaceAll('ACT-', '')}-${_action.subTasks.length + 1}';
                    final subTask = ActionSubTask(
                      id: subTaskId,
                      parentActionId: _action.id,
                      title: title,
                      instruction: instruction,
                      assignedStaff: selectedStaff.name,
                      assignedStaffId: selectedStaff.personId,
                      assignedStaffEmail: selectedStaff.email,
                      dueDate: dueDateStr,
                      status: 'Open',
                      progressWeight: selectedWeight,
                      remarks: remarksController.text.trim(),
                    );

                    final dateStr = _formatCurrentDate();
                    final logEntry =
                        '$dateStr: Sub-task "${subTask.title}" created and assigned to ${subTask.assignedStaff} (Weight: ${subTask.progressWeight}%).';

                    setState(() {
                      _history.insert(0, logEntry);
                      _action = _action.copyWith(
                        subTasks: [..._action.subTasks, subTask],
                        history: _history,
                      );
                    });

                    // Add in-app notification for assigned staff
                    NotificationService.safeDispatch(
                      () => NotificationService.instance.notifySubtaskAssigned(
                        action: _action,
                        assigneeUserId: selectedStaff.personId,
                        subtaskTitle: subTask.title,
                        assignedByName: userProfile?.name,
                        organizationId: _action.organizationId,
                      ),
                      context: 'ActionDetailsScreen.addSubtask',
                    );
                    MockPeopleStore.instance.addNotification(
                      TeamNotification(
                        id: 'NTF-${MockPeopleStore.instance.notifications.length + 1}',
                        managerId: selectedStaff.personId,
                        teamId: 'TEAM-OPS',
                        title: 'New Sub-task Assigned',
                        message:
                            'You have been assigned sub-task "${subTask.title}" under Action ${_action.id}.',
                      ),
                    );

                    _persistUpdate();
                    Navigator.of(dialogCtx).pop();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Sub-task "${subTask.title}" delegated to ${subTask.assignedStaff}.',
                        ),
                        backgroundColor: const Color(0xFF1565C0),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: const Text('Create Sub-task'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCompleteSubTaskDialog(ActionSubTask subTask) {
    final remarksController = TextEditingController();
    final evidenceController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppTheme.cardBg(dialogCtx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.isDark(dialogCtx)
                      ? const Color(0xFF064E3B).withValues(alpha: 0.3)
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF16A34A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete Sub-task — ${subTask.id}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(dialogCtx),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subTask.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(dialogCtx),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.isDark(dialogCtx)
                          ? const Color(0xFF064E3B).withValues(alpha: 0.25)
                          : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.isDark(dialogCtx)
                            ? const Color(0xFF047857)
                            : const Color(0xFFBBF7D0),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.trending_up_rounded,
                          size: 20,
                          color: Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Completing this sub-task adds +${subTask.progressWeight}% progress to parent Action ${_action.id}.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.isDark(dialogCtx)
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF166534),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Closing Remarks / Work Summary *',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(dialogCtx),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: remarksController,
                    maxLines: 3,
                    style: TextStyle(color: AppTheme.textPrimary(dialogCtx)),
                    decoration: InputDecoration(
                      hintText: 'Describe completed work, checklist verification, or corrective actions taken...',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(dialogCtx),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      filled: true,
                      fillColor: AppTheme.inputFill(dialogCtx),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppTheme.inputBorder(dialogCtx),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppTheme.inputBorder(dialogCtx),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'Evidence Reference / Attachment Name (Optional)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(dialogCtx),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: evidenceController,
                    style: TextStyle(color: AppTheme.textPrimary(dialogCtx)),
                    decoration: InputDecoration(
                      hintText: 'e.g., Scaffolding_ZoneB_Signoff.pdf',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(dialogCtx),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      filled: true,
                      fillColor: AppTheme.inputFill(dialogCtx),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppTheme.inputBorder(dialogCtx),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppTheme.inputBorder(dialogCtx),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppTheme.textSecondary(dialogCtx)),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final remarks = remarksController.text.trim();
                if (remarks.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please enter closing remarks / work summary.',
                      ),
                      backgroundColor: Color(0xFFDC2626),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                final evidence = evidenceController.text.trim();
                final nowStr = _formatCurrentDate();
                final completedByName = widget.isWorker
                    ? (_action.assignedTo.isNotEmpty
                          ? _action.assignedTo
                          : 'R. Kumar')
                    : 'Current User';

                final updatedSubTask = subTask.copyWith(
                  status: 'Completed',
                  completedAt: nowStr,
                  completedBy: completedByName,
                  remarks: remarks,
                  evidence: evidence,
                );

                final newSubTasks = _action.subTasks
                    .map((s) => s.id == subTask.id ? updatedSubTask : s)
                    .toList();

                final newPercent =
                    (_action.percentComplete + subTask.progressWeight).clamp(
                      0,
                      100,
                    );
                final logEntry =
                    '$nowStr: Sub-task "${subTask.title}" completed by $completedByName (+${subTask.progressWeight}% progress).';

                setState(() {
                  _history.insert(0, logEntry);
                  if (evidence.isNotEmpty && !_attachments.contains(evidence)) {
                    _attachments.add(evidence);
                  }
                  _action = _action.copyWith(
                    subTasks: newSubTasks,
                    percentComplete: newPercent,
                    attachments: _attachments,
                    history: _history,
                  );
                });

                // In-app notification for parent action owner
                MockPeopleStore.instance.addNotification(
                  TeamNotification(
                    id: 'NTF-${MockPeopleStore.instance.notifications.length + 1}',
                    managerId: _action.assignedTo,
                    teamId: 'TEAM-OPS',
                    title: 'Sub-task Completed',
                    message:
                        'Sub-task "${subTask.title}" under Action ${_action.id} was completed by $completedByName.',
                  ),
                );

                _persistUpdate();
                Navigator.of(dialogCtx).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Sub-task marked completed (+${subTask.progressWeight}% progress added to ${_action.id}).',
                    ),
                    backgroundColor: const Color(0xFF16A34A),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: const Text('Mark as Completed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // TAB BAR NAVIGATION (OVERVIEW, LIFECYCLE, SUB-TASKS, EVIDENCE, HISTORY, COMMENTS, RELATED)
  // ===========================================================================

  Widget _buildTabBar() {
    final tabs = <(String, IconData, int)>[
      ('Overview', Icons.dashboard_outlined, 0),
      ('Lifecycle', Icons.alt_route_rounded, 0),
      ('Sub-tasks', Icons.playlist_add_check_rounded, _action.subTasks.length),
      (
        'Evidence & Attachments',
        Icons.attach_file_rounded,
        _attachments.length,
      ),
      ('History', Icons.history_rounded, _history.length),
      ('Comments', Icons.chat_bubble_outline_rounded, _comments.length),
      ('Related Actions', Icons.link_rounded, 0),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      padding: const EdgeInsets.all(4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.asMap().entries.map((entry) {
            final idx = entry.key;
            final tab = entry.value;
            final isSelected = _selectedTabIndex == idx;

            return InkWell(
              onTap: () => setState(() => _selectedTabIndex = idx),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1565C0)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.$2,
                      size: 16,
                      color: isSelected
                          ? Colors.white
                          : AppTheme.textSecondary(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tab.$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : AppTheme.textSecondary(context),
                      ),
                    ),
                    if (tab.$3 > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.25)
                              : (AppTheme.isDark(context)
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${tab.$3}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ===========================================================================
  // ACTIVE TAB CONTENT ROUTER
  // ===========================================================================

  Widget _buildActiveTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildOverviewTab();
      case 1:
        return _buildLifecycleTab();
      case 2:
        return _buildSubTasksTab();
      case 3:
        return _buildEvidenceTab();
      case 4:
        return _buildHistoryTab();
      case 5:
        return _buildCommentsTab();
      case 6:
        return _buildRelatedActionsTab();
      default:
        return _buildOverviewTab();
    }
  }

  // ===========================================================================
  // SUB-TASKS TAB & COMPONENTS
  // ===========================================================================

  Widget _buildSubTasksTab() {
    return _cardContainer(
      title: 'Delegated Sub-tasks',
      icon: Icons.playlist_add_check_rounded,
      trailing: ElevatedButton.icon(
        onPressed: _showForwardSubTaskDialog,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text(
          'Delegate Sub-task',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
      child: _action.subTasks.isEmpty
          ? _buildEmptySubTasksState()
          : Column(
              children: _action.subTasks.map((subTask) {
                return _buildSubTaskCard(subTask);
              }).toList(),
            ),
    );
  }

  Widget _buildEmptySubTasksState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.isDark(context)
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_tree_outlined,
              size: 36,
              color: Color(0xFF1565C0),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No sub-tasks delegated yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Delegate specific child tasks to team members while tracking progress on this main action.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _showForwardSubTaskDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.playlist_add_rounded, size: 17),
            label: const Text(
              'Delegate Sub-task',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTaskCard(ActionSubTask subTask) {
    final isCompleted = subTask.isCompleted;
    final statusColor = isCompleted
        ? const Color(0xFF16A34A)
        : (subTask.status == 'In Progress'
              ? const Color(0xFFEA580C)
              : const Color(0xFF1565C0));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.isDark(context)
            ? const Color(0xFF1E293B)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? (AppTheme.isDark(context)
                    ? const Color(0xFF065F46)
                    : const Color(0xFFBBF7D0))
              : AppTheme.cardBorder(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.actionIdBg(context),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.actionIdBorder(context)),
                ),
                child: Text(
                  subTask.id,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.actionIdText(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  subTask.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.isDark(context)
                      ? const Color(0xFF581C87).withValues(alpha: 0.3)
                      : const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.isDark(context)
                        ? const Color(0xFF7E22CE).withValues(alpha: 0.5)
                        : const Color(0xFFE9D5FF),
                  ),
                ),
                child: Text(
                  'Weight: ${subTask.progressWeight}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFA855F7),
                  ),
                ),
              ),
              if (subTask.dueDate.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 14,
                      color: AppTheme.textSecondary(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Due: ${subTask.dueDate}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Sub-task Title
          Text(
            subTask.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
              color: isCompleted
                  ? AppTheme.textSecondary(context)
                  : AppTheme.textPrimary(context),
            ),
          ),
          if (subTask.instruction.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subTask.instruction,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Assignee & Completion badge row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: const Color(0xFF1565C0),
                    child: Text(
                      subTask.assignedStaff.isNotEmpty
                          ? subTask.assignedStaff[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    subTask.assignedStaff,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ],
              ),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.isDark(context)
                        ? const Color(0xFF065F46).withValues(alpha: 0.35)
                        : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.isDark(context)
                          ? const Color(0xFF059669).withValues(alpha: 0.5)
                          : const Color(0xFF86EFAC),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Completed on ${subTask.completedAt}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.isDark(context)
                              ? const Color(0xFF34D399)
                              : const Color(0xFF166534),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _showCompleteSubTaskDialog(subTask),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 15,
                  ),
                  label: const Text('Complete Sub-task'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),

          // Completion remarks or evidence if completed
          if (isCompleted &&
              (subTask.remarks.isNotEmpty || subTask.evidence.isNotEmpty)) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.isDark(context)
                    ? const Color(0xFF064E3B).withValues(alpha: 0.25)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.isDark(context)
                      ? const Color(0xFF047857)
                      : const Color(0xFFBBF7D0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subTask.remarks.isNotEmpty)
                    Text(
                      'Closure Remarks: ${subTask.remarks}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.isDark(context)
                            ? const Color(0xFF34D399)
                            : const Color(0xFF166534),
                      ),
                    ),
                  if (subTask.evidence.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Evidence: ${subTask.evidence}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.isDark(context)
                              ? const Color(0xFF6EE7B7)
                              : const Color(0xFF15803D),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubTasksOverviewCard() {
    return _cardContainer(
      title: 'Delegated Sub-tasks (${_action.subTasks.length})',
      icon: Icons.playlist_add_check_rounded,
      trailing: TextButton.icon(
        onPressed: () {
          setState(() => _selectedTabIndex = 2);
        },
        icon: const Icon(Icons.open_in_new_rounded, size: 14),
        label: const Text('View All Sub-tasks', style: TextStyle(fontSize: 12)),
      ),
      child: Column(
        children: _action.subTasks.map((st) {
          final isDone = st.isCompleted;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.isDark(context)
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDone
                    ? (AppTheme.isDark(context)
                          ? const Color(0xFF065F46)
                          : const Color(0xFFBBF7D0))
                    : AppTheme.cardBorder(context),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    isDone
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: isDone
                        ? const Color(0xFF16A34A)
                        : AppTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        st.title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                          color: isDone
                              ? AppTheme.textSecondary(context)
                              : AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.actionIdBg(context),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppTheme.actionIdBorder(context),
                              ),
                            ),
                            child: Text(
                              st.assignedStaff,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.actionIdText(context),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.isDark(context)
                                  ? const Color(0xFF581C87)
                                        .withValues(alpha: 0.3)
                                  : const Color(0xFFFAF5FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+${st.progressWeight}%',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFA855F7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===========================================================================
  // 1. OVERVIEW TAB
  // ===========================================================================

  Widget _buildWorkCompletedRemarksCard() {
    final updates = _action.allProgressUpdates
        .where((u) => u.hasWorkCompletedRemarks)
        .toList();

    return _cardContainer(
      title: 'Work Completed & Progress Remarks',
      icon: Icons.assignment_turned_in_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1565C0).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${updates.length} Entries',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1565C0),
          ),
        ),
      ),
      child: updates.isEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              alignment: Alignment.center,
              child: Text(
                'No work completed remarks submitted yet.',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < updates.length; i++) ...[
                  if (i > 0) const Divider(height: 24),
                  _buildWorkCompletedItem(updates[i]),
                ],
              ],
            ),
    );
  }

  Widget _buildWorkCompletedItem(ActionProgressUpdate u) {
    final isManager = u.submitterRoleLabel == 'Manager';
    final roleColor =
        isManager ? const Color(0xFF1565C0) : const Color(0xFF059669);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                u.effectiveSubject,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${u.progress}% Complete',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16A34A),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            if (u.messageType.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.isDark(context)
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  u.messageType,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline,
                    size: 14, color: AppTheme.textSecondary(context)),
                const SizedBox(width: 4),
                Text(
                  u.updatedByName.isNotEmpty ? u.updatedByName : 'System User',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                u.submitterRoleLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: roleColor,
                ),
              ),
            ),
            if (u.updateDate.isNotEmpty)
              Text(
                '• ${u.updateDate}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSecondary(context),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          u.effectiveWorkCompleted,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppTheme.textPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkPendingRoadblocksCard() {
    final updates = _action.allProgressUpdates
        .where((u) => u.hasPendingWorkOrRoadblocks)
        .toList();

    return _cardContainer(
      title: 'Work Pending & Roadblocks',
      icon: Icons.warning_amber_rounded,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEA580C).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${updates.length} Reports',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFFEA580C),
          ),
        ),
      ),
      child: updates.isEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              alignment: Alignment.center,
              child: Text(
                'No pending work or roadblocks reported.',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < updates.length; i++) ...[
                  if (i > 0) const Divider(height: 24),
                  _buildPendingRoadblockItem(updates[i]),
                ],
              ],
            ),
    );
  }

  Widget _buildPendingRoadblockItem(ActionProgressUpdate u) {
    final isManager = u.submitterRoleLabel == 'Manager';
    final roleColor =
        isManager ? const Color(0xFF1565C0) : const Color(0xFF059669);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline,
                    size: 14, color: AppTheme.textSecondary(context)),
                const SizedBox(width: 4),
                Text(
                  u.updatedByName.isNotEmpty ? u.updatedByName : 'System User',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                u.submitterRoleLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: roleColor,
                ),
              ),
            ),
            if (u.updateDate.isNotEmpty)
              Text(
                '• ${u.updateDate}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSecondary(context),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (u.pendingWork.trim().isNotEmpty) ...[
          _buildRemarkFieldRow(
            label: 'Work Still Pending / Next Steps',
            value: u.pendingWork.trim(),
            color: const Color(0xFFEA580C),
            icon: Icons.pending_actions_outlined,
          ),
          const SizedBox(height: 8),
        ],
        if (u.requirement.trim().isNotEmpty) ...[
          _buildRemarkFieldRow(
            label: 'Specific Equipment / Material Requirement',
            value: u.requirement.trim(),
            color: const Color(0xFF0284C7),
            icon: Icons.handyman_outlined,
          ),
          const SizedBox(height: 8),
        ],
        if (u.suggestion.trim().isNotEmpty) ...[
          _buildRemarkFieldRow(
            label: 'Suggestion for HSSE Manager',
            value: u.suggestion.trim(),
            color: const Color(0xFF7C3AED),
            icon: Icons.lightbulb_outline_rounded,
          ),
          const SizedBox(height: 8),
        ],
        if (u.remarks.trim().isNotEmpty) ...[
          _buildRemarkFieldRow(
            label: 'General Safety Remarks',
            value: u.remarks.trim(),
            color: const Color(0xFF64748B),
            icon: Icons.shield_outlined,
          ),
        ],
      ],
    );
  }

  Widget _buildRemarkFieldRow({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.isDark(context)
            ? const Color(0xFF1E293B)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  children: [
                    _buildLatestProgressCard(),
                    const SizedBox(height: 16),
                    _buildWorkCompletedRemarksCard(),
                    const SizedBox(height: 16),
                    _buildWorkPendingRoadblocksCard(),
                    const SizedBox(height: 16),
                    _buildActionInfoCard(),
                    const SizedBox(height: 16),
                    if (_action.subTasks.isNotEmpty) ...[
                      _buildSubTasksOverviewCard(),
                      const SizedBox(height: 16),
                    ],
                    _buildRequirementsScopeCard(),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _buildOwnershipCard(),
                    const SizedBox(height: 16),
                    _buildTimelineCard(),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildLatestProgressCard(),
            const SizedBox(height: 16),
            _buildWorkCompletedRemarksCard(),
            const SizedBox(height: 16),
            _buildWorkPendingRoadblocksCard(),
            const SizedBox(height: 16),
            _buildActionInfoCard(),
            const SizedBox(height: 16),
            if (_action.subTasks.isNotEmpty) ...[
              _buildSubTasksOverviewCard(),
              const SizedBox(height: 16),
            ],
            _buildOwnershipCard(),
            const SizedBox(height: 16),
            _buildTimelineCard(),
            const SizedBox(height: 16),
            _buildRequirementsScopeCard(),
          ],
        );
      },
    );
  }

  Widget _buildLatestProgressCard() {
    final latestUpdate = _action.latestProgressUpdate;
    final statusColor = _statusColor(_action.status);

    return _cardContainer(
      title: 'Current Progress & Status',
      icon: Icons.trending_up_rounded,
      trailing: _action.isClosed
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                'Closed',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16A34A),
                ),
              ),
            )
          : (_action.isReadyForReview
                ? ElevatedButton.icon(
                    onPressed: _handleApproveAndCloseAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 16),
                    label: const Text(
                      'Approve & Close',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : (_canShowUpdateAction
                    ? ElevatedButton.icon(
                        onPressed: _handleOpenUpdateScreen,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                        ),
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: const Text(
                          'Update Action',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Completion: ${_action.percentComplete}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            _action.status,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: _action.percentComplete.clamp(0, 100) / 100.0,
                        backgroundColor: AppTheme.progressTrackBg(context),
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    ),
                    if (widget.currentUserId != null &&
                        widget.currentUserId!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_pin_circle_rounded,
                            size: 14,
                            color: Color(0xFF0D9488),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'My Contribution: ${_action.myContribution(widget.currentUserId!)}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D9488),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_action.individualContributions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Individual Contributions Breakdown:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _action.individualContributions.entries.map((
                          e,
                        ) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.containerBg(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.cardBorder(context),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 12,
                                  color: Color(0xFF1565C0),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${e.key}: ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                                Text(
                                  '${e.value}%',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1565C0),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppTheme.dividerColor(context), height: 1),
          const SizedBox(height: 12),
          if (latestUpdate != null) ...[
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (latestUpdate.updateDate.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 14,
                        color: AppTheme.textSecondary(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Latest Update: ${latestUpdate.updateDate}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                if (latestUpdate.updatedByName.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 14,
                        color: AppTheme.textSecondary(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Updated by: ${latestUpdate.updatedByName}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LATEST WORK UPDATE',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latestUpdate.comments.isNotEmpty
                        ? latestUpdate.comments
                        : 'No comments provided in latest update.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary(context),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'No progress updates have been submitted for this action yet.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
          if (_action.isClosed) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 16,
                        color: Color(0xFF16A34A),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'FORMAL CLOSURE VERIFICATION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Closed by: ${_action.closedByName?.isNotEmpty == true ? _action.closedByName! : "Unspecified"}  •  Date: ${_action.closedAt != null ? "${_action.closedAt!.day.toString().padLeft(2, "0")} ${_monthName(_action.closedAt!.month)} ${_action.closedAt!.year}" : "Recorded"}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  if (_action.closureComment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _action.closureComment,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textPrimary(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionInfoCard() {
    return _cardContainer(
      title: 'Action Information',
      icon: Icons.info_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action Required Banner
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.isDark(context)
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: const Color(0xFF1565C0)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ACTION REQUIRED',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3B82F6),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _action.actionRequired.isNotEmpty
                                ? _action.actionRequired
                                : 'No specific action requirement specified.',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary(context),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _detailRow(
            'Description',
            _action.description.isNotEmpty
                ? _action.description
                : 'No detailed narrative provided.',
          ),
          _detailRow(
            'Department',
            _action.department.isNotEmpty ? _action.department : 'General',
          ),
          if (_action.section.isNotEmpty)
            _detailRow('Section', _action.section),
          _detailRow(
            'Source & Category',
            '${_action.source.isNotEmpty ? _action.source : "HSSE Audit"}  •  ${_action.category.isNotEmpty ? _action.category : "General Action"}',
          ),
          if (_action.supportingPerson.isNotEmpty)
            _detailRow('Supporting Person', _action.supportingPerson),
        ],
      ),
    );
  }

  Widget _buildRequirementsScopeCard() {
    final hasScope =
        _action.requirement.isNotEmpty ||
        _action.pendingReason.isNotEmpty ||
        _action.suggestion.isNotEmpty;

    if (!hasScope) return const SizedBox.shrink();

    return _cardContainer(
      title: 'Scope & Review Context',
      icon: Icons.assignment_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_action.requirement.isNotEmpty)
            _detailRow('Specific Requirement', _action.requirement),
          if (_action.pendingReason.isNotEmpty)
            _detailRow('Pending / Hold Reason', _action.pendingReason),
          if (_action.suggestion.isNotEmpty)
            _detailRow('Corrective Suggestion', _action.suggestion),
        ],
      ),
    );
  }

  Widget _buildOwnershipCard() {
    final createdByDetails = _getPersonDetails(
      _action.createdByName.isNotEmpty ? _action.createdByName : _action.assignedBy,
      ref: _action.createdByPerson ?? _action.assignedByPerson,
      isAssigner: true,
    );
    final assignedByDetails = _getPersonDetails(
      _action.assignedBy,
      ref: _action.assignedByPerson,
      isAssigner: true,
    );
    final assignedToDetails = _getPersonDetails(
      _action.assignedTo,
      ref: _action.primaryAssignee,
      isAssigner: false,
    );

    return _cardContainer(
      title: 'Ownership & Participants',
      icon: Icons.people_outline_rounded,
      trailing: ElevatedButton.icon(
        onPressed: _showForwardActionDialog,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
        label: const Text(
          'Add Contributor / Forward',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 0. Created By Section
          if (_action.createdByName.isNotEmpty)
            _buildPersonCardSection(
              sectionTitle: 'Created By',
              name: createdByDetails.$1,
              role: createdByDetails.$2,
              department: createdByDetails.$3,
              accentColor: const Color(0xFF6366F1),
              personRef: _action.createdByPerson,
            ),

          // 1. Assigned By Section
          _buildPersonCardSection(
            sectionTitle: 'Assigned By',
            name: assignedByDetails.$1,
            role: assignedByDetails.$2,
            department: assignedByDetails.$3,
            accentColor: const Color(0xFF0D9488),
            personRef: _action.assignedByPerson,
          ),

          // 2. Action Owner (Formally Responsible)
          if (_action.isExternalRecipient) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.isDark(context)
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'EXTERNAL RECIPIENT',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEA580C),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA580C)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFFEA580C)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'EXTERNAL',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEA580C),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEA580C),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          (_action.externalRecipientName ?? _action.assignedTo)
                                  .isNotEmpty
                              ? (_action.externalRecipientName ??
                                        _action.assignedTo)[0]
                                    .toUpperCase()
                              : 'E',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _action.externalRecipientName ??
                                  _action.assignedTo,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Recipient Type: External',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                            if ((_action.externalRecipientEmail ??
                                    _action.externalRecipient?.email ??
                                    '')
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Email: ${_action.externalRecipientEmail ?? _action.externalRecipient?.email}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Email Reminder: ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _action.emailReminderEnabled
                                        ? const Color(0xFF16A34A)
                                              .withValues(alpha: 0.12)
                                        : AppTheme.containerBg(context),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: _action.emailReminderEnabled
                                          ? const Color(0xFF16A34A)
                                                .withValues(alpha: 0.3)
                                          : AppTheme.cardBorder(context),
                                    ),
                                  ),
                                  child: Text(
                                    _action.emailReminderEnabled ? 'ON' : 'OFF',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _action.emailReminderEnabled
                                          ? const Color(0xFF16A34A)
                                          : AppTheme.textMuted(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            _buildPersonCardSection(
              sectionTitle: 'Action Owner (Primary Responsible)',
              name: assignedToDetails.$1,
              role: assignedToDetails.$2,
              department: assignedToDetails.$3,
              accentColor: const Color(0xFF1565C0),
              personRef: _action.primaryAssignee,
              isOwnerBadge: true,
            ),
          ],

          // 3. Required Assignees Section
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'REQUIRED ASSIGNEES (${_action.assignees.where((a) => a.isRequired).length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary(context),
                    letterSpacing: 0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_action.allRequiredAssigneesCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'All Work Completed',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Pending Work Completion',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_action.assignees.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_rounded,
                    size: 16,
                    color: Color(0xFF1565C0),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_action.assignedTo} (Owner & Primary Assignee)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ),
                  Text(
                    _action.percentComplete >= 100 ? 'Completed' : 'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _action.percentComplete >= 100
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFEA580C),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._action.assignees.map((assignee) {
              final isCurrentUser = widget.currentUserId == assignee.profileId;
              final canToggle =
                  widget.managerContext?.isManager == true || isCurrentUser;

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.containerBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Row(
                  children: [
                    Icon(
                      assignee.isOwner
                          ? Icons.verified_user_rounded
                          : Icons.person_rounded,
                      size: 16,
                      color: assignee.isOwner
                          ? const Color(0xFF1565C0)
                          : const Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                assignee.profileName.isNotEmpty
                                    ? assignee.profileName
                                    : 'Assignee',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (assignee.isOwner
                                              ? const Color(0xFF1565C0)
                                              : const Color(0xFF6366F1))
                                          .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  assignee.isOwner ? 'Owner' : 'Required',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: assignee.isOwner
                                        ? const Color(0xFF1565C0)
                                        : const Color(0xFF6366F1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (assignee.workCompleted &&
                              assignee.completedAt != null)
                            Text(
                              'Completed work on ${ActionRecord.formatDateForUi(assignee.completedAt)}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: canToggle
                          ? () async {
                              final nextState = !assignee.workCompleted;
                              await ActionService.instance
                                  .markAssigneeCompleted(
                                    actionId: _action.id,
                                    profileId: assignee.profileId,
                                    completed: nextState,
                                  );
                              final reloaded = await ActionService.instance
                                  .fetchActionById(_action.id);
                              if (reloaded != null && mounted) {
                                setState(() {
                                  _action = reloaded;
                                });
                                widget.onUpdateAction?.call();
                              }
                            }
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (assignee.workCompleted
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFEA580C))
                                  .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color:
                                (assignee.workCompleted
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFEA580C))
                                    .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              assignee.workCompleted
                                  ? Icons.check_circle_rounded
                                  : Icons.pending_rounded,
                              size: 13,
                              color: assignee.workCompleted
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFEA580C),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              assignee.workCompleted ? 'Completed' : 'Pending',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: assignee.workCompleted
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFEA580C),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

          // 4. Supporting Contributors Section
          const SizedBox(height: 12),
          Text(
            'SUPPORTING CONTRIBUTORS (${_action.contributors.length})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          if (_action.contributors.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Text(
                'No additional contributors have been added to this action.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            )
          else
            ..._action.contributors.map((contrib) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.containerBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.people_alt_rounded,
                      size: 16,
                      color: Color(0xFF0D9488),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                contrib.profileName.isNotEmpty
                                    ? contrib.profileName
                                    : 'Contributor',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D9488)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Contributor',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0D9488),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (contrib.notes.isNotEmpty)
                            Text(
                              contrib.notes,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          if (contrib.addedByName.isNotEmpty)
                            Text(
                              'Added by ${contrib.addedByName}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary(context)
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

          // 5. Delegated Sub-tasks summary
          if (_action.subTasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: _detailRow(
                'Delegated Sub-tasks',
                '${_action.subTasks.where((s) => s.isCompleted).length} of ${_action.subTasks.length} Completed',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPersonCardSection({
    required String sectionTitle,
    required String name,
    required String role,
    required String department,
    required Color accentColor,
    ActionPersonReference? personRef,
    bool isOwnerBadge = false,
  }) {
    final roleAndDept = department.isNotEmpty ? '$role • $department' : role;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.isDark(context)
            ? const Color(0xFF1E293B)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  sectionTitle.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isOwnerBadge) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'OWNER',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (personRef != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.actionIdBg(context),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppTheme.actionIdBorder(context),
                              ),
                            ),
                            child: Text(
                              personRef.typeLabel,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.actionIdText(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roleAndDept,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    if (personRef != null &&
                        (personRef.email.isNotEmpty ||
                            personRef.phone.isNotEmpty)) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (personRef.email.isNotEmpty) personRef.email,
                          if (personRef.phone.isNotEmpty) personRef.phone,
                        ].join('  •  '),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.textMuted(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard() {
    final completionUpdate = _action.progressUpdates
        .where((u) => u.progress == 100)
        .firstOrNull;
    final hasManagerReviewed =
        _action.isClosed ||
        _action.status == 'Ready for Review' ||
        _action.status == 'Approved & Closed';

    return _cardContainer(
      title: 'Dates & Milestones',
      icon: Icons.calendar_today_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timelineDateRow(
            'Date Raised',
            _action.dateRaised.isNotEmpty ? _action.dateRaised : 'Not recorded',
            Icons.add_circle_outline_rounded,
            const Color(0xFF0284C7),
          ),
          _timelineDateRow(
            'Start Date',
            _action.startDate.isNotEmpty ? _action.startDate : 'Not recorded',
            Icons.play_circle_outline_rounded,
            const Color(0xFF0D9488),
          ),
          _timelineDateRow(
            'Target Closure Date',
            _action.targetDate.isNotEmpty ? _action.targetDate : 'Not set',
            Icons.flag_outlined,
            const Color(0xFFEA580C),
          ),
          _timelineDateRow(
            'Next Follow-up',
            _action.followUp.isNotEmpty && _action.followUp != '-'
                ? _action.followUp
                : 'Not scheduled',
            Icons.schedule_rounded,
            const Color(0xFF7C3AED),
          ),
          _timelineDateRow(
            '100% Completion Date',
            completionUpdate != null && completionUpdate.updateDate.isNotEmpty
                ? completionUpdate.updateDate
                : 'Not yet',
            Icons.done_all_rounded,
            const Color(0xFF2563EB),
          ),
          _timelineDateRow(
            'Manager Review Date',
            hasManagerReviewed
                ? (_action.closeDate.isNotEmpty
                      ? _action.closeDate
                      : 'Pending Review')
                : 'Not yet',
            Icons.rate_review_outlined,
            const Color(0xFF9333EA),
          ),
          _timelineDateRow(
            'Closed Date',
            _action.closeDate.isNotEmpty ? _action.closeDate : 'Not yet',
            Icons.check_circle_outline_rounded,
            const Color(0xFF16A34A),
          ),
        ],
      ),
    );
  }

  Widget _timelineDateRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textSecondary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. EVIDENCE & ATTACHMENTS TAB
  // ===========================================================================

  Future<void> _downloadEvidenceFile(String fileName) async {
    final cleanFile = ActionService.sanitizeAttachmentFileName(fileName);
    final isManager =
        !widget.isWorker || (widget.managerContext?.isManager == true);
    final userProfile = AuthService.instance.currentProfileData?.userProfile;
    final userId = widget.currentUserId ?? userProfile?.id;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading "$cleanFile"...'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final res = await ActionService.instance.downloadActionAttachment(
      action: _action,
      fileName: cleanFile,
      userId: userId,
      isManager: isManager,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded "$cleanFile" successfully.'),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error ?? 'Failed to download "$cleanFile".'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _previewEvidenceFile(String fileName) async {
    final cleanFile = ActionService.sanitizeAttachmentFileName(fileName);
    final userProfile = AuthService.instance.currentProfileData?.userProfile;
    final userId = widget.currentUserId ?? userProfile?.id;

    await ActionAttachmentPreviewDialog.show(
      context,
      action: _action,
      fileName: cleanFile,
      currentUserId: userId,
      isWorker: widget.isWorker,
    );
  }

  Widget _buildEvidenceItemCard(ActionEvidenceItem ev,
      {bool showDelete = false}) {
    final fileName = ev.fileName;
    final isPdf = fileName.toLowerCase().endsWith('.pdf');
    final isImg = fileName.toLowerCase().endsWith('.jpg') ||
        fileName.toLowerCase().endsWith('.jpeg') ||
        fileName.toLowerCase().endsWith('.png') ||
        fileName.toLowerCase().endsWith('.webp');

    final color = isPdf
        ? const Color(0xFFDC2626)
        : isImg
            ? const Color(0xFF0284C7)
            : const Color(0xFF1565C0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.isDark(context)
            ? const Color(0xFF1E293B)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPdf
                  ? Icons.picture_as_pdf_outlined
                  : isImg
                      ? Icons.image_outlined
                      : Icons.description_outlined,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ev.uploadedBy.isNotEmpty
                      ? 'Uploaded by ${ev.uploadedBy} • ${ev.fileType}'
                      : 'Verified HSSE Evidence File • ${ev.fileType}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('preview_attachment_${fileName}_btn'),
            icon: const Icon(Icons.visibility_outlined, size: 20),
            color: AppTheme.primaryAccent(context),
            tooltip: 'Preview Document',
            onPressed: () => _previewEvidenceFile(fileName),
          ),
          IconButton(
            key: Key('download_attachment_${fileName}_btn'),
            icon: const Icon(Icons.download_rounded, size: 20),
            color: const Color(0xFF1565C0),
            tooltip: 'Download File',
            onPressed: () => _downloadEvidenceFile(fileName),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceColumnHeader({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          '$title ($count)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: AppTheme.textPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyEvidenceColumn(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.inputFill(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: AppTheme.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildEvidenceTab() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 768;

    final originalDocs = _action.originalDocuments;
    final staffEvidence = _action.staffUpdateEvidence;
    final managerEvidence =
        List<ActionEvidenceItem>.from(_action.managerUpdateEvidence);
    final actionEvidence =
        List<ActionEvidenceItem>.from(_action.actionEvidence);

    // Reconcile any unclassified files currently in _attachments into Action Evidence
    final classifiedNames =
        _action.allClassifiedEvidence.map((e) => e.fileName).toSet();
    for (final att in _attachments) {
      if (!classifiedNames.contains(att)) {
        classifiedNames.add(att);
        actionEvidence.add(
          ActionEvidenceItem(
            fileName: att,
            fileType: ActionEvidenceItem.resolveFileType(att),
            classification: EvidenceClassification.actionEvidence,
            uploadedBy: widget.isWorker ? 'Staff' : 'Manager',
            uploaderRole: widget.isWorker ? 'staff' : 'manager',
            uploadedAt: DateTime.now(),
            actionId: _action.id,
          ),
        );
      }
    }

    final hasAnyEvidence = _attachments.isNotEmpty ||
        originalDocs.isNotEmpty ||
        staffEvidence.isNotEmpty ||
        managerEvidence.isNotEmpty ||
        actionEvidence.isNotEmpty;

    return _cardContainer(
      title: 'Evidence & Attachments',
      icon: Icons.attach_file_rounded,
      trailing: ElevatedButton.icon(
        onPressed: _handleUploadEvidence,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        icon: const Icon(Icons.upload_file_rounded, size: 16),
        label: const Text(
          'Upload Evidence',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
      child: !hasAnyEvidence
          ? _buildEmptyEvidenceState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. ORIGINAL ACTION DOCUMENTS
                if (originalDocs.isNotEmpty) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF64748B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ORIGINAL ACTION DOCUMENTS (${originalDocs.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...originalDocs.map(
                    (ev) => _buildEvidenceItemCard(ev),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                ],

                // 2. ACTION EVIDENCE (TOP-LEVEL UPLOADS)
                if (actionEvidence.isNotEmpty) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.folder_shared_outlined,
                          size: 16,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ACTION EVIDENCE (${actionEvidence.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...actionEvidence.map(
                    (ev) => _buildEvidenceItemCard(ev,
                        showDelete: _canUploadEvidence),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                ],

                // 3. TWO-COLUMN EVIDENCE AREA: STAFF & MANAGER EVIDENCE
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Column 1: STAFF UPDATE EVIDENCE
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildEvidenceColumnHeader(
                              title: 'STAFF UPDATE EVIDENCE',
                              count: staffEvidence.length,
                              color: const Color(0xFF059669),
                              icon: Icons.engineering_outlined,
                            ),
                            const SizedBox(height: 10),
                            if (staffEvidence.isEmpty)
                              _buildEmptyEvidenceColumn(
                                'No staff update evidence submitted yet.',
                              )
                            else
                              ...staffEvidence.map(
                                (ev) => _buildEvidenceItemCard(ev),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Column 2: MANAGER UPDATE EVIDENCE
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildEvidenceColumnHeader(
                              title: 'MANAGER UPDATE EVIDENCE',
                              count: managerEvidence.length,
                              color: const Color(0xFF1565C0),
                              icon: Icons.verified_user_outlined,
                            ),
                            const SizedBox(height: 10),
                            if (managerEvidence.isEmpty)
                              _buildEmptyEvidenceColumn(
                                'No manager update evidence submitted yet.',
                              )
                            else
                              ...managerEvidence.map(
                                (ev) => _buildEvidenceItemCard(ev),
                              ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildEvidenceColumnHeader(
                        title: 'STAFF UPDATE EVIDENCE',
                        count: staffEvidence.length,
                        color: const Color(0xFF059669),
                        icon: Icons.engineering_outlined,
                      ),
                      const SizedBox(height: 10),
                      if (staffEvidence.isEmpty)
                        _buildEmptyEvidenceColumn(
                          'No staff update evidence submitted yet.',
                        )
                      else
                        ...staffEvidence.map(
                          (ev) => _buildEvidenceItemCard(ev),
                        ),
                      const SizedBox(height: 16),
                      _buildEvidenceColumnHeader(
                        title: 'MANAGER UPDATE EVIDENCE',
                        count: managerEvidence.length,
                        color: const Color(0xFF1565C0),
                        icon: Icons.verified_user_outlined,
                      ),
                      const SizedBox(height: 10),
                      if (managerEvidence.isEmpty)
                        _buildEmptyEvidenceColumn(
                          'No manager update evidence submitted yet.',
                        )
                      else
                        ...managerEvidence.map(
                          (ev) => _buildEvidenceItemCard(ev),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }

  Widget _buildEmptyEvidenceState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.isDark(context)
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_upload_outlined,
              size: 36,
              color: Color(0xFF1565C0),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No attachments uploaded yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Upload inspection photos, signed checklists, audit evidence, or safety documentation.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _handleUploadEvidence,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.upload_file_rounded, size: 17),
            label: const Text(
              'Upload Evidence',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. ACTION LIFECYCLE AUDIT TAB
  // ===========================================================================

  Widget _buildLifecycleTab() {
    final events = <_LifecycleEventItem>[];

    // 1. Action Creation
    final createdDate = DateTime.tryParse(
      ActionRecord.formatDateForDb(_action.dateRaised),
    );
    events.add(
      _LifecycleEventItem(
        title: 'Action Created & Logged',
        timestamp: _action.dateRaised.isNotEmpty
            ? _action.dateRaised
            : '01 Jan 2026',
        actor: _action.createdByName.isNotEmpty
            ? _action.createdByName
            : (_action.assignedBy.isNotEmpty
                ? _action.assignedBy
                : 'Unspecified'),
        status: 'Open',
        icon: Icons.add_circle_outline_rounded,
        iconColor: const Color(0xFF1565C0),
        details:
            'Action ${_action.displayId} was registered with Priority "${_action.priority}" under Department "${_action.department}" at Site "${_action.site}".',
        tag: 'Creation',
        sortDate: createdDate,
      ),
    );

    // 2. Initial Assignment
    if (_action.assignedTo.isNotEmpty && _action.assignedTo != 'Select staff') {
      events.add(
        _LifecycleEventItem(
          title: 'Initial Assignment & Target Set',
          timestamp: _action.dateRaised.isNotEmpty
              ? _action.dateRaised
              : '01 Jan 2026',
          actor: _action.assignedBy.isNotEmpty
              ? _action.assignedBy
              : (_action.assignedByPerson?.name.isNotEmpty == true
                  ? _action.assignedByPerson!.name
                  : 'Unspecified'),
          status: 'Assigned',
          icon: Icons.person_add_alt_1_rounded,
          iconColor: const Color(0xFF6366F1),
          details:
              'Action assigned to ${_action.assignedTo}. Due date scheduled for ${_action.targetDate.isNotEmpty ? _action.targetDate : "Not specified"}.',
          tag: 'Assignment',
          sortDate: createdDate?.add(const Duration(minutes: 1)),
        ),
      );
    }

    // 2.5 Start Date Scheduled / Commenced
    if (_action.startDate.isNotEmpty) {
      final startDate = DateTime.tryParse(
        ActionRecord.formatDateForDb(_action.startDate),
      );
      events.add(
        _LifecycleEventItem(
          title: 'Work Scheduled / Started',
          timestamp: _action.startDate,
          actor: _action.assignedTo.isNotEmpty
              ? _action.assignedTo
              : 'Assignee',
          status: 'In Progress',
          icon: Icons.play_circle_outline_rounded,
          iconColor: const Color(0xFF0284C7),
          details:
              'Action work commencement scheduled for ${_action.startDate}.',
          tag: 'Schedule',
          sortDate: startDate ?? createdDate?.add(const Duration(minutes: 2)),
        ),
      );
    }

    // 2.6 Next Follow-Up Date Scheduled
    if (_action.nextFollowUpDate.isNotEmpty &&
        !_action.followUps.any(
          (f) => f.followUpDate == _action.nextFollowUpDate,
        )) {
      final followUpParsed = DateTime.tryParse(
        ActionRecord.formatDateForDb(_action.nextFollowUpDate),
      );
      events.add(
        _LifecycleEventItem(
          title: 'Follow-Up Date Scheduled',
          timestamp: _action.nextFollowUpDate,
          actor: _action.assignedBy.isNotEmpty
              ? _action.assignedBy
              : (_action.assignedByPerson?.name.isNotEmpty == true
                  ? _action.assignedByPerson!.name
                  : 'Unspecified'),
          status: 'Follow-up Scheduled',
          icon: Icons.calendar_month_rounded,
          iconColor: const Color(0xFF7C3AED),
          details:
              'Next follow-up review scheduled for ${_action.nextFollowUpDate}.',
          tag: 'Follow-Up',
          sortDate:
              followUpParsed ?? createdDate?.add(const Duration(minutes: 3)),
        ),
      );
    }

    // 3. Follow-Up Checkpoints
    for (final f in _action.followUps) {
      final fDate = DateTime.tryParse(
        ActionRecord.formatDateForDb(f.followUpDate),
      );
      events.add(
        _LifecycleEventItem(
          title: 'Follow-Up Checkpoint (${f.status})',
          timestamp: f.followUpDate,
          submissionTimestamp: f.createdAt != null
              ? '${f.createdAt!.day.toString().padLeft(2, '0')} ${_monthName(f.createdAt!.month)} ${f.createdAt!.year} at ${f.createdAt!.hour.toString().padLeft(2, '0')}:${f.createdAt!.minute.toString().padLeft(2, '0')}'
              : null,
          actor: f.createdByName.isNotEmpty ? f.createdByName : 'Unknown',
          status: f.status,
          icon: Icons.calendar_month_rounded,
          iconColor: const Color(0xFF7C3AED),
          details: f.notes.isNotEmpty
              ? f.notes
              : 'Follow-up progress review scheduled for ${f.followUpDate}.',
          tag: 'Follow-Up',
          sortDate: f.createdAt ?? fDate,
        ),
      );
    }

    // 4. Contributors Added (Forward / Add Contributor)
    for (final c in _action.contributors) {
      final cDateStr = c.createdAt != null
          ? '${c.createdAt!.day.toString().padLeft(2, '0')} ${_monthName(c.createdAt!.month)} ${c.createdAt!.year}'
          : 'Recent';
      final cSubmissionStr = c.createdAt != null
          ? '${c.createdAt!.day.toString().padLeft(2, '0')} ${_monthName(c.createdAt!.month)} ${c.createdAt!.year} at ${c.createdAt!.hour.toString().padLeft(2, '0')}:${c.createdAt!.minute.toString().padLeft(2, '0')}'
          : null;
      events.add(
        _LifecycleEventItem(
          title: 'Contributor Added: ${c.profileName}',
          timestamp: cDateStr,
          submissionTimestamp: cSubmissionStr,
          actor: c.addedByName.isNotEmpty ? c.addedByName : 'User',
          status: 'In Progress',
          icon: Icons.person_add_alt_1_rounded,
          iconColor: const Color(0xFF0D9488),
          details: c.notes.isNotEmpty
              ? '${c.notes} (Owner remains: ${_action.assignedTo})'
              : 'Added as supporting collaborator without ownership transfer. (Owner remains: ${_action.assignedTo})',
          tag: 'Contributor',
          sortDate: c.createdAt,
        ),
      );
    }

    // 5. Progress Updates (sorted chronologically)
    final updates = List<ActionProgressUpdate>.from(_action.progressUpdates);
    for (final up in updates) {
      final hasReached100 = up.progress >= 100;
      final submissionStr = up.createdAt != null
          ? '${up.createdAt!.day.toString().padLeft(2, '0')} ${_monthName(up.createdAt!.month)} ${up.createdAt!.year} at ${up.createdAt!.hour.toString().padLeft(2, '0')}:${up.createdAt!.minute.toString().padLeft(2, '0')}'
          : null;

      final contribDetails = up.contributionValue > 0
          ? ' [Contribution: +${up.contributionValue}% by ${up.updatedByName.isNotEmpty ? up.updatedByName : _action.assignedTo} (${up.roleInAction})]'
          : '';

      final upDate =
          up.createdAt ??
          DateTime.tryParse(ActionRecord.formatDateForDb(up.updateDate));

      events.add(
        _LifecycleEventItem(
          title: hasReached100
              ? '100% Work Completed'
              : 'Progress Update (${up.progress}%)',
          timestamp: up.updateDate,
          submissionTimestamp: submissionStr,
          actor: up.updatedByName.isNotEmpty
              ? up.updatedByName
              : _action.assignedTo,
          status: up.status,
          progress: up.progress,
          icon: hasReached100
              ? Icons.task_alt_rounded
              : Icons.trending_up_rounded,
          iconColor: hasReached100
              ? const Color(0xFF16A34A)
              : const Color(0xFF0284C7),
          details:
              (up.comments.isNotEmpty
                  ? up.comments
                  : 'Work progress reported at ${up.progress}%.') +
              contribDetails,
          attachmentsCount: up.attachments.length,
          tag: hasReached100 ? 'Milestone' : 'Progress',
          sortDate: upDate,
        ),
      );
    }

    // 6. Milestone: Ready for Review (if 100% completed and pending manager sign-off)
    if (_action.isReadyForReview && !_action.isClosed) {
      final reviewDate = _action.progressUpdates.isNotEmpty
          ? (_action.progressUpdates.last.createdAt ??
                DateTime.tryParse(
                  ActionRecord.formatDateForDb(
                    _action.progressUpdates.last.updateDate,
                  ),
                ))
          : null;

      events.add(
        _LifecycleEventItem(
          title: 'Submitted for Manager Review',
          timestamp: _action.progressUpdates.isNotEmpty
              ? _action.progressUpdates.last.updateDate
              : _action.targetDate,
          actor: _action.assignedTo,
          status: 'Ready for Review',
          icon: Icons.rate_review_rounded,
          iconColor: const Color(0xFFD97706),
          details: 'Field remediation work completed. Safety manager review and closure audit pending.',
          tag: 'Verification',
          sortDate: reviewDate?.add(const Duration(minutes: 1)),
        ),
      );
    }

    // 7. Manager Review / Request More Information (if manager message is present)
    if (_action.managerMessage.isNotEmpty) {
      events.add(
        _LifecycleEventItem(
          title: 'Manager Review Feedback',
          timestamp: _action.progressUpdates.isNotEmpty
              ? _action.progressUpdates.last.updateDate
              : 'Recent',
          actor: _action.closedByName ?? 'Safety Manager',
          status: _action.isClosed ? 'Verified' : 'Info Requested',
          icon: Icons.feedback_outlined,
          iconColor: const Color(0xFFF59E0B),
          details: _action.managerMessage,
          tag: 'Manager Note',
        ),
      );
    }

    // 8. Action Closure / Audit Verification (if closed)
    if (_action.isClosed || _action.closedAt != null) {
      final closedDateStr = _action.closedAt != null
          ? '${_action.closedAt!.day.toString().padLeft(2, '0')} ${_monthName(_action.closedAt!.month)} ${_action.closedAt!.year}'
          : (_action.closeDate.isNotEmpty ? _action.closeDate : 'Closed');

      final submissionStr = _action.closedAt != null
          ? '${_action.closedAt!.day.toString().padLeft(2, '0')} ${_monthName(_action.closedAt!.month)} ${_action.closedAt!.year} at ${_action.closedAt!.hour.toString().padLeft(2, '0')}:${_action.closedAt!.minute.toString().padLeft(2, '0')}'
          : null;

      events.add(
        _LifecycleEventItem(
          title: 'Action Closed & Retained for Compliance',
          timestamp: closedDateStr,
          submissionTimestamp: submissionStr,
          actor:
              _action.closedByName != null && _action.closedByName!.isNotEmpty
              ? _action.closedByName!
              : 'Safety Manager',
          status: 'Closed',
          icon: Icons.verified_rounded,
          iconColor: const Color(0xFF16A34A),
          details: _action.closureComment.isNotEmpty ? _action.closureComment : 'Safety action verified and formally signed off. Retained permanently for compliance and audit reporting.',
          tag: 'Closed & Retained',
          sortDate:
              _action.closedAt ??
              DateTime.tryParse(
                ActionRecord.formatDateForDb(_action.closeDate),
              ),
        ),
      );
    }

    // Chronological sort
    events.sort((a, b) {
      final da =
          a.sortDate ??
          DateTime.tryParse(ActionRecord.formatDateForDb(a.timestamp)) ??
          DateTime(2020);
      final db =
          b.sortDate ??
          DateTime.tryParse(ActionRecord.formatDateForDb(b.timestamp)) ??
          DateTime(2020);
      return da.compareTo(db);
    });

    return _cardContainer(
      title: 'Action Lifecycle & Audit Trail (${events.length} Events)',
      icon: Icons.alt_route_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.containerBg(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Color(0xFF1565C0),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Complete chronological audit log from action initiation to current status. Preserved permanently.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...events.asMap().entries.map((entry) {
            final idx = entry.key;
            final ev = entry.value;
            final isLast = idx == events.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline connector & icon
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ev.iconColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ev.iconColor.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(ev.icon, size: 16, color: ev.iconColor),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: AppTheme.cardBorder(context),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Event Card Content
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.containerBg(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.cardBorder(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  ev.title,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: ev.iconColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  ev.tag,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: ev.iconColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_outline_rounded,
                                    size: 14,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    ev.actor,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary(context),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.event_outlined,
                                    size: 14,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    ev.timestamp,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                              if (ev.submissionTimestamp != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time_rounded,
                                      size: 14,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Submitted: ${ev.submissionTimestamp}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.textMuted(context),
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              if (ev.attachmentsCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1565C0)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.attach_file_rounded,
                                        size: 12,
                                        color: Color(0xFF1565C0),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${ev.attachmentsCount} Attachment${ev.attachmentsCount == 1 ? "" : "s"}',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1565C0),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ev.details,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textPrimary(context),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. ACTION HISTORY TAB
  // ===========================================================================

  Widget _buildHistoryTab() {
    return Column(
      children: [
        if (_action.progressUpdates.isNotEmpty) ...[
          _cardContainer(
            title: 'Progress Updates History',
            icon: Icons.timeline_rounded,
            trailing: ElevatedButton.icon(
              onPressed: _handleOpenUpdateScreen,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
              ),
              icon: const Icon(Icons.edit_note_rounded, size: 16),
              label: const Text(
                'Update Action',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            child: Column(
              children: _action.progressUpdates.map((u) {
                final statusCol = _statusColor(u.status);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.containerBg(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${u.progress}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusCol.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              u.status,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: statusCol,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            u.updateDate,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                      if (u.updatedByName.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Updated by: ${u.updatedByName}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        u.comments,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textPrimary(context),
                          height: 1.35,
                        ),
                      ),
                      if (u.attachments.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: u.attachments.map((att) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.cardBg(context),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppTheme.cardBorder(context),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.attach_file_rounded,
                                    size: 13,
                                    color: Color(0xFF1565C0),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    att,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _cardContainer(
          title: 'Action Audit Log & Lifecycle History',
          icon: Icons.history_rounded,
          child: _history.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No history entries recorded yet.',
                      style: TextStyle(color: AppTheme.textSecondary(context)),
                    ),
                  ),
                )
              : Column(
                  children: _history.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final text = entry.value;
                    final isLast = idx == _history.length - 1;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: idx == 0
                                    ? const Color(0xFF1565C0)
                                    : (AppTheme.isDark(context)
                                          ? const Color(0xFF1E293B)
                                          : const Color(0xFFF1F5F9)),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: idx == 0
                                      ? const Color(0xFF1565C0)
                                      : AppTheme.cardBorder(context),
                                  width: 1.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                idx == 0
                                    ? Icons.check_rounded
                                    : Icons.circle_rounded,
                                size: idx == 0 ? 16 : 8,
                                color: idx == 0
                                    ? Colors.white
                                    : AppTheme.textSecondary(context),
                              ),
                            ),
                            if (!isLast)
                              Container(
                                width: 2,
                                height: 36,
                                color: AppTheme.dividerColor(context),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.isDark(context)
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppTheme.cardBorder(context),
                              ),
                            ),
                            child: Text(
                              text,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary(context),
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 4. COMMENTS TAB
  // ===========================================================================

  Widget _buildCommentsTab() {
    return _cardContainer(
      title: 'Action Communication & Notes',
      icon: Icons.chat_bubble_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Comment Composer Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.isDark(context)
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  style: TextStyle(color: AppTheme.textPrimary(context)),
                  decoration: InputDecoration(
                    hintText: 'Add a safety note, review comment, or progress remark...',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary(context),
                    ),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _handleAddComment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 15),
                  label: const Text(
                    'Post Note',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Comments List
          if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No comments yet. Post a safety note above.',
                  style: TextStyle(color: AppTheme.textSecondary(context)),
                ),
              ),
            )
          else
            ..._comments.map((comment) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: comment.isWorker
                                ? const Color(0xFF0284C7)
                                : const Color(0xFF1565C0),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            comment.author.isNotEmpty
                                ? comment.author[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comment.author,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              Text(
                                comment.role,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: AppTheme.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.isDark(context)
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            comment.type,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (comment.subject != null &&
                        comment.subject!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        comment.subject!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      comment.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary(context),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      comment.time,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textMuted(context),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ===========================================================================
  // 5. RELATED ACTIONS TAB
  // ===========================================================================

  Widget _buildRelatedActionsTab() {
    final related = _relatedActions;

    return _cardContainer(
      title: 'Related Actions in ${_action.department.isNotEmpty ? _action.department : "Department"} / ${_action.site.isNotEmpty ? _action.site : "Site"}',
      icon: Icons.link_rounded,
      child: related.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No related actions found in this section.',
                  style: TextStyle(color: AppTheme.textSecondary(context)),
                ),
              ),
            )
          : Column(
              children: related.map((relAction) {
                return InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ActionDetailsScreen(
                          action: relAction,
                          onUpdateAction: widget.onUpdateAction,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.isDark(context)
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.cardBorder(context)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.actionIdBg(context),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: AppTheme.actionIdBorder(context),
                            ),
                          ),
                          child: Text(
                            relAction.id,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.actionIdText(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                relAction.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              Text(
                                'Assigned to ${relAction.assignedTo} • Due ${relAction.targetDate}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _badge(
                          relAction.status,
                          _statusColor(relAction.status),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppTheme.textSecondary(context),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  // ===========================================================================
  // SHARED UI HELPER WIDGETS
  // ===========================================================================

  Widget _cardContainer({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: AppTheme.isDark(context)
            ? []
            : const [
                BoxShadow(
                  color: Color(0x060F172A),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trailing == null)
            Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF1565C0)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
              ],
            )
          else
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: const Color(0xFF1565C0)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                  ],
                ),
                trailing,
              ],
            ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              color: AppTheme.textPrimary(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'closed':
        return const Color(0xFF059669);
      case 'overdue':
        return const Color(0xFFDC2626);
      case 'pending review':
        return const Color(0xFF7C3AED);
      case 'in progress':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF1565C0);
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
        return const Color(0xFFDC2626);
      case 'high':
        return const Color(0xFFEA580C);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF1565C0);
    }
  }

  IconData _priorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
        return Icons.error_outline_rounded;
      case 'high':
        return Icons.priority_high_rounded;
      case 'low':
        return Icons.arrow_downward_rounded;
      default:
        return Icons.fiber_manual_record_rounded;
    }
  }
}

class _CommentItem {
  _CommentItem({
    required this.author,
    required this.role,
    required this.type,
    required this.message,
    required this.time,
    required this.isWorker,
    this.subject,
  });

  final String author;
  final String role;
  final String type;
  final String message;
  final String time;
  final bool isWorker;
  final String? subject;
}

class _LifecycleEventItem {
  final String title;
  final String timestamp;
  final String? submissionTimestamp;
  final String actor;
  final String status;
  final int? progress;
  final IconData icon;
  final Color iconColor;
  final String details;
  final int attachmentsCount;
  final String tag;
  final DateTime? sortDate;

  const _LifecycleEventItem({
    required this.title,
    required this.timestamp,
    this.submissionTimestamp,
    required this.actor,
    required this.status,
    this.progress,
    required this.icon,
    required this.iconColor,
    required this.details,
    this.attachmentsCount = 0,
    required this.tag,
    this.sortDate,
  });
}
