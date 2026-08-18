// SPDX-License-Identifier: AGPL-3.0-only

import 'note_file.dart';

class ProjectDeadline {
  const ProjectDeadline({
    required this.dueDate,
    required this.title,
    required this.summary,
    required this.notePath,
    required this.noteKind,
    required this.lineNumber,
  });

  final DateTime dueDate;
  final String title;
  final String summary;
  final String notePath;
  final NoteKind noteKind;
  final int lineNumber;

  bool isDueOn(DateTime date) =>
      dueDate.year == date.year &&
      dueDate.month == date.month &&
      dueDate.day == date.day;
}
