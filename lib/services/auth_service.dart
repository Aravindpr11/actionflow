import 'dart:async';
import 'dart:io';

import 'package:action_flow/core/config/supabase_config.dart';
import 'package:action_flow/features/auth/models/manager_scope_item.dart';
import 'package:action_flow/features/dashboard/manager_dashboard/models/manager_context.dart';
import 'package:action_flow/features/profile/models/user_profile_model.dart';
import 'package:action_flow/models/organization.dart';
import 'package:action_flow/services/calendar_task_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolved user profile and authorization metadata loaded directly from public.profiles
class AuthProfileData {
  final UserProfile userProfile;
  final String roleCode; // 'admin', 'manager', 'staff'
  final String status; // 'active', 'inactive', 'pending_approval', 'suspended'
  final bool isActive;
  final bool isPrimaryAdmin;
  final bool isPlatformAdmin;
  final String? organizationId;
  final Organization? organization;

  /// Whether this user is an authorized Company Admin (internal admin role bound to a company)
  bool get isCompanyAdmin =>
      roleCode.toLowerCase() == 'admin' &&
      !isPlatformAdmin &&
      organizationId != null;

  const AuthProfileData({
    required this.userProfile,
    required this.roleCode,
    required this.status,
    required this.isActive,
    required this.isPrimaryAdmin,
    this.isPlatformAdmin = false,
    this.organizationId = Organization.sobhaId,
    this.organization = const Organization(
      id: Organization.sobhaId,
      name: Organization.sobhaName,
      code: Organization.sobhaCode,
      isActive: true,
    ),
  });

  /// Factory constructor for an authoritative Platform Administrator
  factory AuthProfileData.platformAdmin({
    required String authUserId,
    required String email,
    String? fullName,
  }) {
    final name = (fullName != null && fullName.trim().isNotEmpty)
        ? fullName.trim()
        : (email.isNotEmpty
              ? email.split('@').first
              : 'Platform Administrator');

    final userProfile = UserProfile(
      id: authUserId,
      name: name,
      email: email,
      phone: '',
      designation: 'Platform Administrator',
      department: 'Platform Administration',
      division: 'Global Platform Governance',
      site: 'Global',
      team: '',
      role: 'Platform Administrator',
      accountStatus: 'Active',
      permissions: const [
        'Global Platform Administration',
        'Create & Manage Organizations',
        'Cross-Company Configuration & Audits',
        'Platform Security & Infrastructure',
        'Global Broadcast Dispatch',
      ],
      organizationId: null,
      organizationName: '',
    );

    return AuthProfileData(
      userProfile: userProfile,
      roleCode: 'admin',
      status: 'active',
      isActive: true,
      isPrimaryAdmin: false,
      isPlatformAdmin: true,
      organizationId: null,
      organization: null,
    );
  }
}

/// Information loaded from public.account_requests for users awaiting verification or approval
class AuthAccountRequestData {
  final String id;
  final String authUserId;
  final String fullName;
  final String email;
  final String status; // 'pending_email_verification', 'pending_admin_approval', 'approved', 'rejected'
  final bool isEmailVerified;
  final String? rejectionReason;
  final String? requestedRoleCode;
  final String? organizationId;

  const AuthAccountRequestData({
    required this.id,
    required this.authUserId,
    required this.fullName,
    required this.email,
    required this.status,
    this.isEmailVerified = false,
    this.rejectionReason,
    this.requestedRoleCode,
    this.organizationId,
  });
}

/// Detailed result of attempting to fetch an account request from public.account_requests
sealed class AccountRequestFetchResult {
  const AccountRequestFetchResult();
}

class AccountRequestFetchSuccess extends AccountRequestFetchResult {
  final AuthAccountRequestData accountRequest;
  const AccountRequestFetchSuccess(this.accountRequest);
}

class AccountRequestFetchNotFound extends AccountRequestFetchResult {
  const AccountRequestFetchNotFound();
}

class AccountRequestFetchError extends AccountRequestFetchResult {
  final String errorMessage;
  const AccountRequestFetchError(this.errorMessage);
}

/// Detailed result of attempting to fetch a user profile from public.profiles
sealed class ProfileFetchResult {
  const ProfileFetchResult();
}

class ProfileFetchSuccess extends ProfileFetchResult {
  final AuthProfileData profileData;
  const ProfileFetchSuccess(this.profileData);
}

class ProfileFetchNotFound extends ProfileFetchResult {
  const ProfileFetchNotFound();
}

class ProfileFetchError extends ProfileFetchResult {
  final String errorMessage;
  const ProfileFetchError(this.errorMessage);
}

/// Result of a Supabase Auth sign-in attempt
class AuthSignInResult {
  final bool isSuccess;
  final String? errorMessage;
  final AuthProfileData? profileData;
  final AuthAccountRequestData? accountRequest;
  final Session? session;
  final User? user;
  final bool isDatabaseError;
  final bool isProfileMissing;

  const AuthSignInResult.success({
    this.session,
    this.user,
    this.profileData,
    this.accountRequest,
  }) : isSuccess = true,
       errorMessage = null,
       isDatabaseError = false,
       isProfileMissing = false;

  const AuthSignInResult.failure(
    this.errorMessage, {
    this.isDatabaseError = false,
    this.isProfileMissing = false,
  }) : isSuccess = false,
       profileData = null,
       accountRequest = null,
       session = null,
       user = null;
}

/// Result of a Supabase Auth sign-up attempt
class AuthSignUpResult {
  final bool isSuccess;
  final String? errorMessage;
  final User? user;
  final Session? session;
  final bool isDuplicateEmail;
  final bool isNetworkError;

  const AuthSignUpResult.success({required this.user, this.session})
    : isSuccess = true,
      errorMessage = null,
      isDuplicateEmail = false,
      isNetworkError = false;

  const AuthSignUpResult.failure(
    this.errorMessage, {
    this.isDuplicateEmail = false,
    this.isNetworkError = false,
  }) : isSuccess = false,
       user = null,
       session = null;
}

/// Result of an account password update attempt
class AuthPasswordUpdateResult {
  final bool isSuccess;
  final String? errorMessage;

  const AuthPasswordUpdateResult.success()
    : isSuccess = true,
      errorMessage = null;

  const AuthPasswordUpdateResult.failure(this.errorMessage) : isSuccess = false;
}

/// Result of a password-reset request attempt
class AuthPasswordResetResult {
  final bool isSuccess;
  final String? errorMessage;

  const AuthPasswordResetResult.success()
    : isSuccess = true,
      errorMessage = null;

  const AuthPasswordResetResult.failure(this.errorMessage) : isSuccess = false;
}

/// Represents an error captured from an authentication URL fragment or query parameters.
class AuthLinkError {
  final String error;
  final String errorCode;
  final String description;

  const AuthLinkError({
    required this.error,
    required this.errorCode,
    required this.description,
  });

  bool get isExpired =>
      errorCode == 'otp_expired' ||
      (error == 'access_denied' &&
          description.toLowerCase().contains('expired')) ||
      description.toLowerCase().contains('expired');

  String get userFriendlyMessage {
    if (isExpired) {
      return 'Your invitation or password reset link has expired. Please request a new link to continue.';
    }
    return description.isNotEmpty
        ? description
        : 'The authentication link is invalid or has already been used.';
  }
}

/// In-memory classification of the initial auth flow detected at application launch
enum InitialAuthFlow { none, invite, recovery }

/// Production authentication service managing Supabase Auth lifecycle,
/// database profile derivation, and session persistence.
class AuthService {
  static final AuthService instance = AuthService._internal();

  AuthService._internal();

  factory AuthService([SupabaseClient? customClient]) {
    if (customClient != null) {
      return AuthService._withClient(customClient);
    }
    return instance;
  }

  AuthService._withClient(this._customClient);

  @visibleForTesting
  AuthService.forTesting([SupabaseClient? client]) : _customClient = client;

  SupabaseClient? _customClient;
  StreamSubscription<AuthState>? _authSubscription;
  AuthProfileData? _currentProfileData;
  Session? _currentSession;

  @visibleForTesting
  void setSessionForTesting(Session? session) {
    _currentSession = session;
  }

