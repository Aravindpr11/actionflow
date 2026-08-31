import 'package:action_flow/features/auth/screens/login_screen.dart';
import 'package:action_flow/features/users/screens/users_screen.dart';
import 'package:flutter/material.dart';

import '../data/mock_action_store.dart';
import '../models/action_record.dart';
import 'action_details_screen.dart';
import 'add_action_screen.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final store = MockActionStore.instance;

  void openAddAction() async {
    final action = await Navigator.of(context).push<ActionRecord>(
      MaterialPageRoute(
        builder: (_) => AddActionScreen(actionId: 'AC-${store.nextId()}'),
      ),
    );
    if (action != null && mounted) {
      store.add(action);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${action.id} added to the Action Register')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final navItems = <_NavItemData>[
      _NavItemData('Dashboard', Icons.dashboard_rounded, true),
      _NavItemData('Action Register', Icons.list_alt_rounded),
      _NavItemData('Add Action', Icons.add_circle_outline_rounded),
      _NavItemData('My Actions', Icons.assignment_turned_in_rounded),
      _NavItemData('Calendar', Icons.calendar_month_rounded),
      _NavItemData('Reports & Graphs', Icons.bar_chart_rounded),
      _NavItemData('Notifications', Icons.notifications_rounded),
      _NavItemData('Documents', Icons.folder_rounded),
      _NavItemData('Users', Icons.people_alt_rounded),
      _NavItemData('Settings', Icons.settings_rounded),
    ];

    final summaryCards = <_SummaryCardData>[
      _SummaryCardData(
        label: 'All Actions',
        count: '148',
        color: const Color(0xFF1565C0),
        icon: Icons.assignment_rounded,
      ),
      _SummaryCardData(
        label: 'Open',
        count: '36',
        color: const Color(0xFF4CAF50),
        icon: Icons.pending_actions_rounded,
      ),
      _SummaryCardData(
        label: 'Overdue',
        count: '12',
        color: const Color(0xFFF57C00),
        icon: Icons.warning_amber_rounded,
      ),
      _SummaryCardData(
        label: 'Due Soon',
        count: '18',
        color: const Color(0xFF2196F3),
        icon: Icons.schedule_rounded,
      ),
      _SummaryCardData(
        label: 'Follow-up Due',
        count: '09',
        color: const Color(0xFF7E57C2),
        icon: Icons.repeat_rounded,
      ),
      _SummaryCardData(
        label: 'Critical / High',
        count: '07',
        color: const Color(0xFFD32F2F),
        icon: Icons.priority_high_rounded,
      ),
      _SummaryCardData(
        label: 'Closed',
        count: '76',
        color: const Color(0xFF2E7D32),
        icon: Icons.check_circle_rounded,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidebar = constraints.maxWidth >= 1100;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSidebar)
                _Sidebar(
                  navItems: navItems,
                  onUsers: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UsersScreen()),
                    );
                  },
                  onLogout: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TopHeader(
                        isMobile: !showSidebar,
                        onLogout: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _DashboardOverview(
                        summaryCards: summaryCards,
                        isDesktop: showSidebar,
                      ),
                      const SizedBox(height: 20),
                      _QuickActionsRow(onAddAction: openAddAction),
                      const SizedBox(height: 20),
                      const _DashboardCharts(),
                      const SizedBox(height: 20),
                      _ActionRegisterSection(
                        sampleActions: store.actions,
                        onActionTap: (action) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ActionDetailsScreen(action: action),
                            ),
                          );
                        },
                        onAddAction: openAddAction,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.navItems,
    required this.onUsers,
    required this.onLogout,
  });

  final List<_NavItemData> navItems;
  final VoidCallback onUsers;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  ),
                ),
                child: const Icon(
                  Icons.work_history_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ActionFlow',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    'HSSE Action Tracker',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),
          Expanded(
            child: ListView.separated(
              itemCount: navItems.length,
              itemBuilder: (context, index) {
                final item = navItems[index];
                return ListTile(
                  dense: true,
                  selected: item.isActive,
                  selectedTileColor: const Color(0xFFE3F2FD),
                  leading: Icon(
                    item.icon,
                    color: item.isActive
                        ? const Color(0xFF1565C0)
                        : const Color(0xFF475569),
                    size: 20,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontWeight: item.isActive
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: item.isActive
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF334155),
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  onTap: item.label == 'Users' ? onUsers : () {},
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 2),
            ),
          ),
          const Divider(),
          ListTile(
            dense: true,
            leading: const Icon(Icons.logout_rounded, color: Color(0xFFB91C1C)),
            title: const Text(
              'Logout',
              style: TextStyle(color: Color(0xFFB91C1C)),
            ),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({required this.isMobile, required this.onLogout});

  final bool isMobile;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final branding = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMobile)
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.menu_rounded),
                ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.work_history_rounded,
                  color: Color(0xFF1565C0),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ActionFlow',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    'HSSE Action Tracker',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          );
          final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isMobile
                    ? _fitFilterWidth(constraints.maxWidth, 180)
                    : 260,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search actions, projects, people',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              Stack(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      size: 26,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          '3',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFF1565C0),
                        child: Text(
                          'M',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (!isMobile)
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Manager',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Operations Lead',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if (!isMobile)
                TextButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Logout'),
                ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [branding, const SizedBox(height: 12), controls],
            );
          }
          return Row(
            children: [
              Expanded(child: branding),
              const SizedBox(width: 18),
              controls,
            ],
          );
        },
      ),
    );
  }
}

