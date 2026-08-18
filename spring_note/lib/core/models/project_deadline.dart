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
    required this.isCompleted,
    required this.sourceLine,
  });

  final DateTime dueDate;
  final String title;
  final String summary;
  final String notePath;
  final NoteKind noteKind;
  final int lineNumber;
  final bool isCompleted;
  final String sourceLine;

  bool isDueOn(DateTime date) =>
      dueDate.year == date.year &&
      dueDate.month == date.month &&
      dueDate.day == date.day;
}

class ProjectDateCandidate {
  const ProjectDateCandidate({
    required this.date,
    required this.lineNumber,
    required this.sourceLine,
    required this.start,
    required this.end,
    required this.matchedText,
  });

  final DateTime date;
  final int lineNumber;
  final String sourceLine;
  final int start;
  final int end;
  final String matchedText;
}
