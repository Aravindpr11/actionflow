import 'dart:async';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/data/mock_action_store.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/services/action_service.dart';
import 'package:action_flow/services/app_file_picker_service.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:action_flow/widgets/document_preview/action_attachment_preview_dialog.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class ManagerActionUpdateScreen extends StatefulWidget {
  const ManagerActionUpdateScreen({
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
  State<ManagerActionUpdateScreen> createState() =>
      _ManagerActionUpdateScreenState();
}

class _ManagerActionUpdateScreenState extends State<ManagerActionUpdateScreen> {
  final _formKey = GlobalKey<FormState>();

  late ActionRecord _currentAction;
  late DateTime _updateDate;
  late int _progress;
  late String _status;
  late final TextEditingController _commentsController;
  late final TextEditingController _pendingReasonController;
  late final TextEditingController _subjectController;
  late final TextEditingController _requirementController;
  late final TextEditingController _suggestionController;
  late final TextEditingController _remarksController;
  String _messageType = 'Progress Update';
  String? _existingUpdateId;
  bool _isEditingExisting = false;

  final List<String> _attachments = [];
  final List<AppPickedFile> _pendingPickedFiles = [];
  bool _isUploadingAttachments = false;
  final List<ActionSubTask> _allSubTasks = [];
  bool _isLoadingSubtasks = false;
  String? _subtaskLoadError;
  bool _isSubmitting = false;
  String? _errorMessage;
  int _selectedTabIndex = 0;

  static const List<String> _validStatuses = [
    'In Progress',
    'Open',
    'Pending Review',
    'Under Escalation',
    'On Hold',
  ];

  static const List<int> _quickChips = [0, 20, 40, 50, 60, 75, 100];

  Future<void> _loadSubtasks({int? overridePercent}) async {
    setState(() {
      _isLoadingSubtasks = true;
      _subtaskLoadError = null;
    });
    try {
      final effectiveId = widget.action.id.isNotEmpty
          ? widget.action.id
          : widget.action.actionNumber;
      final tasks =
          await ActionService.instance.fetchActionSubtasks(effectiveId);
      int? actionPercent = overridePercent;
      if (ActionService.instance.client != null) {
        try {
          final act =
              await ActionService.instance.fetchActionById(effectiveId);
          if (act != null) {
            actionPercent ??= act.percentComplete;
            if (mounted) {
              setState(() {
                _currentAction = act;
                MockActionStore.instance.update(act);
              });
            }
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isLoadingSubtasks = false;
          if (tasks.isNotEmpty) {
            _allSubTasks.clear();
            _allSubTasks.addAll(tasks);
          } else if (_allSubTasks.isEmpty &&
              _currentAction.subTasks.isNotEmpty) {
            _allSubTasks.addAll(_currentAction.subTasks);
          }
          if (overridePercent != null) {
            _progress = overridePercent;
          } else if (actionPercent != null) {
            _progress = actionPercent;
          }
        });
      }
    } catch (e) {
      debugPrint('[ManagerActionUpdateScreen] Error loading subtasks: $e');
      if (mounted) {
        setState(() {
          _isLoadingSubtasks = false;
          if (_allSubTasks.isEmpty && _currentAction.subTasks.isNotEmpty) {
            _allSubTasks.addAll(_currentAction.subTasks);
          }
          _subtaskLoadError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final existing = MockActionStore.instance.actions.firstWhereOrNull(
      (a) =>
          a.id == widget.action.id ||
          a.actionNumber == widget.action.id ||
          a.id == widget.action.actionNumber,
    );
    _currentAction = existing ?? widget.action;
    _updateDate = DateTime.now();
    _progress = _currentAction.percentComplete.clamp(0, 100);

    if (_currentAction.subTasks.isNotEmpty) {
      _allSubTasks.addAll(_currentAction.subTasks);
    }

    if (existing == null) {
      MockActionStore.instance.add(_currentAction);
    } else if (_currentAction.subTasks.isNotEmpty) {
      MockActionStore.instance
          .update(existing.copyWith(subTasks: _currentAction.subTasks));
    }

    _loadSubtasks();

    final latestUpdate = _currentAction.latestProgressUpdateFor(
          widget.currentUserId,
          isManager: true,
        ) ??
        _currentAction.latestProgressUpdate;
    _existingUpdateId = latestUpdate?.id;
    _isEditingExisting = latestUpdate != null;

    final initialSubject = (latestUpdate != null && latestUpdate.effectiveSubject.isNotEmpty)
        ? latestUpdate.effectiveSubject
        : (_currentAction.workerMessageSubject.isNotEmpty
            ? _currentAction.workerMessageSubject
            : _currentAction.subject);

    final initialComments = (latestUpdate != null && latestUpdate.effectiveWorkCompleted.isNotEmpty)
        ? latestUpdate.effectiveWorkCompleted
        : (_currentAction.managerMessage.isNotEmpty
            ? _currentAction.managerMessage
            : (_currentAction.workerMessage.isNotEmpty
                ? _currentAction.workerMessage
                : _currentAction.remarks));

    final initialPending = (latestUpdate != null && latestUpdate.pendingWork.isNotEmpty)
        ? latestUpdate.pendingWork
        : _currentAction.pendingReason;

    final initialRequirement = (latestUpdate != null && latestUpdate.requirement.isNotEmpty)
        ? latestUpdate.requirement
        : _currentAction.requirement;

    final initialSuggestion = (latestUpdate != null && latestUpdate.suggestion.isNotEmpty)
        ? latestUpdate.suggestion
        : _currentAction.suggestion;

    final initialRemarks = (latestUpdate != null && latestUpdate.remarks.isNotEmpty)
        ? latestUpdate.remarks
        : _currentAction.remarks;

    final initialPercent = (latestUpdate != null)
        ? latestUpdate.progress.clamp(0, 100)
        : _currentAction.percentComplete.clamp(0, 100);

    final initialStatus = (latestUpdate != null && _validStatuses.contains(latestUpdate.status))
        ? latestUpdate.status
        : (_validStatuses.contains(_currentAction.status)
            ? _currentAction.status
            : 'In Progress');

    final initialMessageType = (latestUpdate != null && latestUpdate.messageType.isNotEmpty)
        ? latestUpdate.messageType
        : (_currentAction.messageType.isNotEmpty
            ? _currentAction.messageType
            : 'Progress Update');

    _progress = initialPercent;
    _status = initialStatus;
    _commentsController = TextEditingController(text: initialComments);
    _pendingReasonController = TextEditingController(text: initialPending);
    _subjectController = TextEditingController(text: initialSubject);
    _requirementController = TextEditingController(text: initialRequirement);
    _suggestionController = TextEditingController(text: initialSuggestion);
    _remarksController = TextEditingController(text: initialRemarks);
    _messageType = initialMessageType;
  }

  @override
  void dispose() {
    _commentsController.dispose();
    _pendingReasonController.dispose();
    _subjectController.dispose();
    _requirementController.dispose();
    _suggestionController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    const months = [
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
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

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
        if (!_attachments.contains(cleanName)) {
          _attachments.add(cleanName);
        }
        _pendingPickedFiles.removeWhere(
          (f) => ActionService.sanitizeAttachmentFileName(f.name) == cleanName,
        );
        _pendingPickedFiles.add(picked);
      });
    } catch (e) {
      debugPrint('[ManagerActionUpdateScreen] Error picking attachment: $e');
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
      action: _currentAction,
      fileName: file,
      currentUserId: widget.currentUserId,
      isWorker: false,
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
        action: _currentAction,
        fileName: file,
        userId: widget.currentUserId,
        isManager: true,
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

  Future<void> _submitUpdate({bool submitForReview = false}) async {
    if (!_formKey.currentState!.validate()) {
      if (_selectedTabIndex != 0) {
        setState(() => _selectedTabIndex = 0);
      }
      return;
    }
    if (_isUploadingAttachments) return;

    if (submitForReview) {
      if (_progress != 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Progress must be 100% when submitting for review.'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (_allSubTasks.any((t) => !t.isCompleted)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'All assigned subtasks must be completed before submitting for review.',
            ),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final dateStr = _formatDate(_updateDate);

      final combinedAttachments = <String>[
        ..._currentAction.attachments,
        ..._attachments.where((a) => !_currentAction.attachments.contains(a)),
      ];

      final newlyAddedAttachments = _attachments
          .where((a) => !_currentAction.attachments.contains(a))
          .toList();

      final tempActionForUpload = _currentAction.copyWith(
        attachments: combinedAttachments,
      );

      final uploadOk = await _uploadPendingFiles(tempActionForUpload);
      if (!uploadOk) {
        setState(() => _isSubmitting = false);
        return;
      }

      final contribution = (_progress - _currentAction.percentComplete).clamp(
        0,
        100,
      );

      final effectiveStatus = submitForReview
          ? 'Pending Review'
          : ((_status == 'Completed' && _progress < 100)
              ? 'In Progress'
              : _status);

      final effectiveSubject = _subjectController.text.trim().isNotEmpty
          ? _subjectController.text.trim()
          : (_currentAction.subject.isNotEmpty
              ? _currentAction.subject
              : 'Progress Update');

      final progressUpdate = ActionProgressUpdate(
        id: 'update-${now.millisecondsSinceEpoch}',
        actionId: _currentAction.id,
        updatedById: widget.currentUserId ?? _currentAction.assignedToId ?? '',
        updatedByName: widget.currentUserName ?? 'Manager',
        updateDate: dateStr,
        progress: _progress,
        status: effectiveStatus,
        comments: _commentsController.text.trim(),
        attachments: newlyAddedAttachments,
        roleInAction: 'manager',
        contributionValue: contribution,
        createdAt: now,
        subject: effectiveSubject,
        messageType: _messageType,
        workCompleted: _commentsController.text.trim(),
        pendingWork: _pendingReasonController.text.trim(),
        requirement: _requirementController.text.trim(),
        suggestion: _suggestionController.text.trim(),
        remarks: _remarksController.text.trim(),
      );

      final nextHistory = [
        ..._currentAction.history,
        '$dateStr: Manager update: $_progress% ($effectiveStatus) - ${_commentsController.text.trim()}',
      ];

      final updatedAction = await ActionService.instance.submitProgressUpdate(
        actionId: _currentAction.id,
        existingUpdateId: _isEditingExisting ? _existingUpdateId : null,
        updateDate: _updateDate,
        progress: _progress,
        status: effectiveStatus,
        comments: _commentsController.text.trim(),
        contributionValue: contribution,
        attachments: combinedAttachments,
        roleInAction: 'manager',
        updatedById: widget.currentUserId ?? _currentAction.assignedToId,
        updatedByName: widget.currentUserName ?? 'Manager',
        subject: effectiveSubject,
        messageType: _messageType,
        workCompleted: _commentsController.text.trim(),
        pendingWork: _pendingReasonController.text.trim(),
        requirement: _requirementController.text.trim(),
        suggestion: _suggestionController.text.trim(),
        remarks: _remarksController.text.trim(),
        subTasks: _allSubTasks,
        history: nextHistory,
      );

      final nextProgressUpdates = _isEditingExisting
          ? _currentAction.updateProgressUpdate(progressUpdate.copyWith(id: _existingUpdateId)).progressUpdates
          : [progressUpdate, ..._currentAction.progressUpdates];

      final resultAction = updatedAction.copyWith(
        status: effectiveStatus,
        percentComplete: _progress,
        subTasks: _allSubTasks,
        attachments: combinedAttachments,
        progressUpdates: updatedAction.progressUpdates.isNotEmpty
            ? updatedAction.progressUpdates
            : nextProgressUpdates,
        history: nextHistory,
        pendingReason: _pendingReasonController.text.trim(),
        workerMessageSubject: effectiveSubject,
        messageType: _messageType,
        requirement: _requirementController.text.trim(),
        suggestion: _suggestionController.text.trim(),
        remarks: _remarksController.text.trim(),
      );
      _currentAction = resultAction;
      MockActionStore.instance.update(resultAction);

      if (ActionService.instance.client != null) {
        try {
          await ActionService.instance.updateAction(resultAction);
        } catch (e) {
          debugPrint('[ManagerActionUpdateScreen] updateAction error: $e');
        }
      }

      _attachments.clear();
      _pendingPickedFiles.clear();

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action update saved successfully.'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(resultAction);
    } catch (e) {
      debugPrint('[ManagerActionUpdateScreen] Error submitting update: $e');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to persist update to database: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to persist update to database: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 950;
    final action = widget.action;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.cardBg(context),
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary(context),
            size: 22,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.actionIdBg(context),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.actionIdBorder(context)),
              ),
              child: Text(
                action.id,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.actionIdText(context),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Update Action — Manager Portal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: const [
          ThemeToggleButton(),
          SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
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
                if (_errorMessage != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFDC2626),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                  'Action Register',
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
            'Record manager updates, review subtasks, add verified evidence, and update action progress.',
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
    final catColor = _categoryColor(_currentAction.category);
    final catIcon = _categoryIcon(_currentAction.category);
    final statusCol = _statusColor(_currentAction.status);
    final priorityCol = _priorityColor(_currentAction.priority);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isVerySmall = screenWidth < 380;

    return Container(
      padding:
          EdgeInsets.all(isVerySmall ? 10 : (screenWidth < 500 ? 12 : 18)),
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
                        _currentAction.displayId.isNotEmpty
                            ? _currentAction.displayId
                            : _currentAction.id,
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
                        _currentAction.priority,
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
                        _currentAction.status,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: statusCol,
                        ),
                      ),
                    ),
                    if (_currentAction.category.isNotEmpty)
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
                          _currentAction.category,
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
                  _currentAction.subject,
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
                      label: _currentAction.site.isNotEmpty
                          ? _currentAction.site
                          : '—',
                    ),
                    if (_currentAction.section.isNotEmpty)
                      _heroMetaItem(
                        icon: Icons.layers_outlined,
                        label: _currentAction.section,
                      ),
                    if (_currentAction.department.isNotEmpty)
                      _heroMetaItem(
                        icon: Icons.apartment_rounded,
                        label: _currentAction.department,
                      ),
                    if (_currentAction.team.isNotEmpty)
                      _heroMetaItem(
                        icon: Icons.group_outlined,
                        label: _currentAction.team,
                      ),
                    _heroMetaItem(
                      icon: Icons.calendar_today_outlined,
                      label: 'Target: ${_currentAction.targetDate}',
                    ),
                    _heroMetaItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Assigned: ${_currentAction.assignedTo}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _circularProgressIndicator(),
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

  Widget _circularProgressIndicator() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 50,
          height: 50,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: _progress / 100,
                strokeWidth: 5,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _progress == 100
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF1565C0),
                ),
              ),
              Center(
                child: Text(
                  '$_progress%',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Progress',
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.textMuted(context),
          ),
        ),
      ],
    );
  }

  Widget _tabNavigationBar() {
    final tabs = [
      {'label': 'Update', 'icon': Icons.edit_note_rounded},
      {
        'label': 'Evidence (${_attachments.length})',
        'icon': Icons.attach_file_rounded,
      },
      {
        'label': 'History (${_currentAction.history.length})',
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

  List<String> _availableStatuses() {
    const standard = [
      'In Progress',
      'Open',
      'Pending Review',
      'Under Escalation',
      'On Hold',
    ];
    if (!standard.contains(_status)) {
      return [_status, ...standard];
    }
    return standard;
  }

  List<String> _availablePercentOptions() {
    const standard = [
      '0%',
      '20%',
      '25%',
      '40%',
      '50%',
      '60%',
      '75%',
      '80%',
      '90%',
      '100%',
    ];
    final current = '$_progress%';
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
                description:
                    'Use to report progress, completed work, pending work, or delays. The action remains active in your workload.',
              );
              final col2 = _guideChip(
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF7C3AED),
                title: 'Submit for Review (Completed Work)',
                description:
                    'Use when work is 100% completed. Moves action to "Pending Review" for Manager verification.',
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

  Widget _progressAndStatusPanel() {
    return _panel(
      title: 'PROGRESS & STATUS',
      icon: Icons.sync_rounded,
      children: [
        // Row 1: Update Date & Status
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update Date *',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _updateDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() => _updateDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.containerBg(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.cardBorder(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: AppTheme.textSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(_updateDate),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status *',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    dropdownColor: AppTheme.cardBg(context),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary(context),
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.inputFill(context),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppTheme.inputBorder(context),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: AppTheme.inputBorder(context),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Color(0xFF1565C0)),
                      ),
                    ),
                    items: _availableStatuses()
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s, style: const TextStyle(fontSize: 13)),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _status = val);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_allSubTasks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
        const SizedBox(height: 16),
        // Progress Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress: $_progress% *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$_progress% Completed',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1565C0),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _select(
          '% Complete',
          '$_progress%',
          _availablePercentOptions(),
          (value) => setState(
            () => _progress = int.parse(value!.replaceAll('%', '')),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _progress == 100
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF1565C0),
                  inactiveTrackColor: AppTheme.progressTrackBg(context),
                  thumbColor: _progress == 100
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF1565C0),
                  trackHeight: 6,
                ),
                child: Slider(
                  value: _progress.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '$_progress%',
                  onChanged: (val) {
                    setState(() => _progress = val.round());
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
                '$_progress%',
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
          children: _quickChips.map((val) {
            final isSelected = _progress == val;
            return ChoiceChip(
              label: Text('$val%'),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) setState(() => _progress = val);
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
        const SizedBox(height: 10),
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
                    '$_progress%',
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
                  value: _progress / 100.0,
                  minHeight: 7,
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _progress == 100
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF1565C0),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // 100% guide / non-closure banner
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
              Icon(
                _progress == 100
                    ? Icons.task_alt_rounded
                    : Icons.info_outline_rounded,
                color: const Color(0xFF1565C0),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _progress == 100
                      ? 'Progress is set to 100%. When all requirements and evidence are ready, click "Submit for Review" below to send this action for Manager verification.\nSetting progress to 100% indicates all operational tasks are done, but does NOT automatically close the action. Actions must be formally verified.'
                      : 'Setting progress to 100% indicates all operational tasks are done, but does NOT automatically close the action. Actions must be formally verified.',
                  style: TextStyle(
                    fontSize: 12,
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
    );
  }

  Widget _tasksPanel() {
    final totalCount = _allSubTasks.length;
    final completedCount = _allSubTasks.where((t) => t.isCompleted).length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _panel(
      title: 'TASKS & CHECKLIST ($completedCount / $totalCount COMPLETED)',
      icon: Icons.checklist_rtl_rounded,
      children: [
        for (int i = 0; i < _allSubTasks.length; i++) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _allSubTasks[i].isCompleted
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
                key: Key('manager_task_checkbox_$i'),
                value: _allSubTasks[i].isCompleted,
                activeColor: const Color(0xFF16A34A),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  _allSubTasks[i].title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    decoration: _allSubTasks[i].isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: _allSubTasks[i].isCompleted
                        ? AppTheme.textMuted(context)
                        : AppTheme.textPrimary(context),
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_allSubTasks[i].instruction.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _allSubTasks[i].instruction,
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
                          'Assignee: ${_allSubTasks[i].assignedStaff.isNotEmpty ? _allSubTasks[i].assignedStaff : "Staff"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _allSubTasks[i].isCompleted
                                ? const Color(0xFF16A34A).withValues(alpha: 0.15)
                                : const Color(0xFFEA580C).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _allSubTasks[i].isCompleted
                                  ? const Color(0xFF16A34A).withValues(alpha: 0.3)
                                  : const Color(0xFFEA580C).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            _allSubTasks[i].isCompleted ? 'Completed' : 'Pending',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _allSubTasks[i].isCompleted
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFEA580C),
                            ),
                          ),
                        ),
                        if (_allSubTasks[i].isReopened)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
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
                        if (_allSubTasks[i].dueDate.isNotEmpty)
                          Text(
                            '• Due: ${_allSubTasks[i].dueDate}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        if (_allSubTasks[i].isCompleted &&
                            _allSubTasks[i].completedAt.isNotEmpty)
                          Text(
                            '• Completed: ${_allSubTasks[i].completedAt}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _allSubTasks[i] = _allSubTasks[i].copyWith(
                      status: val ? 'Completed' : 'Open',
                      completedAt: val ? DateTime.now().toIso8601String() : '',
                      completedBy: val
                          ? (widget.currentUserName ?? 'Manager')
                          : '',
                    );
                    final allDone = _allSubTasks.every((t) => t.isCompleted);
                    if (allDone) {
                      _progress = 100;
                    }
                  });
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _workCompletedRemarksPanel() {
    return _panel(
      title: 'WORK COMPLETED & PROGRESS REMARKS',
      icon: Icons.assignment_turned_in_rounded,
      children: [
        _field(
          'Update Subject *',
          _subjectController,
          hintText: 'e.g. Scaffolding inspection completed, clips replaced...',
          validator: (v) => null,
        ),
        const SizedBox(height: 12),
        _select(
          'Update Message Type',
          _messageType,
          const [
            'Progress Update',
            'Work Completed',
            'Pending Work / Delay',
            'Requirement',
            'Suggestion',
            'General Remark',
            'Completion Explanation',
          ],
          (val) {
            if (val != null) setState(() => _messageType = val);
          },
        ),
        const SizedBox(height: 12),
        _field(
          'Work Completed & Description *',
          _commentsController,
          key: const Key('manager_update_comments_field'),
          maxLines: 4,
          helperText:
              'Explain work performed, measurements taken, or assistance needed.',
          hintText:
              'Explain work performed, measurements taken, or assistance needed...',
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please provide a description of the work completed.';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _workPendingRoadblocksPanel() {
    return _panel(
      title: 'WORK PENDING & ROADBLOCKS',
      icon: Icons.pending_actions_rounded,
      children: [
        _field(
          'Work Still Pending / Next Steps',
          _pendingReasonController,
          maxLines: 2,
          helperText:
              'List any remaining steps, inspections, or pending site conditions.',
          hintText:
              'List any remaining steps, inspections, or pending site conditions...',
        ),
        const SizedBox(height: 12),
        _field(
          'Specific Equipment / Material Requirement',
          _requirementController,
          maxLines: 2,
          hintText:
              'Detail exact specifications, part numbers, or logistical support needed...',
        ),
        const SizedBox(height: 12),
        _field(
          'Suggestion for HSSE Manager',
          _suggestionController,
          maxLines: 2,
          hintText:
              'Propose long-term hazard prevention or operational improvements...',
        ),
        const SizedBox(height: 12),
        _field(
          'General Safety Remarks',
          _remarksController,
          maxLines: 2,
          hintText:
              'Observations regarding site housekeeping, weather, or contractor safety...',
        ),
      ],
    );
  }

  Widget _attachmentsPanel() {
    return _panel(
      title: 'ATTACHMENTS & EVIDENCE',
      icon: Icons.attach_file_rounded,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Attachments',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _isUploadingAttachments ? null : _pickAttachment,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add File'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                side: const BorderSide(color: Color(0xFF1565C0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
        const SizedBox(height: 8),
        if (_attachments.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No attachments added for this update.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No new documents selected for this update. (Previously attached files remain preserved in Action Details)',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          ..._attachments.map(
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
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Color(0xFFDC2626),
                    ),
                    onPressed: () {
                      setState(() {
                        _attachments.remove(file);
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
        ],
      ],
    );
  }

  Widget _editModeIndicatorBanner() {
    final hasLatest = _currentAction.latestProgressUpdateFor(
          widget.currentUserId,
          isManager: true,
        ) != null ||
        _currentAction.latestProgressUpdate != null;

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
                const Icon(
                  Icons.edit_note_rounded,
                  size: 20,
                  color: Color(0xFF1565C0),
                ),
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
                label: const Text(
                  'Log as New Update',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ),
          ];

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF1565C0).withValues(alpha: 0.3),
              ),
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
              Icon(
                Icons.add_circle_outline,
                size: 18,
                color: AppTheme.textSecondary(context),
              ),
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
                final latest = _currentAction.latestProgressUpdateFor(
                      widget.currentUserId,
                      isManager: true,
                    ) ??
                    _currentAction.latestProgressUpdate;
                if (latest != null) {
                  setState(() {
                    _isEditingExisting = true;
                    _existingUpdateId = latest.id;
                    if (latest.effectiveSubject.isNotEmpty) {
                      _subjectController.text = latest.effectiveSubject;
                    }
                    if (latest.effectiveWorkCompleted.isNotEmpty) {
                      _commentsController.text = latest.effectiveWorkCompleted;
                    }
                    if (latest.pendingWork.isNotEmpty) {
                      _pendingReasonController.text = latest.pendingWork;
                    }
                    if (latest.requirement.isNotEmpty) {
                      _requirementController.text = latest.requirement;
                    }
                    if (latest.suggestion.isNotEmpty) {
                      _suggestionController.text = latest.suggestion;
                    }
                    if (latest.remarks.isNotEmpty) {
                      _remarksController.text = latest.remarks;
                    }
                    _progress = latest.progress.clamp(0, 100);
                    if (_validStatuses.contains(latest.status)) {
                      _status = latest.status;
                    }
                    if (latest.messageType.isNotEmpty) {
                      _messageType = latest.messageType;
                    }
                  });
                }
              },
              icon: const Icon(Icons.edit_note_rounded, size: 14),
              label: const Text(
                'Edit Latest Saved Update',
                style: TextStyle(fontSize: 11.5),
              ),
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
        _progressAndStatusPanel(),
        const SizedBox(height: 16),
        if (_isLoadingSubtasks) ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ] else if (_allSubTasks.isNotEmpty) ...[
          if (_subtaskLoadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _subtaskLoadError!,
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
          _tasksPanel(),
          const SizedBox(height: 16),
        ],
        _workCompletedRemarksPanel(),
        const SizedBox(height: 16),
        _workPendingRoadblocksPanel(),
        const SizedBox(height: 16),
        _attachmentsPanel(),
      ],
    );
  }

  Widget _tabEvidenceContent() {
    final evidenceList = _currentAction.allClassifiedEvidence;
    final classifiedNames = evidenceList.map((e) => e.fileName).toSet();
    final allEvidence = List<ActionEvidenceItem>.from(evidenceList);
    for (final att in _currentAction.attachments) {
      final clean = att.trim();
      if (clean.isNotEmpty && !classifiedNames.contains(clean)) {
        classifiedNames.add(clean);
        allEvidence.add(
          ActionEvidenceItem(
            fileName: clean,
            fileType: ActionEvidenceItem.resolveFileType(clean),
            classification: EvidenceClassification.originalActionDocument,
            uploadedBy: _currentAction.assignedBy.isNotEmpty
                ? _currentAction.assignedBy
                : 'Manager',
            uploaderRole: 'manager',
            uploadedAt:
                _currentAction.createdAt ?? _currentAction.createdDateTime,
            actionId: _currentAction.id,
          ),
        );
      }
    }

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
                label: const Text('Add File'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_attachments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Column(
                children: [
                  Text(
                    'No attachments added for this update.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'No new documents selected for this update.\n(Previously attached documents remain preserved in Action Details)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._attachments.map(
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
                        _attachments.remove(file);
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
        // PREVIOUSLY SUBMITTED EVIDENCE
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
              'PREVIOUSLY SUBMITTED EVIDENCE (${allEvidence.length})',
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
        if (allEvidence.isEmpty)
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
                    'No previously submitted evidence for this action.',
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
          ...allEvidence.map((ev) {
            final isPdf = ev.fileName.toLowerCase().endsWith('.pdf');
            final isImg = ev.fileName.toLowerCase().endsWith('.jpg') ||
                ev.fileName.toLowerCase().endsWith('.png') ||
                ev.fileName.toLowerCase().endsWith('.jpeg');
            final tagColor = ev.isOriginal
                ? const Color(0xFF64748B)
                : (ev.isManagerUpdate
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF059669));

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
                                ev.classificationLabel,
                                style: TextStyle(
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
                          '${ev.fileType} • Submitted by ${ev.uploadedBy.isNotEmpty ? ev.uploadedBy : (ev.isManagerUpdate ? "Manager" : "Staff")} (${ev.uploaderRole})${ev.uploadedAt != null ? " • ${ActionRecord.formatDateForUi(ev.uploadedAt)}" : ""}',
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
    final historyList = _currentAction.history;

    return _panel(
      title: 'ACTIVITY LOG & PROGRESS UPDATES HISTORY',
      icon: Icons.history_rounded,
      children: [
        if (historyList.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No activity history logged yet.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textMuted(context),
                ),
              ),
            ),
          )
        else
          ...historyList.reversed.map((entry) {
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
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    size: 18,
                    color: Color(0xFF1565C0),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textPrimary(context),
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
                onPressed: () => Navigator.of(context).maybePop(),
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
                  'Cancel',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _submitUpdate(submitForReview: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  side: const BorderSide(color: Color(0xFF7C3AED), width: 1.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.check_circle_rounded, size: 16),
                label: const Text(
                  'Submit for Review',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _submitUpdate(submitForReview: false),
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
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 16),
                label: const Text(
                  'Save Update',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sidebarColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _quickActionsCard(),
        const SizedBox(height: 14),
        _actionSummaryDetailsCard(),
      ],
    );
  }

  Widget _quickActionsCard() {
    return _panel(
      title: 'QUICK ACTIONS',
      icon: Icons.bolt_rounded,
      children: [
        _quickActionButton(
          icon: Icons.check_circle_outline_rounded,
          label: 'Mark as Complete (100%)',
          color: const Color(0xFF16A34A),
          onTap: () {
            setState(() {
              _progress = 100;
              _selectedTabIndex = 0;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Progress set to 100%. Ready for review.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        _quickActionButton(
          icon: Icons.attach_file_rounded,
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
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionSummaryDetailsCard() {
    return _panel(
      title: 'ACTION DETAILS SUMMARY',
      icon: Icons.info_outline_rounded,
      children: [
        _summaryRow('Action ID', _currentAction.id),
        _summaryRow('Priority', _currentAction.priority),
        _summaryRow('Category', _currentAction.category),
        _summaryRow('Status', _status),
        _summaryRow(
          'Site / Location',
          _currentAction.site.isNotEmpty ? _currentAction.site : '—',
        ),
        _summaryRow('Section', _currentAction.section),
        _summaryRow('Department', _currentAction.department),
        _summaryRow('Teams', _currentAction.team),
        _summaryRow('Target Date', _currentAction.targetDate),
        _summaryRow('Assigned To', _currentAction.assignedTo),
        _summaryRow('Assigned By', _currentAction.assignedBy),
        _summaryRow('Progress', '$_progress%'),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.textMuted(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
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
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    Key? key,
    int maxLines = 1,
    String? helperText,
    String? hintText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(fontSize: 13.5, color: AppTheme.textPrimary(context)),
      validator: validator ??
          (label.endsWith('*')
              ? (value) => value == null || value.trim().isEmpty
                  ? 'Please enter $label'
                  : null
              : null),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 13,
          color: AppTheme.textSecondary(context),
        ),
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 12.5,
          color: AppTheme.textMuted(context),
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
      initialValue: values.contains(value)
          ? value
          : (values.isNotEmpty ? values.first : null),
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
            (v) => DropdownMenuItem(
              value: v,
              child: Text(
                v,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'closed':
        return const Color(0xFF16A34A);
      case 'in progress':
        return const Color(0xFF0284C7);
      case 'pending review':
        return const Color(0xFFD97706);
      case 'overdue':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF64748B);
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
      case 'high':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF16A34A);
    }
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'safety':
      case 'inspection':
        return Icons.verified_user_rounded;
      case 'equipment':
        return Icons.handyman_rounded;
      case 'environmental':
        return Icons.eco_rounded;
      default:
        return Icons.assignment_turned_in_rounded;
    }
  }

  Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'safety':
        return const Color(0xFFDC2626);
      case 'inspection':
        return const Color(0xFF1565C0);
      case 'equipment':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF059669);
    }
  }
}
