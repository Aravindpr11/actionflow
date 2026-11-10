import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/person.dart';

class DuplicatePersonDialog extends StatelessWidget {
  const DuplicatePersonDialog({
    required this.existingPerson,
    this.duplicateReason = 'email or phone number',
    super.key,
  });

  final Person existingPerson;
  final String duplicateReason;

  @override
  Widget build(BuildContext context) {
    final isInternal = existingPerson.type == PersonType.internalUser;

    return Dialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFFD97706).withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFF59E0B),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Person already exists',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'A record with this contact info was found in ActionFlow.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Person Details Card
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
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
                              CircleAvatar(
                                backgroundColor: isInternal
                                    ? const Color(0xFF1565C0)
                                    : const Color(0xFF475569),
                                radius: 18,
                                child: Text(
                                  existingPerson.name.isNotEmpty
                                      ? existingPerson.name[0].toUpperCase()
                                      : 'P',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      existingPerson.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                    ),
                                    if (existingPerson.designation.isNotEmpty)
                                      Text(
                                        existingPerson.designation,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary(
                                            context,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isInternal
                                      ? const Color(0xFF1565C0)
                                            .withValues(alpha: 0.15)
                                      : const Color(0xFF7E57C2)
                                            .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isInternal ? 'Internal' : 'External',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isInternal
                                        ? const Color(0xFF38BDF8)
                                        : const Color(0xFFA78BFA),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Divider(
                            height: 20,
                            color: AppTheme.cardBorder(context),
                          ),
                          _detailRow(
                            context,
                            Icons.email_outlined,
                            'Email',
                            existingPerson.email,
                          ),
                          const SizedBox(height: 6),
                          _detailRow(
                            context,
                            Icons.phone_outlined,
                            'Phone',
                            existingPerson.phone,
                          ),
                          if (isInternal &&
                              existingPerson.department.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _detailRow(
                              context,
                              Icons.business_outlined,
                              'Department',
                              existingPerson.department,
                            ),
                          ],
                          if (!isInternal &&
                              existingPerson.company.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _detailRow(
                              context,
                              Icons.corporate_fare_outlined,
                              'Company',
                              existingPerson.company,
                            ),
                          ],
                          if (existingPerson.site.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _detailRow(
                              context,
                              Icons.location_on_outlined,
                              'Site',
                              existingPerson.site,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Would you like to select and use this existing person instead of creating a duplicate?',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              // Actions
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.containerBg(context),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border(
                    top: BorderSide(color: AppTheme.cardBorder(context)),
                  ),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary(context),
                        side: BorderSide(color: AppTheme.cardBorder(context)),
                      ),
                      child: const Text('Cancel / Edit'),
                    ),
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(existingPerson),
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                      ),
                      label: const Text('Use Existing Person'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary(context)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary(context),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textPrimary(context),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
