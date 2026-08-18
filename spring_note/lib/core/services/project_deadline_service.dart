// SPDX-License-Identifier: AGPL-3.0-only

import '../models/local_data_state.dart';
import '../models/note_file.dart';
import '../models/project_deadline.dart';
import 'note_service.dart';

class ProjectDeadlineService {
  const ProjectDeadlineService({this.noteService = const NoteService()});

  final NoteService noteService;

  static final RegExp _deadlineLabel = RegExp(
    r'(?:截止(?:日期|时间)?|到期(?:日期|日|时间)?|deadline|due\s*date|due)\s*[:：]?\s*',
    caseSensitive: false,
  );
  static final RegExp _datePattern = RegExp(
    r'(\d{4})\s*(?:[-/.年])\s*(\d{1,2})\s*(?:[-/.月])\s*(\d{1,2})\s*日?',
  );
  static final RegExp _completedTask = RegExp(
    r'^\s*(?:[-*+]\s*)?\[[xX]\]',
  );

  Future<List<ProjectDeadline>> listDeadlines(
    LocalDataState localDataState,
  ) async {
    final deadlines = <ProjectDeadline>[];
    for (final source in <({String directory, NoteKind kind})>[
      (directory: localDataState.dailyNotesDirectory, kind: NoteKind.daily),
      (directory: localDataState.weeklyNotesDirectory, kind: NoteKind.weekly),
      (directory: localDataState.monthlyNotesDirectory, kind: NoteKind.monthly),
    ]) {
      final notes = await noteService.listMarkdownFiles(
        directoryPath: source.directory,
        kind: source.kind,
      );
      for (final note in notes) {
        final content = await noteService.readMarkdown(note.path);
        deadlines.addAll(parseMarkdown(note: note, content: content));
      }
    }
    deadlines.sort((left, right) {
      final dateOrder = left.dueDate.compareTo(right.dueDate);
      if (dateOrder != 0) {
        return dateOrder;
      }
      final titleOrder = left.title.compareTo(right.title);
      if (titleOrder != 0) {
        return titleOrder;
      }
      return left.lineNumber.compareTo(right.lineNumber);
    });
    return deadlines;
  }

  List<ProjectDeadline> parseMarkdown({
    required NoteFile note,
    required String content,
  }) {
    final deadlines = <ProjectDeadline>[];
    final seen = <String>{};
    final lines = content.split(RegExp(r'\r?\n'));
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (_completedTask.hasMatch(line)) {
        continue;
      }
      final labelMatch = _deadlineLabel.firstMatch(line);
      if (labelMatch == null) {
        continue;
      }
      final dateMatch = _datePattern.firstMatch(
        line.substring(labelMatch.end),
      );
      if (dateMatch == null) {
        continue;
      }
      final date = _tryDate(
        int.parse(dateMatch.group(1)!),
        int.parse(dateMatch.group(2)!),
        int.parse(dateMatch.group(3)!),
      );
      if (date == null) {
        continue;
      }
      final summary = _summaryFromLine(
        line,
        labelStart: labelMatch.start,
        dateEnd: labelMatch.end + dateMatch.end,
        fallback: note.title,
      );
      final identity = '${note.path}|${date.toIso8601String()}|$summary';
      if (!seen.add(identity)) {
        continue;
      }
      deadlines.add(
        ProjectDeadline(
          dueDate: date,
          title: note.title,
          summary: summary,
          notePath: note.path,
          noteKind: note.kind,
          lineNumber: index + 1,
        ),
      );
    }
    return deadlines;
  }

  DateTime? _tryDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  String _summaryFromLine(
    String line, {
    required int labelStart,
    required int dateEnd,
    required String fallback,
  }) {
    final before = line.substring(0, labelStart);
    final after = line.substring(dateEnd);
    final combined = '$before $after'
        .replaceFirst(RegExp(r'^\s*(?:[-*+]\s*)?\[[ xX]\]\s*'), '')
        .replaceFirst(RegExp(r'^\s*(?:[-*+]\s*|#{1,6}\s*)'), '')
        .replaceAll(RegExp(r'^[\s:：,，;；|—-]+|[\s:：,，;；|—-]+$'), '')
        .trim();
    return combined.isEmpty ? fallback : combined;
  }
}
