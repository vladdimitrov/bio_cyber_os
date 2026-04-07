import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LibrarySearchSheet extends StatefulWidget {
  final String title;
  final String table;
  final String emptyMessage;
  final String addNewLabel;
  final Future<void> Function() onAddNew;
  final void Function(Map<String, dynamic> row) onPick;
  final String Function(Map<String, dynamic> row) getName;
  final String Function(Map<String, dynamic> row)? getSubtitle;
  final IconData Function(Map<String, dynamic> row)? getIcon;

  /// PostgREST `.or(...)` filter, e.g. `user_id.eq.<uuid>,user_id.is.null`.
  final String? accessOrFilter;

  const LibrarySearchSheet({
    super.key,
    required this.title,
    required this.table,
    required this.emptyMessage,
    required this.addNewLabel,
    required this.onAddNew,
    required this.onPick,
    required this.getName,
    this.getSubtitle,
    this.getIcon,
    this.accessOrFilter,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String table,
    required String emptyMessage,
    required String addNewLabel,
    required Future<void> Function() onAddNew,
    required void Function(Map<String, dynamic> row) onPick,
    required String Function(Map<String, dynamic> row) getName,
    String Function(Map<String, dynamic> row)? getSubtitle,
    IconData Function(Map<String, dynamic> row)? getIcon,
    String? accessOrFilter,
  }) {
    const bg = Color(0xFF050510);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.95,
        child: LibrarySearchSheet(
          title: title,
          table: table,
          emptyMessage: emptyMessage,
          addNewLabel: addNewLabel,
          onAddNew: onAddNew,
          onPick: onPick,
          getName: getName,
          getSubtitle: getSubtitle,
          getIcon: getIcon,
          accessOrFilter: accessOrFilter,
        ),
      ),
    );
  }

  @override
  State<LibrarySearchSheet> createState() => _LibrarySearchSheetState();
}

class _LibrarySearchSheetState extends State<LibrarySearchSheet> {
  final _client = Supabase.instance.client;
  final _controller = TextEditingController();

  String _q = '';
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _all = const [];
  List<Map<String, dynamic>> _results = const [];
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final rid = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = _client.from(widget.table).select();
      final orf = widget.accessOrFilter?.trim();
      if (orf != null && orf.isNotEmpty) {
        query = query.or(orf);
      }
      final data = await query.order('name').limit(500);
      if (!mounted || rid != _requestId) return;
      final rows = (data as List).cast<Map<String, dynamic>>();
      rows.sort((a, b) =>
          widget.getName(a).toLowerCase().compareTo(widget.getName(b).toLowerCase()));
      setState(() {
        _all = rows;
        _results = rows;
        _loading = false;
      });
      _applyFilter(_q);
    } catch (e) {
      if (!mounted || rid != _requestId) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _applyFilter(String q) {
    final trimmed = q.trim().toLowerCase();
    setState(() {
      _q = q;
      if (trimmed.isEmpty) {
        _results = _all;
      } else {
        _results = _all
            .where((r) => widget.getName(r).toLowerCase().contains(trimmed))
            .toList(growable: false);
      }
    });
  }

  List<TextSpan> _highlight(String text, String q) {
    const cyan = Color(0xFF00F3FF);
    final query = q.trim();
    if (query.isEmpty) return [TextSpan(text: text)];
    final lower = text.toLowerCase();
    final ql = query.toLowerCase();
    final idx = lower.indexOf(ql);
    if (idx < 0) return [TextSpan(text: text)];
    return [
      TextSpan(text: text.substring(0, idx)),
      TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(color: cyan, fontWeight: FontWeight.w800),
      ),
      TextSpan(text: text.substring(idx + query.length)),
    ];
  }

  Widget? _ownershipBadge(Map<String, dynamic> row) {
    if (!row.containsKey('user_id')) return null;
    const cyan = Color(0xFF00F3FF);
    final uid = _client.auth.currentUser?.id;
    final ownerId = row['user_id'];
    final isSystem = ownerId == null;
    final isPersonal = !isSystem && uid != null && ownerId.toString() == uid;
    final label = isSystem ? 'SYSTEM' : (isPersonal ? 'PERSONAL' : 'SHARED');
    final color = isSystem
        ? const Color(0xFF757575)
        : (isPersonal ? cyan : const Color(0xFF88CCFF));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: cyan, width: 2)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: cyan,
                  tooltip: 'Close',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _applyFilter,
                    style: const TextStyle(color: cyan, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF757575),
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _q.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                _controller.clear();
                                _applyFilter('');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: cyan, width: 1),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: cyan, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _error.toString(),
                          style: const TextStyle(color: cyan),
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.emptyMessage,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: cyan,
                                      fontFamily: 'monospace',
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await widget.onAddNew();
                                      await _loadAll();
                                    },
                                    icon: const Icon(Icons.add),
                                    label: Text(widget.addNewLabel),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: cyan,
                                      side: const BorderSide(color: cyan, width: 1),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.zero,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await widget.onAddNew();
                                    await _loadAll();
                                  },
                                  icon: const Icon(Icons.add),
                                  label: Text(widget.addNewLabel),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF88CCFF),
                                    side: const BorderSide(color: cyan, width: 1),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                ),
                              ),
                              for (final row in _results)
                                ListTile(
                                  leading: Icon(
                                    widget.getIcon?.call(row) ??
                                        Icons.library_books_outlined,
                                    color: cyan,
                                  ),
                                  trailing: _ownershipBadge(row),
                                  title: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(
                                        color: Color(0xAA00F3FF),
                                        fontFamily: 'monospace',
                                        letterSpacing: 0.6,
                                      ),
                                      children: _highlight(widget.getName(row), _q),
                                    ),
                                  ),
                                  subtitle: widget.getSubtitle == null
                                      ? null
                                      : Text(
                                          widget.getSubtitle!(row),
                                          style: const TextStyle(
                                            color: Color(0xFF757575),
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.onPick(row);
                                  },
                                ),
                              const SizedBox(height: 18),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