  @visibleForTesting
  void setProfileDataForTesting(AuthProfileData? profileData) {
    _currentProfileData = profileData;
  }

  /// Sets the active database profile data (e.g., during session restoration or live profile refresh)
  void setCurrentProfileData(AuthProfileData? profileData) {
    _currentProfileData = profileData;
  }

  SupabaseClient? get _client => _customClient ?? SupabaseConfig.clientOrNull;

  /// Currently active database profile data
  AuthProfileData? get currentProfileData => _currentProfileData;

  /// Currently active user profile model
  UserProfile? get currentProfile => _currentProfileData?.userProfile;

  /// Currently active organization model
  Organization? get currentOrganization => _currentProfileData?.organization;

  /// Currently active organization ID
  String? get currentOrganizationId => _currentProfileData?.organizationId;

  /// Whether the currently active user is a Platform Admin
  bool get isPlatformAdmin => _currentProfileData?.isPlatformAdmin ?? false;

  /// Whether the currently active user is an authorized Company Admin
  bool get isCompanyAdmin => _currentProfileData?.isCompanyAdmin ?? false;

  /// Currently active Supabase Auth session
  Session? get currentSession =>
      _currentSession ?? _client?.auth.currentSession;

  /// Currently active Supabase Auth user
  User? get currentUser => currentSession?.user ?? _client?.auth.currentUser;

  /// Whether a valid user session is currently active
  bool get isAuthenticated => currentSession != null;

  /// Stream of Supabase Auth state changes
  Stream<AuthState>? get authStateChanges => _client?.auth.onAuthStateChange;

  /// Authenticate against Supabase Auth with email and password,
  /// then load the authoritative profile from public.profiles.
  Future<AuthSignInResult> signIn({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      return const AuthSignInResult.failure(
        'Authentication service is currently unavailable.',
      );
    }

    try {
      final response = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = response.user;
      final session = response.session;

      if (user == null) {
        return const AuthSignInResult.failure('Invalid username or password');
      }

      _currentSession = session;

      // 1. Authoritative approval check:
      // Check public.account_requests first for ANY applicant account state
      final accountResult = await fetchAccountRequestResult(
        user.id,
        email: user.email,
      );

      if (accountResult is AccountRequestFetchSuccess) {
        final req = accountResult.accountRequest;
        final reqStatus = req.status.toLowerCase().trim();

        // If email is not confirmed in auth.users or account_requests
        if (user.emailConfirmedAt == null || !req.isEmailVerified) {
          return AuthSignInResult.success(
            session: session,
            user: user,
            accountRequest: req,
          );
        }

        // If account request is still awaiting admin approval or rejected
        if (reqStatus == 'pending_admin_approval' ||
            reqStatus == 'pending_approval' ||
            reqStatus == 'pending_email_verification' ||
            reqStatus == 'rejected') {
          return AuthSignInResult.success(
            session: session,
            user: user,
            accountRequest: req,
          );
        }

        // If reqStatus == 'approved', proceed to fetch approved profile below
      } else if (accountResult is AccountRequestFetchError) {
        return AuthSignInResult.failure(
          accountResult.errorMessage,
          isDatabaseError: true,
        );
      }

      // 2. If email is unconfirmed on auth.users and no account request found
      if (user.emailConfirmedAt == null) {
        return const AuthSignInResult.failure(
          'Please verify your email before signing in.',
        );
      }

      // 3. Fetch authoritative profile from public.profiles
      final profileResult = await fetchProfileResult(user.id);

      if (profileResult is ProfileFetchSuccess) {
        _currentProfileData = profileResult.profileData;
        return AuthSignInResult.success(
          session: session,
          user: user,
          profileData: profileResult.profileData,
        );
      }

      if (profileResult is ProfileFetchError) {
        // Distinguish database/network error from missing profile!
        // Do NOT silently fall back or assume staff!
        return AuthSignInResult.failure(
          profileResult.errorMessage,
          isDatabaseError: true,
        );
      }

      // 4. User authenticated in auth.users, but truly has neither profile nor account_request
      return const AuthSignInResult.failure(
        'Account authenticated, but no organizational profile was found in the database. Please contact your system administrator.',
        isProfileMissing: true,
      );
    } on AuthException catch (e) {
      return AuthSignInResult.failure(_sanitizeAuthError(e.message));
    } on SocketException {
      return const AuthSignInResult.failure(
        'Network connection error. Please check your internet connection and try again.',
      );
    } on TimeoutException {
      return const AuthSignInResult.failure(
        'Connection timed out. Please check your internet connection and try again.',
      );
    } catch (e) {
      // General error without leaking raw internal details
      final msg = e.toString().toLowerCase();
      if (msg.contains('network') ||
          msg.contains('socket') ||
          msg.contains('failed host lookup') ||
          msg.contains('clientexception')) {
        return const AuthSignInResult.failure(
          'Network connection error. Please check your internet connection and try again.',
        );
      }
      return const AuthSignInResult.failure('Invalid username or password');
    }
  }

  /// Safely updates the authenticated user's password in Supabase Auth.
  /// Validates password policy (minimum 8 characters, letters and numbers)
  /// and sanitizes any server error messages.
  /// Passwords are never stored, logged, or retained beyond this call.
  Future<AuthPasswordUpdateResult> updatePassword(String newPassword) async {
    final client = _client;
    if (client == null) {
      return const AuthPasswordUpdateResult.failure(
        'Authentication service is currently unavailable.',
      );
    }

    final trimmed = newPassword.trim();
    if (trimmed.length < 8) {
      return const AuthPasswordUpdateResult.failure(
        'Password must be at least 8 characters long.',
      );
    }

    final hasLetters = RegExp(r'[A-Za-z]').hasMatch(trimmed);
    final hasNumbers = RegExp(r'[0-9]').hasMatch(trimmed);
    if (!hasLetters || !hasNumbers) {
      return const AuthPasswordUpdateResult.failure(
        'Password must contain both letters and numbers.',
      );
    }

    try {
      await client.auth.updateUser(UserAttributes(password: trimmed));
      return const AuthPasswordUpdateResult.success();
    } on AuthException catch (e) {
      return AuthPasswordUpdateResult.failure(
        _sanitizePasswordError(e.message),
      );
    } on SocketException {
      return const AuthPasswordUpdateResult.failure(
        'Network connection error. Please check your internet connection and try again.',
      );
    } on TimeoutException {
      return const AuthPasswordUpdateResult.failure(
        'Connection timed out. Please check your internet connection and try again.',
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('network') ||
          msg.contains('socket') ||
          msg.contains('failed host lookup') ||
          msg.contains('clientexception')) {
        return const AuthPasswordUpdateResult.failure(
          'Network connection error. Please check your internet connection and try again.',
        );
      }
      return const AuthPasswordUpdateResult.failure(
        'Unable to update password. Please try again.',
      );
    }
  }

  /// Sends a real password reset email through Supabase Auth using the
  /// configured redirect URL. On web, uses the current origin dynamically.
  /// On mobile/desktop, the redirect falls back to null (Supabase deep link).
  ///
  /// Returns [AuthPasswordResetResult.failure] with a user-visible message for:
  ///   - Rate limiting (over_email_send_rate_limit)
  ///   - Network errors
  ///   - PKCE/async-storage failures
  ///   - Other real API errors
  ///
  /// Returns [AuthPasswordResetResult.success] when:
  ///   - The API call succeeded
  ///   - The email was not found (to prevent account enumeration)
  Future<AuthPasswordResetResult> resetPasswordForEmail(
    String email, {
    String? redirectTo,
  }) async {
    final client = _client;
    if (client == null) {
      return const AuthPasswordResetResult.failure(
        'Authentication service is currently unavailable.',
      );
    }

    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty ||
        !cleanEmail.contains('@') ||
        !cleanEmail.contains('.')) {
      return const AuthPasswordResetResult.failure(
        'Please enter a valid email address.',
      );
    }

