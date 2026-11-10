import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/request_models.dart';

/// Reusable filter and search bar for Request Management
class RequestFilterBar extends StatelessWidget {
  const RequestFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.selectedType,
    required this.onTypeChanged,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.selectedPriority,
    required this.onPriorityChanged,
    required this.selectedSort,
    required this.onSortChanged,
    required this.onResetFilters,
    this.showStatusFilter = true,
    this.selectedDepartment = 'All Departments',
    this.availableDepartments = const ['All Departments'],
    this.onDepartmentChanged,
    this.selectedSite = 'All Sites',
    this.availableSites = const ['All Sites'],
    this.onSiteChanged,
    this.dateRange,
    this.onDateRangeChanged,
  });

  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String selectedType;
  final ValueChanged<String> onTypeChanged;
  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;
  final String selectedPriority;
  final ValueChanged<String> onPriorityChanged;
  final String selectedSort;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onResetFilters;
  final bool showStatusFilter;

  // Dedicated Department & Site filters
  final String selectedDepartment;
  final List<String> availableDepartments;
  final ValueChanged<String>? onDepartmentChanged;

  final String selectedSite;
  final List<String> availableSites;
  final ValueChanged<String>? onSiteChanged;

  // Date range filter
  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?>? onDateRangeChanged;

  bool get hasActiveFilters =>
      searchQuery.isNotEmpty ||
      selectedType != 'All Types' ||
      (showStatusFilter && selectedStatus != 'All Statuses') ||
      selectedPriority != 'All Priorities' ||
      selectedDepartment != 'All Departments' ||
      selectedSite != 'All Sites' ||
      dateRange != null ||
      selectedSort != 'Newest First';

  Future<void> _pickDateRange(BuildContext context) async {
    if (onDateRangeChanged == null) return;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: dateRange,
    );
    if (picked != null) {
      onDateRangeChanged!(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Search Input
              Expanded(
                child: TextField(
                  key: const Key('request_search_field'),
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search by ID, title, requester, department, site...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.cardBorder(context)),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                  ),
                ),
              ),
              if (hasActiveFilters) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const Key('request_reset_filters_button'),
                  onPressed: onResetFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Reset Filters'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Filter Chips / Dropdowns Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Request Type Dropdown
                _buildDropdown(
                  context: context,
                  label: 'Type',
                  value: selectedType,
                  items: ['All Types', ...RequestType.values],
                  onChanged: (v) => onTypeChanged(v ?? 'All Types'),
                ),
                const SizedBox(width: 8),

                // Status Dropdown
                if (showStatusFilter) ...[
                  _buildDropdown(
                    context: context,
                    label: 'Status',
                    value: selectedStatus,
                    items: ['All Statuses', ...RequestStatus.values],
                    onChanged: (v) => onStatusChanged(v ?? 'All Statuses'),
                  ),
                  const SizedBox(width: 8),
                ],

                // Priority Dropdown
                _buildDropdown(
                  context: context,
                  label: 'Priority',
                  value: selectedPriority,
                  items: ['All Priorities', ...RequestPriority.values],
                  onChanged: (v) => onPriorityChanged(v ?? 'All Priorities'),
                ),
                const SizedBox(width: 8),

                // Department Dropdown
                if (availableDepartments.length > 1 && onDepartmentChanged != null) ...[
                  _buildDropdown(
                    context: context,
                    label: 'Dept',
                    value: selectedDepartment,
                    items: availableDepartments,
                    onChanged: (v) => onDepartmentChanged!(v ?? 'All Departments'),
                  ),
                  const SizedBox(width: 8),
                ],

                // Site Dropdown
                if (availableSites.length > 1 && onSiteChanged != null) ...[
                  _buildDropdown(
                    context: context,
                    label: 'Site',
                    value: selectedSite,
                    items: availableSites,
                    onChanged: (v) => onSiteChanged!(v ?? 'All Sites'),
                  ),
                  const SizedBox(width: 8),
                ],

                // Date Range Button
                if (onDateRangeChanged != null) ...[
                  InkWell(
                    key: const Key('request_date_range_button'),
                    onTap: () => _pickDateRange(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: dateRange != null
                            ? const Color(0xFF0284C7).withValues(alpha: 0.12)
                            : (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF1E293B)
                                : Colors.white),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: dateRange != null
                              ? const Color(0xFF0284C7)
                              : AppTheme.cardBorder(context),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.date_range_rounded,
                            size: 14,
                            color: dateRange != null
                                ? const Color(0xFF0284C7)
                                : AppTheme.textSecondary(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dateRange == null
                                ? 'Date Range'
                                : '${dateRange!.start.toIso8601String().substring(0, 10)} - ${dateRange!.end.toIso8601String().substring(0, 10)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: dateRange != null
                                  ? const Color(0xFF0284C7)
                                  : AppTheme.textPrimary(context),
                            ),
                          ),
                          if (dateRange != null) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => onDateRangeChanged!(null),
                              child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF0284C7)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Sort Dropdown
                _buildDropdown(
                  context: context,
                  label: 'Sort',
                  value: selectedSort,
                  items: const ['Newest First', 'Oldest First', 'Required Date', 'Priority'],
                  onChanged: (v) => onSortChanged(v ?? 'Newest First'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required BuildContext context,
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isDense: true,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary(context),
              ),
              items: items
                  .map((it) => DropdownMenuItem(value: it, child: Text(it)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
