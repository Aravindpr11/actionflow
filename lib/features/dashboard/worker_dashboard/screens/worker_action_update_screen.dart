import 'dart:async';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/widgets/document_preview/action_attachment_preview_dialog.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../manager_dashboard/data/mock_action_store.dart';
import '../../manager_dashboard/models/action_record.dart';

class WorkerActionUpdateScreen extends StatefulWidget {
  const WorkerActionUpdateScreen({
    required this.action,
    this.currentUserId,
    this.currentUserName,
    this.currentUserEmail,
    super.key,
  });

  final ActionRecord action;
  final String? currentUserId;
  final String? currentUserName;
  final String? currentUserEmail;

  @override
  State<WorkerActionUpdateScreen> createState() =>
      _WorkerActionUpdateScreenState();
}

class _WorkerActionUpdateScreenState extends State<WorkerActionUpdateScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController subject;
  late final TextEditingController message;
  late final TextEditingController requirement;
  late final TextEditingController pendingReason;
  late final TextEditingController suggestion;
  late final TextEditingController remarks;
  late int percent;
  late String status;
  String messageType = 'Progress Update';
  final attachments = <String>[];
  final List<AppPickedFile> _pendingPickedFiles = [];
  bool _isUploadingAttachments = false;
  final List<ActionSubTask> _allSubTasks = [];
  bool _isLoadingSubtasks = false;
  String? _subtaskLoadError;
  int _selectedTabIndex = 0;
  String? _existingUpdateId;
  bool _isEditingExisting = false;

  Future<void> _pickAttachment() async {
    try {
      final picked = await AppFilePicker.pickSingleFile(
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'csv',
          'txt',
        ],
      );
      if (picked == null) return;

      const maxSizeBytes = 10 * 1024 * 1024;
      if (picked.size > maxSizeBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'File "${picked.name}" exceeds the 10MB limit (${picked.formattedSize}). Please choose a smaller file.',
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final cleanName = ActionService.sanitizeAttachmentFileName(picked.name);
      if (cleanName.isEmpty) return;

      setState(() {
        if (!attachments.contains(cleanName)) {
          attachments.add(cleanName);
        }
        _pendingPickedFiles.removeWhere(
          (f) => ActionService.sanitizeAttachmentFileName(f.name) == cleanName,
        );
        _pendingPickedFiles.add(picked);
      });
    } catch (e) {
      debugPrint('[WorkerActionUpdateScreen] Error picking attachment: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to select file: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _uploadPendingFiles(ActionRecord targetAction) async {
    if (_pendingPickedFiles.isEmpty) return true;
    setState(() => _isUploadingAttachments = true);

    try {
      for (final file in List.of(_pendingPickedFiles)) {
        final res = await ActionService.instance.uploadActionAttachment(
          action: targetAction,
          fileName: file.name,
          bytes: file.bytes,
        );
        if (!res.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  res.error ?? 'Failed to upload attachment ${file.name}.',
                ),
                backgroundColor: const Color(0xFFDC2626),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          if (mounted) {
            setState(() => _isUploadingAttachments = false);
          }
          return false;
        }
      }
      _pendingPickedFiles.clear();
      if (mounted) {
        setState(() => _isUploadingAttachments = false);
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Attachment upload error: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isUploadingAttachments = false);
      }
      return false;
    }
  }

  void _handlePreviewAttachment(String file) {
    ActionAttachmentPreviewDialog.show(
      context,
      action: widget.action,
      fileName: file,
      currentUserId: widget.currentUserId,
      isWorker: true,
    );
  }

  Future<void> _handleDownloadAttachment(String file) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Preparing download for "$file"...'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    try {
      final res = await ActionService.instance.downloadActionAttachment(
        action: widget.action,
        fileName: file,
        userId: widget.currentUserId,
        isManager: false,
      );
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      if (!res.success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(res.error ?? 'Failed to download attachment.'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Successfully downloaded "$file"'),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error downloading attachment: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _isTaskAuthorized(ActionSubTask task) {
    // External tasks belong to external contractors, never visible to staff in worker portal
    if (task.isExternal) return false;

    final userId = widget.currentUserId?.trim();
    final userEmail = widget.currentUserEmail?.trim().toLowerCase();

    // 1. Direct match by staff profile UUID
    if (userId != null &&
        userId.isNotEmpty &&
        task.assignedStaffId.trim().isNotEmpty &&
        task.assignedStaffId.trim().toLowerCase() == userId.toLowerCase()) {
      return true;
    }

    // 2. Direct match by verified staff email
    if (userEmail != null &&
        userEmail.isNotEmpty &&
        task.assignedStaffEmail.trim().isNotEmpty &&
        task.assignedStaffEmail.trim().toLowerCase() == userEmail) {
      return true;
    }

    // 3. Direct match by staff name
    final userName = widget.currentUserName?.trim().toLowerCase();
    if (userName != null &&
        userName.isNotEmpty &&
        task.assignedStaff.trim().isNotEmpty &&
        task.assignedStaff.trim().toLowerCase() == userName) {
      return true;
    }

    // 4. Inherited action-level assignment when task has no distinct assignee specified:
    if (task.assignedStaffId.trim().isEmpty && task.assignedStaffEmail.trim().isEmpty) {
      final primaryId = widget.action.assignedToId ?? widget.action.primaryAssignee?.personId;
      if (userId != null && userId.isNotEmpty && primaryId != null && primaryId.trim().toLowerCase() == userId.toLowerCase()) {
        return true;
      }
      final primaryEmail = widget.action.primaryAssignee?.email.trim().toLowerCase();
      if (userEmail != null && userEmail.isNotEmpty && primaryEmail != null && primaryEmail == userEmail) {
        return true;
      }
      if (userId != null && userId.isNotEmpty && widget.action.assignees.any((a) => a.profileId.trim().toLowerCase() == userId.toLowerCase())) {
        return true;
      }
      if (userEmail != null && userEmail.isNotEmpty && widget.action.assignees.any((a) => a.profileEmail.trim().toLowerCase() == userEmail)) {
        return true;
      }
    }

    // Fallback ONLY when no credentials are provided at all (e.g. headless unit testing without user context)
    if ((userId == null || userId.isEmpty) && (userEmail == null || userEmail.isEmpty)) {
      return true;
    }

    return false;
  }

  List<ActionSubTask> get _visibleSubTasks =>
      _allSubTasks.where(_isTaskAuthorized).toList();

  int calculateProgressFromSubtasks(List<ActionSubTask> subtasks) {
    if (subtasks.isEmpty) return percent;
    final completed = subtasks.where((t) => t.isCompleted).length;
    return ((completed / subtasks.length) * 100).round().clamp(0, 100);
  }

  Future<String?> _showReopenTaskDialog(BuildContext context, String taskTitle) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.replay_rounded, color: Color(0xFFD97706), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reopen Task: $taskTitle',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please provide a reason for reopening this task (optional):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. Needs correction or revised verification...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            ),
            child: const Text('Reopen Task'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSubtasks({int? overridePercent}) async {
    setState(() {
      _isLoadingSubtasks = true;
      _subtaskLoadError = null;
    });
    try {
      final effectiveId = widget.action.id.isNotEmpty
          ? widget.action.id
          : widget.action.actionNumber;
      final tasks = await ActionService.instance.fetchActionSubtasks(effectiveId);
      int? actionPercent = overridePercent;
      if (actionPercent == null && ActionService.instance.client != null) {
        try {
          final act = await ActionService.instance.fetchActionById(effectiveId);
          if (act != null) actionPercent = act.percentComplete;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isLoadingSubtasks = false;
          if (tasks.isNotEmpty) {
            _allSubTasks.clear();
            _allSubTasks.addAll(tasks);
          } else if (_allSubTasks.isEmpty && widget.action.subTasks.isNotEmpty) {
            _allSubTasks.addAll(widget.action.subTasks);
          }
          if (overridePercent != null) {
            percent = overridePercent;
          } else if (_allSubTasks.isNotEmpty) {
            percent = calculateProgressFromSubtasks(_allSubTasks);
          } else if (actionPercent != null) {
            percent = actionPercent;
          }
        });
      }
    } catch (e) {
      debugPrint('[WorkerActionUpdateScreen] Error loading subtasks: $e');
      if (mounted) {
        setState(() {
          _isLoadingSubtasks = false;
          if (_allSubTasks.isEmpty && widget.action.subTasks.isNotEmpty) {
            _allSubTasks.addAll(widget.action.subTasks);
          }
          _subtaskLoadError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final action = widget.action;
    if (action.subTasks.isNotEmpty) {
      _allSubTasks.addAll(action.subTasks);
    }
    if (ActionService.instance.client == null) {
      final existing = MockActionStore.instance.actions
          .firstWhereOrNull((a) => a.id == action.id);
      if (existing == null) {
        MockActionStore.instance.add(action);
      } else if (action.subTasks.isNotEmpty && existing.subTasks.isEmpty) {
        MockActionStore.instance.update(existing.copyWith(subTasks: action.subTasks));
      }
    }
    _loadSubtasks();

    final latestUpdate = action.latestProgressUpdateFor(
          widget.currentUserId,
          isManager: false,
        ) ??
        action.latestProgressUpdate;
    _existingUpdateId = latestUpdate?.id;
    _isEditingExisting = latestUpdate != null;

    final initialSubject =
        (latestUpdate != null && latestUpdate.effectiveSubject.isNotEmpty)
            ? latestUpdate.effectiveSubject
            : (action.workerMessageSubject.isNotEmpty
                ? action.workerMessageSubject
                : action.subject);

    final initialMessage =
        (latestUpdate != null && latestUpdate.effectiveWorkCompleted.isNotEmpty)
            ? latestUpdate.effectiveWorkCompleted
            : (action.workerMessage.isNotEmpty
                ? action.workerMessage
                : (action.remarks.isNotEmpty ? action.remarks : ''));

    final initialRequirement =
        (latestUpdate != null && latestUpdate.requirement.isNotEmpty)
            ? latestUpdate.requirement
            : action.requirement;

    final initialPending =
        (latestUpdate != null && latestUpdate.pendingWork.isNotEmpty)
            ? latestUpdate.pendingWork
            : action.pendingReason;

    final initialSuggestion =
        (latestUpdate != null && latestUpdate.suggestion.isNotEmpty)
            ? latestUpdate.suggestion
            : action.suggestion;

    final initialRemarks =
        (latestUpdate != null && latestUpdate.remarks.isNotEmpty)
            ? latestUpdate.remarks
            : action.remarks;

    final initialPercent = (latestUpdate != null)
        ? latestUpdate.progress.clamp(0, 100)
        : action.percentComplete.clamp(0, 100);

    final initialStatus =
        (latestUpdate != null && latestUpdate.status.isNotEmpty)
            ? ((latestUpdate.status == 'Completed' ||
                    latestUpdate.status == 'Pending Review')
                ? 'In Progress'
                : latestUpdate.status)
            : ((action.status == 'Completed' ||
                    action.status == 'Pending Review')
                ? 'In Progress'
                : action.status);

    final initialMessageType =
        (latestUpdate != null && latestUpdate.messageType.isNotEmpty)
            ? latestUpdate.messageType
            : (action.messageType.isNotEmpty
                ? action.messageType
                : 'Progress Update');

    subject = TextEditingController(text: initialSubject);
    message = TextEditingController(text: initialMessage);
    requirement = TextEditingController(text: initialRequirement);
    pendingReason = TextEditingController(text: initialPending);
    suggestion = TextEditingController(text: initialSuggestion);
    remarks = TextEditingController(text: initialRemarks);
    percent = initialPercent;
    status = initialStatus;
    messageType = initialMessageType;
    // NOTE: Newly selected documents for this update session initialize empty.
    // Previously attached documents must NOT appear in Update Action,
    // and remain preserved in Action Details without duplication.
  }

  @override
  void dispose() {
    for (final controller in [
      subject,
      message,
      requirement,
      pendingReason,
      suggestion,
      remarks,
    ]) {
      controller.dispose();
    }
    super.dispose();
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

  Color _statusColor(String st) {
    switch (st) {
      case 'Open':
        return const Color(0xFF0284C7);
      case 'In Progress':
        return const Color(0xFF2E7D32);
      case 'Pending Review':
      case 'Pending':
        return const Color(0xFF7C3AED);
      case 'Overdue':
        return const Color(0xFFEA580C);
      case 'Completed':
      case 'Closed':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF64748B);
    }
  }

  Color _priorityColor(String pr) {
    switch (pr) {
      case 'Critical':
        return const Color(0xFFDC2626);
      case 'High':
        return const Color(0xFFEA580C);
      case 'Medium':
        return const Color(0xFFD97706);
      case 'Low':
      default:
        return const Color(0xFF0284C7);
    }
  }

  IconData _categoryIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('tool') ||
        cat.contains('equipment') ||
        cat.contains('maintenance') ||
        cat.contains('machine')) {
      return Icons.home_repair_service_rounded;
    } else if (cat.contains('electric') ||
        cat.contains('power') ||
        cat.contains('wiring')) {
      return Icons.electrical_services_rounded;
    } else if (cat.contains('fire') ||
        cat.contains('hazard') ||
        cat.contains('safety') ||
        cat.contains('emergency')) {
      return Icons.local_fire_department_rounded;
    } else if (cat.contains('train') ||
        cat.contains('competenc') ||
        cat.contains('learn') ||
        cat.contains('drill')) {
      return Icons.school_rounded;
    } else if (cat.contains('environ') ||
        cat.contains('spill') ||
        cat.contains('waste') ||
        cat.contains('eco') ||
        cat.contains('chemical')) {
      return Icons.eco_rounded;
    } else if (cat.contains('inspect') ||
        cat.contains('audit') ||
        cat.contains('check') ||
        cat.contains('assessment')) {
      return Icons.fact_check_rounded;
    }
    return Icons.assignment_rounded;
  }

  Color _categoryColor(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('tool') ||
        cat.contains('equipment') ||
        cat.contains('maintenance')) {
      return const Color(0xFF0284C7);
    } else if (cat.contains('electric') || cat.contains('power')) {
      return const Color(0xFFD97706);
    } else if (cat.contains('fire') ||
        cat.contains('hazard') ||
        cat.contains('safety')) {
      return const Color(0xFFDC2626);
    } else if (cat.contains('train') || cat.contains('competenc')) {
      return const Color(0xFF7C3AED);
    } else if (cat.contains('environ') ||
        cat.contains('spill') ||
        cat.contains('waste')) {
      return const Color(0xFF16A34A);
    } else if (cat.contains('inspect') || cat.contains('audit')) {
      return const Color(0xFF0891B2);
    }
    return const Color(0xFF1565C0);
  }

  /// Normal Progress Update:
  /// - Keeps the action in its current active workload status (Open, In Progress, Overdue, etc.)
  /// - Does NOT move the action to 'Pending Review' or auto-close it
  /// - Updates progress percentage, remarks, and update fields
  /// - Appends Action History log (e.g. "Staff progress update: 40% → 65%")
  Future<void> _saveProgressUpdate() async {
    if (_isUploadingAttachments) return;

    if (subject.text.trim().isEmpty) {
      subject.text = widget.action.subject.isNotEmpty
          ? widget.action.subject
          : 'Progress Update';
    }
    if (message.text.trim().isEmpty) {
      message.text = 'Staff progress update: $percent% ($status).';
    }

    if (!formKey.currentState!.validate()) {
      if (_selectedTabIndex != 0) {
        setState(() => _selectedTabIndex = 0);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please complete the required update fields before saving.',
          ),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')} ${_monthName(now.month)} ${now.year}';
    final prevPercent = widget.action.percentComplete;
    final String historyEntry;
    if (prevPercent != percent) {
      historyEntry =
          '$dateStr: Staff progress update: $prevPercent% → $percent%.';
    } else {
      historyEntry = '$dateStr: Staff progress update: $percent% ($status).';
    }
    final nextHistory = [...widget.action.history, historyEntry];

    // Ensure status remains active (never Pending Review or Completed during Save Update)
    final activeStatus = (status == 'Completed' || status == 'Pending Review')
        ? 'In Progress'
        : status;

    // Reconcile _allSubTasks with widget.action.subTasks to ensure peer tasks are never dropped
    final reconciledTasks = widget.action.subTasks.map((t) {
      final updated = _allSubTasks.firstWhereOrNull((u) => u.id == t.id);
      return updated ?? t;
    }).toList();
    for (final u in _allSubTasks) {
      if (!reconciledTasks.any((t) => t.id == u.id)) {
        reconciledTasks.add(u);
      }
    }

    // Combine existing action attachments with newly selected attachments
    final combinedAttachments = <String>[
      ...widget.action.attachments,
      ...attachments.where((a) => !widget.action.attachments.contains(a)),
    ];

    final tempActionForUpload = widget.action.copyWith(attachments: combinedAttachments);
    final uploadOk = await _uploadPendingFiles(tempActionForUpload);
    if (!uploadOk) return;

    ActionRecord updatedAction;
    try {
      updatedAction = await ActionService.instance.submitProgressUpdate(
        actionId: widget.action.id,
        existingUpdateId: _isEditingExisting ? _existingUpdateId : null,
        updateDate: now,
        progress: percent,
        status: activeStatus,
        comments: message.text.trim().isNotEmpty
            ? message.text.trim()
            : (remarks.text.trim().isNotEmpty
                ? remarks.text.trim()
                : 'Progress update: $percent%'),
        contributionValue: (percent - prevPercent).clamp(0, 100).toInt(),
        attachments: combinedAttachments,
        roleInAction: 'assignee',
        updatedById: widget.currentUserId ?? widget.action.assignedToId,
        updatedByName: widget.currentUserName ?? widget.action.assignedTo,
        subject: subject.text.trim(),
        messageType: messageType,
        workCompleted: message.text.trim(),
        pendingWork: pendingReason.text.trim(),
        requirement: requirement.text.trim(),
        suggestion: suggestion.text.trim(),
        remarks: remarks.text.trim(),
        subTasks: reconciledTasks,
        history: nextHistory,
      );

      // Reconcile and synchronize subtasks if needed
      if (ActionService.instance.client != null) {
        try {
          await ActionService.instance.updateAction(
            updatedAction.copyWith(subTasks: reconciledTasks),
          );
        } catch (subtaskSyncErr) {
          debugPrint('[WorkerActionUpdateScreen] subtask sync non-fatal: $subtaskSyncErr');
        }
      }
    } catch (e) {
      debugPrint('[WorkerActionUpdateScreen] error on save update: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to persist update to database: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Clear local selection after saving
    attachments.clear();
    _pendingPickedFiles.clear();

    if (!mounted) return;
    Navigator.of(context).pop(updatedAction);
  }

  /// Explicit Completion Submission:
  /// - Used only when Staff believes the action is 100% complete
  /// - Validates percentage must be 100% and completion remarks provided
  /// - Validates all assigned tasks are completed
  /// - Transitions status to 'Pending Review'
  /// - Appends Action History log: "Staff submitted action for Manager review"
  Future<void> _submitForReview() async {
    if (_isUploadingAttachments) return;

    if (subject.text.trim().isEmpty) {
      subject.text = widget.action.subject.isNotEmpty
          ? widget.action.subject
          : 'Action Completion Review';
    }
    if (message.text.trim().isEmpty) {
      message.text = 'Work completed (100%). Submitted for Manager review.';
    }

    if (!formKey.currentState!.validate()) {
      if (_selectedTabIndex != 0) {
        setState(() => _selectedTabIndex = 0);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please complete the required update fields before submitting.',
          ),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_visibleSubTasks.any((t) => !t.isCompleted)) {
      if (_selectedTabIndex != 0) {
        setState(() => _selectedTabIndex = 0);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'All assigned tasks must be completed before submitting for review.',
          ),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (percent != 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Progress must be 100% when submitting action for Manager review.',
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Save Progress',
            textColor: Colors.white,
            onPressed: _saveProgressUpdate,
          ),
        ),
      );
      return;
    }
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')} ${_monthName(now.month)} ${now.year}';
    final nextHistory = [
      ...widget.action.history,
      '$dateStr: Staff submitted action for Manager review.',
    ];

    // Reconcile _allSubTasks with widget.action.subTasks to ensure peer tasks are never dropped
    final reconciledTasks = widget.action.subTasks.map((t) {
      final updated = _allSubTasks.firstWhereOrNull((u) => u.id == t.id);
      return updated ?? t;
    }).toList();
    for (final u in _allSubTasks) {
      if (!reconciledTasks.any((t) => t.id == u.id)) {
        reconciledTasks.add(u);
      }
    }

    // Combine existing action attachments with newly selected attachments
    final combinedAttachments = <String>[
      ...widget.action.attachments,
      ...attachments.where((a) => !widget.action.attachments.contains(a)),
    ];

    final tempActionForUpload = widget.action.copyWith(attachments: combinedAttachments);
    final uploadOk = await _uploadPendingFiles(tempActionForUpload);
    if (!uploadOk) return;

    ActionRecord submittedAction;
    final prevPercent = widget.action.percentComplete;
    try {
      submittedAction = await ActionService.instance.submitProgressUpdate(
        actionId: widget.action.id,
        existingUpdateId: _isEditingExisting ? _existingUpdateId : null,
        updateDate: now,
        progress: 100,
        status: 'Pending Review',
        comments: message.text.trim().isNotEmpty
            ? message.text.trim()
            : (remarks.text.trim().isNotEmpty
                ? remarks.text.trim()
                : 'Completion submitted for review'),
        contributionValue: (100 - prevPercent).clamp(0, 100).toInt(),
        attachments: combinedAttachments,
        roleInAction: 'assignee',
        updatedById: widget.currentUserId ?? widget.action.assignedToId,
        updatedByName: widget.currentUserName ?? widget.action.assignedTo,
        subject: subject.text.trim(),
        messageType: 'Completion Explanation',
        workCompleted: message.text.trim(),
        pendingWork: pendingReason.text.trim(),
        requirement: requirement.text.trim(),
        suggestion: suggestion.text.trim(),
        remarks: remarks.text.trim(),
        subTasks: reconciledTasks,
        history: nextHistory,
      );

      if (ActionService.instance.client != null) {
        try {
          await ActionService.instance.updateAction(
            submittedAction.copyWith(subTasks: reconciledTasks),
          );
        } catch (subtaskSyncErr) {
          debugPrint('[WorkerActionUpdateScreen] subtask sync non-fatal: $subtaskSyncErr');
        }
      }
    } catch (e) {
      debugPrint('[WorkerActionUpdateScreen] error on submit for review: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit action for review to database: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Clear local selection after submitting
    attachments.clear();
    _pendingPickedFiles.clear();

    if (!mounted) return;
    Navigator.of(context).pop(submittedAction);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 950;

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
          tooltip: 'Back to My Actions',
        ),
        titleSpacing: 0,
        title: screenWidth < 500
            ? Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.actionIdBg(context),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: AppTheme.actionIdBorder(context),
                      ),
                    ),
                    child: Text(
                      widget.action.id,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.actionIdText(context),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.actionIdBg(context),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppTheme.actionIdBorder(context),
                      ),
                    ),
                    child: Text(
                      widget.action.id,
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
                      'Update Action - ${widget.action.subject}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ),
                ],
              ),
        actions: [
          if (screenWidth >= 650) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: OutlinedButton.icon(
                onPressed: _saveProgressUpdate,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF1565C0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.save_outlined, size: 15),
                label: const Text(
                  'Save Update',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: 4,
                right: 12,
                top: 8,
                bottom: 8,
              ),
              child: ElevatedButton.icon(
                onPressed: _submitForReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
                label: const Text(
                  'Submit for Review',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(
                Icons.save_outlined,
                color: Color(0xFF1565C0),
                size: 20,
              ),
              onPressed: _saveProgressUpdate,
              tooltip: 'Save Update',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            IconButton(
              icon: const Icon(
                Icons.check_circle_outline_rounded,
                color: Color(0xFF1565C0),
                size: 20,
              ),
              onPressed: _submitForReview,
              tooltip: 'Submit for Review',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: Form(
        key: formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: EdgeInsets.all(screenWidth < 500 ? 12 : 20),
              children: [
                _pageHeaderBreadcrumb(),
                const SizedBox(height: 12),
                _actionSummaryHero(),
                const SizedBox(height: 16),
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _tabNavigationBar(),
                            const SizedBox(height: 16),
                            _buildActiveTabContent(),
                            const SizedBox(height: 16),
                            _bottomActionBar(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(flex: 3, child: _sidebarColumn()),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _tabNavigationBar(),
                      const SizedBox(height: 16),
                      _buildActiveTabContent(),
                      const SizedBox(height: 16),
                      _sidebarColumn(),
                      const SizedBox(height: 16),
                      _bottomActionBar(),
                    ],
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageHeaderBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Text(
                  'My Actions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppTheme.textMuted(context),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.actionIdBg(context),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.action.id,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.actionIdText(context),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppTheme.textMuted(context),
              ),
              Text(
                'Update Action',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Report progress, add evidence, request assistance, or submit completion for manager review.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionSummaryHero() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final statusCol = _statusColor(widget.action.status);
    final priorityCol = _priorityColor(widget.action.priority);
    final catIcon = _categoryIcon(widget.action.category);
    final catColor = _categoryColor(widget.action.category);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isVerySmall = screenWidth < 380;

    return Container(
      padding: EdgeInsets.all(isVerySmall ? 10 : (screenWidth < 500 ? 12 : 18)),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(isVerySmall ? 8 : 12),
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: catColor.withValues(alpha: isDark ? 0.4 : 0.25),
              ),
            ),
            child: Icon(catIcon, size: isVerySmall ? 22 : 28, color: catColor),
          ),
          SizedBox(width: isVerySmall ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
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
                        widget.action.id,
                        style: TextStyle(
                          color: AppTheme.actionIdText(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: priorityCol.withValues(
                          alpha: isDark ? 0.2 : 0.1,
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        widget.action.priority,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: priorityCol,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: statusCol.withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        widget.action.status,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: statusCol,
                        ),
                      ),
                    ),
                    if (widget.action.category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          widget.action.category,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: catColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.action.subject,
                  style: TextStyle(
                    fontSize: isVerySmall ? 15 : 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _heroMetaItem(
                      icon: Icons.location_on_outlined,
                      label: widget.action.site.isNotEmpty
                          ? widget.action.site
                          : '—',
                    ),
                    if (widget.action.section.isNotEmpty)
                      _heroMetaItem(
                        icon: Icons.layers_outlined,
                        label: widget.action.section,
                      ),
                    if (widget.action.department.isNotEmpty)
                      _heroMetaItem(
                        icon: Icons.apartment_rounded,
                        label: widget.action.department,
                      ),
                    if (widget.action.team.isNotEmpty)
                      _heroMetaItem(
                        icon: Icons.group_outlined,
                        label: widget.action.team,
                      ),
                    _heroMetaItem(
                      icon: Icons.calendar_today_outlined,
                      label: 'Target: ${widget.action.targetDate}',
                    ),
                    _heroMetaItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Assigned: ${widget.action.assignedTo}',
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

  Widget _heroMetaItem({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.textMuted(context)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary(context),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _tabNavigationBar() {
    final tabs = [
      {'label': 'Update', 'icon': Icons.edit_note_rounded},
      {
        'label': 'Evidence (${attachments.length})',
        'icon': Icons.attach_file_rounded,
      },
      {
        'label': 'History (${widget.action.history.length})',
        'icon': Icons.history_rounded,
      },
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
          children: List.generate(tabs.length, (index) {
            final isSelected = _selectedTabIndex == index;
            final tab = tabs[index];
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => setState(() => _selectedTabIndex = index),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
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
                        tab['icon'] as IconData,
                        size: 16,
                        color: isSelected
                            ? Colors.white
                            : AppTheme.textSecondary(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab['label'] as String,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _tabUpdateContent();
      case 1:
        return _tabEvidenceContent();
      case 2:
        return _tabHistoryContent();
      default:
        return _tabUpdateContent();
    }
  }

  Widget _tasksPanel() {
    final visible = _visibleSubTasks;
    final completedCount = visible.where((t) => t.isCompleted).length;
    final totalCount = visible.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _panel(
      title: 'TASKS & CHECKLIST ($completedCount / $totalCount COMPLETED)',
      icon: Icons.checklist_rtl_rounded,
      children: [
        for (int i = 0; i < visible.length; i++) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: visible[i].isCompleted
                    ? (isDark
                        ? const Color(0xFF059669)
                        : const Color(0xFF86EFAC))
                    : (isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0)),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: CheckboxListTile(
              key: Key('worker_task_checkbox_$i'),
              value: visible[i].isCompleted,
              activeColor: const Color(0xFF16A34A),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                visible[i].title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  decoration: visible[i].isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  color: visible[i].isCompleted
                      ? AppTheme.textMuted(context)
                      : AppTheme.textPrimary(context),
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (visible[i].instruction.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      visible[i].instruction,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Assignee: ${visible[i].assignedStaff.isNotEmpty ? visible[i].assignedStaff : "Staff"}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'Internal',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: visible[i].isCompleted
                              ? const Color(0xFF16A34A).withValues(alpha: 0.15)
                              : const Color(0xFFEA580C).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: visible[i].isCompleted
                                ? const Color(0xFF16A34A).withValues(alpha: 0.3)
                                : const Color(0xFFEA580C).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          visible[i].isCompleted ? 'Completed' : 'Pending',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: visible[i].isCompleted
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFEA580C),
                          ),
                        ),
                      ),
                      if (visible[i].isReopened)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFFD97706).withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Text(
                            'Reopened / Needs Correction',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                      if (visible[i].dueDate.isNotEmpty)
                        Text(
                          '• Due: ${visible[i].dueDate}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      if (visible[i].isCompleted && visible[i].completedAt.isNotEmpty)
                        Text(
                          '• Completed: ${visible[i].completedAt}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                    ],
                  ),
                  if (visible[i].isReopened && visible[i].reopenReason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFD97706).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Correction requested: ${visible[i].reopenReason}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFFD97706),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              onChanged: (checked) async {
                final messenger = ScaffoldMessenger.of(context);
                final now = DateTime.now();
                final nowStr =
                    '${now.day.toString().padLeft(2, '0')} ${_monthName(now.month)} ${now.year}';
                final workerName = (widget.currentUserName != null &&
                        widget.currentUserName!.isNotEmpty)
                    ? widget.currentUserName!
                    : (widget.action.assignedTo.isNotEmpty
                        ? widget.action.assignedTo
                        : 'Staff');
                final targetTaskId = visible[i].id;
                final prevStatus = visible[i].status;
                final prevCompletedAt = visible[i].completedAt;
                final prevCompletedBy = visible[i].completedBy;
                final prevPercent = percent;

                String? reopenReason;
                if (checked == false) {
                  final reason = await _showReopenTaskDialog(context, visible[i].title);
                  if (reason == null) {
                    // User dismissed/cancelled dialog, do not change state
                    return;
                  }
                  reopenReason = reason;
                }

                setState(() {
                  final allIdx =
                      _allSubTasks.indexWhere((t) => t.id == targetTaskId);
                  if (allIdx != -1) {
                    if (checked == true) {
                      _allSubTasks[allIdx] = _allSubTasks[allIdx].copyWith(
                        status: 'Completed',
                        completedAt: nowStr,
                        completedBy: workerName,
                        reopenReason: '',
                      );
                    } else {
                      _allSubTasks[allIdx] = _allSubTasks[allIdx].copyWith(
                        status: 'Open',
                        completedAt: '',
                        completedBy: '',
                        reopenReason: reopenReason ?? '',
                      );
                    }
                    percent = calculateProgressFromSubtasks(_allSubTasks);
                  }
                });

                try {
                  final res = await ActionService.instance.submitSubtaskToggle(
                    actionId: widget.action.id,
                    taskId: targetTaskId,
                    isCompleted: checked == true,
                    reopenReason: reopenReason,
                  );

                  if (res['success'] == true) {
                    await _loadSubtasks();
                  } else {
                    setState(() {
                      final allIdx =
                          _allSubTasks.indexWhere((t) => t.id == targetTaskId);
                      if (allIdx != -1) {
                        _allSubTasks[allIdx] = _allSubTasks[allIdx].copyWith(
                          status: prevStatus,
                          completedAt: prevCompletedAt,
                          completedBy: prevCompletedBy,
                        );
                      }
                      percent = prevPercent;
                    });
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(res['error']?.toString() ?? 'Failed to update task.'),
                        backgroundColor: const Color(0xFFDC2626),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  setState(() {
                    final allIdx =
                        _allSubTasks.indexWhere((t) => t.id == targetTaskId);
                    if (allIdx != -1) {
                      _allSubTasks[allIdx] = _allSubTasks[allIdx].copyWith(
                        status: prevStatus,
                        completedAt: prevCompletedAt,
                        completedBy: prevCompletedBy,
                      );
                    }
                    percent = prevPercent;
                  });
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error updating task: $e'),
                      backgroundColor: const Color(0xFFDC2626),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
          ),
        ),
        ],
      ],
    );
  }

  Widget _loadingTasksPanel() {
    return _panel(
      title: 'TASKS & CHECKLIST',
      icon: Icons.checklist_rtl_rounded,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 10),
              Text(
                'Loading assigned tasks...',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorTasksPanel() {
    return _panel(
      title: 'TASKS & CHECKLIST',
      icon: Icons.checklist_rtl_rounded,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFDC2626).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFDC2626), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Failed to retrieve assigned tasks: $_subtaskLoadError',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _loadSubtasks,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFDC2626)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _peerTasksOnlyPanel() {
    return _panel(
      title: 'TASKS & CHECKLIST',
      icon: Icons.checklist_rtl_rounded,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E293B)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF334155)
                  : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This action contains tasks assigned to other team members or external contractors.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editModeIndicatorBanner() {
    final hasLatest = widget.action.latestProgressUpdateFor(
          widget.currentUserId,
          isManager: false,
        ) != null ||
        widget.action.latestProgressUpdate != null;

    if (!_isEditingExisting && !hasLatest) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 450;

        if (_isEditingExisting) {
          final content = [
            Row(
              children: [
                const Icon(Icons.edit_note_rounded, size: 20, color: Color(0xFF1565C0)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Editing Saved Progress Update',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      Text(
                        'Changes will update your previously saved update without creating duplicates.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: isNarrow ? Alignment.centerRight : Alignment.center,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isEditingExisting = false;
                    _existingUpdateId = null;
                  });
                },
                icon: const Icon(Icons.add_circle_outline, size: 14),
                label: const Text('Log as New Update', style: TextStyle(fontSize: 11.5)),
              ),
            ),
          ];

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.3)),
            ),
            child: isNarrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      content[0],
                      const SizedBox(height: 4),
                      content[1],
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: content[0]),
                      content[1],
                    ],
                  ),
          );
        }

        final content = [
          Row(
            children: [
              Icon(Icons.add_circle_outline, size: 18, color: AppTheme.textSecondary(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Creating a new progress update record.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: isNarrow ? Alignment.centerRight : Alignment.center,
            child: TextButton.icon(
              onPressed: () {
                final latest = widget.action.latestProgressUpdateFor(
                      widget.currentUserId,
                      isManager: false,
                    ) ??
                    widget.action.latestProgressUpdate;
                if (latest != null) {
                  setState(() {
                    _isEditingExisting = true;
                    _existingUpdateId = latest.id;
                    if (latest.effectiveSubject.isNotEmpty) {
                      subject.text = latest.effectiveSubject;
                    }
                    if (latest.effectiveWorkCompleted.isNotEmpty) {
                      message.text = latest.effectiveWorkCompleted;
                    }
                    if (latest.pendingWork.isNotEmpty) {
                      pendingReason.text = latest.pendingWork;
                    }
                    if (latest.requirement.isNotEmpty) {
                      requirement.text = latest.requirement;
                    }
                    if (latest.suggestion.isNotEmpty) {
                      suggestion.text = latest.suggestion;
                    }
                    if (latest.remarks.isNotEmpty) {
                      remarks.text = latest.remarks;
                    }
                    percent = latest.progress.clamp(0, 100);
                    if (latest.messageType.isNotEmpty) {
                      messageType = latest.messageType;
                    }
                  });
                }
              },
              icon: const Icon(Icons.edit_note_rounded, size: 14),
              label: const Text('Edit Latest Saved Update', style: TextStyle(fontSize: 11.5)),
            ),
          ),
        ];

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.containerBg(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cardBorder(context)),
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    content[0],
                    const SizedBox(height: 4),
                    content[1],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: content[0]),
                    content[1],
                  ],
                ),
        );
      },
    );
  }

  Widget _tabUpdateContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _workflowGuidanceBanner(),
        const SizedBox(height: 16),
        _editModeIndicatorBanner(),
        if (_isLoadingSubtasks && _allSubTasks.isEmpty) ...[
          _loadingTasksPanel(),
          const SizedBox(height: 16),
        ] else if (_subtaskLoadError != null && _allSubTasks.isEmpty) ...[
          _errorTasksPanel(),
          const SizedBox(height: 16),
        ] else if (_visibleSubTasks.isNotEmpty) ...[
          _tasksPanel(),
          const SizedBox(height: 16),
        ] else if (_allSubTasks.isNotEmpty) ...[
          _peerTasksOnlyPanel(),
          const SizedBox(height: 16),
        ],
        _panel(
          title: 'PROGRESS & STATUS',
          icon: Icons.sync_rounded,
          children: [
            _select(
              'Current Status (Active)',
              status,
              _availableStatuses(),
              (value) => setState(() {
                status = value!;
              }),
            ),
            if (_allSubTasks.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1E3A8A).withValues(alpha: 0.25)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1D4ED8).withValues(alpha: 0.4)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: Color(0xFF1565C0)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tasks: ${_allSubTasks.where((t) => t.isCompleted).length} of ${_allSubTasks.length} completed. Report overall action progress below.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            _select(
              '% Complete',
              '$percent%',
              _availablePercentOptions(),
              (value) => setState(
                () => percent = int.parse(value!.replaceAll('%', '')),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: percent == 100
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF1565C0),
                      inactiveTrackColor: AppTheme.progressTrackBg(context),
                      thumbColor: percent == 100
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF1565C0),
                      trackHeight: 6,
                    ),
                    child: Slider(
                      value: percent.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '$percent%',
                      onChanged: (val) {
                        setState(() => percent = val.round());
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$percent%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [0, 20, 40, 50, 60, 75, 100].map((pct) {
                final isSelected = percent == pct;
                return ChoiceChip(
                  label: Text('$pct%'),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => percent = pct);
                  },
                  selectedColor: const Color(0xFF1565C0),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : AppTheme.textSecondary(context),
                  ),
                  backgroundColor: AppTheme.containerBg(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFF1565C0)
                          : AppTheme.cardBorder(context),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Completion Progress',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percent / 100.0,
                      minHeight: 7,
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percent == 100
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF1565C0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (percent == 100)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1D4ED8).withValues(alpha: 0.5)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.task_alt_rounded,
                      color: Color(0xFF1565C0),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Progress is set to 100%. When all requirements and evidence are ready, click "Submit for Review" below to send this action for Manager verification.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF93C5FD)
                              : const Color(0xFF1E40AF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        _panel(
          title: 'WORK COMPLETED & PROGRESS REMARKS',
          icon: Icons.assignment_turned_in_rounded,
          children: [
            _field('Update Subject *', subject),
            _select('Update Message Type', messageType, const [
              'Progress Update',
              'Work Completed',
              'Pending Work / Delay',
              'Requirement',
              'Suggestion',
              'General Remark',
              'Completion Explanation',
            ], (value) => setState(() => messageType = value!)),
            _field(
              'Work Completed & Description *',
              message,
              maxLines: 4,
              helperText: 'Explain work performed, measurements taken, or assistance needed.',
            ),
          ],
        ),
        _panel(
          title: 'WORK PENDING & ROADBLOCKS',
          icon: Icons.pending_actions_rounded,
          children: [
            _field(
              'Work Still Pending / Next Steps',
              pendingReason,
              maxLines: 2,
              helperText: 'List any remaining steps, inspections, or pending site conditions.',
            ),
            _field(
              'Specific Equipment / Material Requirement',
              requirement,
              maxLines: 2,
            ),
            _field('Suggestion for HSSE Manager', suggestion, maxLines: 2),
            _field('General Safety Remarks', remarks, maxLines: 2),
          ],
        ),
        _panel(
          title: 'ATTACHMENTS & EVIDENCE',
          icon: Icons.attach_file_rounded,
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isUploadingAttachments ? null : _pickAttachment,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1D4ED8).withValues(alpha: 0.5)
                        : const Color(0xFFBFDBFE),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_rounded, size: 17),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Add Inspection Photo / Document Evidence',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (attachments.isEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No new documents selected for this update. (Previously attached files remain preserved in Action Details)',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              ...attachments.map(
                (file) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.containerBg(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.cardBorder(context)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        color: Color(0xFF1565C0),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          file,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppTheme.textMuted(context),
                        ),
                        onPressed: () {
                          setState(() {
                            attachments.remove(file);
                            _pendingPickedFiles.removeWhere(
                              (f) =>
                                  ActionService.sanitizeAttachmentFileName(
                                    f.name,
                                  ) ==
                                  file ||
                                  f.name == file,
                            );
                          });
                        },
                        tooltip: 'Remove file',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _tabEvidenceContent() {
    final staffEvidence = widget.action.staffUpdateEvidence;

    return _panel(
      title: 'INSPECTION EVIDENCE & ATTACHMENTS',
      icon: Icons.photo_library_outlined,
      children: [
        // -------------------------------------------------------------
        // NEW EVIDENCE FOR THIS UPDATE (Upload dropzone at top)
        // -------------------------------------------------------------
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.containerBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.cardBorder(context),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                size: 36,
                color: Color(0xFF1565C0),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload Photos, Certificates or Test Reports',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Supported formats: JPG, PNG, PDF (Up to 10MB per file)',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textMuted(context),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isUploadingAttachments ? null : _pickAttachment,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF1565C0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Evidence Document'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (attachments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'No new evidence files selected for this update. Add photos or PDF reports if applicable.\n(Previously attached documents remain preserved in Action Details)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted(context),
                ),
              ),
            ),
          )
        else
          ...attachments.map(
            (file) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: Color(0xFF1565C0),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Newly selected file • Ready for upload on save',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Color(0xFFDC2626),
                    ),
                    onPressed: () {
                      setState(() {
                        attachments.remove(file);
                        _pendingPickedFiles.removeWhere(
                          (f) =>
                              ActionService.sanitizeAttachmentFileName(
                                f.name,
                              ) ==
                              file ||
                              f.name == file,
                        );
                      });
                    },
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),
          ),

        // -------------------------------------------------------------
        // PREVIOUSLY SUBMITTED EVIDENCE (below new upload area)
        // -------------------------------------------------------------
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(
              Icons.folder_shared_outlined,
              size: 16,
              color: Color(0xFF1565C0),
            ),
            const SizedBox(width: 6),
            Text(
              'PREVIOUSLY SUBMITTED EVIDENCE (${staffEvidence.length})',
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
        if (staffEvidence.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.containerBg(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.cardBorder(context)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppTheme.textMuted(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No previously submitted evidence from update submissions.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...staffEvidence.map((ev) {
            final isPdf = ev.fileName.toLowerCase().endsWith('.pdf');
            final isImg = ev.fileName.toLowerCase().endsWith('.jpg') ||
                ev.fileName.toLowerCase().endsWith('.png') ||
                ev.fileName.toLowerCase().endsWith('.jpeg');
            const tagColor = Color(0xFF059669);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isPdf
                              ? const Color(0xFFDC2626)
                              : isImg
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFF1565C0))
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isPdf
                          ? Icons.picture_as_pdf_outlined
                          : isImg
                              ? Icons.image_outlined
                              : Icons.description_outlined,
                      size: 20,
                      color: isPdf
                          ? const Color(0xFFDC2626)
                          : isImg
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF1565C0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                ev.fileName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: tagColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Staff Evidence',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: tagColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${ev.fileType} • Submitted by ${ev.uploadedBy.isNotEmpty ? ev.uploadedBy : "Staff"} (${ev.uploaderRole})${ev.uploadedAt != null ? " • ${ActionRecord.formatDateForUi(ev.uploadedAt)}" : ""}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('preview_attachment_${ev.fileName}_btn'),
                    icon: const Icon(
                      Icons.visibility_outlined,
                      color: Color(0xFF0284C7),
                      size: 19,
                    ),
                    tooltip: 'Preview Evidence',
                    onPressed: () => _handlePreviewAttachment(ev.fileName),
                  ),
                  IconButton(
                    key: Key('download_attachment_${ev.fileName}_btn'),
                    icon: const Icon(
                      Icons.download_rounded,
                      color: Color(0xFF1565C0),
                      size: 19,
                    ),
                    tooltip: 'Download Evidence',
                    onPressed: () => _handleDownloadAttachment(ev.fileName),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _tabHistoryContent() {
    final history = widget.action.history;

    return _panel(
      title: 'ACTIVITY LOG & AUDIT TRAIL',
      icon: Icons.history_rounded,
      children: [
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No previous activity history for this action.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textMuted(context),
                ),
              ),
            ),
          )
        else
          ...history.reversed.map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.history_toggle_off_rounded,
                      size: 14,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textPrimary(context),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _sidebarColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _quickActionsCard(),
        const SizedBox(height: 16),
        _actionSummaryDetailsCard(),
      ],
    );
  }

  Widget _actionSummaryDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 17,
                color: Color(0xFF1565C0),
              ),
              const SizedBox(width: 8),
              Text(
                'Action Summary',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sidebarMetaRow('Action ID', widget.action.id),
          _sidebarMetaRow(
            'Category',
            widget.action.category.isNotEmpty
                ? widget.action.category
                : 'General',
          ),
          _sidebarMetaRow('Priority', widget.action.priority),
          _sidebarMetaRow('Status', status),
          _sidebarMetaRow(
            'Site / Location',
            widget.action.site.isNotEmpty ? widget.action.site : '—',
          ),
          _sidebarMetaRow(
            'Section',
            widget.action.section.isNotEmpty ? widget.action.section : '—',
          ),
          _sidebarMetaRow(
            'Department',
            widget.action.department.isNotEmpty
                ? widget.action.department
                : '—',
          ),
          _sidebarMetaRow(
            'Teams',
            widget.action.team.isNotEmpty ? widget.action.team : '—',
          ),
          _sidebarMetaRow('Target Date', widget.action.targetDate),
          _sidebarMetaRow('Assigned To', widget.action.assignedTo),
          _sidebarMetaRow('Assigned By', widget.action.assignedBy),
          _sidebarMetaRow('Progress', '$percent%'),
        ],
      ),
    );
  }

  Widget _sidebarMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textMuted(context),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bolt_rounded,
                size: 17,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 8),
              Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _quickActionButton(
            icon: Icons.done_all_rounded,
            label: 'Mark as Complete (100%)',
            color: const Color(0xFF16A34A),
            onTap: () {
              setState(() {
                percent = 100;
                _selectedTabIndex = 0;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Progress set to 100%. Ready for submission.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          _quickActionButton(
            icon: Icons.add_photo_alternate_rounded,
            label: 'Attach Evidence',
            color: const Color(0xFF1565C0),
            onTap: () async {
              await _pickAttachment();
              if (mounted) {
                setState(() => _selectedTabIndex = 1);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.15
                  : 0.08,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.3
                    : 0.2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _availableStatuses() {
    const standard = ['Open', 'In Progress', 'Pending', 'Overdue'];
    if (!standard.contains(status)) {
      return [status, ...standard];
    }
    return standard;
  }

  List<String> _availablePercentOptions() {
    const standard = [
      '0%',
      '25%',
      '40%',
      '50%',
      '65%',
      '75%',
      '80%',
      '90%',
      '100%',
    ];
    final current = '$percent%';
    if (!standard.contains(current)) {
      final list = [...standard, current];
      list.sort(
        (a, b) =>
            int.parse(a.replaceAll('%', ''))
                .compareTo(int.parse(b.replaceAll('%', ''))),
      );
      return list;
    }
    return standard;
  }

  Widget _workflowGuidanceBanner() {
    return Container(
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
              const Icon(
                Icons.help_outline_rounded,
                size: 17,
                color: Color(0xFF1565C0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Workflow Action Guide',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 550;
              final col1 = _guideChip(
                icon: Icons.sync_rounded,
                color: const Color(0xFF0284C7),
                title: 'Save Update (Progress Report)',
                description: 'Use to report progress, completed work, pending work, or delays. The action remains active in your workload.',
              );
              final col2 = _guideChip(
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF7C3AED),
                title: 'Submit for Review (Completed Work)',
                description: 'Use when work is 100% completed. Moves action to "Pending Review" for Manager verification.',
              );

              if (isNarrow) {
                return Column(
                  children: [col1, const SizedBox(height: 8), col2],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: col1),
                  const SizedBox(width: 12),
                  Expanded(child: col2),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _guideChip({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.15 : 0.06,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary(context),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomActionBar() {
    return Container(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 400 ? 12 : 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x040F172A),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to submit your update?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Save Update = progress report (remains active)  •  Submit for Review = 100% complete (routes to Manager)',
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(null),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary(context),
                  side: BorderSide(color: AppTheme.cardBorder(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Discard Changes',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _saveProgressUpdate,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF1565C0), width: 1.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text(
                  'Save Update',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _submitForReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.check_circle_rounded, size: 16),
                label: const Text(
                  'Submit for Review',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 400 ? 12 : 18),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF1565C0)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textPrimary(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children.map(
            (child) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(fontSize: 13.5, color: AppTheme.textPrimary(context)),
      validator: label.endsWith('*')
          ? (value) => value == null || value.trim().isEmpty
                ? 'Please enter $label'
                : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 13,
          color: AppTheme.textSecondary(context),
        ),
        helperText: helperText,
        helperStyle: TextStyle(
          fontSize: 11.5,
          color: AppTheme.textMuted(context),
        ),
        filled: true,
        fillColor: AppTheme.inputFill(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.inputBorder(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.inputBorder(context)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF1565C0)),
        ),
      ),
    );
  }

  Widget _select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      dropdownColor: AppTheme.cardBg(context),
      style: TextStyle(fontSize: 13.5, color: AppTheme.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 13,
          color: AppTheme.textSecondary(context),
        ),
        filled: true,
        fillColor: AppTheme.inputFill(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.inputBorder(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.inputBorder(context)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF1565C0)),
        ),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(
                item,
                style: TextStyle(color: AppTheme.textPrimary(context)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
