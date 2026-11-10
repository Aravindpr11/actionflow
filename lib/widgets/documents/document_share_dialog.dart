import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/core/theme/app_theme.dart';
import 'package:action_flow/features/users/models/person.dart';
import 'package:action_flow/features/users/models/team.dart';
import 'package:action_flow/models/document_record.dart';
import 'package:action_flow/services/document_service.dart';
import 'package:action_flow/services/email_service.dart';
import 'package:action_flow/services/user_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Comprehensive Document Sharing Dialog for Manager and Staff Portals
/// Supports Department-Isolated Internal Sharing, Role Badging,
/// Duplicate Prevention, Revocation, and Manager External Token Generation.
class DocumentShareDialog extends StatefulWidget {
  const DocumentShareDialog({
    super.key,
    required this.document,
    required this.organizationId,
    required this.currentUserId,
    required this.currentUserName,
    this.currentUserRole = 'manager',
    this.currentUserDepartment,
    this.currentUserDepartmentId,
    this.allowedDepartmentIds = const {},
    required this.onSharesUpdated,
    this.documentService,
    this.userService,
  });

  final DocumentRecord document;
  final String organizationId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final String? currentUserDepartment;
  final String? currentUserDepartmentId;
  final Set<String> allowedDepartmentIds;
  final VoidCallback onSharesUpdated;
  final DocumentService? documentService;
  final UserService? userService;

  static Future<void> show(
    BuildContext context, {
    required DocumentRecord document,
    required String organizationId,
    required String currentUserId,
    required String currentUserName,
    String currentUserRole = 'manager',
    String? currentUserDepartment,
    String? currentUserDepartmentId,
    Set<String> allowedDepartmentIds = const {},
    required VoidCallback onSharesUpdated,
    DocumentService? documentService,
    UserService? userService,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DocumentShareDialog(
        document: document,
        organizationId: organizationId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        currentUserRole: currentUserRole,
        currentUserDepartment: currentUserDepartment,
        currentUserDepartmentId: currentUserDepartmentId,
        allowedDepartmentIds: allowedDepartmentIds,
        onSharesUpdated: onSharesUpdated,
        documentService: documentService,
        userService: userService,
      ),
    );
  }

  @override
  State<DocumentShareDialog> createState() => _DocumentShareDialogState();
}

