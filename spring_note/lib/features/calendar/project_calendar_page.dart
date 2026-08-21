// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/note_external_update.dart';
import '../../core/models/note_file.dart';
import '../../core/models/project_deadline.dart';
import '../../core/services/project_deadline_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../l10n/l10n.dart';

class ProjectCalendarPage extends StatefulWidget {
  const ProjectCalendarPage({
    super.key,
    required this.localDataState,
    this.deadlineService = const ProjectDeadlineService(),
    this.externalNoteUpdate,
    this.onNoteSaved,
  });

  final LocalDataState localDataState;
  final ProjectDeadlineService deadlineService;
  final ValueListenable<NoteExternalUpdate?>? externalNoteUpdate;
  final void Function(NoteKind kind, String path)? onNoteSaved;

  @override
  State<ProjectCalendarPage> createState() => _ProjectCalendarPageState();
}

class _ProjectCalendarPageState extends State<ProjectCalendarPage> {
  late DateTime _focusedMonth = _monthStart(DateTime.now());
  late DateTime _selectedDate = _dateOnly(DateTime.now());
  _AgendaView _agendaView = _AgendaView.selectedDate;
  List<ProjectDeadline> _deadlines = const [];
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;
  final Set<String> _updatingDeadlines = {};

  @override
  void initState() {
    super.initState();
    widget.externalNoteUpdate?.addListener(_handleExternalNoteUpdate);
    unawaited(_loadDeadlines());
  }

