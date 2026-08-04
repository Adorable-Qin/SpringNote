import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/global_sign_item.dart';
import '../../core/theme/app_theme.dart';

/// 返回 null 表示 AI 不可用、已走本地兜底（弹窗关闭，首页展示提示）；
/// 否则返回刷新后的最新全局签列表，弹窗原地更新。
typedef GlobalSignConfirmCallback = Future<List<GlobalSignItem>?> Function(
  List<GlobalSignItem> editedItems,
  List<GlobalSignItem> doneItems,
  List<GlobalSignItem> deletedItems,
);

class GlobalSignDialog extends StatefulWidget {
  const GlobalSignDialog({
    super.key,
    required this.items,
    required this.onConfirm,
  });

  final List<GlobalSignItem> items;
  final GlobalSignConfirmCallback onConfirm;

  @override
  State<GlobalSignDialog> createState() => _GlobalSignDialogState();
}

class _GlobalSignDialogState extends State<GlobalSignDialog> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _doneIds = {};
  final Set<String> _deletedIds = {};
  late List<GlobalSignItem> _items;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
    _rebuildControllers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  void _rebuildControllers() {
    _disposeControllers();
    for (final item in _items) {
      _controllers[item.id] = TextEditingController(text: item.content);
    }
  }

  bool get _hasChanges {
    if (_doneIds.isNotEmpty || _deletedIds.isNotEmpty) {
      return true;
    }
    for (final item in _items) {
      if ((_controllers[item.id]?.text.trim() ?? '') != item.content) {
        return true;
      }
    }
    return false;
  }

  void _toggleDone(String id) {
    setState(() {
      if (!_doneIds.remove(id)) {
        _doneIds.add(id);
        _deletedIds.remove(id);
      }
    });
  }

  void _toggleDeleted(String id) {
    setState(() {
      if (!_deletedIds.remove(id)) {
        _deletedIds.add(id);
        _doneIds.remove(id);
      }
    });
  }

  Future<void> _confirm() async {
    if (!_hasChanges || _confirming) {
      return;
    }
    setState(() => _confirming = true);
    final editedItems = [
      for (final item in _items)
        item.copyWith(
          content: _controllers[item.id]?.text.trim() ?? item.content,
        ),
    ];
    final doneItems = [
      for (final item in editedItems)
        if (_doneIds.contains(item.id)) item,
    ];
    final deletedItems = [
      for (final item in editedItems)
        if (_deletedIds.contains(item.id)) item,
    ];
    final refreshed = await widget.onConfirm(
      editedItems,
      doneItems,
      deletedItems,
    );
    if (!mounted) {
      return;
    }
    if (refreshed == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _confirming = false;
      _items = List.of(refreshed);
      _doneIds.clear();
      _deletedIds.clear();
      _rebuildControllers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final dialogHeight = math.min(
      520.0,
      MediaQuery.sizeOf(context).height * 0.68,
    );

    return Dialog(
      key: const ValueKey('global-sign-dialog'),
      backgroundColor: AppTheme.dialogSurface(context),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 620,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '全局签',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colors.text,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: IconButton(
                      key: const ValueKey('global-sign-close'),
                      onPressed: _confirming
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Text(
                        '暂无内容',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSubtle,
                        ),
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: Scrollbar(
                        controller: _scrollController,
                        interactive: true,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _GlobalSignItemRow(
                              key: ValueKey('global-sign-item-${item.id}'),
                              item: item,
                              controller: _controllers[item.id]!,
                              done: _doneIds.contains(item.id),
                              deleted: _deletedIds.contains(item.id),
                              enabled: !_confirming,
                              onToggleDone: () => _toggleDone(item.id),
                              onToggleDeleted: () => _toggleDeleted(item.id),
                              onChanged: (_) => setState(() {}),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            Divider(height: 1, color: colors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _hasChanges ? '有未确认的变更' : '完成 / 删除 / 修改后请点击确认',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSubtle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _GlobalSignConfirmButton(
                    enabled: _hasChanges && !_confirming,
                    busy: _confirming,
                    onTap: _confirm,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalSignItemRow extends StatelessWidget {
  const _GlobalSignItemRow({
    super.key,
    required this.item,
    required this.controller,
    required this.done,
    required this.deleted,
    required this.enabled,
    required this.onToggleDone,
    required this.onToggleDeleted,
    required this.onChanged,
  });

  final GlobalSignItem item;
  final TextEditingController controller;
  final bool done;
  final bool deleted;
  final bool enabled;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleDeleted;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Opacity(
      opacity: deleted ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    enabled: enabled && !deleted,
                    onChanged: onChanged,
                    maxLines: null,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: done || deleted
                          ? colors.textSubtle
                          : colors.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                      height: 1.5,
                    ),
                    cursorColor: colors.textMuted,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item.id} · 创建 ${_formatSignTime(item.createdAt)} · 更新 ${_formatSignTime(item.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSubtle,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _GlobalSignItemAction(
              key: ValueKey('global-sign-done-${item.id}'),
              tooltip: done ? '取消完成' : '完成',
              icon: done
                  ? Icons.check_circle_rounded
                  : Icons.check_circle_outline_rounded,
              active: done,
              onTap: enabled ? onToggleDone : null,
            ),
            _GlobalSignItemAction(
              key: ValueKey('global-sign-delete-${item.id}'),
              tooltip: deleted ? '恢复' : '删除',
              icon: deleted
                  ? Icons.undo_rounded
                  : Icons.delete_outline_rounded,
              active: deleted,
              onTap: enabled ? onToggleDeleted : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalSignItemAction extends StatelessWidget {
  const _GlobalSignItemAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: 18,
        color: active ? colors.text : colors.textSubtle,
      ),
    );
  }
}

class _GlobalSignConfirmButton extends StatelessWidget {
  const _GlobalSignConfirmButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final background = enabled ? colors.text : colors.surfaceMuted;
    final foreground = enabled ? colors.surface : colors.textSubtle;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        key: const ValueKey('global-sign-confirm'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              : Text(
                  '确认',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

String _formatSignTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
