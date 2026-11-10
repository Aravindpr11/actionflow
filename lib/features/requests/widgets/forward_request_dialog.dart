import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../users/models/person.dart';
import '../../../services/user_service.dart';
import '../models/request_models.dart';
import '../services/request_service.dart';

/// Enterprise dialog allowing an authorized user to forward a request
class ForwardRequestDialog extends StatefulWidget {
  const ForwardRequestDialog({
    super.key,
    required this.request,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole,
    required this.organizationId,
    required this.onForwardSuccess,
  });

  final RequestRecord request;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final String organizationId;
  final VoidCallback onForwardSuccess;

  @override
  State<ForwardRequestDialog> createState() => _ForwardRequestDialogState();
}

class _ForwardRequestDialogState extends State<ForwardRequestDialog> {
  final TextEditingController _notesController = TextEditingController();
  List<Person> _availableUsers = [];
  Person? _selectedRecipient;
  bool _isLoadingUsers = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadEligibleRecipients();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEligibleRecipients() async {
    try {
      final users = await UserService.instance.fetchUsers(
        widget.organizationId,
        allowMockFallback: true,
      );
      if (mounted) {
        setState(() {
          // Exclude self from forwarding recipients
          _availableUsers = users.where((u) => u.id != widget.currentUserId).toList();
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load recipients: $e';
          _isLoadingUsers = false;
        });
      }
    }
  }

  Future<void> _submitForward() async {
    if (_selectedRecipient == null) {
      setState(() {
        _errorMessage = 'Please select a recipient.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await RequestService.instance.forwardRequest(
        requestId: widget.request.id,
        toUserId: _selectedRecipient!.id,
        toUserName: _selectedRecipient!.name,
        notes: _notesController.text.trim(),
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserRole: widget.currentUserRole,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onForwardSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Request ${widget.request.displayId} forwarded to ${_selectedRecipient!.name}.',
            ),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to forward request: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.forward_rounded, color: Color(0xFF0284C7), size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Forward Request',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              // Request info pill
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.containerBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.request.displayId,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.request.title,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                  ),
                ),
              ],

              // Recipient selection
              Text(
                'Forward To:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 6),
              if (_isLoadingUsers)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else
                DropdownButtonFormField<Person>(
                  key: const Key('forward_recipient_dropdown'),
                  value: _selectedRecipient,
                  isExpanded: true,
                  hint: const Text('Select colleague or manager'),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: _availableUsers.map((p) {
                    return DropdownMenuItem<Person>(
                      value: p,
                      child: Text('${p.name} (${p.designation.isNotEmpty ? p.designation : p.roleLabel})'),
                    );
                  }).toList(),
                  onChanged: _isSubmitting ? null : (p) => setState(() => _selectedRecipient = p),
                ),
              const SizedBox(height: 14),

              // Notes
              Text(
                'Forwarding Notes (Optional):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('forward_notes_field'),
                controller: _notesController,
                enabled: !_isSubmitting,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Add instructions, context, or remarks...',
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          key: const Key('forward_submit_button'),
          onPressed: _isSubmitting ? null : _submitForward,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, size: 16),
          label: const Text('Forward'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

