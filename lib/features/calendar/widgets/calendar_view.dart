import 'package:flutter/material.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/manager_dashboard/models/action_record.dart';
import '../models/calendar_task.dart';
import '../../../services/calendar_task_service.dart';

enum CalendarViewMode {
  month,
  week,
  day,
}

enum CalendarItemTypeFilter {
  all,
  actionsOnly,
  followUpsOnly,
  personalTasksOnly,
}

/// Represents an action follow-up checkpoint displayed within the calendar.
class CalendarFollowUpItem {
  final ActionRecord action;
  final ActionFollowUpRecord followUp;

  const CalendarFollowUpItem({
    required this.action,
    required this.followUp,
  });

  String get id =>
      followUp.id.isNotEmpty ? followUp.id : '${action.id}_${followUp.followUpDate}';
  DateTime? get followUpDate => followUp.followUpDateTime;
  String get actionId => action.id;
  String get actionSubject => action.subject;
  String get actionAssignee =>
      action.assignedTo.isNotEmpty ? action.assignedTo : 'Unassigned';
  String get targetDate => action.targetDate;
  String get status => followUp.status;
  String get notes => followUp.notes;
  bool get isCompleted => followUp.isCompleted;
  bool get isCancelled => followUp.isCancelled;
}

enum CalendarStatusFilter {
  all,
  dueToday,
  overdue,
  upcoming,
  completed,
}

/// A comprehensive enterprise Calendar component for ActionFlow.
///
/// Features:
/// - Month, Week, and Day views with fluid navigation (<, Today, >).
/// - Displays authorized official HSSE actions and private personal tasks.
/// - Clear visual distinction between official actions and personal tasks.
/// - Filters by type (All, Official Actions, Personal Tasks) and status (Due Today, Overdue, Upcoming, Completed).
/// - Safe date-boundary handling (normalized local midnight comparisons).
/// - Responsive layout supporting desktop, tablet, and narrow mobile viewports.
class ActionFlowCalendarView extends StatefulWidget {
  final String title;
  final List<ActionRecord> actions;
  final String currentUserId;
  final String? organizationId;
  final bool isManager;
  final void Function(ActionRecord action)? onActionTap;
  final VoidCallback? onRefresh;
  final CalendarTaskService? taskService;
  final DateTime? initialDate;
  final CalendarItemTypeFilter? initialTypeFilter;

  const ActionFlowCalendarView({
    super.key,
    this.title = 'Action Calendar & Due Dates',
    required this.actions,
    required this.currentUserId,
    this.organizationId,
    this.isManager = false,
    this.onActionTap,
    this.onRefresh,
    this.taskService,
    this.initialDate,
    this.initialTypeFilter,
  });

  @override
  State<ActionFlowCalendarView> createState() => _ActionFlowCalendarViewState();
}

class _ActionFlowCalendarViewState extends State<ActionFlowCalendarView> {
  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  CalendarViewMode _viewMode = CalendarViewMode.month;
  CalendarItemTypeFilter _typeFilter = CalendarItemTypeFilter.all;
  CalendarStatusFilter _statusFilter = CalendarStatusFilter.all;

  late final CalendarTaskService _taskService;
  List<CalendarTask> _personalTasks = [];

  @override
  void initState() {
    super.initState();
    final init = widget.initialDate ?? DateTime.now();
    _selectedDate = DateTime(init.year, init.month, init.day);
    _focusedMonth = DateTime(init.year, init.month, 1);
    _typeFilter = widget.initialTypeFilter ?? CalendarItemTypeFilter.all;
    _taskService = widget.taskService ?? CalendarTaskService();
    _loadPersonalTasks();
  }

