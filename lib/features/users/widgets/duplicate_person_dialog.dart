import 'package:flutter/material.dart';

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
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFD97706),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Person already exists',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'A record with this contact info was found in ActionFlow.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB45309),
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
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    if (existingPerson.designation.isNotEmpty)
                                      Text(
                                        existingPerson.designation,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
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
                                      ? const Color(0xFFDBEAFE)
                                      : const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isInternal ? 'Internal' : 'External',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isInternal
                                        ? const Color(0xFF1D4ED8)
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20, color: Color(0xFFE2E8F0)),
                          _detailRow(
                            Icons.email_outlined,
                            'Email',
                            existingPerson.email,
                          ),
                          const SizedBox(height: 6),
                          _detailRow(
                            Icons.phone_outlined,
                            'Phone',
                            existingPerson.phone,
                          ),
                          if (isInternal &&
                              existingPerson.department.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _detailRow(
                              Icons.business_outlined,
                              'Department',
                              existingPerson.department,
                            ),
                          ],
                          if (!isInternal &&
                              existingPerson.company.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _detailRow(
                              Icons.corporate_fare_outlined,
                              'Company',
                              existingPerson.company,
                            ),
                          ],
                          if (existingPerson.site.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _detailRow(
                              Icons.location_on_outlined,
                              'Site',
                              existingPerson.site,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Would you like to select and use this existing person instead of creating a duplicate?',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
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
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
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

  Widget _detailRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
