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
  static final RegExp _fullDatePattern = RegExp(
    r'(\d{4})\s*(?:[-/.年])\s*(\d{1,2})\s*(?:[-/.月])\s*(\d{1,2})\s*日?',
  );
  static final RegExp _monthDayPattern = RegExp(
    r'(\d{1,2})\s*(?:[-/.月])\s*(\d{1,2})\s*日?',
  );
  static final RegExp _taskCheckbox = RegExp(
    r'^(\s*(?:[-*+]\s*)?\[)([ xX])(\])',
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
    DateTime? referenceDate,
  }) {
    final deadlines = <ProjectDeadline>[];
    final seen = <String>{};
    final lines = content.split(RegExp(r'\r?\n'));
    final reference = _dateOnly(referenceDate ?? referenceDateForNote(note));
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final labelMatch = _deadlineLabel.firstMatch(line);
      if (labelMatch == null) {
        continue;
      }
      final parsedDate = _findDate(
        line.substring(labelMatch.end),
        reference: reference,
      );
      if (parsedDate == null) {
        continue;
      }
      final summary = _summaryFromLine(
        line,
        labelStart: labelMatch.start,
        dateEnd: labelMatch.end + parsedDate.end,
        fallback: note.title,
      );
      final identity =
          '${note.path}|${parsedDate.date.toIso8601String()}|$summary';
      if (!seen.add(identity)) {
        continue;
      }
      deadlines.add(
        ProjectDeadline(
          dueDate: parsedDate.date,
          title: note.title,
          summary: summary,
          notePath: note.path,
          noteKind: note.kind,
          lineNumber: index + 1,
          isCompleted:
              _taskCheckbox.firstMatch(line)?.group(2)?.toLowerCase() == 'x',
          sourceLine: line,
        ),
      );
    }
    return deadlines;
  }

  List<ProjectDateCandidate> findImplicitDates({
    required String content,
    DateTime? referenceDate,
  }) {
    final candidates = <ProjectDateCandidate>[];
    final seen = <String>{};
    final lines = content.split(RegExp(r'\r?\n'));
    final reference = _dateOnly(referenceDate ?? DateTime.now());
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (_deadlineLabel.hasMatch(line) ||
          line.trimLeft().startsWith('#') ||
          _taskCheckbox.firstMatch(line)?.group(2)?.toLowerCase() == 'x') {
        continue;
      }
      final parsedDate = _findDate(line, reference: reference);
      if (parsedDate == null) {
        continue;
      }
      final key =
          '${parsedDate.date.toIso8601String()}|${index + 1}|${parsedDate.start}';
      if (!seen.add(key)) {
        continue;
      }
      candidates.add(
        ProjectDateCandidate(
          date: parsedDate.date,
          lineNumber: index + 1,
          sourceLine: line,
          start: parsedDate.start,
          end: parsedDate.end,
          matchedText: line.substring(parsedDate.start, parsedDate.end),
        ),
      );
    }
    return candidates;
  }

  /// Returns a stable reference date for dates that omit the year.
  ///
  /// Daily, weekly, and monthly notes use the date encoded in their filename.
  /// This prevents an overdue `8月20日` from being reinterpreted as next year
  /// merely because the calendar was refreshed after August 20.
  DateTime referenceDateForNote(NoteFile note) {
    final stem = note.name.replaceFirst(
      RegExp(r'\.md$', caseSensitive: false),
      '',
    );
    switch (note.kind) {
      case NoteKind.daily:
        final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(stem);
        if (match != null) {
          final date = _tryDate(
            int.parse(match.group(1)!),
            int.parse(match.group(2)!),
            int.parse(match.group(3)!),
          );
          if (date != null) {
            return date;
          }
        }
        break;
      case NoteKind.weekly:
        final match = RegExp(
          r'^(\d{4})-W(\d{1,2})$',
          caseSensitive: false,
        ).firstMatch(stem);
        if (match != null) {
          final date = _dateFromIsoWeek(
            int.parse(match.group(1)!),
            int.parse(match.group(2)!),
          );
          if (date != null) {
            return date;
          }
        }
        break;
      case NoteKind.monthly:
        final match = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(stem);
        if (match != null) {
          final date = _tryDate(
            int.parse(match.group(1)!),
            int.parse(match.group(2)!),
            1,
          );
          if (date != null) {
            return date;
          }
        }
        break;
    }
    return _dateOnly(note.modifiedAt);
  }

  /// Updates the Markdown checkbox for a calendar item.
  ///
  /// Plain deadline lines are converted to a Markdown task so completion is
  /// persisted in the note itself and remains visible to other views.
  Future<void> setCompleted(
    ProjectDeadline deadline, {
    required bool completed,
  }) async {
    final content = await noteService.readMarkdown(deadline.notePath);
    final lines = content.split(RegExp(r'\r?\n'));
    var index = deadline.lineNumber - 1;
    if (index < 0 ||
        index >= lines.length ||
        lines[index] != deadline.sourceLine) {
      index = lines.indexOf(deadline.sourceLine);
    }
    if (index < 0) {
      throw StateError(
        'The note changed before this calendar item was updated.',
      );
    }

    final line = lines[index];
    final checkbox = _taskCheckbox.firstMatch(line);
    if (checkbox != null) {
      lines[index] =
          '${checkbox.group(1)}${completed ? 'x' : ' '}${checkbox.group(3)}'
          '${line.substring(checkbox.end)}';
    } else {
      final bullet = RegExp(r'^(\s*[-*+]\s+)').firstMatch(line);
      if (bullet != null) {
        lines[index] =
            '${bullet.group(1)}[${completed ? 'x' : ' '}] '
            '${line.substring(bullet.end)}';
      } else {
        final indentation = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
        lines[index] =
            '$indentation- [${completed ? 'x' : ' '}] '
            '${line.substring(indentation.length)}';
      }
    }

    final newline = content.contains('\r\n') ? '\r\n' : '\n';
    await noteService.writeMarkdown(deadline.notePath, lines.join(newline));
  }

  _ParsedProjectDate? _findDate(String text, {required DateTime reference}) {
    final fullMatch = _fullDatePattern.firstMatch(text);
    if (fullMatch != null) {
      final date = _tryDate(
        int.parse(fullMatch.group(1)!),
        int.parse(fullMatch.group(2)!),
        int.parse(fullMatch.group(3)!),
      );
      if (date != null) {
        return _ParsedProjectDate(
          date: date,
          start: fullMatch.start,
          end: fullMatch.end,
        );
      }
    }

    for (final match in _monthDayPattern.allMatches(text)) {
      if (_isPartOfLongerNumber(text, match)) {
        continue;
      }
      final month = int.parse(match.group(1)!);
      final day = int.parse(match.group(2)!);
      var date = _tryDate(reference.year, month, day);
      if (date == null) {
        continue;
      }
      if (date.isBefore(reference)) {
        date = _tryDate(reference.year + 1, month, day);
      }
      if (date != null) {
        return _ParsedProjectDate(
          date: date,
          start: match.start,
          end: match.end,
        );
      }
    }
    return null;
  }

  bool _isPartOfLongerNumber(String text, RegExpMatch match) {
    if (match.start > 0 && _isDigit(text.codeUnitAt(match.start - 1))) {
      return true;
    }
    return match.end < text.length && _isDigit(text.codeUnitAt(match.end));
  }

  bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

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

  DateTime? _dateFromIsoWeek(int year, int week) {
    if (week < 1 || week > 53) {
      return null;
    }
    final januaryFourth = DateTime(year, 1, 4);
    final firstWeekMonday = januaryFourth.subtract(
      Duration(days: januaryFourth.weekday - DateTime.monday),
    );
    final monday = firstWeekMonday.add(Duration(days: (week - 1) * 7));
    if (monday.add(const Duration(days: 3)).year != year) {
      return null;
    }
    return monday;
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

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

class _ParsedProjectDate {
  const _ParsedProjectDate({
    required this.date,
    required this.start,
    required this.end,
  });

  final DateTime date;
  final int start;
  final int end;
}