  @override
  void didUpdateWidget(ActionFlowCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUserId != widget.currentUserId) {
      _loadPersonalTasks();
    }
    if (widget.initialDate != null && widget.initialDate != oldWidget.initialDate) {
      final init = widget.initialDate!;
      setState(() {
        _selectedDate = DateTime(init.year, init.month, init.day);
        _focusedMonth = DateTime(init.year, init.month, 1);
      });
      _loadPersonalTasks();
    }
    if (widget.initialTypeFilter != null && widget.initialTypeFilter != oldWidget.initialTypeFilter) {
      setState(() {
        _typeFilter = widget.initialTypeFilter!;
      });
    }
  }

  Future<void> _loadPersonalTasks() async {
    final effectiveUser = widget.currentUserId.isNotEmpty
        ? widget.currentUserId
        : (SupabaseConfig.clientOrNull?.auth.currentUser?.id ?? '');
    if (effectiveUser.isEmpty) return;
    try {
      final tasks = await _taskService.getTasks(userId: effectiveUser);
      if (mounted) {
        setState(() {
          _personalTasks = tasks;
        });
      }
    } catch (e) {
      debugPrint('[ActionFlowCalendarView] Failed to load personal tasks: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Date Helpers (Normalized to Local Midnight to prevent TZ shifts)
  // ---------------------------------------------------------------------------
  DateTime _toMidnight(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime get _today => _toMidnight(DateTime.now());

  DateTime? _actionDueDate(ActionRecord act) {
    final dt = act.targetDateTime;
    if (dt == null) return null;
    return _toMidnight(dt);
  }

  bool _isActionOverdue(ActionRecord act) {
    if (act.isClosed) return false;
    final due = _actionDueDate(act);
    if (due == null) return false;
    return due.isBefore(_today);
  }

  bool _isActionDueToday(ActionRecord act) {
    if (act.isClosed) return false;
    final due = _actionDueDate(act);
    if (due == null) return false;
    return due.isAtSameMomentAs(_today);
  }

  bool _isActionUpcoming(ActionRecord act) {
    if (act.isClosed) return false;
    final due = _actionDueDate(act);
    if (due == null) return false;
    return due.isAfter(_today);
  }

  DateTime? _followUpDate(CalendarFollowUpItem item) {
    final dt = item.followUpDate;
    if (dt == null) return null;
    return _toMidnight(dt);
  }

  bool _isFollowUpOverdue(CalendarFollowUpItem item) {
    if (item.isCompleted || item.isCancelled) return false;
    final due = _followUpDate(item);
    if (due == null) return false;
    return due.isBefore(_today);
  }

  bool _isFollowUpDueToday(CalendarFollowUpItem item) {
    if (item.isCompleted || item.isCancelled) return false;
    final due = _followUpDate(item);
    if (due == null) return false;
    return due.isAtSameMomentAs(_today);
  }

  bool _isFollowUpUpcoming(CalendarFollowUpItem item) {
    if (item.isCompleted || item.isCancelled) return false;
    final due = _followUpDate(item);
    if (due == null) return false;
    return due.isAfter(_today);
  }

  // ---------------------------------------------------------------------------
  // Filtered Item Resolvers
  // ---------------------------------------------------------------------------
  List<ActionRecord> get _uniqueActions {
    // Avoid duplicate action entries by ID
    final seen = <String>{};
    final unique = <ActionRecord>[];
    for (final act in widget.actions) {
      if (act.id.isNotEmpty && seen.add(act.id)) {
        unique.add(act);
      }
    }
    return unique;
  }

  List<CalendarFollowUpItem> get _uniqueFollowUps {
    final seen = <String>{};
    final items = <CalendarFollowUpItem>[];

    for (final act in _uniqueActions) {
      // 1. Existing follow-up checkpoints on the action
      for (final fu in act.followUps) {
        final key = fu.id.isNotEmpty ? fu.id : '${act.id}_${fu.followUpDate.trim()}';
        if (fu.followUpDate.isNotEmpty && fu.followUpDate != 'Not set' && seen.add(key)) {
          items.add(CalendarFollowUpItem(action: act, followUp: fu));
        }
      }

      // 2. Scheduled next follow-up date (if not already recorded as a checkpoint)
      final nextDate = act.nextFollowUpDate.trim();
      if (nextDate.isNotEmpty && nextDate != 'Not set') {
        final alreadyCovered = act.followUps.any((fu) => fu.followUpDate.trim() == nextDate);
        if (!alreadyCovered) {
          final syntheticKey = 'next_fu_${act.id}_$nextDate';
          if (seen.add(syntheticKey)) {
            items.add(
              CalendarFollowUpItem(
                action: act,
                followUp: ActionFollowUpRecord(
                  id: syntheticKey,
                  actionId: act.id,
                  followUpDate: nextDate,
                  notes: 'Scheduled follow-up checkpoint',
                  status: 'Scheduled',
                  createdByName: act.assignedBy,
                ),
              ),
            );
          }
        }
      }
    }
    return items;
  }

  List<ActionRecord> get _filteredActions {
    if (_typeFilter == CalendarItemTypeFilter.personalTasksOnly ||
        _typeFilter == CalendarItemTypeFilter.followUpsOnly) {
      return [];
    }
    return _uniqueActions.where((act) {
      switch (_statusFilter) {
        case CalendarStatusFilter.dueToday:
          return _isActionDueToday(act);
        case CalendarStatusFilter.overdue:
          return _isActionOverdue(act);
        case CalendarStatusFilter.upcoming:
          return _isActionUpcoming(act);
        case CalendarStatusFilter.completed:
          return act.isClosed;
        case CalendarStatusFilter.all:
          return true;
      }
    }).toList();
  }

  List<CalendarFollowUpItem> get _filteredFollowUps {
    if (_typeFilter == CalendarItemTypeFilter.actionsOnly ||
        _typeFilter == CalendarItemTypeFilter.personalTasksOnly) {
      return [];
    }
    return _uniqueFollowUps.where((item) {
      switch (_statusFilter) {
        case CalendarStatusFilter.dueToday:
          return _isFollowUpDueToday(item);
        case CalendarStatusFilter.overdue:
          return _isFollowUpOverdue(item);
        case CalendarStatusFilter.upcoming:
          return _isFollowUpUpcoming(item);
        case CalendarStatusFilter.completed:
          return item.isCompleted;
        case CalendarStatusFilter.all:
          return true;
      }
    }).toList();
  }

  List<CalendarTask> get _filteredPersonalTasks {
    if (_typeFilter == CalendarItemTypeFilter.actionsOnly ||
        _typeFilter == CalendarItemTypeFilter.followUpsOnly) {
      return [];
    }
    return _personalTasks.where((task) {
      switch (_statusFilter) {
        case CalendarStatusFilter.dueToday:
          return task.isDueToday(_today);
        case CalendarStatusFilter.overdue:
          return task.isOverdue(_today);
        case CalendarStatusFilter.upcoming:
          return task.isUpcoming(_today);
        case CalendarStatusFilter.completed:
          return task.isCompleted;
        case CalendarStatusFilter.all:
          return true;
      }
    }).toList();
  }

  List<ActionRecord> _actionsForDay(DateTime day) {
    final target = _toMidnight(day);
    return _filteredActions.where((act) {
      final due = _actionDueDate(act);
      return due != null && _isSameDay(due, target);
    }).toList();
  }

  List<CalendarFollowUpItem> _followUpsForDay(DateTime day) {
    final target = _toMidnight(day);
    return _filteredFollowUps.where((item) {
      final d = _followUpDate(item);
      return d != null && _isSameDay(d, target);
    }).toList();
  }

  List<CalendarTask> _tasksForDay(DateTime day) {
    final target = _toMidnight(day);
    return _filteredPersonalTasks.where((task) {
      return _isSameDay(task.dueDayMidnight, target);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Navigation Handlers
  // ---------------------------------------------------------------------------
  void _goToPrevious() {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.month:
          _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
          _selectedDate = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
          break;
        case CalendarViewMode.week:
          _selectedDate = _selectedDate.subtract(const Duration(days: 7));
          _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
          break;
        case CalendarViewMode.day:
          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
          _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
          break;
      }
    });
  }

  void _goToNext() {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.month:
          _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
          _selectedDate = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
          break;
        case CalendarViewMode.week:
          _selectedDate = _selectedDate.add(const Duration(days: 7));
          _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
          break;
        case CalendarViewMode.day:
          _selectedDate = _selectedDate.add(const Duration(days: 1));
          _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
          break;
      }
    });
  }

  void _goToToday() {
    setState(() {
      final now = DateTime.now();
      _selectedDate = _toMidnight(now);
      _focusedMonth = DateTime(now.year, now.month, 1);
    });
  }

  // ---------------------------------------------------------------------------
  // Personal Task Dialog (Create / Edit)
  // ---------------------------------------------------------------------------
  Future<void> _openTaskDialog({CalendarTask? taskToEdit, DateTime? initialDueDate}) async {
    final isEditing = taskToEdit != null;
    final titleController = TextEditingController(text: taskToEdit?.title ?? '');
    final descController = TextEditingController(text: taskToEdit?.description ?? '');

    DateTime selectedDueDate = taskToEdit?.dueDate ?? initialDueDate ?? _selectedDate;
    TimeOfDay selectedDueTime = taskToEdit != null
        ? TimeOfDay(hour: taskToEdit.dueDate.hour, minute: taskToEdit.dueDate.minute)
        : const TimeOfDay(hour: 17, minute: 0);

    String selectedPriority = taskToEdit?.priority ?? 'Medium';
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: AppTheme.cardBg(ctx),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.task_alt_rounded,
                      color: Color(0xFF7C3AED),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'Edit Personal Task' : 'New Personal Task',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(ctx),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (dialogError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    dialogError!,
                                    style: const TextStyle(fontSize: 12, color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          'Personal tasks are private to your account only. They are not assigned, shared, or visible to managers.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(ctx),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Title
                        TextFormField(
                          key: const Key('calendar_task_title_field'),
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: 'Task Title *',
                            hintText: 'e.g., Review weekly HSE briefing notes',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter a task title';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Description
                        TextFormField(
                          key: const Key('calendar_task_desc_field'),
                          controller: descController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Description (optional)',
                            hintText: 'Additional private notes or checklist items...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Due Date & Time row
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: selectedDueDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      selectedDueDate = DateTime(
                                        picked.year,
                                        picked.month,
                                        picked.day,
                                        selectedDueTime.hour,
                                        selectedDueTime.minute,
                                      );
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Due Date *',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    isDense: true,
                                    suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                                  ),
                                  child: Text(
                                    '${selectedDueDate.day.toString().padLeft(2, '0')}/${selectedDueDate.month.toString().padLeft(2, '0')}/${selectedDueDate.year}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textPrimary(ctx),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: InkWell(
                                onTap: () async {
                                  final pickedTime = await showTimePicker(
                                    context: ctx,
                                    initialTime: selectedDueTime,
                                  );
                                  if (pickedTime != null) {
                                    setDialogState(() {
                                      selectedDueTime = pickedTime;
                                      selectedDueDate = DateTime(
                                        selectedDueDate.year,
                                        selectedDueDate.month,
                                        selectedDueDate.day,
                                        pickedTime.hour,
                                        pickedTime.minute,
                                      );
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Time',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    isDense: true,
                                    suffixIcon: const Icon(Icons.access_time_rounded, size: 18),
                                  ),
                                  child: Text(
                                    selectedDueTime.format(ctx),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textPrimary(ctx),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Priority
                        DropdownButtonFormField<String>(
                          initialValue: selectedPriority,
                          decoration: InputDecoration(
                            labelText: 'Priority',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Low', child: Text('Low')),
                            DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                            DropdownMenuItem(value: 'High', child: Text('High')),
                            DropdownMenuItem(value: 'Critical', child: Text('Critical')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedPriority = val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary(ctx))),
                ),
                ElevatedButton(
                  key: const Key('calendar_task_save_button'),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;

                          setDialogState(() {
                            isSaving = true;
                            dialogError = null;
                          });

                          final taskDue = DateTime(
                            selectedDueDate.year,
                            selectedDueDate.month,
                            selectedDueDate.day,
                            selectedDueTime.hour,
                            selectedDueTime.minute,
                          );

                          try {
                            if (isEditing) {
                              final updated = taskToEdit.copyWith(
                                title: titleController.text.trim(),
                                description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                                dueDate: taskDue,
                                priority: selectedPriority,
                              );
                              await _taskService.updateTask(updated);
                            } else {
                              final newTask = CalendarTask(
                                id: '',
                                userId: widget.currentUserId,
                                organizationId: widget.organizationId,
                                title: titleController.text.trim(),
                                description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                                dueDate: taskDue,
                                priority: selectedPriority,
                              );
                              await _taskService.createTask(newTask);
                            }

                            if (dialogCtx.mounted) {
                              Navigator.of(dialogCtx).pop();
                            }
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isEditing ? 'Personal task updated' : 'Personal task created'),
                              ),
                            );
                            await _loadPersonalTasks();
                            widget.onRefresh?.call();
                          } catch (e) {
                            final rawError = e.toString()
                                .replaceAll('Exception: ', '')
                                .replaceAll('CalendarTaskPersistenceException: ', '');
                            setDialogState(() {
                              isSaving = false;
                              dialogError = rawError;
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isEditing ? 'Failed to update task: $rawError' : 'Failed to save task: $rawError'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isEditing ? 'Save Changes' : 'Create Task'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deletePersonalTask(CalendarTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task?'),
        content: Text('Are you sure you want to delete "${task.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('calendar_task_confirm_delete_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _taskService.deleteTask(taskId: task.id, userId: widget.currentUserId);
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task deleted')),
          );
          _loadPersonalTasks();
          widget.onRefresh?.call();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete task: ${e.toString().replaceAll("Exception: ", "")}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _togglePersonalTaskCompletion(CalendarTask task, bool isCompleted) async {
    try {
      await _taskService.toggleTaskCompletion(
        taskId: task.id,
        userId: widget.currentUserId,
        isCompleted: isCompleted,
      );
      await _loadPersonalTasks();
      widget.onRefresh?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update task status: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 680;
        final isDesktop = constraints.maxWidth >= 1024;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Action & Schedule Card
            _buildHeaderCard(context, isNarrow: isNarrow, isDesktop: isDesktop),
            const SizedBox(height: 14),

            // Filter Bar
            _buildFilterBar(context, isNarrow: isNarrow),
            const SizedBox(height: 14),

            // Active Calendar View
            if (_viewMode == CalendarViewMode.month)
              _buildMonthView(context, isDesktop: isDesktop, isNarrow: isNarrow)
            else if (_viewMode == CalendarViewMode.week)
              _buildWeekView(context, isDesktop: isDesktop, isNarrow: isNarrow)
            else
              _buildDayView(context, isDesktop: isDesktop),
          ],
        );
      },
    );
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required bool isNarrow,
    required bool isDesktop,
  }) {
    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    String formattedRange;
    switch (_viewMode) {
      case CalendarViewMode.month:
        formattedRange = '${monthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}';
        break;
      case CalendarViewMode.week:
        // Calculate start of week (Monday)
        final weekday = _selectedDate.weekday; // 1 = Mon, 7 = Sun
        final startOfWeek = _selectedDate.subtract(Duration(days: weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        formattedRange = '${startOfWeek.day} ${monthNames[startOfWeek.month - 1].substring(0, 3)} – '
            '${endOfWeek.day} ${monthNames[endOfWeek.month - 1].substring(0, 3)} ${endOfWeek.year}';
        break;
      case CalendarViewMode.day:
        final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        formattedRange = '${weekdays[_selectedDate.weekday - 1]}, ${_selectedDate.day} ${monthNames[_selectedDate.month - 1]} ${_selectedDate.year}';
        break;
    }

    final overdueCount = _filteredActions.where(_isActionOverdue).length +
        _filteredPersonalTasks.where((t) => t.isOverdue(_today)).length;
    final dueTodayCount = _filteredActions.where(_isActionDueToday).length +
        _filteredPersonalTasks.where((t) => t.isDueToday(_today)).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: isNarrow ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (dueTodayCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEA580C).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFEA580C)),
                            ),
                            child: Text(
                              '$dueTodayCount Due Today',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEA580C),
                              ),
                            ),
                          ),
                        ],
                        if (overdueCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red),
                            ),
                            child: Text(
                              '$overdueCount Overdue',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Track target deadlines, scheduled HSE milestones, and your private tasks.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isNarrow) ...[
                if (widget.onRefresh != null)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'Refresh',
                    onPressed: () {
                      widget.onRefresh?.call();
                      _loadPersonalTasks();
                    },
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  key: const Key('add_personal_task_button'),
                  onPressed: () => _openTaskDialog(),
                  icon: const Icon(Icons.add_task_rounded, size: 16),
                  label: const Text('Add Task', style: TextStyle(fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          ),
          if (isNarrow) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key('add_personal_task_button_mobile'),
                    onPressed: () => _openTaskDialog(),
                    icon: const Icon(Icons.add_task_rounded, size: 15),
                    label: const Text('Add Task', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (widget.onRefresh != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    onPressed: () {
                      widget.onRefresh?.call();
                      _loadPersonalTasks();
                    },
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Navigation row: < Date Range > Today, View mode segmented button
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              // Date Controls
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('calendar_prev_button'),
                        icon: const Icon(Icons.chevron_left_rounded, size: 22),
                        tooltip: 'Previous',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: _goToPrevious,
                      ),
                      OutlinedButton(
                        key: const Key('calendar_today_button'),
                        onPressed: _goToToday,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          side: BorderSide(color: AppTheme.cardBorder(context)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('Today', style: TextStyle(fontSize: 11.5)),
                      ),
                      IconButton(
                        key: const Key('calendar_next_button'),
                        icon: const Icon(Icons.chevron_right_rounded, size: 22),
                        tooltip: 'Next',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: _goToNext,
                      ),
                    ],
                  ),
                  Text(
                    formattedRange,
                    style: TextStyle(
                      fontSize: isNarrow ? 13.5 : 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ],
              ),

              // View Mode Switcher
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.containerBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _viewModeButton('Month', CalendarViewMode.month, const Key('view_mode_month')),
                    _viewModeButton('Week', CalendarViewMode.week, const Key('view_mode_week')),
                    _viewModeButton('Day', CalendarViewMode.day, const Key('view_mode_day')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _viewModeButton(String label, CalendarViewMode mode, Key key) {
    final isSelected = _viewMode == mode;
    return InkWell(
      key: key,
      onTap: () => setState(() => _viewMode = mode),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textPrimary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, {required bool isNarrow}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Filters:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
            ),
          ),
          // Type filter chips
          _filterChip(
            label: 'All Items',
            isSelected: _typeFilter == CalendarItemTypeFilter.all,
            key: const Key('filter_type_all'),
            onTap: () => setState(() => _typeFilter = CalendarItemTypeFilter.all),
          ),
          _filterChip(
            label: 'Official Actions',
            icon: Icons.shield_outlined,
            iconColor: const Color(0xFF0284C7),
            isSelected: _typeFilter == CalendarItemTypeFilter.actionsOnly,
            key: const Key('filter_type_actions'),
            onTap: () => setState(() => _typeFilter = CalendarItemTypeFilter.actionsOnly),
          ),
          _filterChip(
            label: 'Follow-ups',
            icon: Icons.history_toggle_off_rounded,
            iconColor: const Color(0xFFD97706),
            isSelected: _typeFilter == CalendarItemTypeFilter.followUpsOnly,
            key: const Key('filter_type_follow_ups'),
            onTap: () => setState(() => _typeFilter = CalendarItemTypeFilter.followUpsOnly),
          ),
          _filterChip(
            label: 'Personal Tasks',
            icon: Icons.person_pin_rounded,
            iconColor: const Color(0xFF7C3AED),
            isSelected: _typeFilter == CalendarItemTypeFilter.personalTasksOnly,
            key: const Key('filter_type_personal_tasks'),
            onTap: () => setState(() => _typeFilter = CalendarItemTypeFilter.personalTasksOnly),
          ),
          Container(
            height: 18,
            width: 1,
            color: AppTheme.cardBorder(context),
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          // Status filter chips
          _filterChip(
            label: 'All Statuses',
            isSelected: _statusFilter == CalendarStatusFilter.all,
            key: const Key('filter_status_all'),
            onTap: () => setState(() => _statusFilter = CalendarStatusFilter.all),
          ),
          _filterChip(
            label: 'Due Today',
            isSelected: _statusFilter == CalendarStatusFilter.dueToday,
            badgeColor: const Color(0xFFEA580C),
            key: const Key('filter_status_due_today'),
            onTap: () => setState(() => _statusFilter = CalendarStatusFilter.dueToday),
          ),
          _filterChip(
            label: 'Overdue',
            isSelected: _statusFilter == CalendarStatusFilter.overdue,
            badgeColor: Colors.red,
            key: const Key('filter_status_overdue'),
            onTap: () => setState(() => _statusFilter = CalendarStatusFilter.overdue),
          ),
          _filterChip(
            label: 'Upcoming',
            isSelected: _statusFilter == CalendarStatusFilter.upcoming,
            badgeColor: const Color(0xFF0284C7),
            key: const Key('filter_status_upcoming'),
            onTap: () => setState(() => _statusFilter = CalendarStatusFilter.upcoming),
          ),
          _filterChip(
            label: 'Completed',
            isSelected: _statusFilter == CalendarStatusFilter.completed,
            badgeColor: const Color(0xFF16A34A),
            key: const Key('filter_status_completed'),
            onTap: () => setState(() => _statusFilter = CalendarStatusFilter.completed),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool isSelected,
    IconData? icon,
    Color? iconColor,
    Color? badgeColor,
    required VoidCallback onTap,
    Key? key,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (badgeColor ?? AppTheme.primaryColor).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (badgeColor ?? AppTheme.primaryColor)
                : AppTheme.cardBorder(context),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: iconColor ?? AppTheme.textPrimary(context)),
              const SizedBox(width: 4),
            ],
            if (badgeColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (badgeColor ?? AppTheme.primaryColor)
                    : AppTheme.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Month View
  // ---------------------------------------------------------------------------
  Widget _buildMonthView(
    BuildContext context, {
    required bool isDesktop,
    required bool isNarrow,
  }) {
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstWeekday = DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday; // 1 = Mon
    final weekdayOffset = (firstWeekday - 1) % 7;
    final totalCells = ((weekdayOffset + daysInMonth + 6) ~/ 7) * 7;

    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final monthGrid = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Weekdays header
          Row(
            children: weekdays.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Grid cells
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: isDesktop ? 1.25 : (isNarrow ? 0.95 : 1.1),
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              final dayNumber = index - weekdayOffset + 1;
              final isValidDay = dayNumber >= 1 && dayNumber <= daysInMonth;

              if (!isValidDay) {
                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.containerBg(context).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }

              final cellDate = DateTime(_focusedMonth.year, _focusedMonth.month, dayNumber);
              final isToday = _isSameDay(cellDate, _today);
              final isSelected = _isSameDay(cellDate, _selectedDate);

              final dayActions = _actionsForDay(cellDate);
              final dayFollowUps = _followUpsForDay(cellDate);
              final dayTasks = _tasksForDay(cellDate);
              final totalItems = dayActions.length + dayFollowUps.length + dayTasks.length;

              final hasOverdue = dayActions.any(_isActionOverdue) ||
                  dayFollowUps.any(_isFollowUpOverdue) ||
                  dayTasks.any((t) => t.isOverdue(_today));
              final hasDueToday = dayActions.any(_isActionDueToday) ||
                  dayFollowUps.any(_isFollowUpDueToday) ||
                  dayTasks.any((t) => t.isDueToday(_today));

              return InkWell(
                key: Key('calendar_day_cell_$dayNumber'),
                onTap: () => setState(() => _selectedDate = cellDate),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withValues(alpha: 0.12)
                        : (isToday
                            ? AppTheme.primaryColor.withValues(alpha: 0.05)
                            : AppTheme.cardBg(context)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isToday
                              ? AppTheme.primaryColor.withValues(alpha: 0.5)
                              : AppTheme.cardBorder(context)),
                      width: isSelected ? 1.6 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Day number & badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                              decoration: isToday
                                  ? BoxDecoration(
                                      color: AppTheme.primaryColor,
                                      borderRadius: BorderRadius.circular(4),
                                    )
                                  : null,
                              child: Text(
                                '$dayNumber',
                                style: TextStyle(
                                  fontSize: isNarrow ? 10 : 11.5,
                                  fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w500,
                                  color: isToday
                                      ? Colors.white
                                      : (isSelected
                                          ? AppTheme.primaryColor
                                          : AppTheme.textPrimary(context)),
                                ),
                              ),
                            ),
                          ),
                          if (totalItems > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              decoration: BoxDecoration(
                                color: hasOverdue
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : (hasDueToday
                                        ? const Color(0xFFEA580C).withValues(alpha: 0.2)
                                        : AppTheme.primaryColor.withValues(alpha: 0.15)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$totalItems',
                                style: TextStyle(
                                  fontSize: isNarrow ? 8.5 : 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: hasOverdue
                                      ? Colors.red
                                      : (hasDueToday
                                          ? const Color(0xFFEA580C)
                                          : AppTheme.primaryColor),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),

                      // Item Indicators / Mini Dots
                      if (totalItems > 0) ...[
                        Wrap(
                          spacing: 3,
                          runSpacing: 2,
                          alignment: WrapAlignment.center,
                          children: [
                            if (dayActions.isNotEmpty)
                              ...dayActions.take(2).map((act) {
                                Color dotColor = const Color(0xFF0284C7);
                                if (act.isClosed) {
                                  dotColor = const Color(0xFF16A34A);
                                } else if (_isActionOverdue(act)) {
                                  dotColor = Colors.red;
                                } else if (_isActionDueToday(act)) {
                                  dotColor = const Color(0xFFEA580C);
                                }
                                return Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            if (dayFollowUps.isNotEmpty)
                              ...dayFollowUps.take(2).map((fu) {
                                Color dotColor = const Color(0xFFD97706);
                                if (fu.isCompleted) {
                                  dotColor = const Color(0xFF16A34A);
                                } else if (_isFollowUpOverdue(fu)) {
                                  dotColor = Colors.red;
                                } else if (_isFollowUpDueToday(fu)) {
                                  dotColor = const Color(0xFFEA580C);
                                }
                                return Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            if (dayTasks.isNotEmpty)
                              ...dayTasks.take(2).map((_) {
                                return Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF7C3AED),
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                          ],
                        ),
                      ],
                      const SizedBox(height: 2),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );

    final selectedDayAgenda = _buildSelectedDayAgenda(context);

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: monthGrid),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: selectedDayAgenda),
        ],
      );
    } else {
      return Column(
        children: [
          monthGrid,
          const SizedBox(height: 14),
          selectedDayAgenda,
        ],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Week View
  // ---------------------------------------------------------------------------
  Widget _buildWeekView(
    BuildContext context, {
    required bool isDesktop,
    required bool isNarrow,
  }) {
    // 7 days starting from Monday
    final weekday = _selectedDate.weekday;
    final startOfWeek = _selectedDate.subtract(Duration(days: weekday - 1));
    final weekDays = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
    final weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    if (isNarrow) {
      // Stacked scrollable week on narrow viewports
      return Column(
        children: weekDays.map((day) {
          final dayActions = _actionsForDay(day);
          final dayFollowUps = _followUpsForDay(day);
          final dayTasks = _tasksForDay(day);
          final isToday = _isSameDay(day, _today);
          final isSelected = _isSameDay(day, _selectedDate);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryColor
                    : (isToday ? AppTheme.primaryColor.withValues(alpha: 0.5) : AppTheme.cardBorder(context)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${weekdayNames[day.weekday - 1]}, ${day.day}/${day.month}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isToday ? AppTheme.primaryColor : AppTheme.textPrimary(context),
                      ),
                    ),
                    if (isToday)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('TODAY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (dayActions.isEmpty && dayFollowUps.isEmpty && dayTasks.isEmpty)
                  Text('No items', style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted(context)))
                else ...[
                  ...dayActions.map((act) => _buildActionCard(context, act, compact: true)),
                  ...dayFollowUps.map((fu) => _buildFollowUpCard(context, fu, compact: true)),
                  ...dayTasks.map((t) => _buildPersonalTaskCard(context, t, compact: true)),
                ],
              ],
            ),
          );
        }).toList(),
      );
    }

    // Multi-column week view for wide screens
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: weekDays.map((day) {
          final isToday = _isSameDay(day, _today);
          final isSelected = _isSameDay(day, _selectedDate);
          final dayActions = _actionsForDay(day);
          final dayFollowUps = _followUpsForDay(day);
          final dayTasks = _tasksForDay(day);

          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedDate = day),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor.withValues(alpha: 0.08)
                      : (isToday ? AppTheme.primaryColor.withValues(alpha: 0.04) : Colors.transparent),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : (isToday ? AppTheme.primaryColor.withValues(alpha: 0.4) : AppTheme.cardBorder(context)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        weekdayNames[day.weekday - 1],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: isToday
                            ? const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle)
                            : null,
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isToday
                                ? Colors.white
                                : (isSelected ? AppTheme.primaryColor : AppTheme.textPrimary(context)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),

                    if (dayActions.isEmpty && dayFollowUps.isEmpty && dayTasks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: Text(
                            'No items',
                            style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted(context)),
                          ),
                        ),
                      )
                    else ...[
                      ...dayActions.map((act) => _buildActionCard(context, act, compact: true)),
                      ...dayFollowUps.map((fu) => _buildFollowUpCard(context, fu, compact: true)),
                      ...dayTasks.map((t) => _buildPersonalTaskCard(context, t, compact: true)),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Day View
  // ---------------------------------------------------------------------------
  Widget _buildDayView(BuildContext context, {required bool isDesktop}) {
    final dayActions = _actionsForDay(_selectedDate);
    final dayFollowUps = _followUpsForDay(_selectedDate);
    final dayTasks = _tasksForDay(_selectedDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_note_rounded, color: AppTheme.primaryColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Agenda for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                key: const Key('add_task_day_view_button'),
                onPressed: () => _openTaskDialog(initialDueDate: _selectedDate),
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text('Add Task for this Day', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF7C3AED)),
                  foregroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Official Actions Section
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(
                'Official HSSE Actions (${dayActions.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (dayActions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No official HSSE actions scheduled or due on this date.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
              ),
            )
          else
            ...dayActions.map((act) => _buildActionCard(context, act, compact: false)),

          const SizedBox(height: 20),

          // Follow-up Checkpoints Section
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(color: const Color(0xFFD97706), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(
                'Follow-up Checkpoints (${dayFollowUps.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (dayFollowUps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No action follow-ups scheduled for this date.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
              ),
            )
          else
            ...dayFollowUps.map((fu) => _buildFollowUpCard(context, fu, compact: false)),

          const SizedBox(height: 20),

          // Personal Tasks Section
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(
                'Private Personal Tasks (${dayTasks.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (dayTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No personal tasks due on this date.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
              ),
            )
          else
            ...dayTasks.map((task) => _buildPersonalTaskCard(context, task, compact: false)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Selected Day Agenda (Side panel on Desktop, bottom on mobile)
  // ---------------------------------------------------------------------------
  Widget _buildSelectedDayAgenda(BuildContext context) {
    final dayActions = _actionsForDay(_selectedDate);
    final dayFollowUps = _followUpsForDay(_selectedDate);
    final dayTasks = _tasksForDay(_selectedDate);

    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.today_rounded, size: 18, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedDate.day} ${monthNames[_selectedDate.month - 1]} ${_selectedDate.year}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ],
              ),
              IconButton(
                key: const Key('add_task_for_selected_day_button'),
                icon: const Icon(Icons.add_task_rounded, size: 18, color: Color(0xFF7C3AED)),
                tooltip: 'Add task for this day',
                onPressed: () => _openTaskDialog(initialDueDate: _selectedDate),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Counts summary
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _agendaCountPill(
                label: 'Actions',
                count: dayActions.length,
                color: const Color(0xFF0284C7),
              ),
              _agendaCountPill(
                label: 'Follow-ups',
                count: dayFollowUps.length,
                color: const Color(0xFFD97706),
              ),
              _agendaCountPill(
                label: 'Personal Tasks',
                count: dayTasks.length,
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (dayActions.isEmpty && dayFollowUps.isEmpty && dayTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_available_outlined, size: 36, color: AppTheme.textMuted(context)),
                    const SizedBox(height: 8),
                    Text(
                      'No items scheduled for this day',
                      style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(context)),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (dayActions.isNotEmpty) ...[
              Text(
                'HSSE Actions (Target Dates)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 6),
              ...dayActions.map((act) => _buildActionCard(context, act, compact: false)),
              const SizedBox(height: 12),
            ],
            if (dayFollowUps.isNotEmpty) ...[
              Text(
                'Follow-up Checkpoints',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(height: 6),
              ...dayFollowUps.map((fu) => _buildFollowUpCard(context, fu, compact: false)),
              const SizedBox(height: 12),
            ],
            if (dayTasks.isNotEmpty) ...[
              Text(
                'Personal Tasks',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 6),
              ...dayTasks.map((t) => _buildPersonalTaskCard(context, t, compact: false)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _agendaCountPill({required String label, required int count, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card: Official HSSE Action
  // ---------------------------------------------------------------------------
  Widget _buildActionCard(BuildContext context, ActionRecord act, {required bool compact}) {
    Color statusColor;
    String statusLabel = act.status;
    if (act.isClosed) {
      statusColor = const Color(0xFF16A34A);
    } else if (_isActionOverdue(act)) {
      statusColor = Colors.red;
    } else if (_isActionDueToday(act)) {
      statusColor = const Color(0xFFEA580C);
    } else {
      statusColor = const Color(0xFF0284C7);
    }

    if (compact) {
      return InkWell(
        key: Key('calendar_action_item_${act.id}'),
        onTap: () => widget.onActionTap?.call(act),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      act.id,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                act.subject,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      key: Key('calendar_action_item_${act.id}'),
      onTap: () => widget.onActionTap?.call(act),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.containerBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.cardBorder(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // HSSE Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, size: 11, color: Color(0xFF0284C7)),
                      SizedBox(width: 3),
                      Text('HSSE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Action ID
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.actionIdBg(context),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.actionIdBorder(context)),
                  ),
                  child: Text(
                    act.id,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.actionIdText(context),
                    ),
                  ),
                ),
                const Spacer(),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              act.subject,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_rounded, size: 12, color: _priorityColor(act.priority)),
                    const SizedBox(width: 3),
                    Text(
                      act.priority,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _priorityColor(act.priority),
                      ),
                    ),
                  ],
                ),
                if (act.targetDate.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_outlined, size: 12, color: AppTheme.textSecondary(context)),
                      const SizedBox(width: 3),
                      Text(
                        'Target: ${act.targetDate}',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context)),
                      ),
                    ],
                  ),
                if (act.assignedTo.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline_rounded, size: 12, color: AppTheme.textSecondary(context)),
                      const SizedBox(width: 3),
                      Text(
                        act.assignedTo,
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card: Personal Calendar Task
  // ---------------------------------------------------------------------------
  Widget _buildPersonalTaskCard(BuildContext context, CalendarTask task, {required bool compact}) {
    final isDone = task.isCompleted;

    if (compact) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            InkWell(
              key: Key('toggle_task_compact_${task.id}'),
              onTap: () => _togglePersonalTaskCompletion(task, !isDone),
              child: Icon(
                isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: isDone ? const Color(0xFF16A34A) : const Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontSize: 10.5,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  color: isDone ? AppTheme.textMuted(context) : AppTheme.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.containerBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Checkbox
              InkWell(
                key: Key('toggle_task_${task.id}'),
                onTap: () => _togglePersonalTaskCompletion(task, !isDone),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: isDone ? const Color(0xFF16A34A) : const Color(0xFF7C3AED),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Personal Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_pin_rounded, size: 11, color: Color(0xFF7C3AED)),
                    SizedBox(width: 3),
                    Text('Personal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED))),
                  ],
                ),
              ),
              const Spacer(),
              // Priority
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _priorityColor(task.priority).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  task.priority,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: _priorityColor(task.priority),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Edit button
              IconButton(
                key: Key('edit_task_${task.id}'),
                icon: const Icon(Icons.edit_outlined, size: 16),
                tooltip: 'Edit Task',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _openTaskDialog(taskToEdit: task),
              ),
              // Delete button
              IconButton(
                key: Key('delete_task_${task.id}'),
                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                tooltip: 'Delete Task',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _deletePersonalTask(task),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color: isDone ? AppTheme.textMuted(context) : AppTheme.textPrimary(context),
                  ),
                ),
                if (task.description != null && task.description!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    task.description!,
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary(context)),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 11, color: AppTheme.textSecondary(context)),
                    const SizedBox(width: 3),
                    Text(
                      '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year} at ${task.dueDate.hour.toString().padLeft(2, '0')}:${task.dueDate.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card: Action Follow-up Checkpoint
  // ---------------------------------------------------------------------------
  Widget _buildFollowUpCard(
    BuildContext context,
    CalendarFollowUpItem item, {
    required bool compact,
  }) {
    Color statusColor;
    final statusLower = item.status.trim().toLowerCase();
    if (item.isCompleted) {
      statusColor = const Color(0xFF16A34A);
    } else if (_isFollowUpOverdue(item)) {
      statusColor = Colors.red;
    } else if (_isFollowUpDueToday(item)) {
      statusColor = const Color(0xFFEA580C);
    } else if (statusLower == 'cancelled') {
      statusColor = Colors.grey;
    } else {
      statusColor = const Color(0xFFD97706);
    }

    if (compact) {
      return InkWell(
        key: Key('calendar_followup_item_${item.id}'),
        onTap: () => _showFollowUpDetailsDialog(context, item),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFD97706).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFFD97706).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    size: 11,
                    color: Color(0xFFD97706),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${item.actionId} (Follow-up)',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD97706),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                item.actionSubject,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      key: Key('calendar_followup_item_${item.id}'),
      onTap: () => _showFollowUpDetailsDialog(context, item),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.containerBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFD97706).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Follow-up Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 11, color: Color(0xFFD97706)),
                      SizedBox(width: 3),
                      Text(
                        'FOLLOW-UP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Action Reference ID
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.actionIdBg(context),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.actionIdBorder(context)),
                  ),
                  child: Text(
                    item.actionId,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.actionIdText(context),
                    ),
                  ),
                ),
                const Spacer(),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    item.status,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.actionSubject,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.alarm_rounded, size: 12, color: Color(0xFFD97706)),
                    const SizedBox(width: 3),
                    Text(
                      'Follow-up: ${item.followUp.followUpDate}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline_rounded, size: 12, color: AppTheme.textSecondary(context)),
                    const SizedBox(width: 3),
                    Text(
                      item.actionAssignee,
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (item.targetDate.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_outlined, size: 12, color: AppTheme.textSecondary(context)),
                      const SizedBox(width: 3),
                      Text(
                        'Target: ${item.targetDate}',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context)),
                      ),
                    ],
                  ),
              ],
            ),
            if (item.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg(context),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.cardBorder(context)),
                ),
                child: Text(
                  item.notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFollowUpDetailsDialog(BuildContext context, CalendarFollowUpItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.history_toggle_off_rounded,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Follow-up Checkpoint Details',
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
                  // Action info banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.containerBg(ctx),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.cardBorder(ctx)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.actionIdBg(ctx),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppTheme.actionIdBorder(ctx)),
                              ),
                              child: Text(
                                item.actionId,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.actionIdText(ctx),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.actionSubject,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Scheduled Date
                  _detailRow(
                    ctx,
                    icon: Icons.calendar_today_rounded,
                    label: 'Scheduled Date',
                    value: item.followUp.followUpDate,
                    valueColor: const Color(0xFFD97706),
                    valueBold: true,
                  ),
                  const SizedBox(height: 8),

                  // Status
                  _detailRow(
                    ctx,
                    icon: Icons.info_outline_rounded,
                    label: 'Checkpoint Status',
                    value: item.status,
                  ),
                  const SizedBox(height: 8),

                  // Responsible Person
                  _detailRow(
                    ctx,
                    icon: Icons.person_outline_rounded,
                    label: 'Responsible Person',
                    value: item.actionAssignee,
                  ),
                  const SizedBox(height: 8),

                  // Action Target Date
                  _detailRow(
                    ctx,
                    icon: Icons.flag_outlined,
                    label: 'Action Target Date',
                    value: item.targetDate.isNotEmpty ? item.targetDate : 'Not specified',
                  ),
                  const SizedBox(height: 8),

                  // Created by
                  if (item.followUp.createdByName.isNotEmpty) ...[
                    _detailRow(
                      ctx,
                      icon: Icons.account_circle_outlined,
                      label: 'Created By',
                      value: item.followUp.createdByName,
                    ),
                    const SizedBox(height: 8),
                  ],

                  const Divider(height: 18),

                  // Notes section
                  Text(
                    'Follow-up Notes / Instructions',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary(ctx),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBg(ctx),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.cardBorder(ctx)),
                    ),
                    child: Text(
                      item.notes.trim().isNotEmpty
                          ? item.notes.trim()
                          : 'No specific notes recorded for this checkpoint.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: item.notes.trim().isNotEmpty
                            ? AppTheme.textPrimary(ctx)
                            : AppTheme.textMuted(ctx),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              key: const Key('follow_up_details_view_action_button'),
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onActionTap?.call(item.action);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('View Action Details'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool valueBold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppTheme.textSecondary(context)),
        const SizedBox(width: 8),
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: valueBold ? FontWeight.bold : FontWeight.w500,
              color: valueColor ?? AppTheme.textPrimary(context),
            ),
          ),
        ),
      ],
    );
  }

  Color _priorityColor(String? priority) {
    switch (priority?.trim().toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'high':
        return const Color(0xFFEA580C);
      case 'medium':
        return const Color(0xFFD97706);
      case 'low':
      default:
        return const Color(0xFF16A34A);
    }
  }
}
