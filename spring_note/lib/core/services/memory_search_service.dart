import 'dart:convert';
import 'dart:io';

import '../../src/rust/api/note_index_api.dart' as rust_note_index;
import '../../src/rust/note_index.dart';
import '../models/local_data_state.dart';
import '../models/memory_message.dart';

typedef MemoryIndexedNoteSearch =
    Future<NoteSearchResult> Function({
      required String dailyDirectoryPath,
      required String weeklyDirectoryPath,
      required String monthlyDirectoryPath,
      required List<String> queries,
      required int maxResults,
    });

typedef MemoryIndexedNoteKindSearch =
    Future<NoteSearchResult> Function({
      required String directoryPath,
      required String kind,
      required List<String> queries,
      required int maxResults,
    });

class MemorySearchService {
  const MemorySearchService({
    this.indexedNoteSearch = rust_note_index.searchAllIndexedNotes,
    this.indexedNoteKindSearch = rust_note_index.searchIndexedNotesByKind,
  });

  final MemoryIndexedNoteSearch indexedNoteSearch;
  final MemoryIndexedNoteKindSearch indexedNoteKindSearch;

  /// 编排类工具（顺序链 / 批量）单次允许携带的最大子调用数；与
  /// ai_tools.rs 中 Schema 的 maxItems 一致，执行层再拦一次防模型违规。
  static const _maxOrchestrationCalls = 8;

  static const _orchestrationToolNames = {
    'run_tool_sequence',
    'run_tool_batch',
  };

  Future<MemoryToolExecution> executeTool({
    required LocalDataState localDataState,
    required String toolName,
    required Map<String, Object?> arguments,
    required int limit,
  }) async {
    // 编排类工具自带完整执行流程（含子调用错误处理），不走下方单工具路径。
    if (toolName == 'run_tool_sequence') {
      return _executeToolSequence(localDataState, arguments, limit);
    }
    if (toolName == 'run_tool_batch') {
      return _executeToolBatch(localDataState, arguments, limit);
    }

    List<MemorySource> sources;
    try {
      sources = switch (toolName) {
        'get_current_date' => <MemorySource>[],
        'resolve_iso_week' => <MemorySource>[],
        'keyword_search' => await search(
          localDataState: localDataState,
          keywords: _readStringList(arguments['keywords']),
          limit: _keywordSearchResultLimit(localDataState),
        ),
        'search_daily_notes' => await searchKind(
          localDataState: localDataState,
          kind: 'daily',
          keywords: _readStringList(arguments['keywords']),
          limit: _keywordSearchResultLimit(localDataState),
        ),
        'search_weekly_notes' => await searchKind(
          localDataState: localDataState,
          kind: 'weekly',
          keywords: _readStringList(arguments['keywords']),
          limit: _keywordSearchResultLimit(localDataState),
        ),
        'search_monthly_notes' => await searchKind(
          localDataState: localDataState,
          kind: 'monthly',
          keywords: _readStringList(arguments['keywords']),
          limit: _keywordSearchResultLimit(localDataState),
        ),
        'read_daily_note' => await _executeReadDaily(
          localDataState,
          arguments['date']?.toString() ?? '',
        ),
        'read_week_daily_notes' => await _executeReadWeek(
          localDataState,
          arguments['startDate']?.toString() ?? '',
          arguments['endDate']?.toString() ?? '',
        ),
        'read_weekly_note' => await _executeReadWeeklyNote(
          localDataState,
          arguments['week']?.toString() ?? '',
        ),
        'read_month_weekly_notes' => await _executeReadMonthWeeklyNotes(
          localDataState,
          arguments['month']?.toString() ?? '',
        ),
        'read_month_report' => await _executeReadMonth(
          localDataState,
          arguments['month']?.toString() ?? '',
        ),
        _ => <MemorySource>[],
      };
    } catch (_) {
      return MemoryToolExecution(
        toolName: toolName,
        arguments: arguments,
        content: jsonEncode({
          'results': const <Object>[],
          'error': 'local_tool_execution_failed',
        }),
        sources: const [],
      );
    }

    final content = switch (toolName) {
      'get_current_date' => _currentDateToolContent(),
      'resolve_iso_week' => _isoWeekRangeToolContent(
        arguments['week']?.toString() ?? '',
      ),
      _ => _sourcesToJson(sources),
    };
    return MemoryToolExecution(
      toolName: toolName,
      arguments: arguments,
      content: content,
      sources: sources,
    );
  }

