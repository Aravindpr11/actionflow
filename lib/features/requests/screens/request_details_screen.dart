import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/document_preview/request_attachment_preview_dialog.dart';
import '../models/request_models.dart';
import '../services/request_service.dart';
import '../widgets/forward_request_dialog.dart';

/// Screen providing comprehensive inspection, workflow visualization,
/// approval decision recording, forwarding, and audit timeline for an ActionFlow Request.
class RequestDetailsScreen extends StatefulWidget {
  const RequestDetailsScreen({
    super.key,
    required this.requestId,
    this.initialRequest,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole,
    this.currentUserEmail = '',
    required this.organizationId,
    this.isManager = false,
    this.onBack,
  });

  final String requestId;
  final RequestRecord? initialRequest;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final String currentUserEmail;
  final String organizationId;
  final bool isManager;
  final VoidCallback? onBack;

  @override
  State<RequestDetailsScreen> createState() => _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends State<RequestDetailsScreen> {
  RequestRecord? _request;
  bool _isLoading = true;
  bool _isDeleting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _request = widget.initialRequest;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = _request == null;
      _errorMessage = null;
    });

    try {
      final req = await RequestService.instance.getRequestDetails(widget.requestId);
      if (mounted) {
        setState(() {
          _request = req;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load request details: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ===========================================================================
  // DECISION ACTIONS
  // ===========================================================================
  Future<void> _handleApprove() async {
    final req = _request;
    if (req == null) return;

    final commentController = TextEditingController();
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_outline_rounded,
                        color: Color(0xFF16A34A), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text('Approve Request'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirm approval for request ${req.displayId}: "${req.title}".',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      req.isSequential
                          ? 'This will record your step approval and advance the workflow.'
                          : 'Parallel workflow: Your approval will be recorded alongside other assigned approvers.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Approval Comments (Optional)',
                        hintText: 'Add any notes, conditions, or instructions...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          try {
                            await RequestService.instance.recordApprovalDecision(
                              requestId: req.id,
                              decision: 'Approved',
                              comments: commentController.text.trim(),
                              currentUserId: widget.currentUserId,
                              currentUserName: widget.currentUserName,
                              currentUserRole: widget.currentUserRole,
                            );
                            if (dialogCtx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Request ${req.displayId} successfully approved.'),
                                  backgroundColor: const Color(0xFF16A34A),
                                ),
                              );
                              _loadDetails();
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (dialogCtx.mounted) {
                              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to record approval: $e'),
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                              );
                            }
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Confirm Approval'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
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

  Future<void> _handleReject() async {
    final req = _request;
    if (req == null) return;

    final reasonController = TextEditingController();
    String? validationError;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cancel_outlined,
                        color: Color(0xFFDC2626), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text('Reject Request'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You are rejecting request ${req.displayId}: "${req.title}".',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Rejection will terminate this workflow. A clear, specific justification is mandatory.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonController,
                      maxLines: 3,
                      onChanged: (_) {
                        if (validationError != null) {
                          setDialogState(() => validationError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Rejection Reason (Required) *',
                        hintText: 'Specify reasons for refusal...',
                        errorText: validationError,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) {
                            setDialogState(() {
                              validationError = 'Rejection reason is mandatory.';
                            });
                            return;
                          }

                          setDialogState(() => isSubmitting = true);
                          try {
                            await RequestService.instance.recordApprovalDecision(
                              requestId: req.id,
                              decision: 'Rejected',
                              comments: reason,
                              currentUserId: widget.currentUserId,
                              currentUserName: widget.currentUserName,
                              currentUserRole: widget.currentUserRole,
                            );
                            if (dialogCtx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Request ${req.displayId} has been rejected.'),
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                              );
                              _loadDetails();
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (dialogCtx.mounted) {
                              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to reject request: $e'),
                                  backgroundColor: const Color(0xFFDC2626),
                                ),
                              );
                            }
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Confirm Rejection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
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

  void _openForwardDialog() {
    final req = _request;
    if (req == null) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => ForwardRequestDialog(
        request: req,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserRole: widget.currentUserRole,
        organizationId: widget.organizationId,
        onForwardSuccess: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Request ${req.displayId} forwarded successfully.'),
              backgroundColor: const Color(0xFF16A34A),
            ),
          );
          _loadDetails();
        },
      ),
    );
  }

  Future<void> _handleComplete() async {
    final req = _request;
    if (req == null) return;

    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Request as Completed'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to mark ${req.displayId} as Completed? This confirms all requested permits, equipment, or access have been executed and closed.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Completion Notes (Optional)',
                  hintText: 'Enter closure remarks...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Completion'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await RequestService.instance.completeRequest(
        requestId: req.id,
        notes: notesController.text.trim(),
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserRole: widget.currentUserRole,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request ${req.displayId} marked Completed.'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
        _loadDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete request: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteRequest(RequestRecord req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFDC2626), size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Permanently Delete Request?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to permanently delete request ${req.displayId} ("${req.title}")?',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action is permanent and cannot be undone. All approval records, audit history, and exclusive attachments will be permanently removed.',
                        style: TextStyle(color: Color(0xFF991B1B), fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            key: const Key('confirm_delete_request_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Permanently Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final result = await RequestService.instance.deleteApprovedRequest(requestId: req.id);
      if (result.success && mounted) {
        final message = result.queuedStorageFilesCount > 0
            ? 'Request ${req.displayId} has been permanently deleted. ${result.queuedStorageFilesCount} attachment(s) queued for secure storage cleanup.'
            : 'Request ${req.displayId} has been permanently deleted.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete request: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  bool get _isRequester {
    final req = _request;
    if (req == null) return false;
    final authUid = SupabaseConfig.clientOrNull?.auth.currentUser?.id;
    return req.createdBy == widget.currentUserId ||
        (authUid != null && req.createdBy == authUid);
  }

  void _handlePreviewAttachment(RequestAttachmentRecord att) {
    RequestAttachmentPreviewDialog.show(context, attachment: att);
  }

  Future<void> _handleDownloadAttachment(RequestAttachmentRecord att) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading "${att.fileName}"...'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final saved = await RequestService.instance.downloadAttachment(
        attachment: att,
      );

      if (mounted && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded "${att.fileName}" successfully.'),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Fallback: copy signed URL to clipboard if file saving encounters restriction
        try {
          final url = await RequestService.instance.getAttachmentDownloadUrl(att.filePath);
          _copyToClipboard(url, 'Secure Attachment URL');
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to download attachment: $e'),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _showResubmitDialog(RequestRecord req) async {
    final responseCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: req.additionalNotes);
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: AppTheme.cardBg(ctx),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.replay_rounded,
                    color: Color(0xFFDC2626),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Respond & Resubmit Request',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(ctx),
                        ),
                      ),
                      Text(
                        req.displayId,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(ctx),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Approver's Rejection Feedback Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.feedback_outlined, size: 16, color: Color(0xFFDC2626)),
                              SizedBox(width: 6),
                              Text(
                                'Rejection Feedback',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            req.rejectionReason ?? 'No reason provided by approver.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary(ctx),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Response TextField
                    TextField(
                      controller: responseCtrl,
                      maxLines: 3,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Your Response / Adjustments *',
                        hintText: 'Describe how you addressed the approver\'s feedback...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Additional Notes TextField
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Updated Additional Notes (Optional)',
                        hintText: 'Any extra details or context...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                ),
                icon: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(isSubmitting ? 'Resubmitting...' : 'Resubmit Request'),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final comment = responseCtrl.text.trim();
                        if (comment.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a response explaining the adjustments made.'),
                              backgroundColor: Color(0xFFDC2626),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);
                        try {
                          await RequestService.instance.resubmitRequest(
                            requestId: req.id,
                            currentUserId: widget.currentUserId,
                            currentUserName: widget.currentUserName,
                            currentUserRole: widget.currentUserRole,
                            comments: comment,
                            additionalNotes: notesCtrl.text.trim(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Request resubmitted successfully for review.'),
                                backgroundColor: Color(0xFF16A34A),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            _loadDetails();
                          }
                        } catch (err) {
                          if (ctx.mounted) {
                            setDialogState(() => isSubmitting = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('Failed to resubmit request: $err'),
                                backgroundColor: const Color(0xFFDC2626),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final req = _request;

    if (_isLoading && req == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null && req == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _handleBack,
          ),
          title: const Text('Request Details'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFDC2626)),
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Color(0xFFDC2626))),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadDetails, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (req == null) {
      return const Scaffold(
        body: Center(child: Text('Request not found.')),
      );
    }

    final canIApprove = req.canUserApprove(widget.currentUserId);

    return Scaffold(
      appBar: _buildAppBar(context, req, canIApprove),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Request Details & Attachments (60%)
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildOverviewCard(context, req, isDark),
                            const SizedBox(height: 16),
                            _buildAttachmentsCard(context, req, isDark),
                            if (req.forwards.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildForwardingHistoryCard(context, req, isDark),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Right Column: Workflow Steps & Timeline (40%)
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildWorkflowCard(context, req, isDark),
                            const SizedBox(height: 16),
                            _buildAuditTimelineCard(context, req, isDark),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                // Narrow / Mobile Layout
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOverviewCard(context, req, isDark),
                    const SizedBox(height: 16),
                    _buildWorkflowCard(context, req, isDark),
                    const SizedBox(height: 16),
                    _buildAttachmentsCard(context, req, isDark),
                    if (req.forwards.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildForwardingHistoryCard(context, req, isDark),
                    ],
                    const SizedBox(height: 16),
                    _buildAuditTimelineCard(context, req, isDark),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // APP BAR
  // ===========================================================================
  PreferredSizeWidget _buildAppBar(BuildContext context, RequestRecord req, bool canIApprove) {
    return AppBar(
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: 'Back',
        onPressed: _handleBack,
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
            ),
            child: Text(
              req.displayId,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              req.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
          onPressed: _loadDetails,
        ),
        IconButton(
          icon: const Icon(Icons.forward_to_inbox_rounded),
          tooltip: 'Forward Request',
          onPressed: _openForwardDialog,
        ),
        if (req.isRejected && _isRequester) ...[
          ElevatedButton.icon(
            onPressed: () => _showResubmitDialog(req),
            icon: const Icon(Icons.replay_rounded, size: 16),
            label: const Text('Resubmit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (canIApprove) ...[
          OutlinedButton.icon(
            onPressed: _handleReject,
            icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFDC2626)),
            label: const Text('Reject', style: TextStyle(color: Color(0xFFDC2626))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFDC2626)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _handleApprove,
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (req.canUserComplete(
          widget.currentUserId,
          isManager: widget.isManager,
          isCompanyAdmin: widget.currentUserRole.toLowerCase().contains('admin'),
          isScoped: widget.isManager,
        )) ...[
          ElevatedButton.icon(
            onPressed: _handleComplete,
            icon: const Icon(Icons.task_alt_rounded, size: 16),
            label: const Text('Mark Completed'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (req.canUserDelete(
          widget.currentUserId,
          isManager: widget.isManager,
          isCompanyAdmin: widget.currentUserRole.toLowerCase().contains('admin'),
          isScoped: widget.isManager,
        )) ...[
          ElevatedButton.icon(
            key: const Key('delete_request_button'),
            onPressed: _isDeleting ? null : () => _handleDeleteRequest(req),
            icon: const Icon(Icons.delete_forever_rounded, size: 16),
            label: const Text('Delete Request'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
        ],
        const SizedBox(width: 8),
      ],
    );
  }

  // ===========================================================================
  // 1. OVERVIEW & SPECIFICATION CARD
  // ===========================================================================
  Widget _buildOverviewCard(BuildContext context, RequestRecord req, bool isDark) {
    final statusColor = RequestStatus.getColor(req.status);
    final priorityColor = RequestPriority.getColor(req.priority);
    final typeColor = RequestType.getColor(req.requestType);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badges Row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Request Type
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(RequestType.getIcon(req.requestType), size: 14, color: typeColor),
                    const SizedBox(width: 6),
                    Text(
                      req.requestType,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: typeColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Priority
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: priorityColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: priorityColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${req.priority} Priority',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: priorityColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(RequestStatus.getIcon(req.status), size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      req.status,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Rejection Banner (if rejected)
          if (req.isRejected) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Request Rejected',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    req.rejectionReason ?? 'No reason provided.',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  if (_isRequester) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: const Text('Respond & Resubmit Request'),
                      onPressed: () => _showResubmitDialog(req),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Completion Banner (if completed)
          if (req.isCompleted) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.task_alt_rounded, color: Color(0xFF0284C7), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Request execution has been finalized and marked as Completed.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0284C7),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Title
          SelectableText(
            req.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Description
          const Text(
            'DETAILED DESCRIPTION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            req.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Specifications Table
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _buildInfoItem(
                context,
                label: 'Requester',
                value: '${req.createdByName} (${req.createdByRole})',
                icon: Icons.person_outline_rounded,
              ),
              _buildInfoItem(
                context,
                label: 'Requester Email',
                value: req.createdByEmail.isNotEmpty ? req.createdByEmail : 'N/A',
                icon: Icons.email_outlined,
              ),
              _buildInfoItem(
                context,
                label: 'Department',
                value: req.departmentName.isNotEmpty ? req.departmentName : 'All Departments',
                icon: Icons.business_outlined,
              ),
              _buildInfoItem(
                context,
                label: 'Site / Facility',
                value: req.siteName.isNotEmpty ? req.siteName : 'All Sites',
                icon: Icons.location_on_outlined,
              ),
              _buildInfoItem(
                context,
                label: 'Required Date & Time',
                value: '${req.requiredByDate}${req.requiredByTime.isNotEmpty ? " at ${req.requiredByTime}" : ""}',
                icon: Icons.schedule_rounded,
              ),
              _buildInfoItem(
                context,
                label: 'Date Submitted',
                value: req.createdAt != null
                    ? '${req.createdAt!.year}-${req.createdAt!.month.toString().padLeft(2, '0')}-${req.createdAt!.day.toString().padLeft(2, '0')} ${req.createdAt!.hour.toString().padLeft(2, '0')}:${req.createdAt!.minute.toString().padLeft(2, '0')}'
                    : 'N/A',
                icon: Icons.history_rounded,
              ),
            ],
          ),

          if (req.additionalNotes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              'ADDITIONAL NOTES / INSTRUCTIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              req.additionalNotes,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppTheme.textSecondary(context)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. ATTACHMENTS CARD
  // ===========================================================================
  Widget _buildAttachmentsCard(BuildContext context, RequestRecord req, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              const Icon(Icons.attach_file_rounded, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Attachments',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${req.attachments.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (req.attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No supporting files attached to this request.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: req.attachments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final att = req.attachments[index];
                return InkWell(
                  onTap: () => _handlePreviewAttachment(att),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.cardBorder(context)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            att.isPdf
                                ? Icons.picture_as_pdf_outlined
                                : (att.isImage
                                    ? Icons.image_outlined
                                    : Icons.insert_drive_file_outlined),
                            size: 20,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                att.fileName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${att.formattedSize} • ${att.contentType.isNotEmpty ? att.contentType : 'Attachment'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 20),
                          tooltip: 'Preview Attachment',
                          onPressed: () => _handlePreviewAttachment(att),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download_rounded, size: 20),
                          tooltip: 'Download Attachment',
                          onPressed: () => _handleDownloadAttachment(att),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. FORWARDING HISTORY CARD
  // ===========================================================================
  Widget _buildForwardingHistoryCard(BuildContext context, RequestRecord req, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              const Icon(Icons.forward_to_inbox_rounded, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Forwarding History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${req.forwards.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF7C3AED),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: req.forwards.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final fwd = req.forwards[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.arrow_right_alt_rounded,
                            size: 18, color: Color(0xFF7C3AED)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).textTheme.bodyMedium?.color,
                              ),
                              children: [
                                TextSpan(
                                  text: fwd.fromUserName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const TextSpan(text: ' forwarded to '),
                                TextSpan(
                                  text: fwd.toUserName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (fwd.createdAt != null)
                          Text(
                            '${fwd.createdAt!.month}/${fwd.createdAt!.day} ${fwd.createdAt!.hour}:${fwd.createdAt!.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                      ],
                    ),
                    if (fwd.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Note: "${fwd.notes}"',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 4. APPROVAL WORKFLOW STEPPER CARD
  // ===========================================================================
  Widget _buildWorkflowCard(BuildContext context, RequestRecord req, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Approval Chain',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  req.approvalType,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            req.isSequential
                ? 'Sequential: Approvals are evaluated step-by-step in designated order.'
                : 'Parallel: All approvers sign off concurrently and independently.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
          ),
          const SizedBox(height: 16),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: req.approvalProgressFraction,
              minHeight: 8,
              backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                req.isApproved
                    ? const Color(0xFF16A34A)
                    : req.isRejected
                        ? const Color(0xFFDC2626)
                        : AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Status: ${req.status}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: RequestStatus.getColor(req.status),
                ),
              ),
              Text(
                req.approvalProgress,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stepper List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: req.approvers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final a = req.approvers[index];
              final isCurrentUser = a.approverId == widget.currentUserId;
              final canAct = req.canUserApprove(a.approverId);

              Color stepColor;
              IconData stepIcon;
              if (a.isApproved) {
                stepColor = const Color(0xFF16A34A);
                stepIcon = Icons.check_circle_rounded;
              } else if (a.isRejected) {
                stepColor = const Color(0xFFDC2626);
                stepIcon = Icons.cancel_rounded;
              } else if (canAct) {
                stepColor = const Color(0xFFD97706);
                stepIcon = Icons.hourglass_top_rounded;
              } else {
                stepColor = const Color(0xFF94A3B8);
                stepIcon = Icons.schedule_rounded;
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCurrentUser
                      ? AppTheme.primaryColor.withOpacity(0.06)
                      : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrentUser
                        ? AppTheme.primaryColor.withOpacity(0.4)
                        : AppTheme.cardBorder(context),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(stepIcon, color: stepColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${req.isSequential ? "Step ${a.stepOrder}: " : ""}${a.approverName}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: stepColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  a.status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: stepColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${a.approverRole}${a.approverDepartment.isNotEmpty ? " • ${a.approverDepartment}" : ""}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                          if (a.decisionComments.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Comment: "${a.decisionComments}"',
                                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                          if (a.decidedAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Decided: ${a.decidedAt!.year}-${a.decidedAt!.month.toString().padLeft(2, '0')}-${a.decidedAt!.day.toString().padLeft(2, '0')} ${a.decidedAt!.hour}:${a.decidedAt!.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 5. AUDIT TIMELINE CARD
  // ===========================================================================
  Widget _buildAuditTimelineCard(BuildContext context, RequestRecord req, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              const Icon(Icons.timeline_rounded, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Audit Trail & History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${req.history.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (req.history.isEmpty)
            Text(
              'No recorded activity log.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(context),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: req.history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final h = req.history[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                h.action,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (h.createdAt != null)
                                Text(
                                  '${h.createdAt!.month}/${h.createdAt!.day} ${h.createdAt!.hour}:${h.createdAt!.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textSecondary(context),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'By ${h.actorName} (${h.actorRole})',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                          if (h.formattedDetails.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              h.formattedDetails,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
