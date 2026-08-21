// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/note_file.dart';
import 'package:spring_note/core/services/note_service.dart';
import 'package:spring_note/core/services/project_deadline_service.dart';

void main() {
  const service = ProjectDeadlineService();
  final note = NoteFile(
    path: '/notes/daily/2026-08-18.md',
    name: '2026-08-18.md',
    title: '2026-08-18 日报',
    modifiedAt: DateTime(2026, 8, 18),
    kind: NoteKind.daily,
  );
  final referenceDate = DateTime(2026, 8, 18);

  test('parses Chinese and English deadline labels', () {
    final deadlines = service.parseMarkdown(
      note: note,
      referenceDate: referenceDate,
      content: '''
- 发布 v2，截止日期：2026-08-30
* 设计评审 到期日 2026年9月2日
- English task Due date: 2026/09/05
''',
    );

    expect(deadlines, hasLength(3));
    expect(deadlines[0].dueDate, DateTime(2026, 8, 30));
    expect(deadlines[0].summary, '发布 v2');
    expect(deadlines[1].dueDate, DateTime(2026, 9, 2));
    expect(deadlines[1].summary, '设计评审');
    expect(deadlines[2].dueDate, DateTime(2026, 9, 5));
    expect(deadlines[2].summary, 'English task');
  });

  test('accepts full dates and month-day dates', () {
    final deadlines = service.parseMarkdown(
      note: note,
      referenceDate: referenceDate,
      content: '''
截止：2026-10-01
截止：2026/10/02
截止：2026.10.03
截止：2026年10月4日
截止：8月30日
截止：1/5
''',
    );

    expect(deadlines.map((deadline) => deadline.dueDate).toList(), [
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 2),
      DateTime(2026, 10, 3),
      DateTime(2026, 10, 4),
      DateTime(2026, 8, 30),
      DateTime(2027, 1, 5),
    ]);
    expect(deadlines.first.summary, note.title);
  });

  test('ignores invalid dates and keeps completed Markdown tasks', () {
    final deadlines = service.parseMarkdown(
      note: note,
      referenceDate: referenceDate,
      content: '''
- [x] 已完成任务 截止：2026-08-20
- [X] Completed task Due: 2026-08-21
- 无效日期 截止：2026-02-30
- 有效任务 Deadline: 2026-08-22
''',
    );

    expect(deadlines, hasLength(3));
    expect(deadlines[0].isCompleted, isTrue);
    expect(deadlines[1].isCompleted, isTrue);
    expect(deadlines[2].isCompleted, isFalse);
    expect(deadlines[2].dueDate, DateTime(2026, 8, 22));
    expect(deadlines[2].summary, '有效任务');
    expect(deadlines[2].lineNumber, 4);
  });

  test('finds implicit full dates and month-day dates for editor prompts', () {
    final candidates = service.findImplicitDates(
      referenceDate: referenceDate,
      content: '''
# 2026-08-18 日报
评审安排在 8月30日
- [x] 已完成事项 9/1
明确事项 截止：9/2
2026-09-03
''',
    );

    expect(candidates, hasLength(2));
    expect(candidates[0].date, DateTime(2026, 8, 30));
    expect(candidates[0].matchedText, '8月30日');
    expect(candidates[1].date, DateTime(2026, 9, 3));
    expect(candidates[1].matchedText, '2026-09-03');
  });

  test('keeps note metadata on each reminder', () {
    final deadline = service
        .parseMarkdown(
          note: note,
          referenceDate: referenceDate,
          content: '''
# 发布计划

- 提交方案 到期：2026-12-01
''',
        )
        .single;

    expect(deadline.title, note.title);
    expect(deadline.notePath, note.path);
    expect(deadline.noteKind, NoteKind.daily);
    expect(deadline.lineNumber, 3);
    expect(deadline.sourceLine, '- 提交方案 到期：2026-12-01');
  });

  test(
    'marks a calendar item completed and incomplete in its source note',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'spring-note-calendar-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}note.md';
      const noteService = NoteService();
      const writableService = ProjectDeadlineService(noteService: noteService);
      await noteService.writeMarkdown(path, '- 提交方案 截止：8月30日\n');
      final writableNote = NoteFile(
        path: path,
        name: 'note.md',
        title: '项目计划',
        modifiedAt: referenceDate,
        kind: NoteKind.daily,
      );

      var deadline = writableService
          .parseMarkdown(
            note: writableNote,
            referenceDate: referenceDate,
            content: await noteService.readMarkdown(path),
          )
          .single;
      await writableService.setCompleted(deadline, completed: true);
      expect(await noteService.readMarkdown(path), contains('- [x] 提交方案'));

      deadline = writableService
          .parseMarkdown(
            note: writableNote,
            referenceDate: referenceDate,
            content: await noteService.readMarkdown(path),
          )
          .single;
      expect(deadline.isCompleted, isTrue);
      await writableService.setCompleted(deadline, completed: false);
      expect(await noteService.readMarkdown(path), contains('- [ ] 提交方案'));
    },
  );

  test('keeps a month-day deadline tied to the dated daily note', () {
    final oldDailyNote = NoteFile(
      path: '/notes/daily/2026-08-18.md',
      name: '2026-08-18.md',
      title: '2026-08-18 日报',
      modifiedAt: DateTime(2026, 8, 21),
      kind: NoteKind.daily,
    );

    final deadline = service
        .parseMarkdown(note: oldDailyNote, content: '- 处理遗留事项 截止：8月20日')
        .single;

    expect(deadline.dueDate, DateTime(2026, 8, 20));
  });

  test('derives stable reference dates from weekly and monthly filenames', () {
    final weeklyNote = NoteFile(
      path: '/notes/weekly/2026-W34.md',
      name: '2026-W34.md',
      title: '2026-W34 周报',
      modifiedAt: DateTime(2026, 8, 21),
      kind: NoteKind.weekly,
    );
    final monthlyNote = NoteFile(
      path: '/notes/monthly/2026-08.md',
      name: '2026-08.md',
      title: '2026-08 月报',
      modifiedAt: DateTime(2026, 8, 21),
      kind: NoteKind.monthly,
    );

    expect(service.referenceDateForNote(weeklyNote), DateTime(2026, 8, 17));
    expect(service.referenceDateForNote(monthlyNote), DateTime(2026, 8));
  });
}