class _DocumentShareDialogState extends State<DocumentShareDialog>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  DocumentService get _docService =>
      widget.documentService ?? DocumentService.instance;
  UserService get _userService => widget.userService ?? UserService.instance;

  bool get _isStaff =>
      widget.currentUserRole.toLowerCase() == 'worker' ||
      widget.currentUserRole.toLowerCase() == 'staff';

  bool get _canShare {
    // Both Managers and Staff can share documents they are authorized to access.
    // Recipient filtering in _matchesStaffDepartment ensures Staff can only share
    // non-authored documents with authorized Department Managers.
    return true;
  }

  List<DocumentShare> _internalShares = [];
  List<DocumentExternalToken> _externalTokens = [];
  bool _isLoadingShares = true;

  // Internal sharing state
  List<Person> _allEligibleUsers = [];
  List<Person> _filteredEligibleUsers = [];
  bool _isLoadingUsers = true;
  String? _userLoadError;
  Person? _selectedUser;
  String _internalPermission = 'view';
  bool _isSharing = false;
  final TextEditingController _searchCtrl = TextEditingController();

  // External tab state (managers only)
  final TextEditingController _extEmailCtrl = TextEditingController();
  final TextEditingController _extNameCtrl = TextEditingController();
  int _extExpiryDays = 14;
  final String _extPermission = 'view';
  bool _isGeneratingExt = false;
  bool _isRetryingEmail = false;
  String? _generatedPlainToken;
  String? _generatedShareUrl;
  DocumentExternalToken? _lastGeneratedToken;
  String? _extEmailDeliveryStatus;
  String? _extEmailDeliveryError;

  @override
  void initState() {
    super.initState();
    if (!_isStaff) {
      _tabController = TabController(length: 2, vsync: this);
    }
    _loadShares();
    if (_canShare) {
      _loadEligibleUsers();
    } else {
      _isLoadingUsers = false;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchCtrl.dispose();
    _extEmailCtrl.dispose();
    _extNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShares() async {
    setState(() => _isLoadingShares = true);
    try {
      final shares = await _docService.fetchDocumentShares(
        documentId: widget.document.id,
        organizationId: widget.organizationId,
      );
      List<DocumentExternalToken> tokens = [];
      if (!_isStaff) {
        tokens = await _docService.fetchDocumentExternalTokens(
          documentId: widget.document.id,
          organizationId: widget.organizationId,
        );
      }
      if (mounted) {
        setState(() {
          _internalShares = shares;
          _externalTokens = tokens;
          _isLoadingShares = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingShares = false);
    }
  }

  Future<void> _loadEligibleUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      _userService.invalidateCache();
      final users = await _userService.fetchUsers(
        widget.organizationId,
        allowMockFallback: DocumentService.allowInMemoryStoreForTests ||
            !SupabaseConfig.isInitialized,
      );

      int excludedInactive = 0;
      int excludedSelf = 0;
      int excludedOrg = 0;
      int excludedDept = 0;
      int excludedAdmin = 0;

      final eligible = users.where((p) {
        if (!p.isActive) {
          excludedInactive++;
          return false;
        }
        if (p.id == widget.currentUserId) {
          excludedSelf++;
          return false;
        }
        if (p.type != PersonType.internalUser) return false;

        // Organization isolation check
        if (p.organizationId != null &&
            p.organizationId!.isNotEmpty &&
            !DocumentService.isOrgMatch(p.organizationId, widget.organizationId)) {
          excludedOrg++;
          return false;
        }

        // Staff Sharing: Strictly limited to colleagues and managers in the same department/organization.
        // System Administrator, Company Admin, Platform Admin, and other admin-portal-only roles
        // are strictly hidden from the Staff Portal recipient picker.
        if (_isStaff) {
          if (_isAdminPortalUser(p)) {
            excludedAdmin++;
            debugPrint(
              '[DocumentShareDialog] Excluded admin user ${p.name} (${p.id}, role: ${p.roleLabel}, desig: ${p.designation}) from Staff Portal recipient picker.',
            );
            return false;
          }

          final matches = _matchesStaffDepartment(p);
          if (!matches) {
            excludedDept++;
            debugPrint(
              '[DocumentShareDialog] Excluded user ${p.name} (${p.id}, role: ${p.roleLabel}, dept: ${p.department}, deptId: ${p.departmentId}) due to department isolation.',
            );
          } else {
            debugPrint(
              '[DocumentShareDialog] Included user ${p.name} (${p.id}, role: ${p.roleLabel}, dept: ${p.department}, deptId: ${p.departmentId}) as eligible.',
            );
          }
          return matches;
        }

        // Manager Sharing: According to existing organization and department permissions
        return _matchesManagerDepartment(p);
      }).toList();

      final activeSameOrgUsers = users.where((p) =>
          p.isActive &&
          DocumentService.isOrgMatch(p.organizationId, widget.organizationId)).toList();
      final sameDeptStaffCount = activeSameOrgUsers.where((p) =>
          p.role == UserRole.actionOwnerWorker &&
          !p.designation.toLowerCase().contains('manager') &&
          _matchesStaffDepartment(p) &&
          p.id != widget.currentUserId).length;
      final managerRoleAccountsCount = activeSameOrgUsers.where((p) =>
          p.role == UserRole.departmentManager ||
          p.role == UserRole.admin ||
          p.designation.toLowerCase().contains('manager') ||
          p.designation.toLowerCase().contains('admin')).length;

      debugPrint(
        '[DocumentShareDialog Diagnosis] Stage 1 - Caller: id=${widget.currentUserId}, org=${widget.organizationId}, role=${widget.currentUserRole}, dept="${widget.currentUserDepartment}", deptId=${widget.currentUserDepartmentId}',
      );
      debugPrint(
        '[DocumentShareDialog Diagnosis] Stage 2 - Document: id=${widget.document.id}, deptId=${widget.document.departmentId}, category="${widget.document.category}"',
      );
      debugPrint(
        '[DocumentShareDialog Diagnosis] Stage 3 Counts: '
        'rawRowsReturned=${users.length}, '
        'activeSameOrg=${activeSameOrgUsers.length}, '
        'sameDeptStaff=$sameDeptStaffCount, '
        'managerRoleAccounts=$managerRoleAccountsCount, '
        'finalEligible=${eligible.length}',
      );

      debugPrint('[DocumentShareDialog] Filter results: ${eligible.length} eligible, '
          'excluded: self=$excludedSelf, inactive=$excludedInactive, org=$excludedOrg, dept=$excludedDept, admin=$excludedAdmin');

      if (mounted) {
        setState(() {
          _allEligibleUsers = eligible;
          _isLoadingUsers = false;
          _userLoadError = null;
          _applySearchFilter();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _allEligibleUsers = [];
          _filteredEligibleUsers = [];
          _userLoadError = 'Unable to load eligible users: $e';
          _isLoadingUsers = false;
        });
      }
    }
  }

  static bool _departmentsMatch(String a, String b) {
    final normA = a.trim().toLowerCase();
    final normB = b.trim().toLowerCase();
    if (normA.isEmpty || normB.isEmpty) return false;
    if (normA == normB) return true;
    if (normA == 'all' || normB == 'all') return true;
    if (normA.contains(normB) || normB.contains(normA)) return true;

    final tokensA = normA
        .split(RegExp(r'[\/,\&\|\+]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty);
    final tokensB = normB
        .split(RegExp(r'[\/,\&\|\+]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty);

    for (final ta in tokensA) {
      for (final tb in tokensB) {
        if (ta == tb || ta.contains(tb) || tb.contains(ta)) return true;
      }
    }
    return false;
  }

  /// Checks whether a user account belongs to an Admin Portal role (System Administrator,
  /// Company Admin, Platform Admin, etc.) that must not be exposed in the Staff Portal picker.
  static bool _isAdminPortalUser(Person person) {
    if (person.role == UserRole.departmentManager) {
      return false;
    }
    if (person.role == UserRole.admin) {
      return true;
    }
    final roleText = person.roleLabel.trim().toLowerCase();
    if (roleText.contains('admin') ||
        roleText.contains('system administrator') ||
        roleText.contains('platform') ||
        roleText.contains('company admin')) {
      return true;
    }
    final desig = person.designation.trim().toLowerCase();
    if (desig.contains('system admin') ||
        desig.contains('platform admin') ||
        desig.contains('company admin') ||
        desig == 'administrator' ||
        desig == 'admin') {
      return true;
    }
    return false;
  }

  /// Checks whether a user account is an eligible department manager.
  static bool _isDepartmentManager(Person person) {
    if (_isAdminPortalUser(person)) return false;
    if (person.role == UserRole.departmentManager) return true;
    final rLabel = person.roleLabel.trim().toLowerCase();
    if (rLabel.contains('department manager') || rLabel == 'manager') return true;
    final desig = person.designation.trim().toLowerCase();
    if (desig.contains('manager') ||
        desig.contains('lead') ||
        desig.contains('director') ||
        desig.contains('supervisor') ||
        desig.contains('head')) {
      return true;
    }
    return false;
  }

  bool _matchesStaffDepartment(Person person) {
    // 0. Admin Portal accounts (System Administrator, Company Admin, Platform Admin) must never be eligible
    if (_isAdminPortalUser(person)) {
      return false;
    }

    // 1. Department Managers across the organization are eligible recipients
    if (_isDepartmentManager(person)) {
      return true;
    }

    // If staff member is not the author, they cannot share with other staff members (only with managers)
    final isAuthor = widget.document.isOwnedBy(widget.currentUserId) ||
        (widget.document.createdByName.isNotEmpty &&
            widget.document.createdByName.toLowerCase() == widget.currentUserName.toLowerCase());
    if (!isAuthor) {
      return false;
    }

    final docDeptId = widget.document.departmentId?.trim();
    final userDeptId = widget.currentUserDepartmentId?.trim();
    final userDept = widget.currentUserDepartment?.trim().toLowerCase();
    final docCategory = widget.document.category.trim().toLowerCase();

    // 2. For colleagues (staff): Strictly enforce same department
    if (person.departmentId != null && person.departmentId!.isNotEmpty) {
      if (docDeptId != null &&
          docDeptId.isNotEmpty &&
          person.departmentId == docDeptId) {
        return true;
      }
      if (userDeptId != null &&
          userDeptId.isNotEmpty &&
          person.departmentId == userDeptId) {
        return true;
      }
    }

    if (userDept != null && userDept.isNotEmpty && userDept != 'all') {
      if (person.department.isNotEmpty &&
          _departmentsMatch(person.department, userDept)) {
        return true;
      }
    }

    if (docCategory.isNotEmpty &&
        person.department.isNotEmpty &&
        _departmentsMatch(person.department, docCategory)) {
      return true;
    }

    return false;
  }

  bool _matchesManagerDepartment(Person person) {
    // Fellow managers and admins in the organization are eligible recipients
    if (_isDepartmentManager(person) ||
        person.role == UserRole.admin ||
        _isAdminPortalUser(person)) {
      return true;
    }

    final docDeptId = widget.document.departmentId?.trim();
    if (docDeptId != null && docDeptId.isNotEmpty) {
      return person.departmentId == docDeptId ||
          widget.allowedDepartmentIds.isEmpty ||
          widget.allowedDepartmentIds.contains(person.departmentId);
    }
    return widget.allowedDepartmentIds.isEmpty ||
        widget.allowedDepartmentIds.contains(person.departmentId);
  }

  void _onSearchChanged(String query) {
    _applySearchFilter();
  }

  void _applySearchFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredEligibleUsers = _allEligibleUsers;
      } else {
        _filteredEligibleUsers = _allEligibleUsers.where((p) {
          final nameMatch = p.name.toLowerCase().contains(q);
          final emailMatch = p.email.toLowerCase().contains(q);
          final roleMatch = p.roleLabel.toLowerCase().contains(q);
          final desigMatch = p.designation.toLowerCase().contains(q);
          final deptMatch = p.department.toLowerCase().contains(q);
          return nameMatch || emailMatch || roleMatch || desigMatch || deptMatch;
        }).toList();
      }
    });
  }

  bool _isAlreadyShared(String personId) {
    return _internalShares.any((s) => s.userId == personId);
  }

  Future<void> _shareWithSelectedUser() async {
    if (_selectedUser == null) return;
    final user = _selectedUser!;

    if (_isAlreadyShared(user.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document is already shared with ${user.name}.'),
          backgroundColor: const Color(0xFFD97706),
        ),
      );
      return;
    }

    setState(() => _isSharing = true);
    try {
      await _docService.shareDocumentInternal(
        documentId: widget.document.id,
        organizationId: widget.organizationId,
        userId: user.id,
        userName: user.name,
        userEmail: user.email,
        permission: _internalPermission,
        sharedBy: widget.currentUserId,
        sharedByName: widget.currentUserName,
        callerRole: widget.currentUserRole,
        callerDepartmentId: widget.currentUserDepartmentId,
        recipientDepartmentId: user.departmentId,
        recipientRole: user.role == UserRole.departmentManager
            ? 'manager'
            : (user.role == UserRole.admin ? 'admin' : 'staff'),
        recipientIsActive: user.isActive,
        recipientOrganizationId: user.organizationId,
        allowedDepartmentIds: widget.allowedDepartmentIds,
      );

      setState(() {
        _selectedUser = null;
      });
      await _loadShares();
      widget.onSharesUpdated();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Document successfully shared with ${user.name} (${user.roleLabel}).',
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
            content: Text('Failed to share: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _revokeShare(DocumentShare share) async {
    try {
      await _docService.revokeDocumentInternalShare(
        shareId: share.id,
        userId: share.userId,
        documentId: widget.document.id,
        organizationId: widget.organizationId,
      );

      await _loadShares();
      widget.onSharesUpdated();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Access revoked for ${share.userName}.'),
            backgroundColor: const Color(0xFF64748B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Revocation failed: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _generateExternalToken() async {
    final email = _extEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid recipient email.')),
      );
      return;
    }

    setState(() {
      _isGeneratingExt = true;
      _generatedPlainToken = null;
      _generatedShareUrl = null;
      _lastGeneratedToken = null;
      _extEmailDeliveryStatus = null;
      _extEmailDeliveryError = null;
    });

    try {
      final tokenResult = await _docService.createExternalShareToken(
        documentId: widget.document.id,
        organizationId: widget.organizationId,
        recipientEmail: email,
        recipientName: _extNameCtrl.text.trim(),
        expiresInDays: _extExpiryDays,
        permission: _extPermission,
        createdBy: widget.currentUserId,
        createdByName: widget.currentUserName,
      );

      final tokenString = tokenResult.token;
      final baseUrl = kIsWeb ? Uri.base.origin : 'https://actionflow.enterprise';
      final shareUrl = '$baseUrl/doc-access?token=$tokenString';

      _generatedPlainToken = tokenString;
      _generatedShareUrl = shareUrl;
      _lastGeneratedToken = tokenResult.record;

      // Automatically email the external recipient the secure document access link
      final emailResult = await EmailService.instance.sendExternalDocumentShareEmail(
        recipientEmail: email,
        recipientName: _extNameCtrl.text.trim(),
        documentTitle: widget.document.title,
        documentCategory: widget.document.category,
        accessUrl: shareUrl,
        expiresAt: tokenResult.record.expiresAt,
        permission: _extPermission,
        senderName: widget.currentUserName,
      );

      if (emailResult.isSuccess) {
        _extEmailDeliveryStatus = 'sent';
        _extEmailDeliveryError = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Secure document link generated and emailed to $email.'),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        _extEmailDeliveryStatus = emailResult.status;
        _extEmailDeliveryError = emailResult.errorMessage ?? 'Email delivery failed';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Link generated, but email delivery failed: ${emailResult.errorMessage ?? 'Unknown error'}'),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      _extEmailCtrl.clear();
      _extNameCtrl.clear();
      await _loadShares();
      widget.onSharesUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate token: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingExt = false);
    }
  }

  Future<void> _retryEmailDelivery() async {
    if (_generatedPlainToken == null ||
        _generatedShareUrl == null ||
        _lastGeneratedToken == null) {
      return;
    }

    setState(() => _isRetryingEmail = true);
    try {
      final emailResult = await EmailService.instance.sendExternalDocumentShareEmail(
        recipientEmail: _lastGeneratedToken!.recipientEmail,
        recipientName: _lastGeneratedToken!.recipientName,
        documentTitle: widget.document.title,
        documentCategory: widget.document.category,
        accessUrl: _generatedShareUrl!,
        expiresAt: _lastGeneratedToken!.expiresAt,
        permission: _lastGeneratedToken!.permission,
        senderName: widget.currentUserName,
      );

      if (emailResult.isSuccess) {
        setState(() {
          _extEmailDeliveryStatus = 'sent';
          _extEmailDeliveryError = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Email successfully delivered to ${_lastGeneratedToken!.recipientEmail}.'),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        setState(() {
          _extEmailDeliveryStatus = emailResult.status;
          _extEmailDeliveryError = emailResult.errorMessage ?? 'Email delivery failed';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Email retry failed: ${emailResult.errorMessage ?? 'Unknown error'}'),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error retrying email: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRetryingEmail = false);
    }
  }

  Future<void> _revokeExternalToken(DocumentExternalToken token) async {
    try {
      await _docService.revokeExternalShareToken(
        tokenId: token.id,
        documentId: widget.document.id,
        organizationId: widget.organizationId,
        revokedBy: widget.currentUserId,
        reason: 'Revoked via Document Sharing Modal',
      );
      await _loadShares();
      widget.onSharesUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('External access for ${token.recipientEmail} revoked.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Revocation failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogWidth = (media.size.width * 0.9).clamp(360.0, 600.0);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppTheme.cardBg(context),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.share_outlined,
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
                      'Share Document',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    Text(
                      widget.document.title,
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
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (!_isStaff && _tabController != null) ...[
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF1565C0),
              unselectedLabelColor: AppTheme.textSecondary(context),
              indicatorColor: const Color(0xFF1565C0),
              tabs: const [
                Tab(text: 'Internal Colleagues & Managers'),
                Tab(text: 'External Links'),
              ],
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: 520,
        child: !_canShare
            ? _buildNotAuthorizedView()
            : (!_isStaff && _tabController != null
                ? TabBarView(
                    controller: _tabController,
                    children: [
                      _buildInternalSharingTab(),
                      _buildExternalSharingTab(),
                    ],
                  )
                : _buildInternalSharingTab()),
      ),
    );
  }

  Widget _buildNotAuthorizedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 48,
                color: Color(0xFFD97706),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sharing Restricted',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Staff members may only share documents they have authored.\nThis document was uploaded by "${widget.document.createdByName.isNotEmpty ? widget.document.createdByName : 'another user'}".',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInternalSharingTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            _isStaff
                ? 'Select eligible colleagues or managers in your department to grant access:'
                : 'Select colleagues or managers in your organization:',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 10),

          // Diagnostic Error Banner if recipient loading failed
          if (_userLoadError != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    color: Color(0xFFDC2626),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _userLoadError!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('retry_load_recipients_button'),
                    onPressed: _loadEligibleUsers,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(50, 30),
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Search Field
          TextField(
            key: const Key('documents_recipient_search_field'),
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search by name, email, or designation...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Selection Dropdown & Permission
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<Person>(
                  // ignore: deprecated_member_use
                  value: _filteredEligibleUsers.contains(_selectedUser)
                      ? _selectedUser
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _isLoadingUsers
                        ? 'Loading Recipients...'
                        : (_userLoadError != null
                            ? 'Error loading recipients'
                            : (_filteredEligibleUsers.isEmpty
                                ? (_searchCtrl.text.trim().isNotEmpty
                                    ? 'No matching recipients found'
                                    : 'No eligible recipients found')
                                : 'Select Colleague / Manager')),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  selectedItemBuilder: (context) {
                    return _filteredEligibleUsers.map((p) {
                      final deptPart =
                          p.department.isNotEmpty ? ' • ${p.department}' : '';
                      final rolePart = p.designation.isNotEmpty
                          ? p.designation
                          : p.roleLabel;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${p.name} ($rolePart$deptPart)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList();
                  },
                  items: _filteredEligibleUsers.map((p) {
                    final already = _isAlreadyShared(p.id);
                    final deptPart =
                        p.department.isNotEmpty ? ' • ${p.department}' : '';
                    final rolePart = p.designation.isNotEmpty
                        ? p.designation
                        : p.roleLabel;
                    return DropdownMenuItem<Person>(
                      value: p,
                      enabled: !already,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              '${p.name} ($rolePart$deptPart)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: already ? AppTheme.textMuted(context) : null,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: already
                                  ? Colors.grey.withValues(alpha: 0.15)
                                  : (p.role == UserRole.departmentManager ||
                                          p.role == UserRole.admin
                                      ? const Color(0xFF1565C0)
                                          .withValues(alpha: 0.12)
                                      : const Color(0xFF0D9488)
                                          .withValues(alpha: 0.12)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              already ? 'Already Shared' : p.roleLabel,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: already
                                    ? Colors.grey
                                    : (p.role == UserRole.departmentManager ||
                                            p.role == UserRole.admin
                                        ? const Color(0xFF1565C0)
                                        : const Color(0xFF0D9488)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: _isLoadingUsers || _filteredEligibleUsers.isEmpty
                      ? null
                      : (p) => setState(() => _selectedUser = p),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  // ignore: deprecated_member_use
                  value: _internalPermission,
                  decoration: InputDecoration(
                    labelText: 'Permission',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'view', child: Text('View Only')),
                    DropdownMenuItem(
                      value: 'download',
                      child: Text('Download'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _internalPermission = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: FilledButton(
                  key: const Key('documents_confirm_share_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isSharing ||
                          _selectedUser == null ||
                          _isAlreadyShared(_selectedUser!.id)
                      ? null
                      : _shareWithSelectedUser,
                  child: _isSharing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Share'),
                ),
              ),
            ],
          ),

          if (!_isLoadingUsers && _userLoadError == null && _allEligibleUsers.isEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                _isStaff
                    ? 'No other active colleagues or managers were found in your department.'
                    : 'No other active colleagues or managers were found in your organization.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
          ],
          if (!_isLoadingUsers &&
              _userLoadError == null &&
              _allEligibleUsers.isNotEmpty &&
              _filteredEligibleUsers.isEmpty &&
              _searchCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'No eligible recipients match "${_searchCtrl.text.trim()}".',
                style: TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active Shares (${_internalShares.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              if (_isLoadingShares)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (!_isLoadingShares && _internalShares.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'This document is not currently shared with any individual user.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            )
          else
            ..._internalShares.map((s) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
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
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        size: 16,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.userName.isNotEmpty ? s.userName : 'Colleague',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          Text(
                            '${s.userEmail} • Permission: ${s.permission.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.remove_circle_outline, size: 14),
                      label: const Text('Revoke', style: TextStyle(fontSize: 12)),
                      onPressed: () => _revokeShare(s),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildExternalSharingTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'Generate a secure, time-limited link for external contractors, auditors, or authorities:',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _extEmailCtrl,
            decoration: InputDecoration(
              labelText: 'Recipient Email *',
              hintText: 'e.g. auditor@external.com',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _extNameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Recipient Name (Optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  // ignore: deprecated_member_use
                  value: _extExpiryDays,
                  decoration: InputDecoration(
                    labelText: 'Link Expires In',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 3, child: Text('3 Days')),
                    DropdownMenuItem(value: 7, child: Text('7 Days')),
                    DropdownMenuItem(value: 14, child: Text('14 Days')),
                    DropdownMenuItem(value: 30, child: Text('30 Days')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _extExpiryDays = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
            ),
            icon: _isGeneratingExt
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.link_rounded, size: 16),
            label: const Text('Generate Secure Link'),
            onPressed: _isGeneratingExt ? null : _generateExternalToken,
          ),
          if (_generatedShareUrl != null) ...[
            const SizedBox(height: 14),
            if (_extEmailDeliveryStatus == 'sent')
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.mark_email_read_outlined, color: Color(0xFF16A34A), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Secure Link Generated & Emailed to ${_lastGeneratedToken?.recipientEmail ?? 'Recipient'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF16A34A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('Copy Link'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF16A34A)),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _generatedShareUrl!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Share URL copied to clipboard!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _generatedShareUrl!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Notice: The plaintext token is displayed only once. The database stores only the SHA-256 cryptographic hash.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Secure Link Generated (Email Delivery Failed)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFFDC2626),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('Copy Link'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _generatedShareUrl!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Share URL copied to clipboard!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Email could not be delivered: ${_extEmailDeliveryError ?? "Unknown error"}. You may copy the access link above or retry sending.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: _isRetryingEmail
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                                )
                              : const Icon(Icons.refresh_rounded, size: 14),
                          label: const Text('Retry Sending Email'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(color: Color(0xFFDC2626)),
                          ),
                          onPressed: _isRetryingEmail ? null : _retryEmailDelivery,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Notice: The database stores only the SHA-256 cryptographic hash. Retrying sends the existing valid token without creating duplicate tokens.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 20),
          Text(
            'Active External Links (${_externalTokens.length})',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          if (_externalTokens.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.containerBg(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'No external tokens generated.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            )
          else
            ..._externalTokens.map((t) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.containerBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${t.recipientEmail} (${t.isRevoked ? "REVOKED" : "Active"})',
                        style: TextStyle(
                          fontSize: 12,
                          color: t.isRevoked ? Colors.grey : null,
                        ),
                      ),
                    ),
                    if (!t.isRevoked)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => _revokeExternalToken(t),
                        child: const Text('Revoke'),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
