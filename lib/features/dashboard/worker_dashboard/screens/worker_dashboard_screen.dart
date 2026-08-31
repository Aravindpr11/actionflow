import 'package:flutter/material.dart';

import '../../../auth/screens/login_screen.dart';
import '../../manager_dashboard/data/mock_action_store.dart';
import '../../manager_dashboard/models/action_record.dart';
import '../../manager_dashboard/screens/action_details_screen.dart';
import 'worker_action_update_screen.dart';

class WorkerDashboardScreen extends StatefulWidget {
  const WorkerDashboardScreen({super.key});

  @override
  State<WorkerDashboardScreen> createState() => _WorkerDashboardScreenState();
}

class _WorkerDashboardScreenState extends State<WorkerDashboardScreen> {
  static const workerName = 'R. Kumar';
  final store = MockActionStore.instance;
  final searchController = TextEditingController();
  String statusFilter = 'All Statuses';
  String priorityFilter = 'All Priorities';
  String siteFilter = 'All Sites';
  String dateFilter = 'All Dates';
  String sortOrder = 'Newest First';
  int navigationIndex = 0;

  List<ActionRecord> get myActions =>
      store.actions.where((action) => action.assignedTo == workerName).toList();

  List<ActionRecord> get visibleActions {
    final query = searchController.text.trim().toLowerCase();
    final filtered = myActions.where((action) {
      final matchesQuery =
          query.isEmpty ||
          action.id.toLowerCase().contains(query) ||
          action.subject.toLowerCase().contains(query) ||
          action.site.toLowerCase().contains(query);
      final matchesStatus =
          statusFilter == 'All Statuses' || action.status == statusFilter;
      final matchesPriority =
          priorityFilter == 'All Priorities' ||
          action.priority == priorityFilter;
      final matchesSite =
          siteFilter == 'All Sites' || action.site == siteFilter;
      return matchesQuery && matchesStatus && matchesPriority && matchesSite;
    }).toList();
    if (sortOrder == 'Target Date') {
      filtered.sort(
        (first, second) => first.targetDate.compareTo(second.targetDate),
      );
    } else if (sortOrder == 'Priority') {
      const rank = {'Critical': 0, 'High': 1, 'Medium': 2, 'Low': 3};
      filtered.sort(
        (first, second) =>
            (rank[first.priority] ?? 4).compareTo(rank[second.priority] ?? 4),
      );
    }
    return filtered;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> openUpdate(ActionRecord action) async {
    final updated = await Navigator.of(context).push<ActionRecord>(
      MaterialPageRoute(
        builder: (_) => WorkerActionUpdateScreen(action: action),
      ),
    );
    if (updated != null && mounted) {
      store.update(updated);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${updated.id} update sent for manager review')),
      );
    }
  }