  Future<MemoryRecallResult> recall({
    required LocalDataState localDataState,
    required String question,
    required int limit,
  }) async {
    final maxSteps = limit.clamp(1, 120);
    final steps = <MemoryReActStep>[];
    final sources = <MemorySource>[];

    for (final tool in await _runDateTools(localDataState, question)) {
      final step = _step(
        thought: '问题包含明确的日期、周或月份线索，先读取对应 Markdown，避免只依赖模糊关键词。',
        tool: tool,
      );
      steps.add(step);
      sources.addAll(tool.sources);
      if (steps.length >= maxSteps) {
        return MemoryRecallResult(sources: _dedupe(sources), steps: steps);
      }
    }

    final keywordSources = await search(
      localDataState: localDataState,
      keywords: _keywordArguments(question),
      limit: _keywordSearchResultLimit(localDataState),
    );
    final keywordTool = MemoryToolCall(
      name: 'keyword_search',
      label: '关键词搜索',
      arguments: {'keywords': _keywordArguments(question)},
      sources: keywordSources,
    );
    steps.add(
      _step(thought: '需要从全部日报、周报、月报中定位相关线索，因此执行关键词搜索。', tool: keywordTool),
    );
    sources.addAll(keywordSources);

    final shouldResolveDaily =
        steps.length < maxSteps &&
        _asksWhen(question) &&
        keywordSources.isNotEmpty;
    if (shouldResolveDaily) {
      final date = _dateFromSource(keywordSources.first);
      if (date != null) {
        final source = await _readDaily(localDataState, date);
        final tool = MemoryToolCall(
          name: 'read_daily_note',
          label: '查看命中日期的完整日报',
          arguments: {'date': _formatDate(date)},
          sources: source == null ? [] : [source],
        );
        steps.add(
          _step(thought: '关键词搜索已经命中具体日期，继续读取该日完整日报，以确认事件发生时间和上下文。', tool: tool),
        );
        sources.addAll(tool.sources);
      }
    }

    return MemoryRecallResult(
      sources: _dedupe(sources).take(maxSteps).toList(),
      steps: steps.take(maxSteps).toList(),
    );
  }

  Future<List<MemorySource>> search({
    required LocalDataState localDataState,
    required List<String> keywords,
    required int limit,
  }) async {
    final terms = _normalizedSearchTerms(keywords);
    if (terms.isEmpty) {
      return const [];
    }

    final indexed = await indexedNoteSearch(
      dailyDirectoryPath: localDataState.dailyNotesDirectory,
      weeklyDirectoryPath: localDataState.weeklyNotesDirectory,
      monthlyDirectoryPath: localDataState.monthlyNotesDirectory,
      queries: terms,
      maxResults: 200,
    );
    if (!indexed.ok) {
      throw StateError(
        indexed.errorMessage.isEmpty
            ? 'Indexed note search failed.'
            : indexed.errorMessage,
      );
    }
    return _rankFiles(
      indexed.notes.map((note) => File(note.path)),
      terms,
      localDataState,
      limit,
    );
  }

  Future<List<MemorySource>> searchKind({
    required LocalDataState localDataState,
    required String kind,
    required List<String> keywords,
    required int limit,
  }) async {
    final terms = _normalizedSearchTerms(keywords);
    if (terms.isEmpty) {
      return const [];
    }
    final directoryPath = switch (kind) {
      'daily' => localDataState.dailyNotesDirectory,
      'weekly' => localDataState.weeklyNotesDirectory,
      'monthly' => localDataState.monthlyNotesDirectory,
      _ => throw ArgumentError.value(kind, 'kind', 'Unknown note kind'),
    };
    final indexed = await indexedNoteKindSearch(
      directoryPath: directoryPath,
      kind: kind,
      queries: terms,
      maxResults: 200,
    );
    if (!indexed.ok) {
      throw StateError(
        indexed.errorMessage.isEmpty
            ? 'Indexed note search failed.'
            : indexed.errorMessage,
      );
    }
    return _rankFiles(
      indexed.notes.map((note) => File(note.path)),
      terms,
      localDataState,
      limit,
    );
  }

  List<String> _normalizedSearchTerms(List<String> keywords) {
    return keywords
        .map((keyword) => keyword.trim().toLowerCase())
        .where((keyword) => keyword.runes.length >= 2)
        .toSet()
        .toList();
  }

