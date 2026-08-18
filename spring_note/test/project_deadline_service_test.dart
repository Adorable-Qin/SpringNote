// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/note_file.dart';
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

  test('parses Chinese and English deadline labels', () {
    final deadlines = service.parseMarkdown(
      note: note,
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

  test('accepts dash slash dot and Chinese date separators', () {
    final deadlines = service.parseMarkdown(
      note: note,
      content: '''
截止：2026-10-01
截止：2026/10/02
截止：2026.10.03
截止：2026年10月4日
''',
    );

    expect(
      deadlines.map((deadline) => deadline.dueDate).toList(),
      [
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 3),
        DateTime(2026, 10, 4),
      ],
    );
    expect(deadlines.first.summary, note.title);
  });

  test('ignores invalid dates and completed Markdown tasks', () {
    final deadlines = service.parseMarkdown(
      note: note,
      content: '''
- [x] 已完成任务 截止：2026-08-20
- [X] Completed task Due: 2026-08-21
- 无效日期 截止：2026-02-30
- 有效任务 Deadline: 2026-08-22
''',
    );

    expect(deadlines, hasLength(1));
    expect(deadlines.single.dueDate, DateTime(2026, 8, 22));
    expect(deadlines.single.summary, '有效任务');
    expect(deadlines.single.lineNumber, 4);
  });

  test('keeps note metadata on each reminder', () {
    final deadline = service.parseMarkdown(
      note: note,
      content: '''
# 发布计划

- 提交方案 到期：2026-12-01
''',
    ).single;

    expect(deadline.title, note.title);
    expect(deadline.notePath, note.path);
    expect(deadline.noteKind, NoteKind.daily);
    expect(deadline.lineNumber, 3);
  });
}