    try {
      final defaultRedirect = kIsWeb
          ? '${Uri.base.scheme}://${Uri.base.host}${Uri.base.hasPort ? ':${Uri.base.port}' : ''}'
          : null;
      await client.auth.resetPasswordForEmail(
        cleanEmail,
        redirectTo: redirectTo ?? defaultRedirect,
      );
      return const AuthPasswordResetResult.success();
    } on AuthException catch (e) {
      debugPrint(
        '[AuthService] resetPasswordForEmail AuthException: ${e.message}',
      );
      final msg = e.message.toLowerCase();
      // Rate limiting — always surface this so the user knows to wait
      if (msg.contains('rate limit') ||
          msg.contains('over_email_send_rate_limit')) {
        return const AuthPasswordResetResult.failure(
          'Too many password reset requests. Supabase limits one reset email '
          'per hour. Please wait before requesting again.',
        );
      }
      // "User not found" — return success to prevent account enumeration
      if (msg.contains('user not found') || msg.contains('invalid email')) {
        return const AuthPasswordResetResult.success();
      }
      // Surface all other real AuthExceptions to the UI
      return AuthPasswordResetResult.failure(
        'Password reset request failed: ${e.message}',
      );
    } on SocketException {
      return const AuthPasswordResetResult.failure(
        'Network connection error. Please check your internet connection and try again.',
      );
    } on TimeoutException {
      return const AuthPasswordResetResult.failure(
        'Connection timed out. Please check your internet connection and try again.',
      );
    } catch (e) {
      debugPrint('[AuthService] resetPasswordForEmail unexpected error: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('network') ||
          msg.contains('socket') ||
          msg.contains('failed host lookup') ||
          msg.contains('clientexception')) {
        return const AuthPasswordResetResult.failure(
          'Network connection error. Please check your internet connection and try again.',
        );
      }
      // PKCE async-storage assertion — client not fully initialized for PKCE flow
      if (msg.contains('asyncstorage') || msg.contains('pkce')) {
        return const AuthPasswordResetResult.failure(
          'Password reset is temporarily unavailable. Please restart the app and try again.',
        );
      }
      // Return success for unknown errors to prevent account enumeration
      return const AuthPasswordResetResult.success();
    }
  }

  /// Allows a logged-in user to change their password by verifying their
  /// current password against Supabase Auth before updating to the new password.
  /// Works across all roles (Platform Owner, Company Admin, Manager, Staff).
  Future<AuthPasswordUpdateResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final client = _client;
    if (client == null) {
      return const AuthPasswordUpdateResult.failure(
        'Authentication service is currently unavailable.',
      );
    }

    if (currentPassword.isEmpty) {
      return const AuthPasswordUpdateResult.failure(
        'Please enter your current password.',
      );
    }

    if (currentPassword == newPassword) {
      return const AuthPasswordUpdateResult.failure(
        'New password cannot be the same as your current password.',
      );
    }

    final userEmail = currentUser?.email;
    if (userEmail == null || userEmail.isEmpty) {
      return const AuthPasswordUpdateResult.failure(
        'No active user email found for authentication.',
      );
    }

    // 1. Verify current password with Supabase Auth
    try {
      await client.auth.signInWithPassword(
        email: userEmail,
        password: currentPassword,
      );
    } on AuthException catch (_) {
      return const AuthPasswordUpdateResult.failure(
        'The current password entered is incorrect.',
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('network') || msg.contains('socket')) {
        return const AuthPasswordUpdateResult.failure(
          'Network error verifying current password. Please try again.',
        );
      }
      return const AuthPasswordUpdateResult.failure(
        'The current password entered is incorrect.',
      );
    }

    // 2. Update to new password
    return updatePassword(newPassword);
  }

  /// Sanitizes password-specific error messages
  String _sanitizePasswordError(String rawMessage) {
    final msg = rawMessage.toLowerCase();
    if (msg.contains('password should be at least') ||
        msg.contains('password is too short')) {
      return 'Password must be at least 8 characters long.';
    }
    if (msg.contains('same password') ||
        msg.contains('should be different from the old password')) {
      return 'New password cannot be the same as your old password.';
    }
    if (msg.contains('rate limit') || msg.contains('too many requests')) {
      return 'Too many password update attempts. Please wait a moment and try again.';
    }
    return 'Unable to update password. Please ensure it meets security requirements.';
  }

  static InitialAuthFlow _capturedInitialAuthFlow = InitialAuthFlow.none;
  static AuthLinkError? _capturedAuthLinkError;
  static bool _isPasswordRecoveryActive = false;
  static String? _capturedExternalUpdateToken;

  /// Captures the initial auth flow from [uri] (or [Uri.base] by default on web)
  /// before Supabase SDK strips URL parameters via [clearAuthUrlParameters].
  /// In-memory state only. Never persisted to local storage or database.
  static void captureInitialAuthFlow([Uri? uri]) {
    final targetUri = uri ?? (kIsWeb ? Uri.base : null);
    if (targetUri == null) {
      _capturedInitialAuthFlow = InitialAuthFlow.none;
      _capturedAuthLinkError = null;
      _capturedExternalUpdateToken = null;
      return;
    }
    final fragment = targetUri.fragment;
    final fragmentLower = fragment.toLowerCase();
    final query = targetUri.queryParameters;

    // Parse fragment parameters if present (format: key=val&key2=val2 or /path?key=val or #key=val)
    final fragmentParams = <String, String>{};
    String fragmentPath = '';
    if (fragment.isNotEmpty) {
      final cleanFragment = fragment.startsWith('#')
          ? fragment.substring(1)
          : fragment;

      final qIndex = cleanFragment.indexOf('?');
      fragmentPath = qIndex != -1 ? cleanFragment.substring(0, qIndex) : cleanFragment;
      final queryPart = qIndex != -1
          ? cleanFragment.substring(qIndex + 1)
          : (cleanFragment.contains('=') ? cleanFragment : '');

      if (queryPart.isNotEmpty) {
        final parts = queryPart.split('&');
        for (final part in parts) {
          final kv = part.split('=');
          if (kv.isNotEmpty) {
            final key = Uri.decodeQueryComponent(kv[0]).trim();
            final val = kv.length > 1
                ? Uri.decodeQueryComponent(kv.sublist(1).join('='))
                : '';
            fragmentParams[key] = val;
          }
        }
      }
    }

    // Inspect for error query or fragment parameters (e.g. otp_expired, access_denied)
    final err = query['error'] ?? fragmentParams['error'];
    final errCode = query['error_code'] ?? fragmentParams['error_code'];
    final errDesc =
        query['error_description'] ?? fragmentParams['error_description'];

    if (err != null || errCode != null || errDesc != null) {
      _capturedAuthLinkError = AuthLinkError(
        error: err ?? '',
        errorCode: errCode ?? '',
        description: (errDesc ?? '').replaceAll('+', ' '),
      );
      _capturedInitialAuthFlow = InitialAuthFlow.none;
      _capturedExternalUpdateToken = null;
      return;
    }

    _capturedAuthLinkError = null;

    // Check for External Action Update flow & token
    final token = query['token'] ?? fragmentParams['token'];
    final isExternalUpdateRoute = targetUri.path.contains('external-update') ||
        fragmentPath.contains('external-update') ||
        fragmentLower.contains('external-update');

    if (isExternalUpdateRoute || (token != null && token.isNotEmpty)) {
      _capturedExternalUpdateToken = token ?? '';
      _capturedInitialAuthFlow = InitialAuthFlow.none;
      _isPasswordRecoveryActive = false;
      return;
    }

    _capturedExternalUpdateToken = null;

    if (fragmentLower.contains('type=invite') || query['type'] == 'invite') {
      _capturedInitialAuthFlow = InitialAuthFlow.invite;
      _isPasswordRecoveryActive = false;
    } else if (fragmentLower.contains('type=recovery') ||
        query['type'] == 'recovery') {
      _capturedInitialAuthFlow = InitialAuthFlow.recovery;
      _isPasswordRecoveryActive = true;
    } else {
      _capturedInitialAuthFlow = InitialAuthFlow.none;
      _isPasswordRecoveryActive = false;
    }
  }

  /// Currently captured external update access token (in-memory only).
  static String? get capturedExternalUpdateToken => _capturedExternalUpdateToken;

  /// Consumes and clears the captured external update token.
  static void clearCapturedExternalUpdateToken() {
    _capturedExternalUpdateToken = null;
  }

  @visibleForTesting
  static void setCapturedExternalUpdateTokenForTesting(String? token) {
    _capturedExternalUpdateToken = token;
  }

  /// Currently captured initial auth flow (in-memory only).
  static InitialAuthFlow get capturedInitialAuthFlow =>
      _capturedInitialAuthFlow;

  /// Consumes and clears the captured initial auth flow so that it is not
  /// re-triggered on subsequent normal in-app navigation or re-routing.
  static void clearCapturedInitialAuthFlow() {
    _capturedInitialAuthFlow = InitialAuthFlow.none;
  }

  @visibleForTesting
  static void setCapturedInitialAuthFlowForTesting(InitialAuthFlow flow) {
    _capturedInitialAuthFlow = flow;
    _isPasswordRecoveryActive = (flow == InitialAuthFlow.recovery);
  }

  /// Currently captured authentication link error (e.g. expired link)
  static AuthLinkError? get capturedAuthLinkError => _capturedAuthLinkError;

  /// Consumes and clears the captured authentication link error.
  static void clearCapturedAuthLinkError() {
    _capturedAuthLinkError = null;
  }

  @visibleForTesting
  static void setCapturedAuthLinkErrorForTesting(AuthLinkError? error) {
    _capturedAuthLinkError = error;
  }

  /// Whether password recovery mode is currently active
  static bool get isPasswordRecoveryActive => _isPasswordRecoveryActive;

  /// Consumes and clears the password recovery mode flag.
  static void clearPasswordRecoveryState() {
    _isPasswordRecoveryActive = false;
  }

  @visibleForTesting
  static void setPasswordRecoveryActiveForTesting(bool active) {
    _isPasswordRecoveryActive = active;
  }

  /// Inspects whether the application has arrived via an incoming invite flow.
  /// Checks preserved in-memory initial state first, then current URL as fallback.
  static bool get isIncomingInviteFlow {
    if (_capturedAuthLinkError != null) return false;
    if (_capturedInitialAuthFlow == InitialAuthFlow.recovery ||
        _isPasswordRecoveryActive) {
      return false;
    }
    if (_capturedInitialAuthFlow == InitialAuthFlow.invite) return true;
    if (!kIsWeb) return false;
    final fragment = Uri.base.fragment.toLowerCase();
    final query = Uri.base.queryParameters;
    return fragment.contains('type=invite') || query['type'] == 'invite';
  }

  /// Inspects whether the application has arrived via an incoming password recovery flow.
  /// Checks preserved in-memory initial state first, then current URL as fallback.
  static bool get isIncomingRecoveryFlow {
    if (_capturedAuthLinkError != null) return false;
    if (_capturedInitialAuthFlow == InitialAuthFlow.invite) return false;
    if (_capturedInitialAuthFlow == InitialAuthFlow.recovery) return true;
    if (_isPasswordRecoveryActive) return true;
    if (!kIsWeb) return false;
    final fragment = Uri.base.fragment.toLowerCase();
    final query = Uri.base.queryParameters;
    return fragment.contains('type=recovery') || query['type'] == 'recovery';
  }

  /// Canonical parser for mapping a database profile record (including joined roles, departments, sites)
  /// into an authoritative [AuthProfileData] model.
  static AuthProfileData parseProfileData(
    Map<dynamic, dynamic> raw,
    String authUserId, {
    bool isPlatformAdmin = false,
  }) {
    final data = Map<String, dynamic>.from(raw);

    final bool isPlatformAdminResolved =
        isPlatformAdmin || data['is_platform_admin'] == true;

    // 1. Resolve role code and name
    String roleCode = '';
    String roleName = '';

    final dynamic rolesRaw = data['roles'];
    if (rolesRaw is Map) {
      roleCode = (rolesRaw['code']?.toString() ?? '').toLowerCase().trim();
      roleName = rolesRaw['name']?.toString().trim() ?? '';
    } else if (rolesRaw is List &&
        rolesRaw.isNotEmpty &&
        rolesRaw.first is Map) {
      final first = rolesRaw.first as Map;
      roleCode = (first['code']?.toString() ?? '').toLowerCase().trim();
      roleName = first['name']?.toString().trim() ?? '';
    }

    // 2. Primary admin, explicit admin, or platform admin check
    final bool isPrimaryAdmin = data['is_primary_admin'] == true;
    if (isPlatformAdminResolved ||
        isPrimaryAdmin ||
        roleCode == 'admin' ||
        roleName.toLowerCase() == 'admin') {
      roleCode = 'admin';
    }

    // 3. Resolve department
    String deptName = isPlatformAdminResolved
        ? 'Platform Administration'
        : (roleCode == 'admin'
              ? 'Enterprise System Administration'
              : 'Operations & Maintenance');
    String deptDivision = isPlatformAdminResolved
        ? 'Global Platform Governance'
        : (roleCode == 'admin'
              ? 'System & Organization Governance'
              : 'Operations & HSSE');

    final dynamic deptsRaw = data['departments'];
    if (deptsRaw is Map) {
      deptName = deptsRaw['name']?.toString() ?? deptName;
      deptDivision = deptsRaw['division']?.toString() ?? deptDivision;
    } else if (deptsRaw is List &&
        deptsRaw.isNotEmpty &&
        deptsRaw.first is Map) {
      final first = deptsRaw.first as Map;
      deptName = first['name']?.toString() ?? deptName;
      deptDivision = first['division']?.toString() ?? deptDivision;
    }

    // 4. Resolve site
    String siteName = isPlatformAdminResolved
        ? 'Global'
        : (roleCode == 'admin' ? 'Corporate Headquarters' : 'Main Facility');

    final dynamic sitesRaw = data['sites'];
    if (sitesRaw is Map) {
      siteName = sitesRaw['name']?.toString() ?? siteName;
    } else if (sitesRaw is List &&
        sitesRaw.isNotEmpty &&
        sitesRaw.first is Map) {
      final first = sitesRaw.first as Map;
      siteName = first['name']?.toString() ?? siteName;
    }

    // 5. Derive permissions and format role
    final List<String> permissions;
    final String formattedRole;
    if (isPlatformAdminResolved) {
      formattedRole = 'Platform Administrator';
      permissions = const [
        'Global Platform Administration',
        'Create & Manage Organizations',
        'Cross-Company Configuration & Audits',
        'Platform Security & Infrastructure',
        'Global Broadcast Dispatch',
      ];
    } else if (roleCode == 'admin') {
      formattedRole = 'System Administrator';
      permissions = const [
        'Full System Configuration Access',
        'User, Department & Site Governance',
        'Security Policy & 2FA Enforcement',
        'System Audit Log Inspection',
        'Emergency Broadcast Dispatch',
      ];
    } else if (roleCode == 'manager') {
      formattedRole = 'Manager / Action Approver';
      permissions = const [
        'Create & Assign Actions',
        'Approve Action Closures & Evidence',
        'Escalate SLA Breaches & Overdue Items',
        'Export Compliance & Audit Reports',
        'Manage Department Team Members',
      ];
    } else {
      roleCode = 'staff';
      formattedRole = 'Action Assignee / Field Worker';
      permissions = const [
        'View Assigned Actions',
        'Submit Action Progress & Evidence Updates',
        'Request Action Extensions & Reassignments',
        'Access Field Safety Documentation',
      ];
    }

    final statusStr = ((data['status'] as String?) ?? 'active')
        .toLowerCase()
        .trim();
    final bool isActive = data['is_active'] != false;

    // Resolve organization (with default fallback to Sobha for company tenants)
    Organization? organization;
    String? orgId;
    String orgName = '';

    if (isPlatformAdminResolved) {
      // Platform admin belongs strictly to the platform itself (Tier 0 Global),
      // never bound to any single tenant company even if a legacy profile row exists.
      organization = null;
      orgId = null;
      orgName = '';
    } else {
      organization = Organization.sobha();
      orgId = Organization.sobhaId;
      orgName = Organization.sobhaName;

      final dynamic orgsRaw = data['organizations'];
      if (orgsRaw is Map) {
        organization = Organization.fromJson(
          Map<String, dynamic>.from(orgsRaw),
        );
        orgId = organization.id;
        orgName = organization.name;
      } else if (orgsRaw is List &&
          orgsRaw.isNotEmpty &&
          orgsRaw.first is Map) {
        organization = Organization.fromJson(
          Map<String, dynamic>.from(orgsRaw.first as Map),
        );
        orgId = organization.id;
        orgName = organization.name;
      } else if (data['organization_id'] != null) {
        orgId = data['organization_id'].toString();
        if (orgId == Organization.sobhaId) {
          organization = Organization.sobha();
          orgName = organization.name;
        } else {
          orgName =
              (data['organization_name'] as String?) ?? Organization.sobhaName;
          organization = Organization(
            id: orgId,
            name: orgName,
            code: orgName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_'),
            isActive: true,
          );
        }
      }
    }

    final userProfile = UserProfile(
      id: (data['id'] as String?) ?? authUserId,
      name: (data['full_name'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      phone: (data['phone'] as String?) ?? '',
      designation:
          (data['designation'] as String?) ??
          (isPlatformAdminResolved ? 'Platform Administrator' : ''),
      department: deptName,
      division: deptDivision,
      site: siteName,
      team: '',
      role: formattedRole,
      supervisor: '',
      certifications: '',
      accountStatus: statusStr == 'active' && isActive ? 'Active' : statusStr,
      permissions: permissions,
      avatarUrl: data['avatar_url'] as String?,
      organizationId: orgId,
      organizationName: orgName,
      departmentId: data['department_id']?.toString(),
      siteId: data['site_id']?.toString(),
    );

    return AuthProfileData(
      userProfile: userProfile,
      roleCode: roleCode,
      status: statusStr,
      isActive: isActive,
      isPrimaryAdmin: isPrimaryAdmin,
      isPlatformAdmin: isPlatformAdminResolved,
      organizationId: orgId,
      organization: organization,
    );
  }

  /// Loads the authoritative profile from public.profiles by auth UID,
  /// with explicit classification between success, not found, and error.
  Future<ProfileFetchResult> fetchProfileResult(String authUserId) async {
    final client = _client;
    if (client == null) {
      if (_currentProfileData != null) {
        return ProfileFetchSuccess(_currentProfileData!);
      }
      return const ProfileFetchError('Authentication service is unavailable.');
    }

    try {
      // 1. Check whether this authenticated user exists in public.platform_admins
      // BEFORE requiring a public.profiles row.
      bool isPlatformAdmin = false;
      Object? platformAdminTableError;
      Object? platformAdminRpcError;

      // Method A: Check via SECURITY DEFINER function is_platform_admin()
      // This is the canonical PostgreSQL security-barrier helper that executes
      // with database owner privileges, bypassing table-level GRANT requirements
      // and RLS self-referencing recursion on public.platform_admins.
      try {
        final dynamic rpcResult = await client.rpc('is_platform_admin');
        if (rpcResult == true) {
          isPlatformAdmin = true;
          debugPrint(
            '[AuthService] User $authUserId verified as Platform Admin via is_platform_admin() RPC',
          );
        }
      } catch (rpcErr) {
        platformAdminRpcError = rpcErr;
        debugPrint('[AuthService] is_platform_admin() RPC note: $rpcErr');
      }

      // Method B: Fallback direct query on public.platform_admins if RPC did not verify
      if (!isPlatformAdmin) {
        try {
          final dynamic platformAdminRow = await client
              .from('platform_admins')
              .select('user_id')
              .eq('user_id', authUserId)
              .maybeSingle();
          if (platformAdminRow != null) {
            isPlatformAdmin = true;
            debugPrint(
              '[AuthService] User $authUserId verified as Platform Admin via platform_admins table',
            );
          }
        } catch (tableErr) {
          platformAdminTableError = tableErr;
          debugPrint(
            '[AuthService] platform_admins table query error for $authUserId: $tableErr',
          );
        }
      }

      Map<String, dynamic>? profileMap;

      // 2. Primary path: Canonical joined query shape matching roles, departments, sites
      try {
        final dynamic joinedRaw = await client
            .from('profiles')
            .select('''
              id,
              full_name,
              email,
              phone,
              designation,
              department_id,
              site_id,
              role_id,
              organization_id,
              status,
              is_active,
              is_primary_admin,
              avatar_url,
              roles(id, name, code),
              departments(id, name, division),
              sites(id, name),
              organizations(id, name, code, is_active)
            ''')
            .eq('id', authUserId)
            .maybeSingle();

        if (joinedRaw != null) {
          profileMap = Map<String, dynamic>.from(joinedRaw as Map);
        }
      } catch (joinedError) {
        debugPrint(
          'Joined profile query note: $joinedError. Attempting direct query fallback.',
        );
      }

      // 3. Direct query fallback if joined query returned null or threw
      if (profileMap == null) {
        final dynamic raw = await client
            .from('profiles')
            .select()
            .eq('id', authUserId)
            .maybeSingle();

        if (raw != null) {
          profileMap = Map<String, dynamic>.from(raw as Map);

          // Lazily resolve role if not already populated
          if (profileMap['roles'] == null && profileMap['role_id'] != null) {
            try {
              final dynamic roleRow = await client
                  .from('roles')
                  .select('id, name, code')
                  .eq('id', profileMap['role_id'])
                  .maybeSingle();
              if (roleRow != null) {
                profileMap['roles'] = roleRow;
              }
            } catch (e) {
              debugPrint('Error looking up role by role_id: $e');
            }
          }

          // Lazily resolve department if not admin
          if (profileMap['departments'] == null &&
              profileMap['department_id'] != null &&
              profileMap['is_primary_admin'] != true) {
            try {
              final dynamic deptRow = await client
                  .from('departments')
                  .select('id, name, division')
                  .eq('id', profileMap['department_id'])
                  .maybeSingle();
              if (deptRow != null) {
                profileMap['departments'] = deptRow;
              }
            } catch (e) {
              debugPrint('Error looking up department: $e');
            }
          }

          // Lazily resolve site if not admin
          if (profileMap['sites'] == null &&
              profileMap['site_id'] != null &&
              profileMap['is_primary_admin'] != true) {
            try {
              final dynamic siteRow = await client
                  .from('sites')
                  .select('id, name')
                  .eq('id', profileMap['site_id'])
                  .maybeSingle();
              if (siteRow != null) {
                profileMap['sites'] = siteRow;
              }
            } catch (e) {
              debugPrint('Error looking up site: $e');
            }
          }
        }
      }

      // 4. Platform Admin Profile Synthesis:
      // If the authenticated user is a Platform Admin and has no row in public.profiles,
      // return a successful AuthProfileData without requiring a public.profiles row
      // or synthesizing any company-bound organization.
      if (isPlatformAdmin && profileMap == null) {
        final currentUser = client.auth.currentUser;
        final email = (currentUser != null && currentUser.id == authUserId)
            ? (currentUser.email ?? '')
            : '';
        final rawFullName = currentUser?.userMetadata?['full_name'] as String?;
        final fullName = (rawFullName != null && rawFullName.trim().isNotEmpty)
            ? rawFullName.trim()
            : (email.isNotEmpty
                  ? email.split('@').first
                  : 'Platform Administrator');

        final synthMap = <String, dynamic>{
          'id': authUserId,
          'full_name': fullName,
          'email': email,
          'designation': 'Platform Administrator',
          'status': 'active',
          'is_active': true,
          'is_primary_admin': false,
          'is_platform_admin': true,
          'organization_id': null,
        };

        final profileData = parseProfileData(
          synthMap,
          authUserId,
          isPlatformAdmin: true,
        );
        _currentProfileData = profileData;
        return ProfileFetchSuccess(profileData);
      }

      // 5. Standard non-platform user: if no profile found in public.profiles, return NotFound.
      // If a database error occurred during platform admin verification and the user has no company profile,
      // surface the exact database error rather than silently claiming "no profile found".
      if (profileMap == null) {
        if (!isPlatformAdmin &&
            platformAdminRpcError != null &&
            platformAdminTableError != null) {
          return ProfileFetchError(
            'Database error verifying platform administrator status: $platformAdminTableError (RPC error: $platformAdminRpcError)',
          );
        }
        return const ProfileFetchNotFound();
      }

      // 6. Account Request Approval Verification:
      // If this is not a Platform Admin, verify whether an account request exists for this user.
      // If an account request exists and its status is NOT 'approved' (e.g. pending_admin_approval,
      // pending_email_verification, or rejected), the user is strictly NOT approved, and any
      // profile record MUST NOT be returned as an active profile.
      if (!isPlatformAdmin) {
        try {
          final dynamic reqRow = await client
              .from('account_requests')
              .select('id, status')
              .eq('auth_user_id', authUserId)
              .maybeSingle();
          if (reqRow is Map) {
            final st =
                (reqRow['status'] as String?)?.toLowerCase().trim() ?? '';
            if (st == 'pending_admin_approval' ||
                st == 'pending_approval' ||
                st == 'pending_email_verification' ||
                st == 'rejected') {
              debugPrint(
                '[AuthService] User $authUserId access blocked: account request status is "$st".',
              );
              return const ProfileFetchNotFound();
            }
          }
        } catch (reqCheckErr) {
          debugPrint(
            'Error verifying account_requests in fetchProfileResult: $reqCheckErr',
          );
        }
      }

      final profileData = parseProfileData(
        profileMap,
        authUserId,
        isPlatformAdmin: isPlatformAdmin,
      );

      // Automatically sync active profile cache when loading profile for current user
      final currentAuthId =
          _currentSession?.user.id ?? _client?.auth.currentUser?.id;
      if (currentAuthId == null || currentAuthId == authUserId) {
        _currentProfileData = profileData;
      }

      return ProfileFetchSuccess(profileData);
    } on SocketException catch (e) {
      debugPrint('Network error loading profile: $e');
      return const ProfileFetchError(
        'Network error connecting to database. Please check your internet connection.',
      );
    } on TimeoutException catch (e) {
      debugPrint('Timeout loading profile: $e');
      return const ProfileFetchError(
        'Connection timed out loading profile. Please try again.',
      );
    } catch (e) {
      debugPrint('Database error loading profile: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('network') ||
          msg.contains('socket') ||
          msg.contains('failed host lookup') ||
          msg.contains('clientexception')) {
        return const ProfileFetchError(
          'Network error connecting to database. Please check your internet connection.',
        );
      }
      return ProfileFetchError('Database error loading user profile: $e');
    }
  }

  /// Convenience wrapper returning AuthProfileData? for existing call sites
  Future<AuthProfileData?> fetchProfile(String authUserId) async {
    final result = await fetchProfileResult(authUserId);
    if (result is ProfileFetchSuccess) {
      return result.profileData;
    }
    return null;
  }

  /// Loads the authoritative ManagerContext for an authenticated manager user,
  /// including profile details, organization context, and active manager scopes.
  Future<ManagerContext?> fetchManagerContext(String authUserId) async {
    final client = _client;
    if (client == null) return null;

    try {
      final profileResult = await fetchProfileResult(authUserId);
      if (profileResult is! ProfileFetchSuccess) {
        debugPrint(
          '[AuthService] fetchManagerContext: profile not found for $authUserId',
        );
        return null;
      }

      final profileData = profileResult.profileData;
      final orgId = profileData.organizationId ?? Organization.sobhaId;
      final orgName = profileData.organization?.name ?? Organization.sobhaName;

      // Query active manager scopes joined with departments and sites
      final scopesResponse = await client
          .from('manager_scopes')
          .select('''
            department_id,
            site_id,
            departments:department_id(id, name, is_active),
            sites:site_id(id, name, is_active)
          ''')
          .eq('manager_profile_id', authUserId);

      final List<ManagerScopeItem> scopes = [];
      for (final item in scopesResponse) {
        final deptMap = item['departments'] as Map<String, dynamic>?;
        final siteMap = item['sites'] as Map<String, dynamic>?;

        final deptId = (item['department_id'] as String?) ?? '';
        final siteId = (item['site_id'] as String?) ?? '';
        final deptName = deptMap?['name']?.toString() ?? 'Department';
        final siteName = siteMap?['name']?.toString() ?? 'Site';
        final deptActive = deptMap?['is_active'] != false;
        final siteActive = siteMap?['is_active'] != false;

        // Only include active department and active site combinations
        if (deptId.isNotEmpty &&
            siteId.isNotEmpty &&
            deptActive &&
            siteActive) {
          scopes.add(
            ManagerScopeItem(
              departmentId: deptId,
              departmentName: deptName,
              siteId: siteId,
              siteName: siteName,
            ),
          );
        }
      }

      return ManagerContext(
        authUserId: authUserId,
        profile: profileData.userProfile,
        organizationId: orgId,
        organizationName: orgName,
        scopes: scopes,
        isActive: profileData.isActive && profileData.status == 'active',
      );
    } catch (e, st) {
      debugPrint('[AuthService] Error fetching manager context: $e\n$st');
      return null;
    }
  }

  /// Authoritatively verifies whether the currently authenticated Supabase user
  /// is a designated Platform Administrator by querying PostgreSQL is_platform_admin()
  /// and public.platform_admins. Returns true ONLY if confirmed by the database.
  Future<bool> verifyPlatformAdminAuthority() async {
    final client = _client;
    if (client == null || !SupabaseConfig.isInitialized) {
      return isPlatformAdmin;
    }
    final user = currentUser;
    if (user == null) {
      return isPlatformAdmin;
    }

    bool verified = false;
    try {
      final dynamic rpcResult = await client.rpc('is_platform_admin');
      if (rpcResult == true) {
        verified = true;
      }
    } catch (e) {
      debugPrint('[AuthService] verifyPlatformAdminAuthority RPC note: $e');
    }

    if (!verified) {
      try {
        final dynamic row = await client
            .from('platform_admins')
            .select('user_id')
            .eq('user_id', user.id)
            .maybeSingle();
        if (row != null) {
          verified = true;
        }
      } catch (e) {
        debugPrint('[AuthService] verifyPlatformAdminAuthority table note: $e');
      }
    }

    return verified;
  }

  /// Fetches an organization by its unique slug code.
  /// Seamlessly falls back to Sobha for 'sobha' or when running in offline/pre-migration environments.
  Future<Organization?> fetchOrganizationByCode(String code) async {
    final trimmed = code.trim().toLowerCase();
    if (trimmed.isEmpty) return null;

    final client = _client;
    if (client == null) {
      if (trimmed == Organization.sobhaCode) {
        return Organization.sobha();
      }
      return null;
    }

    try {
      final dynamic row = await client
          .from('organizations')
          .select()
          .eq('code', trimmed)
          .maybeSingle();

      if (row != null && row is Map) {
        return Organization.fromJson(Map<String, dynamic>.from(row));
      }
    } catch (e) {
      debugPrint('Error fetching organization by code "$code": $e');
    }

    if (trimmed == Organization.sobhaCode) {
      return Organization.sobha();
    }
    return null;
  }

  /// Fetches an organization by its primary ID.
  /// Seamlessly falls back to Sobha for sobhaId or when running in offline/pre-migration environments.
  Future<Organization?> fetchOrganizationById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;

    final client = _client;
    if (client == null) {
      if (trimmed == Organization.sobhaId) {
        return Organization.sobha();
      }
      return null;
    }

    try {
      final dynamic row = await client
          .from('organizations')
          .select()
          .eq('id', trimmed)
          .maybeSingle();

      if (row != null && row is Map) {
        return Organization.fromJson(Map<String, dynamic>.from(row));
      }
    } catch (e) {
      debugPrint('Error fetching organization by id "$id": $e');
    }

    if (trimmed == Organization.sobhaId) {
      return Organization.sobha();
    }
    return null;
  }

  /// Fetches all registered organizations (active only by default).
  /// Falls back to Sobha when table is not yet accessible or in offline/pre-migration environments.
  Future<List<Organization>> fetchOrganizations({
    bool activeOnly = true,
  }) async {
    final client = _client;
    if (client == null) {
      return [Organization.sobha()];
    }

    try {
      var query = client.from('organizations').select();
      if (activeOnly) {
        query = query.eq('is_active', true);
      }
      final dynamic rows = await query.order('name');
      if (rows != null && rows is List && rows.isNotEmpty) {
        return rows
            .map(
              (r) => Organization.fromJson(Map<String, dynamic>.from(r as Map)),
            )
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching organizations: $e');
    }

    return [Organization.sobha()];
  }

  /// Fetches account request status from public.account_requests with typed outcome distinction.
  Future<AccountRequestFetchResult> fetchAccountRequestResult(
    String authUserId, {
    String? email,
  }) async {
    final client = _client;
    if (client == null) {
      return const AccountRequestFetchError(
        'Authentication service is unavailable.',
      );
    }

    try {
      dynamic raw = await client
          .from('account_requests')
          .select(
            'id, auth_user_id, organization_id, full_name, email, status, is_email_verified, rejection_reason, requested_role_id',
          )
          .eq('auth_user_id', authUserId)
          .maybeSingle();

      if (raw == null && email != null && email.trim().isNotEmpty) {
        raw = await client
            .from('account_requests')
            .select(
              'id, auth_user_id, organization_id, full_name, email, status, is_email_verified, rejection_reason, requested_role_id',
            )
            .eq('email', email.trim())
            .maybeSingle();
      }

      if (raw == null) {
        return const AccountRequestFetchNotFound();
      }

      final data = Map<String, dynamic>.from(raw as Map);
      String? reqRoleCode;

      final requestedRoleId = data['requested_role_id'] as String?;
      if (requestedRoleId != null && requestedRoleId.isNotEmpty) {
        try {
          final dynamic roleRow = await client
              .from('roles')
              .select('id, name, code')
              .eq('id', requestedRoleId)
              .maybeSingle();
          if (roleRow != null && roleRow is Map) {
            reqRoleCode = roleRow['code'] as String?;
          }
        } catch (roleErr) {
          debugPrint(
            'Error looking up role code for requested_role_id $requestedRoleId: $roleErr',
          );
        }
      }

      final accountData = AuthAccountRequestData(
        id: (data['id'] as String?) ?? '',
        authUserId: (data['auth_user_id'] as String?) ?? authUserId,
        fullName: (data['full_name'] as String?) ?? '',
        email: (data['email'] as String?) ?? '',
        status: (data['status'] as String?) ?? 'pending_approval',
        isEmailVerified: data['is_email_verified'] == true,
        rejectionReason: data['rejection_reason'] as String?,
        requestedRoleCode: reqRoleCode,
        organizationId: data['organization_id'] as String?,
      );

      return AccountRequestFetchSuccess(accountData);
    } on SocketException catch (e) {
      debugPrint('Network error loading account request: $e');
      return const AccountRequestFetchError(
        'Network error connecting to database. Please check your internet connection.',
      );
    } on TimeoutException catch (e) {
      debugPrint('Timeout loading account request: $e');
      return const AccountRequestFetchError(
        'Connection timed out loading account request. Please try again.',
      );
    } catch (e) {
      debugPrint('Database error loading account request: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('network') ||
          msg.contains('socket') ||
          msg.contains('failed host lookup') ||
          msg.contains('clientexception')) {
        return const AccountRequestFetchError(
          'Network error connecting to database. Please check your internet connection.',
        );
      }
      return AccountRequestFetchError(
        'Database error loading account request: $e',
      );
    }
  }

  /// Convenience wrapper returning AuthAccountRequestData? for callers.
  /// Throws when a database error occurs so errors are not silently swallowed.
  Future<AuthAccountRequestData?> fetchAccountRequest(String authUserId) async {
    final result = await fetchAccountRequestResult(authUserId);
    if (result is AccountRequestFetchSuccess) {
      return result.accountRequest;
    }
    if (result is AccountRequestFetchError) {
      throw Exception(result.errorMessage);
    }
    return null;
  }

  /// Sign out the current user session and reset cached profile state.
  Future<void> signOut() async {
    final client = _client;
    _currentProfileData = null;
    _currentSession = null;

    // Clear personal task in-memory store for session isolation
    MockCalendarTaskStore.instance.clear();

    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (e) {
        debugPrint('Sign-out error: $e');
      }
    }
  }

  /// Initializes the onAuthStateChange listener handling session persistence,
  /// token refresh, and profile loading on reload.
  void initializeAuthStateListener({
    void Function(AuthChangeEvent event, Session? session)? onStateChanged,
  }) {
    final client = _client;
    if (client == null) return;

    _authSubscription?.cancel();
    _authSubscription = client.auth.onAuthStateChange.listen(
      (data) async {
        final event = data.event;
        final session = data.session;
        _currentSession = session;

        try {
          switch (event) {
            case AuthChangeEvent.initialSession:
            case AuthChangeEvent.signedIn:
            case AuthChangeEvent.tokenRefreshed:
            case AuthChangeEvent.userUpdated:
              if (session != null) {
                _currentProfileData = await fetchProfile(session.user.id);
              } else {
                _currentProfileData = null;
              }
              break;
            case AuthChangeEvent.passwordRecovery:
              _isPasswordRecoveryActive = true;
              if (session != null) {
                _currentProfileData = await fetchProfile(session.user.id);
              }
              break;
            case AuthChangeEvent.signedOut:
              _currentProfileData = null;
              _currentSession = null;
              _isPasswordRecoveryActive = false;
              _capturedAuthLinkError = null;
              break;
            default:
              break;
          }
        } catch (e) {
          debugPrint('Auth event handling error: $e');
        }

        onStateChanged?.call(event, session);
      },
      onError: (Object error) {
        debugPrint('Auth state listener error: $error');
      },
    );
  }

  /// Deletes the currently authenticated user's account using the atomic RPC
  /// `public.delete_self_account()`.
  /// Cascades deletions through all related records, reassigns created actions to admin,
  /// signs out the user, and clears all session state.
  Future<void> deleteSelfAccount() async {
    final client = _client;
    if (client == null) {
      throw Exception('Authentication service is currently unavailable.');
    }
    try {
      await client.rpc('delete_self_account');
    } catch (e) {
      debugPrint('Error deleting account via delete_self_account RPC: $e');
      rethrow;
    } finally {
      await signOut();
    }
  }

  /// Whether an active Supabase client is configured
  bool get hasClient => _client != null;

  /// Creates the exact initial signup metadata payload for Staff account requests.
  /// Strictly adheres to the database trigger contract (`trg_on_auth_user_created`):
  /// - Excludes supervisor_id, manager_id, scopes array, and admin role.
  /// - Excludes email from metadata (authoritative email is passed directly to signUp).
  /// - team_id is included only when selected (omitted otherwise).
  static Map<String, dynamic> buildStaffSignupMetadata({
    required String fullName,
    String? phone,
    required String designation,
    required String departmentId,
    required String siteId,
    String? teamId,
  }) {
    final meta = <String, dynamic>{
      'full_name': fullName.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      'designation': designation.trim(),
      'requested_role': 'staff',
      'department_id': departmentId.trim(),
      'site_id': siteId.trim(),
    };
    if (teamId != null && teamId.trim().isNotEmpty) {
      meta['team_id'] = teamId.trim();
    }
    return meta;
  }

  /// Creates the exact initial signup metadata payload for Manager account requests.
  /// Strictly adheres to the database trigger contract (`trg_on_auth_user_created`):
  /// - Includes scopes array with exact department_id and site_id pairs.
  /// - Excludes team_id, supervisor_id, manager_id, and admin role.
  /// - Excludes email from metadata (authoritative email is passed directly to signUp).
  static Map<String, dynamic> buildManagerSignupMetadata({
    required String fullName,
    String? phone,
    required String designation,
    required List<ManagerScopeItem> scopes,
  }) {
    return <String, dynamic>{
      'full_name': fullName.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      'designation': designation.trim(),
      'requested_role': 'manager',
      'scopes': scopes
          .map(
            (s) => {
              'department_id': s.departmentId.trim(),
              'site_id': s.siteId.trim(),
            },
          )
          .toList(),
    };
  }

  /// Fetches active departments from public.departments.
  /// In production / real Supabase signup, fails if data cannot be retrieved so
  /// the form displays a retry state rather than submitting mock/fake IDs.
  Future<List<DepartmentOption>> fetchDepartments({
    String? organizationId,
    bool fallbackToDefaults = false,
  }) async {
    final client = _client;
    if (client == null) {
      if (fallbackToDefaults) return defaultDepartments;
      throw Exception('Database client is not available.');
    }
    try {
      var query = client
          .from('departments')
          .select('id, name, code')
          .eq('is_active', true);
      if (organizationId != null && organizationId.isNotEmpty) {
        query = query.eq('organization_id', organizationId);
      }
      final dynamic raw = await query.order('name');
      if (raw is List && raw.isNotEmpty) {
        return raw.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return DepartmentOption(
            id: map['id']?.toString() ?? '',
            name: map['name']?.toString() ?? '',
            code: map['code']?.toString() ?? '',
          );
        }).toList();
      }
      if (fallbackToDefaults) return defaultDepartments;
      throw Exception('No active departments found in database.');
    } catch (e) {
      if (fallbackToDefaults) return defaultDepartments;
      rethrow;
    }
  }

  /// Fetches active sites from public.sites.
  Future<List<SiteOption>> fetchSites({
    String? organizationId,
    bool fallbackToDefaults = false,
  }) async {
    final client = _client;
    if (client == null) {
      if (fallbackToDefaults) return defaultSites;
      throw Exception('Database client is not available.');
    }
    try {
      var query = client
          .from('sites')
          .select('id, name, code')
          .eq('is_active', true);
      if (organizationId != null && organizationId.isNotEmpty) {
        query = query.eq('organization_id', organizationId);
      }
      final dynamic raw = await query.order('name');
      if (raw is List && raw.isNotEmpty) {
        return raw.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return SiteOption(
            id: map['id']?.toString() ?? '',
            name: map['name']?.toString() ?? '',
            code: map['code']?.toString() ?? '',
          );
        }).toList();
      }
      if (fallbackToDefaults) return defaultSites;
      throw Exception('No active sites found in database.');
    } catch (e) {
      if (fallbackToDefaults) return defaultSites;
      rethrow;
    }
  }

  /// Fetches active teams from public.teams.
  Future<List<TeamOption>> fetchTeams({
    String? organizationId,
    bool fallbackToDefaults = false,
  }) async {
    final client = _client;
    if (client == null) {
      if (fallbackToDefaults) return defaultTeams;
      throw Exception('Database client is not available.');
    }
    try {
      var query = client
          .from('teams')
          .select('id, name, department_id, is_active')
          .eq('is_active', true);
      if (organizationId != null && organizationId.isNotEmpty) {
        query = query.eq('organization_id', organizationId);
      }
      final dynamic raw = await query.order('name');
      if (raw is List && raw.isNotEmpty) {
        return raw.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return TeamOption(
            id: map['id']?.toString() ?? '',
            name: map['name']?.toString() ?? '',
            departmentId: map['department_id']?.toString() ?? '',
            isActive: map['is_active'] != false,
          );
        }).toList();
      }
      if (fallbackToDefaults) return defaultTeams;
      return const [];
    } catch (e) {
      if (fallbackToDefaults) return defaultTeams;
      rethrow;
    }
  }

  /// Performs real Supabase Auth signUp with email, password, and raw_user_meta_data.
  /// The database trigger `trg_on_auth_user_created` creates public.account_requests.
  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> data,
  }) async {
    final client = _client;
    if (client == null) {
      return const AuthSignUpResult.failure(
        'Authentication service is currently unavailable. Please try again later.',
      );
    }

    try {
      final response = await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: data,
      );

      final user = response.user;
      if (user == null) {
        return const AuthSignUpResult.failure(
          'Unable to create account. Please verify your details and try again.',
        );
      }

      _currentSession = response.session;

      return AuthSignUpResult.success(user: user, session: response.session);
    } on AuthException catch (e) {
      final sanitized = sanitizeSignUpError(e.message);
      final isDup = _isDuplicateEmailError(e.message);
      return AuthSignUpResult.failure(sanitized, isDuplicateEmail: isDup);
    } on SocketException {
      return const AuthSignUpResult.failure(
        'Network connection error. Please check your internet connection and try again.',
        isNetworkError: true,
      );
    } on TimeoutException {
      return const AuthSignUpResult.failure(
        'Connection timed out. Please check your internet connection and try again.',
        isNetworkError: true,
      );
    } catch (e) {
      final sanitized = sanitizeSignUpError(e.toString());
      final isNet =
          sanitized.contains('Network') || sanitized.contains('internet');
      return AuthSignUpResult.failure(sanitized, isNetworkError: isNet);
    }
  }

  static bool _isDuplicateEmailError(String raw) {
    final msg = raw.toLowerCase();
    return msg.contains('already registered') ||
        msg.contains('user already exists') ||
        msg.contains('email already exists') ||
        msg.contains('duplicate key value');
  }

  /// Sanitizes signup errors without leaking raw SQL, database triggers, or internals
  static String sanitizeSignUpError(String rawMessage) {
    final msg = rawMessage.toLowerCase();

    // 1. Duplicate email
    if (_isDuplicateEmailError(rawMessage)) {
      return 'An account with this email already exists. Please sign in or use a different email.';
    }

    // 2. Weak password
    if (msg.contains('password') &&
        (msg.contains('short') ||
            msg.contains('least') ||
            msg.contains('weak') ||
            msg.contains('6'))) {
      return 'Password must be at least 6 characters long.';
    }

    // 3. Invalid email format
    if (msg.contains('invalid email') ||
        msg.contains('unable to validate email') ||
        msg.contains('valid email')) {
      return 'Please enter a valid email address.';
    }

    // 4. Rate limit
    if (msg.contains('rate limit') ||
        msg.contains('over_email_send_rate_limit') ||
        msg.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }

    // 5. Network / connection
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('failed host lookup') ||
        msg.contains('clientexception') ||
        msg.contains('connection timed out')) {
      return 'Network connection error. Please check your internet connection and try again.';
    }

    // 6. Organization / Trigger validation errors (sanitized)
    if (msg.contains('department') &&
        (msg.contains('invalid') ||
            msg.contains('inactive') ||
            msg.contains('not exist'))) {
      return 'The selected department is invalid or inactive. Please select an active department.';
    }
    if (msg.contains('site') &&
        (msg.contains('invalid') ||
            msg.contains('inactive') ||
            msg.contains('not exist'))) {
      return 'The selected site is invalid or inactive. Please select an active site.';
    }
    if (msg.contains('team') &&
        (msg.contains('belong') || msg.contains('inactive'))) {
      return 'The selected team does not belong to your organization or is inactive. Please re-select your team.';
    }
    if (msg.contains('duplicate scope')) {
      return 'Duplicate management scopes detected. Please remove any repeated department and site combinations.';
    }
    if (msg.contains('scopes array') || msg.contains('at least one')) {
      return 'Please configure at least one valid Department and Site scope.';
    }
    if (msg.contains('security violation') ||
        msg.contains('admin role cannot be requested') ||
        msg.contains('admin role')) {
      return 'Administrator accounts must be created by existing system administrators.';
    }

    // 7. Generic database / Postgres errors -> safe friendly message
    if (msg.contains('postgres') ||
        msg.contains('pgrst') ||
        msg.contains('syntax error') ||
        msg.contains('violates') ||
        msg.contains('constraint') ||
        msg.contains('trigger') ||
        msg.contains('database error')) {
      return 'Unable to complete registration due to an organizational validation error. Please verify your selections or contact your administrator.';
    }

    return 'Unable to complete registration. Please check your details and try again.';
  }

  /// Disposes active listener subscriptions
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
  }

  /// Sanitizes auth error messages into user-friendly strings without leaking database internals
  String _sanitizeAuthError(String rawMessage) {
    final msg = rawMessage.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials') ||
        msg.contains('invalid grant') ||
        msg.contains('invalid email or password')) {
      return 'Invalid username or password';
    }
    if (msg.contains('email not confirmed') ||
        msg.contains('email_not_confirmed')) {
      return 'Please verify your email address before signing in.';
    }
    if (msg.contains('rate limit') ||
        msg.contains('over_email_send_rate_limit') ||
        msg.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (msg.contains('user not found')) {
      return 'Invalid username or password';
    }
    return 'Invalid username or password';
  }
}
