import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/action_record.dart';
import 'package:action_flow/features/external_update/models/external_action_payload.dart';
import 'package:action_flow/features/external_update/services/external_action_service.dart';
import 'package:action_flow/widgets/common/action_flow_logo.dart';
import 'package:action_flow/widgets/common/theme_toggle_button.dart';
import 'package:flutter/material.dart';

/// Dedicated, responsive external contractor update portal.
/// Accessible via secure token link without creating an ActionFlow account.
class ExternalActionUpdateScreen extends StatefulWidget {
  const ExternalActionUpdateScreen({
    super.key,
    required this.token,
    this.initialPayload,
  });

  final String token;
  final ExternalActionPayload? initialPayload;

  @override
  State<ExternalActionUpdateScreen> createState() =>
      _ExternalActionUpdateScreenState();
}

class _ExternalActionUpdateScreenState
    extends State<ExternalActionUpdateScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  String? _loadError;
  bool _isExpired = false;
  bool _isRevoked = false;

  ExternalActionPayload? _actionData;
  final List<ActionSubTask> _subTasks = [];

  // Form State
  late int _progress;
  late String _status;
  late final TextEditingController _commentsController;
  final List<String> _attachments = [];

  bool _isSubmitting = false;
  bool _submitSuccess = false;
  String? _submitError;
  DateTime? _submittedAt;

  static const List<String> _allowedStatuses = [
    'In Progress',
    'Open',
    'Pending Review',
    'Under Escalation',
    'On Hold',
  ];

  @override
  void initState() {
    super.initState();
    _commentsController = TextEditingController();

    if (widget.initialPayload != null) {
      _actionData = widget.initialPayload;
      if (_actionData!.subTasks.isNotEmpty) {
        _subTasks.addAll(_actionData!.subTasks);
      }
      _progress = _actionData!.percentComplete.clamp(0, 100);
      _status = _allowedStatuses.contains(_actionData!.status)
          ? _actionData!.status
          : 'In Progress';
      _isLoading = false;
      MockExternalActionStore.instance.registerToken(
        rawToken: widget.token,
        payload: _actionData!,
      );
    } else {
      _loadActionDetails();
    }
  }

  @override
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _loadActionDetails() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _isExpired = false;
      _isRevoked = false;
    });

    final result = await ExternalActionService.instance.fetchActionByToken(
      widget.token,
    );

    if (!mounted) return;

    if (result is ExternalActionFetchSuccess) {
      setState(() {
        _actionData = result.payload;
        _subTasks.clear();
        if (result.payload.subTasks.isNotEmpty) {
          _subTasks.addAll(result.payload.subTasks);
        }
        _progress = result.payload.percentComplete.clamp(0, 100);
        _status = _allowedStatuses.contains(result.payload.status)
            ? result.payload.status
            : 'In Progress';
        _isLoading = false;
      });
    } else if (result is ExternalActionFetchFailure) {
      setState(() {
        _loadError = result.errorMessage;
        _isExpired = result.isExpired;
        _isRevoked = result.isRevoked;
        _isLoading = false;
      });
    }
  }

  Future<void> _submitUpdate() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final result = await ExternalActionService.instance.submitProgressUpdate(
      rawToken: widget.token,
      progress: _progress,
      status: _status,
      comments: _commentsController.text.trim(),
      attachments: _attachments,
    );

    if (!mounted) return;

    if (result is ExternalActionSubmitSuccess) {
      setState(() {
        _isSubmitting = false;
        _submitSuccess = true;
        _submittedAt = result.submittedAt;
      });
    } else if (result is ExternalActionSubmitFailure) {
      setState(() {
        _isSubmitting = false;
        _submitError = result.errorMessage;
      });
    }
  }

  void _addAttachmentDialog() {
    final nameController = TextEditingController(
      text: 'Proof_of_Work_${_attachments.length + 1}.pdf',
    );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppTheme.cardBg(dialogCtx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Attach Document or Photo',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(dialogCtx),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the document filename or photo reference:',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary(dialogCtx),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textPrimary(dialogCtx),
                ),
                decoration: InputDecoration(
                  labelText: 'Attachment Name',
                  hintText: 'e.g. Valve_Test_Report.pdf',
                  prefixIcon: const Icon(Icons.attachment_rounded, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppTheme.textSecondary(dialogCtx)),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final val = nameController.text.trim();
                if (val.isNotEmpty) {
                  setState(() => _attachments.add(val));
                }
                Navigator.of(dialogCtx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Add Attachment'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SafeArea(
            child: Row(
              children: [
                ActionFlowBrand(logoSize: 32, fontSize: 18, isDark: isDark),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Contractor Portal',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
                const Spacer(),
                const ThemeToggleButton(),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: _buildBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1565C0)),
            ),
            const SizedBox(height: 16),
            Text(
              'Verifying secure access token...',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    if (_loadError != null || _actionData == null) {
      return _buildErrorState(context);
    }

    if (_submitSuccess) {
      return _buildSuccessState(context);
    }

    return _buildFormState(context);
  }

  Widget _buildErrorState(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.link_off_rounded,
                  size: 48,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isExpired
                    ? 'Access Link Has Expired'
                    : (_isRevoked
                        ? 'Access Link Revoked'
                        : 'Invalid Access Token'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _loadError ??
                    'The link you followed is invalid, has expired, or was revoked by the ActionFlow Manager.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.help_outline_rounded,
                      size: 20,
                      color: Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Please request a fresh action update link from your ActionFlow manager.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _loadActionDetails,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry Verification'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessState(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 48,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Progress Update Submitted Successfully',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your progress report has been saved and is now visible to the ActionFlow Manager.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 24),

              // Summary Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow(
                      context,
                      'Action ID',
                      _actionData?.actionNumber ?? '',
                    ),
                    const Divider(height: 16),
                    _buildSummaryRow(
                      context,
                      'Reported Progress',
                      '$_progress%',
                    ),
                    const Divider(height: 16),
                    _buildSummaryRow(context, 'New Status', _status),
                    if (_attachments.isNotEmpty) ...[
                      const Divider(height: 16),
                      _buildSummaryRow(
                        context,
                        'Attachments',
                        '${_attachments.length} file(s)',
                      ),
                    ],
                    if (_submittedAt != null) ...[
                      const Divider(height: 16),
                      _buildSummaryRow(
                        context,
                        'Submission Time',
                        '${_formatDate(_submittedAt!)} ${_submittedAt!.hour.toString().padLeft(2, '0')}:${_submittedAt!.minute.toString().padLeft(2, '0')}',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _submitSuccess = false;
                    _commentsController.clear();
                    _attachments.clear();
                  });
                },
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Submit Another Update'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary(context),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildFormState(BuildContext context) {
    final action = _actionData!;
    final isDark = AppTheme.isDark(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Expiry & Security Badge Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF2563EB).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Secure External Access • Single Action View • Token valid until ${action.expiresAt != null ? _formatDate(action.expiresAt!) : 'Expiry'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E40AF),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Action Details Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.cardBorder(context)),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : const Color(0x060F172A),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Meta row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
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
                        action.actionNumber,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.actionIdText(context),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _buildBadge(context, action.priority, _getPriorityColor(action.priority)),
                        const SizedBox(width: 8),
                        _buildBadge(context, action.status, _getStatusColor(action.status)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Title
                Text(
                  action.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),

                // Organization & Location
                Text(
                  '${action.organizationName} • ${action.department}${action.site.isNotEmpty ? ' • ${action.site}' : ''}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 16),

                // Action Required Box
                if (action.actionRequired.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(color: Color(0xFFF59E0B), width: 3.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Action Required / Scope of Work:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB45309),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          action.actionRequired,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: isDark ? Colors.white70 : const Color(0xFF78350F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Progress Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Current Completion:',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                    Text(
                      '${action.percentComplete}%',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (action.percentComplete / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF1565C0),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Due Date & Recipient Details
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_outlined,
                                size: 16,
                                color: AppTheme.textSecondary(context),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Due: ${action.dueDate.isNotEmpty ? action.dueDate : action.targetDate}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person_pin_outlined,
                                size: 16,
                                color: Color(0xFFEA580C),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Recipient: ${action.recipientName}${action.companyName.isNotEmpty ? ' (${action.companyName})' : ''}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Update Submission Form
          Form(
            key: _formKey,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submit Work Update',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Record progress, update the status, and provide notes for the manager.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 18),

                  if (_subTasks.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.cardBorder(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.checklist_rtl_rounded,
                                size: 18,
                                color: Color(0xFF1565C0),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'ASSIGNED TASKS (${_subTasks.where((t) => t.isCompleted).length} / ${_subTasks.length} COMPLETED)',
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
                          const SizedBox(height: 10),
                          for (int i = 0; i < _subTasks.length; i++) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _subTasks[i].isCompleted
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
                                  key: Key('external_task_checkbox_$i'),
                                  value: _subTasks[i].isCompleted,
                                  activeColor: const Color(0xFF16A34A),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: Text(
                                    _subTasks[i].title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      decoration: _subTasks[i].isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: _subTasks[i].isCompleted
                                          ? AppTheme.textMuted(context)
                                          : AppTheme.textPrimary(context),
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Assignee: ${_subTasks[i].assignedStaff} [External]'
                                    '${_subTasks[i].dueDate.isNotEmpty ? " • Due: ${_subTasks[i].dueDate}" : ""}'
                                    '${_subTasks[i].isCompleted && _subTasks[i].completedAt.isNotEmpty ? " • Completed: ${_subTasks[i].completedAt}" : ""}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.textSecondary(context),
                                    ),
                                  ),
                                  onChanged: (checked) async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    final now = DateTime.now();
                                    final nowStr = _formatDate(now);
                                    final targetTaskId = _subTasks[i].id;
                                    final prevStatus = _subTasks[i].status;
                                    final prevCompletedAt = _subTasks[i].completedAt;
                                    final prevCompletedBy = _subTasks[i].completedBy;
                                    final prevProgress = _progress;

                                    setState(() {
                                      if (checked == true) {
                                        _subTasks[i] = _subTasks[i].copyWith(
                                          status: 'Completed',
                                          completedAt: nowStr,
                                          completedBy: action.recipientName,
                                        );
                                      } else {
                                        _subTasks[i] = _subTasks[i].copyWith(
                                          status: 'Open',
                                          completedAt: '',
                                          completedBy: '',
                                        );
                                      }
                                      final newCompleted =
                                          _subTasks.where((t) => t.isCompleted).length;
                                      _progress = ((newCompleted / _subTasks.length) * 100).round();
                                    });

                                    try {
                                      final res = await ExternalActionService.instance.submitSubtaskToggle(
                                        rawToken: widget.token,
                                        taskId: targetTaskId,
                                        isCompleted: checked == true,
                                      );

                                      if (res['success'] == true) {
                                        if (res['percent_complete'] != null) {
                                          setState(() {
                                            _progress = (res['percent_complete'] as num).toInt();
                                          });
                                        }
                                      } else {
                                        setState(() {
                                          _subTasks[i] = _subTasks[i].copyWith(
                                            status: prevStatus,
                                            completedAt: prevCompletedAt,
                                            completedBy: prevCompletedBy,
                                          );
                                          _progress = prevProgress;
                                        });
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(res['error']?.toString() ?? 'Failed to update task'),
                                              backgroundColor: const Color(0xFFDC2626),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      setState(() {
                                        _subTasks[i] = _subTasks[i].copyWith(
                                          status: prevStatus,
                                          completedAt: prevCompletedAt,
                                          completedBy: prevCompletedBy,
                                        );
                                        _progress = prevProgress;
                                      });
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text('Failed to update task: $e'),
                                            backgroundColor: const Color(0xFFDC2626),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // Progress Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _subTasks.isNotEmpty
                            ? 'Progress (Derived from tasks):'
                            : 'Reported Progress (%):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$_progress%',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_subTasks.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: Color(0xFF1565C0),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Progress is automatically calculated from task completion ($_progress%). Check or uncheck tasks above to update.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF1565C0),
                      thumbColor: const Color(0xFF1565C0),
                      overlayColor: const Color(0xFF1565C0).withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      value: _progress.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '$_progress%',
                      onChanged: _subTasks.isNotEmpty
                          ? null
                          : (val) {
                              setState(() => _progress = val.round());
                            },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Status Dropdown
                  Text(
                    'Update Status:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    isExpanded: true,
                    dropdownColor: AppTheme.cardBg(context),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.textPrimary(context),
                    ),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: _allowedStatuses.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(s),
                      );
                    }).toList(),
                    onChanged: (newVal) {
                      if (newVal != null) {
                        setState(() => _status = newVal);
                      }
                    },
                  ),
                  const SizedBox(height: 18),

                  // Notes / Comments
                  Text(
                    'Work Update Notes / Evidence *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _commentsController,
                    maxLines: 4,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.textPrimary(context),
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Describe work completed, testing conducted, or blockers encountered...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary(context),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please provide update notes describing your progress.';
                      }
                      if (val.trim().length < 5) {
                        return 'Update notes must be at least 5 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  // Attachments Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Attached Photos / Documents:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addAttachmentDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add File Reference'),
                      ),
                    ],
                  ),
                  if (_attachments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'No attachments added yet.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _attachments.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final name = entry.value;
                        return Chip(
                          label: Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () {
                            setState(() => _attachments.removeAt(idx));
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 24),

                  if (_submitError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _submitError!,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Submit Progress Update',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildBadge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
        return const Color(0xFFDC2626);
      case 'high':
        return const Color(0xFFEA580C);
      case 'medium':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF16A34A);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return const Color(0xFF2563EB);
      case 'in progress':
        return const Color(0xFF0284C7);
      case 'pending review':
        return const Color(0xFF7C3AED);
      case 'under escalation':
        return const Color(0xFFDC2626);
      case 'on hold':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF16A34A);
    }
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
    final d = dt.day.toString().padLeft(2, '0');
    final m = months[dt.month - 1];
    return '$d $m ${dt.year}';
  }
}