  @override
  void didUpdateWidget(covariant ProjectCalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalNoteUpdate != oldWidget.externalNoteUpdate) {
      oldWidget.externalNoteUpdate?.removeListener(_handleExternalNoteUpdate);
      widget.externalNoteUpdate?.addListener(_handleExternalNoteUpdate);
    }
    if (_directoriesChanged(oldWidget.localDataState, widget.localDataState)) {
      unawaited(_loadDeadlines());
    }
  }

  @override
  void dispose() {
    widget.externalNoteUpdate?.removeListener(_handleExternalNoteUpdate);
    super.dispose();
  }

  void _handleExternalNoteUpdate() => unawaited(_loadDeadlines());

  Future<void> _loadDeadlines() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final deadlines = await widget.deadlineService.listDeadlines(
        widget.localDataState,
      );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _deadlines = deadlines;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _CalendarStrings.of(context);
    return SpringNotePageScaffold(
      title: strings.title,
      actions: [
        TextButton.icon(
          onPressed: _showToday,
          icon: const Icon(Icons.today_outlined, size: 17),
          label: Text(strings.today),
        ),
        SpringNoteIconButton(
          icon: Icons.refresh_rounded,
          tooltip: strings.refresh,
          onPressed: _loading ? null : () => unawaited(_loadDeadlines()),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 0, 48, 40),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 880) {
              return ListView(
                children: [
                  SizedBox(height: 520, child: _buildCalendarCard(strings)),
                  const SizedBox(height: 20),
                  _buildAgendaCard(strings, bounded: false),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 7, child: _buildCalendarCard(strings)),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: _buildAgendaCard(strings)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCalendarCard(_CalendarStrings strings) {
    final colors = AppTheme.colors(context);
    final monthDays = _calendarDays(_focusedMonth);
    return SoftCard(
      padding: const EdgeInsets.all(22),
      borderRadius: 22,
      withShadow: false,
      child: Column(
        children: [
          Row(
            children: [
              SpringNoteIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: strings.previousMonth,
                onPressed: () => _changeMonth(-1),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      strings.monthLabel(_focusedMonth),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.currentWeek(_isoWeekNumber(DateTime.now())),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SpringNoteIconButton(
                icon: Icons.chevron_right_rounded,
                tooltip: strings.nextMonth,
                onPressed: () => _changeMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final weekday in strings.weekdays)
                Expanded(
                  child: Text(
                    weekday,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSubtle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.08,
              ),
              itemCount: monthDays.length,
              itemBuilder: (context, index) {
                final date = monthDays[index];
                return _CalendarDayTile(
                  date: date,
                  inFocusedMonth: date.month == _focusedMonth.month,
                  selected: _sameDate(date, _selectedDate),
                  today: _sameDate(date, DateTime.now()),
                  deadlines: _deadlinesFor(date),
                  onTap: () => setState(() {
                    _selectedDate = date;
                    _agendaView = _AgendaView.selectedDate;
                    if (date.month != _focusedMonth.month ||
                        date.year != _focusedMonth.year) {
                      _focusedMonth = _monthStart(date);
                    }
                  }),
                );
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _buildAgendaCard(_CalendarStrings strings, {bool bounded = true}) {
    final colors = AppTheme.colors(context);
    final today = _dateOnly(DateTime.now());
    final selectedDeadlines = _deadlinesFor(_selectedDate);
    final overdueDeadlines = _deadlines
        .where(
          (deadline) =>
              !deadline.isCompleted && deadline.dueDate.isBefore(today),
        )
        .toList();
    final dueTodayDeadlines = _deadlinesFor(
      today,
    ).where((deadline) => !deadline.isCompleted).toList();
    final completedDeadlines = _deadlines
        .where((deadline) => deadline.isCompleted)
        .toList();
    final visibleDeadlines = switch (_agendaView) {
      _AgendaView.selectedDate => selectedDeadlines,
      _AgendaView.overdue => overdueDeadlines,
      _AgendaView.dueToday => dueTodayDeadlines,
      _AgendaView.completed => completedDeadlines,
    };
    final agendaTitle = switch (_agendaView) {
      _AgendaView.selectedDate => strings.selectedDateLabel(_selectedDate),
      _AgendaView.overdue => strings.overdueTitle,
      _AgendaView.dueToday => strings.dueTodayTitle,
      _AgendaView.completed => strings.completedTitle,
    };
    final emptyMessage = switch (_agendaView) {
      _AgendaView.selectedDate => strings.noDeadlineOnDate,
      _AgendaView.overdue => strings.noOverdueDeadlines,
      _AgendaView.dueToday => strings.noDeadlinesDueToday,
      _AgendaView.completed => strings.noCompletedDeadlines,
    };
    final emptyDetail = _agendaView == _AgendaView.selectedDate
        ? strings.selectAnotherDate
        : strings.selectDateViewHint;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          agendaTitle,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          strings.deadlineCount(visibleDeadlines.length),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSubtle),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              label: strings.overdue(overdueDeadlines.length),
              color: const Color(0xFFDC2626),
              selected: _agendaView == _AgendaView.overdue,
              onTap: () => _toggleAgendaView(_AgendaView.overdue),
            ),
            _StatusChip(
              label: strings.dueToday(dueTodayDeadlines.length),
              color: const Color(0xFFD97706),
              selected: _agendaView == _AgendaView.dueToday,
              onTap: () => _toggleAgendaView(_AgendaView.dueToday),
            ),
            _StatusChip(
              label: strings.completed(completedDeadlines.length),
              color: const Color(0xFF16A34A),
              selected: _agendaView == _AgendaView.completed,
              onTap: () => _toggleAgendaView(_AgendaView.completed),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_error != null)
          _EmptyAgenda(
            icon: Icons.error_outline_rounded,
            message: strings.loadFailed,
            detail: _error,
          )
        else if (!_loading && _deadlines.isEmpty)
          _EmptyAgenda(
            icon: Icons.event_note_outlined,
            message: strings.noDeadlines,
            detail: strings.formatHint,
          )
        else if (visibleDeadlines.isEmpty)
          _EmptyAgenda(
            icon: Icons.event_available_outlined,
            message: emptyMessage,
            detail: emptyDetail,
          )
        else
          for (var index = 0; index < visibleDeadlines.length; index++) ...[
            _DeadlineCard(
              deadline: visibleDeadlines[index],
              strings: strings,
              showDueDate: _agendaView != _AgendaView.selectedDate,
              updating: _updatingDeadlines.contains(
                _deadlineKey(visibleDeadlines[index]),
              ),
              onToggle: () => _toggleDeadline(visibleDeadlines[index]),
            ),
            if (index != visibleDeadlines.length - 1)
              const SizedBox(height: 10),
          ],
      ],
    );
    return SoftCard(
      padding: const EdgeInsets.all(22),
      borderRadius: 22,
      withShadow: false,
      child: bounded ? SingleChildScrollView(child: content) : content,
    );
  }

  void _toggleAgendaView(_AgendaView view) {
    setState(() {
      _agendaView = _agendaView == view ? _AgendaView.selectedDate : view;
    });
  }

  Future<void> _toggleDeadline(ProjectDeadline deadline) async {
    final key = _deadlineKey(deadline);
    if (_updatingDeadlines.contains(key)) {
      return;
    }
    setState(() => _updatingDeadlines.add(key));
    try {
      await widget.deadlineService.setCompleted(
        deadline,
        completed: !deadline.isCompleted,
      );
      await _loadDeadlines();
      widget.onNoteSaved?.call(deadline.noteKind, deadline.notePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !deadline.isCompleted
                  ? _CalendarStrings.of(context).markedCompleted
                  : _CalendarStrings.of(context).markedIncomplete,
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _updatingDeadlines.remove(key));
      }
    }
  }

  String _deadlineKey(ProjectDeadline deadline) =>
      '${deadline.notePath}:${deadline.lineNumber}';

  List<ProjectDeadline> _deadlinesFor(DateTime date) =>
      _deadlines.where((deadline) => deadline.isDueOn(date)).toList();

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + offset,
      );
      _selectedDate = _focusedMonth;
      _agendaView = _AgendaView.selectedDate;
    });
  }

  void _showToday() {
    final today = _dateOnly(DateTime.now());
    setState(() {
      _focusedMonth = _monthStart(today);
      _selectedDate = today;
      _agendaView = _AgendaView.selectedDate;
    });
  }

  static bool _directoriesChanged(LocalDataState left, LocalDataState right) =>
      left.dailyNotesDirectory != right.dailyNotesDirectory ||
      left.weeklyNotesDirectory != right.weeklyNotesDirectory ||
      left.monthlyNotesDirectory != right.monthlyNotesDirectory;
}

enum _AgendaView { selectedDate, overdue, dueToday, completed }

class _CalendarDayTile extends StatelessWidget {
  const _CalendarDayTile({
    required this.date,
    required this.inFocusedMonth,
    required this.selected,
    required this.today,
    required this.deadlines,
    required this.onTap,
  });

  final DateTime date;
  final bool inFocusedMonth;
  final bool selected;
  final bool today;
  final List<ProjectDeadline> deadlines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final background = selected
        ? colors.text.withValues(alpha: 0.08)
        : Colors.transparent;
    final borderColor = selected
        ? colors.textMuted
        : today
        ? colors.textMuted
        : colors.border.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${date.day}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: inFocusedMonth
                          ? colors.text
                          : colors.textSubtle.withValues(alpha: 0.55),
                      fontWeight: today || selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (deadlines.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _deadlineColor(date).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${deadlines.length}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _deadlineColor(date),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              for (final deadline in deadlines.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: deadline.isCompleted
                              ? const Color(0xFF16A34A)
                              : _deadlineColor(date),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          deadline.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: deadline.isCompleted
                                    ? const Color(0xFF16A34A)
                                    : inFocusedMonth
                                    ? colors.textMuted
                                    : colors.textSubtle.withValues(alpha: 0.5),
                                decoration: deadline.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                fontSize: 9.5,
                              ),
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
}

class _DeadlineCard extends StatelessWidget {
  const _DeadlineCard({
    required this.deadline,
    required this.strings,
    required this.showDueDate,
    required this.onToggle,
    required this.updating,
  });

  final ProjectDeadline deadline;
  final _CalendarStrings strings;
  final bool showDueDate;
  final VoidCallback onToggle;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final color = deadline.isCompleted
        ? const Color(0xFF16A34A)
        : _deadlineColor(deadline.dueDate);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.55),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: deadline.isCompleted
                ? strings.markIncomplete
                : strings.markCompleted,
            child: Checkbox(
              value: deadline.isCompleted,
              onChanged: updating ? null : (_) => onToggle(),
              visualDensity: VisualDensity.compact,
            ),
          ),
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deadline.summary,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: deadline.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: deadline.isCompleted ? colors.textSubtle : null,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${showDueDate ? '${strings.dueDateLabel(deadline.dueDate)} · ' : ''}'
                  '${deadline.title} · ${strings.kind(deadline.noteKind)} · '
                  '${strings.line(deadline.lineNumber)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSubtle),
                ),
                if (deadline.isCompleted) ...[
                  const SizedBox(height: 5),
                  Text(
                    strings.completedLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF16A34A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color.withValues(alpha: 0.18)
          : color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: selected ? Border.all(color: color) : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyAgenda extends StatelessWidget {
  const _EmptyAgenda({required this.icon, required this.message, this.detail});

  final IconData icon;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 34, color: colors.textSubtle),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSubtle),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalendarStrings {
  const _CalendarStrings(this.english);

  final bool english;

  static _CalendarStrings of(BuildContext context) =>
      _CalendarStrings(currentAppLanguage(context) == 'en');

  String get title => english ? 'Project Calendar' : '项目日历';
  String get today => english ? 'Today' : '今天';
  String get refresh => english ? 'Refresh deadlines' : '刷新截止日期';
  String get previousMonth => english ? 'Previous month' : '上个月';
  String get nextMonth => english ? 'Next month' : '下个月';
  String get noDeadlines => english ? 'No deadlines found' : '没有找到截止日期';
  String get noDeadlineOnDate =>
      english ? 'No reminder on this date' : '这一天没有提醒';
  String get noOverdueDeadlines => english ? 'No overdue reminders' : '没有已逾期事项';
  String get noDeadlinesDueToday =>
      english ? 'No reminders due today' : '今天没有到期事项';
  String get noCompletedDeadlines =>
      english ? 'No completed reminders' : '没有已完成事项';
  String get selectAnotherDate =>
      english ? 'Select another date to view its reminders.' : '请选择其他日期查看提醒。';
  String get selectDateViewHint => english
      ? 'Select a calendar date or tap the active status again to return.'
      : '选择日历日期，或再次点击当前状态标签返回按日期查看。';
  String get loadFailed => english ? 'Unable to load deadlines' : '截止日期加载失败';
  String get formatHint => english
      ? 'Add “Due: 2026-08-30” or “Due: 8/30”. Plain dates can also be added from the editor prompt.'
      : '支持“截止：2026-08-30”或“截止：8月30日”；只写日期时，编辑器也会询问是否加入日历。';

  List<String> get weekdays => english
      ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
      : const ['一', '二', '三', '四', '五', '六', '日'];

  String monthLabel(DateTime date) => english
      ? '${_englishMonths[date.month - 1]} ${date.year}'
      : '${date.year}年${date.month}月';

  String currentWeek(int week) =>
      english ? 'Current week · W$week' : '当前周 · W$week';

  String selectedDateLabel(DateTime date) => english
      ? '${_englishMonths[date.month - 1]} ${date.day}, ${date.year}'
      : '${date.year}年${date.month}月${date.day}日';

  String deadlineCount(int count) =>
      english ? '$count reminder${count == 1 ? '' : 's'}' : '$count 条截止提醒';
  String get overdueTitle => english ? 'Overdue reminders' : '已逾期记录';
  String get dueTodayTitle => english ? 'Due today' : '今天到期';
  String get completedTitle => english ? 'Completed reminders' : '已完成记录';
  String overdue(int count) => english ? '$count overdue' : '$count 条已逾期';
  String dueToday(int count) => english ? '$count due today' : '$count 条今天到期';
  String completed(int count) => english ? '$count completed' : '$count 条已完成';
  String get completedLabel => english ? 'Completed' : '已完成';
  String get markCompleted => english ? 'Mark as completed' : '标记为已完成';
  String get markIncomplete => english ? 'Mark as incomplete' : '标记为未完成';
  String get markedCompleted => english ? 'Marked as completed' : '已标记为完成';
  String get markedIncomplete => english ? 'Marked as incomplete' : '已取消完成标记';
  String dueDateLabel(DateTime date) => english
      ? 'Due ${_englishMonths[date.month - 1]} ${date.day}, ${date.year}'
      : '截止 ${date.year}年${date.month}月${date.day}日';
  String line(int lineNumber) =>
      english ? 'line $lineNumber' : '第 $lineNumber 行';
  String kind(NoteKind kind) => switch (kind) {
    NoteKind.daily => english ? 'Daily note' : '日报',
    NoteKind.weekly => english ? 'Weekly note' : '周报',
    NoteKind.monthly => english ? 'Monthly note' : '月报',
  };

  static const _englishMonths = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
}

List<DateTime> _calendarDays(DateTime month) {
  final first = _monthStart(month);
  final gridStart = first.subtract(Duration(days: first.weekday - 1));
  return List.generate(42, (index) => gridStart.add(Duration(days: index)));
}

DateTime _monthStart(DateTime date) => DateTime(date.year, date.month);
DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

int _isoWeekNumber(DateTime date) {
  final start = _dateOnly(date).subtract(Duration(days: date.weekday - 1));
  final isoYear = start.add(const Duration(days: 3)).year;
  final firstWeekStart = _dateOnly(
    DateTime(isoYear, 1, 4),
  ).subtract(Duration(days: DateTime(isoYear, 1, 4).weekday - 1));
  return (start.difference(firstWeekStart).inDays ~/ 7) + 1;
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

Color _deadlineColor(DateTime date) {
  final today = _dateOnly(DateTime.now());
  final due = _dateOnly(date);
  if (due.isBefore(today)) {
    return const Color(0xFFDC2626);
  }
  if (_sameDate(due, today)) {
    return const Color(0xFFD97706);
  }
  return const Color(0xFF2563EB);
}