  void openDetails(ActionRecord action) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActionDetailsScreen(
          action: action,
          onUpdateAction: () => openUpdate(action),
        ),
      ),
    );
  }

  void logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = myActions;
    final visible = visibleActions;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 1000;
          final content = SingleChildScrollView(
            padding: EdgeInsets.all(desktop ? 24 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WorkerHeader(
                  workerName: workerName,
                  desktop: desktop,
                  onLogout: logout,
                ),
                const SizedBox(height: 20),
                _WelcomeBanner(
                  workerName: workerName,
                  actionCount: actions.length,
                ),
                const SizedBox(height: 20),
                _OverviewCards(actions: actions),
                const SizedBox(height: 20),
                _WorkerFilters(
                  searchController: searchController,
                  status: statusFilter,
                  priority: priorityFilter,
                  site: siteFilter,
                  date: dateFilter,
                  sort: sortOrder,
                  onChanged: (values) => setState(() {
                    statusFilter = values.status;
                    priorityFilter = values.priority;
                    siteFilter = values.site;
                    dateFilter = values.date;
                    sortOrder = values.sort;
                  }),
                  onSearchChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                _QuickActions(
                  onUpdatePending: () {
                    final pending = actions
                        .where((action) => action.status == 'Pending')
                        .toList();
                    if (pending.isNotEmpty) openUpdate(pending.first);
                  },
                ),
                const SizedBox(height: 20),
                _NotificationsPanel(),
                const SizedBox(height: 20),
                _MyActionsSection(
                  actions: visible,
                  onOpenDetails: openDetails,
                  onUpdateAction: openUpdate,
                ),
              ],
            ),
          );

          if (desktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WorkerSidebar(onLogout: logout),
                Expanded(child: content),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: content),
              _WorkerBottomNavigation(
                selectedIndex: navigationIndex,
                onChanged: (value) => setState(() => navigationIndex = value),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WorkerSidebar extends StatelessWidget {
  const _WorkerSidebar({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('My Dashboard', Icons.dashboard_rounded),
      ('My Actions', Icons.assignment_turned_in_rounded),
      ('Pending Updates', Icons.pending_actions_rounded),
      ('Notifications', Icons.notifications_rounded),
      ('Documents', Icons.folder_rounded),
    ];
    return Container(
      width: 250,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _WorkerBrand(),
          const SizedBox(height: 30),
          ...items.map(
            (item) => ListTile(
              dense: true,
              selected: item.$1 == 'My Dashboard',
              selectedTileColor: const Color(0xFFE3F2FD),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(item.$2, color: const Color(0xFF1565C0)),
              title: Text(item.$1),
              onTap: () {},
            ),
          ),
          const Spacer(),
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

class _WorkerBottomNavigation extends StatelessWidget {
  const _WorkerBottomNavigation({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onChanged,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.assignment_turned_in_rounded),
          label: 'Actions',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_rounded),
          label: 'Alerts',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    );
  }
}

class _WorkerBrand extends StatelessWidget {
  const _WorkerBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.work_history_rounded, color: Colors.white),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ActionFlow',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'HSSE Action Tracker',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _WorkerHeader extends StatelessWidget {
  const _WorkerHeader({
    required this.workerName,
    required this.desktop,
    required this.onLogout,
  });

  final String workerName;
  final bool desktop;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final controls = Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Stack(
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded, size: 26),
            ),
            Positioned(
              right: 7,
              top: 7,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    '3',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        CircleAvatar(
          backgroundColor: const Color(0xFF1565C0),
          child: Text(
            workerName.substring(0, 1),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (desktop) ...[
          Text(workerName, style: const TextStyle(fontWeight: FontWeight.bold)),
          TextButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
          ),
        ],
      ],
    );
    final brand = desktop ? const SizedBox.shrink() : const _WorkerBrand();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: desktop
          ? Row(
              children: [
                const Expanded(
                  child: Text(
                    'My Dashboard',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                controls,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [brand, const SizedBox(height: 12), controls],
            ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.workerName, required this.actionCount});
  final String workerName;
  final int actionCount;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF1565C0),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Good morning, $workerName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You have $actionCount assigned action${actionCount == 1 ? '' : 's'} requiring attention.',
              style: const TextStyle(color: Color(0xFFDCEBFA)),
            ),
          ],
        ),
        const Icon(
          Icons.health_and_safety_rounded,
          color: Colors.white,
          size: 48,
        ),
      ],
    ),
  );
}