class _DashboardOverview extends StatelessWidget {
  const _DashboardOverview({
    required this.summaryCards,
    required this.isDesktop,
  });

  final List<_SummaryCardData> summaryCards;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dashboard Overview',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 440
                ? 1
                : constraints.maxWidth >= 1400
                ? 7
                : constraints.maxWidth >= 950
                ? 4
                : constraints.maxWidth >= 600
                ? 3
                : 2;
            final cardWidth =
                (constraints.maxWidth - (columns - 1) * 14) / columns;

            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: summaryCards.map((item) {
                return SizedBox(
                  width: cardWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0F172A0F),
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: item.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(item.icon, color: item.color),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: item.color.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  item.count,
                                  style: TextStyle(
                                    color: item.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            item.label,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.count,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: item.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.onAddAction});

  final VoidCallback onAddAction;

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickActionData>[
      _QuickActionData(
        'Create Action',
        Icons.add_circle_outline_rounded,
        const Color(0xFF1565C0),
      ),
      _QuickActionData(
        'View Overdue',
        Icons.warning_amber_rounded,
        const Color(0xFFF57C00),
      ),
      _QuickActionData(
        'View Due Soon',
        Icons.schedule_rounded,
        const Color(0xFF2196F3),
      ),
      _QuickActionData(
        'View Pending Review',
        Icons.task_alt_rounded,
        const Color(0xFF2E7D32),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: actions
              .map(
                (action) => SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: action.label == 'Create Action'
                        ? onAddAction
                        : () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: action.color,
                      elevation: 0,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(action.icon),
                    label: Text(action.label),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ActionRegisterSection extends StatelessWidget {
  const _ActionRegisterSection({
    required this.sampleActions,
    required this.onActionTap,
    required this.onAddAction,
  });

  final List<ActionRecord> sampleActions;
  final ValueChanged<ActionRecord> onActionTap;
  final VoidCallback onAddAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Action Register',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAddAction,
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('Add Action'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: _fitFilterWidth(constraints.maxWidth, 220),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: const Icon(Icons.search_rounded),
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
                SizedBox(
                  width: _fitFilterWidth(constraints.maxWidth, 165),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: 'All Status',
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'All Status',
                        child: Text('All Status'),
                      ),
                      DropdownMenuItem(value: 'Open', child: Text('Open')),
                      DropdownMenuItem(
                        value: 'Overdue',
                        child: Text('Overdue'),
                      ),
                      DropdownMenuItem(value: 'Closed', child: Text('Closed')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                _FilterDropdown(
                  width: 180,
                  initialValue: 'All Divisions',
                  values: const [
                    'All Divisions',
                    'Operations',
                    'Projects',
                    'Corporate',
                  ],
                ),
                _FilterDropdown(
                  width: 200,
                  initialValue: 'All Departments',
                  values: const [
                    'All Departments',
                    'HSE',
                    'Maintenance',
                    'Operations',
                  ],
                ),
                _FilterDropdown(
                  width: 175,
                  initialValue: 'All Sites',
                  values: const [
                    'All Sites',
                    'North Plant',
                    'Warehouse B',
                    'Central Yard',
                    'Admin Block',
                  ],
                ),
                SizedBox(
                  width: _fitFilterWidth(constraints.maxWidth, 165),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: 'All Priority',
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'All Priority',
                        child: Text('All Priority'),
                      ),
                      DropdownMenuItem(
                        value: 'Critical',
                        child: Text('Critical'),
                      ),
                      DropdownMenuItem(value: 'High', child: Text('High')),
                      DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                SizedBox(
                  width: _fitFilterWidth(constraints.maxWidth, 180),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: 'All People',
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'All People',
                        child: Text('All People'),
                      ),
                      DropdownMenuItem(
                        value: 'R. Kumar',
                        child: Text('R. Kumar'),
                      ),
                      DropdownMenuItem(value: 'M. Ali', child: Text('M. Ali')),
                      DropdownMenuItem(
                        value: 'S. Jones',
                        child: Text('S. Jones'),
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                SizedBox(
                  width: _fitFilterWidth(constraints.maxWidth, 160),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: 'Date',
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Date', child: Text('Date')),
                      DropdownMenuItem(
                        value: 'This Week',
                        child: Text('This Week'),
                      ),
                      DropdownMenuItem(
                        value: 'This Month',
                        child: Text('This Month'),
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 900;

              if (isCompact) {
                return Column(
                  children: sampleActions
                      .map(
                        (action) => InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onActionTap(action),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: const Color(0xFFF8FAFC),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        action.subject,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor(action.status)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        action.status,
                                        style: TextStyle(
                                          color: _statusColor(action.status),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('${action.id} • ${action.site}'),
                                const SizedBox(height: 8),
                                Text('Assigned To: ${action.assignedTo}'),
                                Text('Priority: ${action.priority}'),
                                Text('Target Date: ${action.targetDate}'),
                                Text('Complete: ${action.percent}'),
                                Text('Next Follow-up: ${action.followUp}'),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  headingRowColor: MaterialStateProperty.all(
                    const Color(0xFFF8FAFC),
                  ),
                  columns: const [
                    DataColumn(label: Text('Action ID')),
                    DataColumn(label: Text('Subject')),
                    DataColumn(label: Text('Project / Site')),
                    DataColumn(label: Text('Assigned To')),
                    DataColumn(label: Text('Priority')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Target Date')),
                    DataColumn(label: Text('% Complete')),
                    DataColumn(label: Text('Next Follow-up')),
                  ],
                  rows: sampleActions
                      .map(
                        (action) => DataRow(
                          onSelectChanged: (_) => onActionTap(action),
                          cells: [
                            DataCell(Text(action.id)),
                            DataCell(Text(action.subject)),
                            DataCell(Text(action.site)),
                            DataCell(Text(action.assignedTo)),
                            DataCell(Text(action.priority)),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _statusColor(action.status)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  action.status,
                                  style: TextStyle(
                                    color: _statusColor(action.status),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(action.targetDate)),
                            DataCell(Text(action.percent)),
                            DataCell(Text(action.followUp)),
                          ],
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.width,
    required this.initialValue,
    required this.values,
  });

  final double width;
  final String initialValue;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: width > constraints.maxWidth ? constraints.maxWidth : width,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: initialValue,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          items: values
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (_) {},
        ),
      ),
    );
  }
}

double _fitFilterWidth(double availableWidth, double preferredWidth) {
  return availableWidth < preferredWidth ? availableWidth : preferredWidth;
}

class _DashboardCharts extends StatelessWidget {
  const _DashboardCharts();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final panelWidth = isWide
            ? (constraints.maxWidth - 32) / 3
            : constraints.maxWidth;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: panelWidth,
              child: const _ChartPanel(
                title: 'Actions by Status',
                subtitle: 'Current action distribution',
                values: [
                  _ChartValue('Open', 36, Color(0xFF1565C0)),
                  _ChartValue('In Progress', 28, Color(0xFF2E7D32)),
                  _ChartValue('Pending Review', 8, Color(0xFF7E57C2)),
                  _ChartValue('Closed', 76, Color(0xFF64748B)),
                ],
              ),
            ),
            SizedBox(
              width: panelWidth,
              child: const _ChartPanel(
                title: 'Actions by Priority',
                subtitle: 'Risk-weighted action load',
                values: [
                  _ChartValue('Critical', 4, Color(0xFFB91C1C)),
                  _ChartValue('High', 12, Color(0xFFF57C00)),
                  _ChartValue('Medium', 54, Color(0xFF1565C0)),
                  _ChartValue('Low', 78, Color(0xFF2E7D32)),
                ],
              ),
            ),
            SizedBox(width: panelWidth, child: const _DueSoonPanel()),
            SizedBox(
              width: isWide ? constraints.maxWidth - 16 : constraints.maxWidth,
              child: const _TrendPanel(),
            ),
          ],
        );
      },
    );
  }
}

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({
    required this.title,
    required this.subtitle,
    required this.values,
  });

  final String title;
  final String subtitle;
  final List<_ChartValue> values;

  @override
  Widget build(BuildContext context) {
    final maxValue = values
        .map((value) => value.value)
        .reduce((first, second) => first > second ? first : second);

    return _DashboardPanel(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: values
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 94,
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 9,
                          value: item.value / maxValue,
                          backgroundColor: const Color(0xFFE8EEF5),
                          valueColor: AlwaysStoppedAnimation(item.color),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${item.value}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel();

  @override
  Widget build(BuildContext context) {
    const points = [7.0, 5.0, 8.0, 4.0, 6.0, 3.0, 2.0];

    return _DashboardPanel(
      title: 'Overdue Trend',
      subtitle: 'Overdue actions over the last 7 weeks',
      trailing: const Text(
        '12 active',
        style: TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.bold),
      ),
      child: AspectRatio(
        aspectRatio: 2.8,
        child: Column(
          children: [
            Expanded(
              child: CustomPaint(
                painter: _TrendPainter(points),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('W-6'),
                Text('W-5'),
                Text('W-4'),
                Text('W-3'),
                Text('W-2'),
                Text('W-1'),
                Text('Now'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DueSoonPanel extends StatelessWidget {
  const _DueSoonPanel();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Equipment Inspection', 'North Plant', 'Today'),
      ('Safety Training', 'Warehouse B', 'Tomorrow'),
      ('Emergency Exit Check', 'Admin Block', '21 Aug'),
    ];

    return _DashboardPanel(
      title: 'Due Soon',
      subtitle: 'Actions requiring attention',
      trailing: const Text(
        '18 total',
        style: TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.bold),
      ),
      child: Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2196F3),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            item.$2,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item.$3,
                      style: const TextStyle(
                        color: Color(0xFF1565C0),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.points);

  final List<double> points;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE8EEF5)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = const Color(0xFFF57C00)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..color = const Color(0x26F57C00)
      ..style = PaintingStyle.fill;

    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    final fillPath = Path()..moveTo(0, size.height);
    for (var index = 0; index < points.length; index++) {
      final x = size.width * index / (points.length - 1);
      final y = size.height - (points[index] / 10 * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      fillPath.lineTo(x, y);
    }
    fillPath
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
    for (var index = 0; index < points.length; index++) {
      final x = size.width * index / (points.length - 1);
      final y = size.height - (points[index] / 10 * size.height);
      canvas.drawCircle(
        Offset(x, y),
        4,
        Paint()..color = const Color(0xFFF57C00),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => false;
}

class _ChartValue {
  const _ChartValue(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;
}

Color _statusColor(String status) {
  switch (status) {
    case 'Open':
      return const Color(0xFF1565C0);
    case 'In Progress':
      return const Color(0xFF2E7D32);
    case 'Overdue':
      return const Color(0xFFF57C00);
    case 'Pending Review':
      return const Color(0xFF7E57C2);
    case 'Closed':
      return const Color(0xFF2E7D32);
    default:
      return const Color(0xFF64748B);
  }
}

class _NavItemData {
  const _NavItemData(this.label, this.icon, [this.isActive = false]);

  final String label;
  final IconData icon;
  final bool isActive;
}

class _SummaryCardData {
  const _SummaryCardData({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String label;
  final String count;
  final Color color;
  final IconData icon;
}

class _QuickActionData {
  const _QuickActionData(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}