  Future<List<MemorySource>> _rankFiles(
    Iterable<File> files,
    List<String> terms,
    LocalDataState localDataState,
    int limit,
  ) async {
    final scored = <MemorySource>[];

    for (final file in files) {
      String content;
      try {
        content = await file.readAsString();
      } on FileSystemException {
        continue;
      }
      final score = _score(content, terms);
      if (score <= 0) {
        continue;
      }
      final snippet = _snippet(content, terms, localDataState);
      scored.add(
        MemorySource(
          title: _title(file),
          path: file.path,
          snippet: snippet.text,
          score: score,
          truncated: snippet.truncated,
          totalCharacters: snippet.totalCharacters,
        ),
      );
    }

    scored.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return right.path.compareTo(left.path);
    });
    return scored.take(limit.clamp(1, 200)).toList();
  }

  Future<List<MemorySource>> _executeReadDaily(
    LocalDataState state,
    String rawDate,
  ) async {
    final date = DateTime.tryParse(rawDate);
    if (date == null) {
      return [];
    }
    final source = await _readDaily(state, date);
    return source == null ? [] : [source];
  }

  Future<List<MemorySource>> _executeReadWeek(
    LocalDataState state,
    String rawStart,
    String rawEnd,
  ) async {
    final start = DateTime.tryParse(rawStart);
    final end = DateTime.tryParse(rawEnd);
    if (start == null || end == null || end.isBefore(start)) {
      return [];
    }
    final sources = <MemorySource>[];
    final weekLimit = _weekDailyNoteLimit(state);
    for (
      var date = DateTime(start.year, start.month, start.day);
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      final source = await _readDaily(state, date);
      if (source != null) {
        sources.add(source);
      }
      if (sources.length >= weekLimit) {
        break;
      }
    }
    return sources;
  }

  Future<List<MemorySource>> _executeReadWeeklyNote(
    LocalDataState state,
    String rawWeek,
  ) async {
    final week = rawWeek.trim().toUpperCase();
    if (!RegExp(r'^20\d{2}-W(?:0[1-9]|[1-4]\d|5[0-3])$').hasMatch(week)) {
      return [];
    }
    final source = await _readOptionalFile(
      state,
      _join(state.weeklyNotesDirectory, '$week.md'),
      title: '周报 $week',
      score: 120,
    );
    return source == null ? [] : [source];
  }

  Future<List<MemorySource>> _executeReadMonthWeeklyNotes(
    LocalDataState state,
    String rawMonth,
  ) async {
    final month = _parseMonth(rawMonth);
    if (month == null) {
      return [];
    }

    final nextMonth = DateTime(month.year, month.month + 1);
    final weeks = <String>{};
    for (
      var date = month;
      date.isBefore(nextMonth);
      date = date.add(const Duration(days: 1))
    ) {
      weeks.add(_formatIsoWeek(date));
    }

    final sources = await Future.wait(
      weeks.map(
        (week) => _readOptionalFile(
          state,
          _join(state.weeklyNotesDirectory, '$week.md'),
          title: '周报 $week',
          score: 120,
        ),
      ),
    );
    return sources.whereType<MemorySource>().toList();
  }

  Future<List<MemorySource>> _executeReadMonth(
    LocalDataState state,
    String rawMonth,
  ) async {
    final month = _parseMonth(rawMonth);
    if (month == null) {
      return [];
    }
    return _readMonth(state, month);
  }

  DateTime? _parseMonth(String rawMonth) {
    final match = RegExp(r'^(20\d{2})-(\d{2})$').firstMatch(rawMonth.trim());
    if (match == null) {
      return null;
    }
    return _safeDate(int.parse(match.group(1)!), int.parse(match.group(2)!), 1);
  }

  List<String> _readStringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final single = value?.toString().trim() ?? '';
    return single.isEmpty ? [] : [single];
  }

  String _sourcesToJson(List<MemorySource> sources) {
    return jsonEncode({
      'results': sources.map((source) => source.toJson()).toList(),
    });
  }

  String _currentDateToolContent() {
    final now = DateTime.now();
    final isoWeek = _formatIsoWeek(now);
    return jsonEncode({
      'date': _formatDate(now),
      'isoWeek': isoWeek,
      'weekNumber': int.parse(isoWeek.substring(6)),
    });
  }

  String _isoWeekRangeToolContent(String rawWeek) {
    final week = rawWeek.trim().toUpperCase();
    final match = RegExp(
      r'^(20\d{2})-W(0[1-9]|[1-4]\d|5[0-3])$',
    ).firstMatch(week);
    if (match == null) {
      return jsonEncode({'week': week, 'error': 'invalid_iso_week'});
    }
    final start = _dateFromIsoWeek(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
    // 回校验：如 2027-W53 这类该 ISO 年不存在的周，换算结果会落进相邻 ISO 年。
    if (_formatIsoWeek(start) != week) {
      return jsonEncode({'week': week, 'error': 'iso_week_not_exists'});
    }
    return jsonEncode({
      'week': week,
      'startDate': _formatDate(start),
      'endDate': _formatDate(start.add(const Duration(days: 6))),
    });
  }

  /// 顺序执行一组有依赖关系的工具调用。后续步骤的字符串参数可用
  /// `$steps[N].字段`（数组元素 `$steps[N].字段[0]`）引用第 N 步结果；
  /// 某一步失败即中止，返回已完成步骤的结果与失败原因。
  Future<MemoryToolExecution> _executeToolSequence(
    LocalDataState localDataState,
    Map<String, Object?> arguments,
    int limit,
  ) async {
    final steps = _readOrchestrationCalls(arguments['steps']);
    if (steps == null) {
      return _orchestrationError(
        'run_tool_sequence',
        arguments,
        'invalid_steps',
      );
    }

    final stepResults = <Object?>[];
    final outputSteps = <Map<String, Object?>>[];
    final sources = <MemorySource>[];
    String? stopError;

    for (final step in steps) {
      final entry = <String, Object?>{'tool': step.tool};
      outputSteps.add(entry);
      if (_orchestrationToolNames.contains(step.tool)) {
        stopError = entry['error'] = 'nested_orchestration_not_supported';
        break;
      }
      Map<String, Object?> resolvedArguments;
      try {
        resolvedArguments = _resolvePlaceholderMap(step.arguments, stepResults);
      } on FormatException catch (error) {
        entry['arguments'] = step.arguments;
        stopError = entry['error'] = error.message;
        break;
      }
      entry['arguments'] = resolvedArguments;

      final execution = await executeTool(
        localDataState: localDataState,
        toolName: step.tool,
        arguments: resolvedArguments,
        limit: limit,
      );
      sources.addAll(execution.sources);
      final parsed = _tryParseJson(execution.content);
      final stepError = _toolContentError(parsed);
      if (stepError != null) {
        stopError = entry['error'] = stepError;
        break;
      }
      entry['result'] = parsed ?? execution.content;
      stepResults.add(parsed ?? execution.content);
    }

    return MemoryToolExecution(
      toolName: 'run_tool_sequence',
      arguments: arguments,
      content: jsonEncode({
        'steps': outputSteps,
        if (stopError != null) 'stoppedEarly': true,
      }),
      sources: _dedupe(sources),
    );
  }

  /// 并发执行一组相互独立的工具调用；每个条目各自返回结果或错误，
  /// 条目之间没有数据流动，失败互不影响。
  Future<MemoryToolExecution> _executeToolBatch(
    LocalDataState localDataState,
    Map<String, Object?> arguments,
    int limit,
  ) async {
    final calls = _readOrchestrationCalls(arguments['calls']);
    if (calls == null) {
      return _orchestrationError('run_tool_batch', arguments, 'invalid_calls');
    }

    final executions = await Future.wait(
      calls.map((call) async {
        if (_orchestrationToolNames.contains(call.tool)) {
          return (
            entry: <String, Object?>{
              'tool': call.tool,
              'error': 'nested_orchestration_not_supported',
            },
            sources: const <MemorySource>[],
          );
        }
        final execution = await executeTool(
          localDataState: localDataState,
          toolName: call.tool,
          arguments: call.arguments,
          limit: limit,
        );
        final parsed = _tryParseJson(execution.content);
        final stepError = _toolContentError(parsed);
        return (
          entry: <String, Object?>{
            'tool': call.tool,
            'arguments': call.arguments,
            if (stepError != null)
              'error': stepError
            else
              'result': parsed ?? execution.content,
          },
          sources: execution.sources,
        );
      }),
    );

    return MemoryToolExecution(
      toolName: 'run_tool_batch',
      arguments: arguments,
      content: jsonEncode({
        'results': executions.map((item) => item.entry).toList(),
      }),
      sources: _dedupe([for (final item in executions) ...item.sources]),
    );
  }

  /// 读取编排参数中的调用列表；结构非法（非数组、空、超限、条目缺工具名）
  /// 时返回 null，由调用方转为 invalid_* 错误。
  List<({String tool, Map<String, Object?> arguments})>?
  _readOrchestrationCalls(Object? value) {
    if (value is! List ||
        value.isEmpty ||
        value.length > _maxOrchestrationCalls) {
      return null;
    }
    final calls = <({String tool, Map<String, Object?> arguments})>[];
    for (final item in value) {
      if (item is! Map) {
        return null;
      }
      final tool = item['tool']?.toString().trim() ?? '';
      if (tool.isEmpty) {
        return null;
      }
      final rawArguments = item['arguments'];
      calls.add((
        tool: tool,
        arguments: rawArguments is Map
            ? rawArguments.map((key, value) => MapEntry(key.toString(), value))
            : const <String, Object?>{},
      ));
    }
    return calls;
  }

  MemoryToolExecution _orchestrationError(
    String toolName,
    Map<String, Object?> arguments,
    String error,
  ) {
    return MemoryToolExecution(
      toolName: toolName,
      arguments: arguments,
      content: jsonEncode({'error': error}),
      sources: const [],
    );
  }

  Object? _tryParseJson(String content) {
    try {
      return jsonDecode(content);
    } on FormatException {
      return null;
    }
  }

  /// 子工具约定以 content 中的 error 字段表达失败（如 iso_week_not_exists）；
  /// 返回错误码，无错误时返回 null。
  String? _toolContentError(Object? parsedContent) {
    if (parsedContent is Map && parsedContent.containsKey('error')) {
      return parsedContent['error']?.toString() ?? 'unknown_error';
    }
    return null;
  }

  /// `$steps[N].字段` 占位符：N 为已完成步骤的序号（从 0 起），
  /// 字段路径支持 `.field` 与 `[index]` 段。
  static final _stepPlaceholderPattern = RegExp(
    r'\$steps\[(\d+)\]((?:\.[A-Za-z_]\w*|\[\d+\])*)',
  );
  static final _stepPlaceholderSegmentPattern = RegExp(
    r'\.([A-Za-z_]\w*)|\[(\d+)\]',
  );

  Map<String, Object?> _resolvePlaceholderMap(
    Map<String, Object?> arguments,
    List<Object?> stepResults,
  ) {
    final resolved = _resolvePlaceholders(arguments, stepResults);
    return resolved is Map<String, Object?>
        ? resolved
        : const <String, Object?>{};
  }

  /// 递归替换参数中的占位符：整个字符串恰为单个占位符时保留被引用值的
  /// 原始 JSON 类型（数字、布尔、数组等），嵌在文本中时替换为字符串。
  Object? _resolvePlaceholders(Object? value, List<Object?> stepResults) {
    if (value is String) {
      final matches = _stepPlaceholderPattern.allMatches(value).toList();
      if (matches.isEmpty) {
        return value;
      }
      if (matches.length == 1 && matches.single.group(0) == value) {
        return _lookupStepPlaceholder(matches.single, stepResults);
      }
      return value.replaceAllMapped(_stepPlaceholderPattern, (match) {
        final resolved = _lookupStepPlaceholder(match, stepResults);
        return resolved is String ? resolved : jsonEncode(resolved);
      });
    }
    if (value is List) {
      return value
          .map((item) => _resolvePlaceholders(item, stepResults))
          .toList();
    }
    if (value is Map) {
      return value.map(
        (key, item) =>
            MapEntry(key.toString(), _resolvePlaceholders(item, stepResults)),
      );
    }
    return value;
  }

  Object? _lookupStepPlaceholder(Match match, List<Object?> stepResults) {
    final placeholder = match.group(0) ?? '';
    final stepIndex = int.parse(match.group(1)!);
    if (stepIndex >= stepResults.length) {
      throw FormatException('unknown_step_reference: $placeholder');
    }
    var current = stepResults[stepIndex];
    for (final segment in _stepPlaceholderSegmentPattern.allMatches(
      match.group(2)!,
    )) {
      final field = segment.group(1);
      if (field != null) {
        if (current is! Map || !current.containsKey(field)) {
          throw FormatException('placeholder_path_not_found: $placeholder');
        }
        current = current[field];
      } else {
        final index = int.parse(segment.group(2)!);
        if (current is! List || index >= current.length) {
          throw FormatException('placeholder_path_not_found: $placeholder');
        }
        current = current[index];
      }
    }
    return current;
  }

  String buildContextMarkdown(List<MemorySource> sources) {
    if (sources.isEmpty) {
      return '未检索到相关历史 Markdown。';
    }
    return sources
        .map(
          (source) =>
              '## ${source.title}\n路径：${source.path}\n相关片段：\n${source.snippet}',
        )
        .join('\n\n---\n\n');
  }

  String buildReActTrace(List<MemoryReActStep> steps) {
    if (steps.isEmpty) {
      return '未执行工具。';
    }
    return steps
        .map(
          (step) =>
              'Thought: ${step.thought}\nAct: ${step.tool.name}(${step.tool.argumentText})\nObservation: ${step.observation}',
        )
        .join('\n\n');
  }

  MemoryReActStep _step({
    required String thought,
    required MemoryToolCall tool,
  }) {
    return MemoryReActStep(
      thought: thought,
      tool: tool,
      observation: _observation(tool),
    );
  }

  String _observation(MemoryToolCall tool) {
    if (tool.sources.isEmpty) {
      return '${tool.label} 未找到相关记录。';
    }
    final titles = tool.sources.take(4).map((source) => source.title).join('、');
    return '${tool.label} 找到 ${tool.sources.length} 条记录：$titles。';
  }

  Future<List<MemoryToolCall>> _runDateTools(
    LocalDataState state,
    String question,
  ) async {
    final tools = <MemoryToolCall>[];
    final dailyDate = _extractDailyDate(question);
    if (dailyDate != null || _mentionsDaily(question)) {
      final date = dailyDate ?? DateTime.now();
      final source = await _readDaily(state, date);
      tools.add(
        MemoryToolCall(
          name: 'read_daily_note',
          label: '查看某天的日报',
          arguments: {'date': _formatDate(date)},
          sources: source == null ? [] : [source],
        ),
      );
    }

    final weekStart = _extractWeekStart(question);
    if (weekStart != null || _mentionsWeek(question)) {
      final start = weekStart ?? _startOfWeek(DateTime.now());
      tools.add(
        MemoryToolCall(
          name: 'read_week_daily_notes',
          label: '查看某周日报',
          arguments: {
            'startDate': _formatDate(start),
            'endDate': _formatDate(start.add(const Duration(days: 6))),
          },
          sources: await _readWeek(state, start),
        ),
      );
    }

    final month = _extractMonth(question);
    if (month != null || _mentionsMonth(question)) {
      final target =
          month ?? DateTime(DateTime.now().year, DateTime.now().month);
      tools.add(
        MemoryToolCall(
          name: 'read_month_report',
          label: '查看某月月报',
          arguments: {'month': _formatMonth(target)},
          sources: await _readMonth(state, target),
        ),
      );
    }

    return tools;
  }

  Future<MemorySource?> _readDaily(LocalDataState state, DateTime date) async {
    final file = File(
      _join(state.dailyNotesDirectory, '${_formatDate(date)}.md'),
    );
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    final snippet = _snippet(content, const [], state);
    return MemorySource(
      title: '日报 ${_formatDate(date)}',
      path: file.path,
      snippet: snippet.text,
      score: 100,
      truncated: snippet.truncated,
      totalCharacters: snippet.totalCharacters,
    );
  }

  Future<List<MemorySource>> _readWeek(
    LocalDataState state,
    DateTime start,
  ) async {
    final sources = <MemorySource>[];
    for (var index = 0; index < 7; index++) {
      final source = await _readDaily(state, start.add(Duration(days: index)));
      if (source != null) {
        sources.add(source);
      }
    }
    final weekReport = await _readOptionalFile(
      state,
      _join(state.weeklyNotesDirectory, '${_formatIsoWeek(start)}.md'),
      title: '周报 ${_formatIsoWeek(start)}',
      score: 120,
    );
    if (weekReport != null) {
      sources.insert(0, weekReport);
    }
    return sources;
  }

  Future<List<MemorySource>> _readMonth(
    LocalDataState state,
    DateTime month,
  ) async {
    final monthReport = await _readOptionalFile(
      state,
      _join(state.monthlyNotesDirectory, '${_formatMonth(month)}.md'),
      title: '月报 ${_formatMonth(month)}',
      score: 140,
    );
    return monthReport == null ? [] : [monthReport];
  }

  Future<MemorySource?> _readOptionalFile(
    LocalDataState state,
    String path, {
    required String title,
    required int score,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final content = await file.readAsString();
    final snippet = _snippet(content, const [], state);
    return MemorySource(
      title: title,
      path: file.path,
      snippet: snippet.text,
      score: score,
      truncated: snippet.truncated,
      totalCharacters: snippet.totalCharacters,
    );
  }

  List<MemorySource> _dedupe(List<MemorySource> sources) {
    final seen = <String>{};
    final result = <MemorySource>[];
    for (final source in sources) {
      if (seen.add(source.path)) {
        result.add(source);
      }
    }
    return result;
  }

  List<String> _terms(String question) {
    return question
        .toLowerCase()
        .split(
          RegExp(
            r'[\s,，。！？?!.、;；:：()\[\]{}<>《》"'
            '“”‘’]+',
          ),
        )
        .map((term) => term.trim())
        .where((term) => term.runes.length >= 2)
        .take(8)
        .toList();
  }

  List<String> _keywordArguments(String question) {
    final terms = _terms(question);
    if (terms.isEmpty) {
      final fallback = question.trim();
      return fallback.isEmpty ? [] : [fallback];
    }
    const stopWords = {'什么时候', '哪天', '日期', '查看', '一下', '的'};
    final filtered = terms
        .map((term) => _cleanKeyword(term, stopWords))
        .where((term) => term.runes.length >= 2)
        .where((term) => !RegExp(r'^20\d{2}').hasMatch(term))
        .toList();
    final selected = filtered.isEmpty ? terms : filtered;
    return selected.where((term) => term.runes.length >= 2).take(6).toList();
  }

  String _cleanKeyword(String term, Set<String> stopWords) {
    var result = term;
    for (final stopWord in stopWords) {
      result = result.replaceAll(stopWord, '');
    }
    return result.trim();
  }

  int _score(String content, List<String> terms) {
    final lower = content.toLowerCase();
    if (terms.isEmpty) {
      return lower.trim().isEmpty ? 0 : 1;
    }
    var score = 0;
    for (final term in terms) {
      score += RegExp(RegExp.escape(term)).allMatches(lower).length;
    }
    return score;
  }

  int _singleResultMaxCharacters(LocalDataState state) {
    return state.config.memoryResultMaxCharacters.round().clamp(1, 100000);
  }

  int _weekDailyNoteLimit(LocalDataState state) {
    return state.config.memoryWeekDailyNoteLimit.round().clamp(1, 31);
  }

  int _keywordSearchResultLimit(LocalDataState state) {
    return state.config.memoryKeywordSearchResultLimit.round().clamp(1, 200);
  }

  int _keywordContextBefore(LocalDataState state) {
    return state.config.memoryKeywordContextBefore.round().clamp(0, 100000);
  }

  int _keywordContextAfter(LocalDataState state) {
    return state.config.memoryKeywordContextAfter.round().clamp(0, 100000);
  }

  ({String text, bool truncated, int totalCharacters}) _snippet(
    String content,
    List<String> terms,
    LocalDataState state,
  ) {
    final normalized = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    if (normalized.isEmpty) {
      return (text: '（空文档）', truncated: false, totalCharacters: 0);
    }
    final maxCharacters = _singleResultMaxCharacters(state);
    final lower = normalized.toLowerCase();
    var index = -1;
    for (final term in terms) {
      index = lower.indexOf(term);
      if (index >= 0) {
        break;
      }
    }
    if (index < 0) {
      final clipped = normalized.length > maxCharacters;
      return (
        text: clipped
            ? '${normalized.substring(0, maxCharacters)}...'
            : normalized,
        truncated: clipped,
        totalCharacters: normalized.length,
      );
    }
    final contextBefore = _keywordContextBefore(state);
    final contextAfter = _keywordContextAfter(state);
    final start = (index - contextBefore).clamp(0, normalized.length);
    final end = (index + contextAfter).clamp(0, normalized.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < normalized.length ? '...' : '';
    final excerpt = normalized.substring(start, end);
    final clipped = excerpt.length > maxCharacters
        ? excerpt.substring(0, maxCharacters)
        : excerpt;
    final clippedSuffix = suffix.isNotEmpty || excerpt.length > maxCharacters
        ? '...'
        : '';
    return (
      text: '$prefix$clipped$clippedSuffix',
      truncated:
          start > 0 ||
          end < normalized.length ||
          clipped.length < excerpt.length,
      totalCharacters: normalized.length,
    );
  }

  String _title(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    return name.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
  }

  DateTime? _dateFromSource(MemorySource source) {
    final match = RegExp(r'(20\d{2})-(\d{2})-(\d{2})').firstMatch(source.title);
    if (match == null) {
      return null;
    }
    return _safeDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  DateTime? _extractDailyDate(String question) {
    final normalized = question.trim();
    final today = DateTime.now();
    if (normalized.contains('今天')) {
      return DateTime(today.year, today.month, today.day);
    }
    if (normalized.contains('昨天')) {
      final date = today.subtract(const Duration(days: 1));
      return DateTime(date.year, date.month, date.day);
    }
    if (normalized.contains('前天')) {
      final date = today.subtract(const Duration(days: 2));
      return DateTime(date.year, date.month, date.day);
    }

    final full = RegExp(
      r'(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})',
    ).firstMatch(normalized);
    if (full != null) {
      return _safeDate(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      );
    }
    final short = RegExp(
      r'(?<!\d)(\d{1,2})月(\d{1,2})[日号]?',
    ).firstMatch(normalized);
    if (short != null) {
      return _safeDate(
        today.year,
        int.parse(short.group(1)!),
        int.parse(short.group(2)!),
      );
    }
    return null;
  }

  DateTime? _extractWeekStart(String question) {
    final today = DateTime.now();
    if (question.contains('本周') || question.contains('这周')) {
      return _startOfWeek(today);
    }
    if (question.contains('上周')) {
      return _startOfWeek(today).subtract(const Duration(days: 7));
    }
    final iso = RegExp(
      r'(20\d{2})[-\s]?W(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(question);
    if (iso != null) {
      return _dateFromIsoWeek(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
      );
    }
    final zh = RegExp(r'(20\d{2})?年?第\s*(\d{1,2})\s*周').firstMatch(question);
    if (zh != null) {
      return _dateFromIsoWeek(
        zh.group(1) == null ? today.year : int.parse(zh.group(1)!),
        int.parse(zh.group(2)!),
      );
    }
    return null;
  }

  DateTime? _extractMonth(String question) {
    final today = DateTime.now();
    if (question.contains('本月') || question.contains('这个月')) {
      return DateTime(today.year, today.month);
    }
    if (question.contains('上月') || question.contains('上个月')) {
      return DateTime(today.year, today.month - 1);
    }
    final full = RegExp(r'(20\d{2})[-/.年](\d{1,2})月?').firstMatch(question);
    if (full != null) {
      return _safeDate(int.parse(full.group(1)!), int.parse(full.group(2)!), 1);
    }
    final short = RegExp(r'(?<!\d)(\d{1,2})月').firstMatch(question);
    if (short != null) {
      return _safeDate(today.year, int.parse(short.group(1)!), 1);
    }
    return null;
  }

  bool _mentionsDaily(String question) {
    return question.contains('日报') &&
        !question.contains('周') &&
        !question.contains('月');
  }

  bool _mentionsWeek(String question) {
    return question.contains('周报') ||
        question.contains('本周') ||
        question.contains('上周');
  }

  bool _mentionsMonth(String question) {
    return question.contains('月报') ||
        question.contains('本月') ||
        question.contains('上月');
  }

  bool _asksWhen(String question) {
    return question.contains('什么时候') ||
        question.contains('哪天') ||
        question.contains('日期') ||
        question.toLowerCase().contains('when');
  }

  DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  DateTime _dateFromIsoWeek(int year, int week) {
    final jan4 = DateTime(year, 1, 4);
    final week1 = _startOfWeek(jan4);
    return week1.add(Duration(days: (week - 1) * 7));
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatMonth(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
  }

  String _formatIsoWeek(DateTime date) {
    final start = _startOfWeek(date);
    final isoYear = start.add(const Duration(days: 3)).year;
    final first = _startOfWeek(DateTime(isoYear, 1, 4));
    final week = (start.difference(first).inDays ~/ 7) + 1;
    return '${isoYear.toString().padLeft(4, '0')}-W${week.toString().padLeft(2, '0')}';
  }

  String _join(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }
}

class MemoryRecallResult {
  const MemoryRecallResult({required this.sources, required this.steps});

  final List<MemorySource> sources;
  final List<MemoryReActStep> steps;

  List<MemoryToolCall> get tools => steps.map((step) => step.tool).toList();
}

class MemoryReActStep {
  const MemoryReActStep({
    required this.thought,
    required this.tool,
    required this.observation,
  });

  final String thought;
  final MemoryToolCall tool;
  final String observation;

  MemoryMessage toMessage() {
    return MemoryMessage(
      role: 'local_tool',
      content:
          'Thought：$thought\nAct：${tool.name}(${tool.argumentText})\nObservation：$observation',
      createdAt: DateTime.now(),
      toolName: tool.name,
      sources: tool.sources,
    );
  }
}

class MemoryToolCall {
  const MemoryToolCall({
    required this.name,
    required this.label,
    required this.arguments,
    required this.sources,
  });

  final String name;
  final String label;
  final Map<String, Object> arguments;
  final List<MemorySource> sources;

  String get query => argumentText;

  String get argumentText {
    return arguments.entries
        .map((entry) {
          final value = entry.value;
          if (value is List) {
            return '${entry.key}=[${value.join(', ')}]';
          }
          return '${entry.key}=$value';
        })
        .join(', ');
  }
}

class MemoryToolExecution {
  const MemoryToolExecution({
    required this.toolName,
    required this.arguments,
    required this.content,
    required this.sources,
  });

  final String toolName;
  final Map<String, Object?> arguments;
  final String content;
  final List<MemorySource> sources;
}