class _WorkerFilters extends StatelessWidget {
  const _WorkerFilters({
    required this.searchController,
    required this.status,
    required this.priority,
    required this.site,
    required this.date,
    required this.sort,
    required this.onChanged,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final String status;
  final String priority;
  final String site;
  final String date;
  final String sort;
  final ValueChanged<_WorkerFilterValues> onChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Filter My Actions',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: _fieldWidth(width, 240),
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: const InputDecoration(
                    labelText: 'Search',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              _select(width, 170, 'Status', status, const [
                'All Statuses',
                'Open',
                'In Progress',
                'Pending',
                'Pending Review',
                'Overdue',
                'Closed',
              ]),
              _select(width, 170, 'Priority', priority, const [
                'All Priorities',
                'Critical',
                'High',
                'Medium',
                'Low',
              ]),
              _select(width, 170, 'Site', site, const [
                'All Sites',
                'North Plant',
                'Warehouse B',
                'Central Yard',
                'Admin Block',
                'Storage Area',
              ]),
              _select(width, 150, 'Date', date, const [
                'All Dates',
                'This Week',
                'This Month',
              ]),
              _select(width, 170, 'Sort', sort, const [
                'Newest First',
                'Target Date',
                'Priority',
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _select(
    double availableWidth,
    double preferredWidth,
    String label,
    String value,
    List<String> values,
  ) {
    return SizedBox(
      width: _fieldWidth(availableWidth, preferredWidth),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (nextValue) {
          if (nextValue == null) return;
          onChanged(
            _WorkerFilterValues(
              status: label == 'Status' ? nextValue : status,
              priority: label == 'Priority' ? nextValue : priority,
              site: label == 'Site' ? nextValue : site,
              date: label == 'Date' ? nextValue : date,
              sort: label == 'Sort' ? nextValue : sort,
            ),
          );
        },
      ),
    );
  }

  double _fieldWidth(double availableWidth, double preferredWidth) =>
      availableWidth < preferredWidth ? availableWidth : preferredWidth;
}

class _WorkerFilterValues {
  const _WorkerFilterValues({
    required this.status,
    required this.priority,
    required this.site,
    required this.date,
    required this.sort,
  });

  final String status;
  final String priority;
  final String site;
  final String date;
  final String sort;
}

class _OverviewCards extends StatelessWidget {
  const _OverviewCards({required this.actions});
  final List<ActionRecord> actions;

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        'My Total Actions',
        actions.length,
        Icons.assignment_rounded,
        const Color(0xFF1565C0),
      ),
      (
        'Open',
        actions.where((item) => item.status == 'Open').length,
        Icons.pending_actions_rounded,
        const Color(0xFF4CAF50),
      ),
      (
        'Due Soon',
        actions
            .where(
              (item) => item.status != 'Closed' && item.status != 'Overdue',
            )
            .length,
        Icons.schedule_rounded,
        const Color(0xFF2196F3),
      ),
      (
        'Overdue',
        actions.where((item) => item.status == 'Overdue').length,
        Icons.warning_amber_rounded,
        const Color(0xFFF57C00),
      ),
      (
        'Pending Review',
        actions.where((item) => item.status == 'Pending Review').length,
        Icons.rate_review_rounded,
        const Color(0xFF7E57C2),
      ),
      (
        'Completed',
        actions.where((item) => item.percentComplete == 100).length,
        Icons.check_circle_rounded,
        const Color(0xFF2E7D32),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1200
            ? 6
            : constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth < 420
            ? 1
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width,
                  child: _WorkerStatCard(
                    label: card.$1,
                    value: card.$2,
                    icon: card.$3,
                    color: card.$4,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _WorkerStatCard extends StatelessWidget {
  const _WorkerStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onUpdatePending});
  final VoidCallback onUpdatePending;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Quick Actions',
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _quick('View My Actions', Icons.assignment_rounded, () {}),
        _quick(
          'Update Pending Actions',
          Icons.pending_actions_rounded,
          onUpdatePending,
        ),
        _quick('Submit Completion', Icons.task_alt_rounded, onUpdatePending),
        _quick('Add Requirement', Icons.playlist_add_rounded, onUpdatePending),
        _quick(
          'Add Suggestion',
          Icons.lightbulb_outline_rounded,
          onUpdatePending,
        ),
        _quick('View Notifications', Icons.notifications_rounded, () {}),
      ],
    ),
  );

  Widget _quick(String label, IconData icon, VoidCallback onPressed) =>
      OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
}

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel();

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'Notifications',
    child: Column(
      children: const [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.assignment_add, color: Color(0xFF1565C0)),
          title: Text('New action assigned'),
          subtitle: Text('Equipment Inspection requires your update.'),
          trailing: Text('New'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.schedule_rounded, color: Color(0xFFF57C00)),
          title: Text('Action due soon'),
          subtitle: Text('Review your next target date and follow-up.'),
          trailing: Text('Today'),
        ),
      ],
    ),
  );
}

class _MyActionsSection extends StatelessWidget {
  const _MyActionsSection({
    required this.actions,
    required this.onOpenDetails,
    required this.onUpdateAction,
  });
  final List<ActionRecord> actions;
  final ValueChanged<ActionRecord> onOpenDetails;
  final ValueChanged<ActionRecord> onUpdateAction;

  @override
  Widget build(BuildContext context) => _Panel(
    title: 'My Actions',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actions assigned to you',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),
        ...actions.map(
          (action) => _WorkerActionCard(
            action: action,
            onOpenDetails: onOpenDetails,
            onUpdateAction: onUpdateAction,
          ),
        ),
      ],
    ),
  );
}

class _WorkerActionCard extends StatelessWidget {
  const _WorkerActionCard({
    required this.action,
    required this.onOpenDetails,
    required this.onUpdateAction,
  });
  final ActionRecord action;
  final ValueChanged<ActionRecord> onOpenDetails;
  final ValueChanged<ActionRecord> onUpdateAction;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onOpenDetails(action),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${action.id}  •  ${action.site}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        action.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _badge(action.priority, const Color(0xFFF57C00)),
                    const SizedBox(width: 8),
                    _badge(action.status, _statusColor(action.status)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text('Target: ${action.targetDate}'),
                Text('Complete: ${action.percent}'),
                Text('Follow-up: ${action.followUp}'),
                if (action.supportingPerson.isNotEmpty)
                  Text('Supporting: ${action.supportingPerson}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: action.percentComplete / 100,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE8EEF5),
                      valueColor: AlwaysStoppedAnimation(
                        _statusColor(action.status),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => onUpdateAction(action),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Update Action'),
                ),
              ],
            ),
            if (action.status == 'Pending' && action.managerMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Manager message: ${action.managerMessage}',
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

Color _statusColor(String status) {
  switch (status) {
    case 'Open':
      return const Color(0xFF1565C0);
    case 'In Progress':
      return const Color(0xFF2E7D32);
    case 'Pending':
    case 'Pending Review':
      return const Color(0xFF7E57C2);
    case 'Overdue':
      return const Color(0xFFF57C00);
    case 'Completed':
    case 'Closed':
      return const Color(0xFF2E7D32);
    default:
      return const Color(0xFF64748B);
  }
}
