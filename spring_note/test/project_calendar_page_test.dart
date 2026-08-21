// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/note_file.dart';
import 'package:spring_note/core/models/project_deadline.dart';
import 'package:spring_note/core/services/project_deadline_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/calendar/project_calendar_page.dart';

void main() {
  testWidgets('overdue status opens the overdue reminder history', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final overdueDate = DateTime.now().subtract(const Duration(days: 1));
    final deadline = ProjectDeadline(
      dueDate: DateTime(overdueDate.year, overdueDate.month, overdueDate.day),
      title: '项目计划',
      summary: '处理遗留事项',
      notePath: '/notes/daily/overdue.md',
      noteKind: NoteKind.daily,
      lineNumber: 1,
      isCompleted: false,
      sourceLine: '- 处理遗留事项 截止：昨天',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProjectCalendarPage(
          localDataState: _localDataState(),
          deadlineService: _FakeProjectDeadlineService([deadline]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 条已逾期'), findsOneWidget);
    await tester.tap(find.text('1 条已逾期'));
    await tester.pump();

    expect(find.text('已逾期记录'), findsOneWidget);
    expect(find.text('处理遗留事项'), findsWidgets);
    expect(
      find.text(
        '截止 ${deadline.dueDate.year}年${deadline.dueDate.month}月'
        '${deadline.dueDate.day}日 · 项目计划 · 日报 · 第 1 行',
      ),
      findsOneWidget,
    );
  });
}

class _FakeProjectDeadlineService extends ProjectDeadlineService {
  const _FakeProjectDeadlineService(this.deadlines);

  final List<ProjectDeadline> deadlines;

  @override
  Future<List<ProjectDeadline>> listDeadlines(
    LocalDataState localDataState,
  ) async => deadlines;
}

LocalDataState _localDataState() {
  return LocalDataState(
    dataDirectory: '/data',
    configPath: '/data/config.json',
    dailyNotesDirectory: '/data/daily',
    weeklyNotesDirectory: '/data/weekly',
    monthlyNotesDirectory: '/data/monthly',
    config: AppConfig.defaults().copyWith(language: 'zh'),
  );
}
