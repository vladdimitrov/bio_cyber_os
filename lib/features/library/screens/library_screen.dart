import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

import '../../../core/macro_display.dart';
import '../../../core/models/ingredient.dart';
import '../../../core/models/supplement.dart';
import '../../../core/widgets/diet_indicator_badges.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  int _reloadTick = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _reloadTick++);

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(l10n.screenLibrary),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cyan,
          unselectedLabelColor: const Color(0x8800F3FF),
          indicatorColor: cyan,
          labelStyle: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
          tabs: const [
            Tab(text: 'INGREDIENTS'),
            Tab(text: 'RECIPES'),
            Tab(text: 'SUPPLEMENTS'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'library_fab',
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        backgroundColor: bg,
        foregroundColor: cyan,
        onPressed: () async {
          final idx = _tabController.index;
          bool? changed;
          if (idx == 0) {
            changed = await showDialog<bool>(
              context: context,
              builder: (_) => const _IngredientDialog(),
            );
          } else if (idx == 1) {
            changed = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: bg,
              shape:
                  const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              builder: (_) => const _RecipeBuilderSheet(),
            );
          } else {
            changed = await showDialog<bool>(
              context: context,
              builder: (_) => const _SupplementDialog(),
            );
          }
          if (changed == true) _reload();
        },
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _IngredientsTab(
            key: ValueKey('ing-$_reloadTick'),
            onChanged: _reload,
          ),
          _RecipesTab(
            key: ValueKey('rec-$_reloadTick'),
            onChanged: _reload,
          ),
          _SupplementsTab(
            key: ValueKey('sup-$_reloadTick'),
            onChanged: _reload,
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  const bg = Color(0xFF050510);
  const cyan = Color(0xFF00F3FF);
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        title,
        style: const TextStyle(color: cyan, fontFamily: 'monospace'),
      ),
      content: Text(
        body,
        style: const TextStyle(color: cyan, fontFamily: 'monospace'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('DELETE'),
        ),
      ],
    ),
  );
  return res == true;
}

void _showSaveError(BuildContext context, Object e) {
  if (e is PostgrestException && e.code == '23505') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('An item with this name already exists.'),
      ),
    );
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(e.toString())),
  );
}

class _IngredientsTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _IngredientsTab({super.key, required this.onChanged});

  @override
  State<_IngredientsTab> createState() => _IngredientsTabState();
}

class _IngredientsTabState extends State<_IngredientsTab> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>> _rows = const [];

  Widget _ownershipBadge(Object? userId) {
    const cyan = Color(0xFF00F3FF);
    final uid = _client.auth.currentUser?.id;
    final isSystem = userId == null;
    final isPersonal = !isSystem && uid != null && userId.toString() == uid;
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

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await _client
        .from('ingredients')
        .select(
          'id,name,calories_per_100g,protein_per_100g,carbs_per_100g,fat_per_100g,'
          'is_gluten_free,glycemic_index,allergen_level,user_id',
        )
        .order('name');
    return (data as List).cast<Map<String, dynamic>>();
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _refresh() => setState(() {
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00F3FF);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                snap.error.toString(),
                style: const TextStyle(color: cyan),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        final rows = List<Map<String, dynamic>>.from(snap.data!);
        _rows = rows;
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              'No ingredients',
              style: TextStyle(color: cyan, fontFamily: 'monospace'),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final r = rows[index];
            final id = (r['id'] ?? '').toString();
            final name = (r['name'] ?? '').toString();
            final ingRow = Ingredient.fromJson(Map<String, dynamic>.from(r));
            final uid = _client.auth.currentUser?.id;
            final ownerId = r['user_id'];
            final isSystem = ownerId == null;
            final canEditDelete =
                !isSystem && uid != null && ownerId.toString() == uid;
            return ListTile(
              title: Text(
                name,
                style: const TextStyle(
                  color: cyan,
                  fontFamily: 'monospace',
                  letterSpacing: 0.6,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  _ownershipBadge(ownerId),
                  const SizedBox(height: 6),
                  Text(
                    MacroDisplay.macroLine(
                      MacroDisplay.asDouble(r['protein_per_100g']),
                      MacroDisplay.asDouble(r['carbs_per_100g']),
                      MacroDisplay.asDouble(r['fat_per_100g']),
                      MacroDisplay.asDouble(r['calories_per_100g']),
                    ),
                    style: const TextStyle(
                      color: Color(0xFF757575),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DietIndicatorBadges(
                    isGlutenFree: ingRow.isGlutenFree,
                    glycemicIndex: ingRow.glycemicIndex,
                    allergenLevel: ingRow.allergenLevel,
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canEditDelete) ...[
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () async {
                        final changed = await showDialog<bool>(
                          context: context,
                          builder: (_) => _IngredientDialog(existing: r),
                        );
                        if (changed == true) {
                          _refresh();
                          widget.onChanged();
                        }
                      },
                      icon: const Icon(Icons.edit, color: cyan),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: () async {
                        final ok = await _confirmDeleteDialog(
                          context,
                          title: 'DELETE INGREDIENT',
                          body: name,
                        );
                        if (!ok) return;
                        // Optimistic local removal for instant UI feedback.
                        setState(() {
                          _rows = _rows
                              .where(
                                (x) => (x['id'] ?? '').toString() != id,
                              )
                              .toList(growable: false);
                          _future = Future.value(_rows);
                        });
                        await _client.from('ingredients').delete().eq('id', id);
                        _refresh(); // re-fetch authoritative data
                        widget.onChanged();
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RecipesTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _RecipesTab({super.key, required this.onChanged});

  @override
  State<_RecipesTab> createState() => _RecipesTabState();
}

class _RecipesTabState extends State<_RecipesTab> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>> _rows = const [];

  Widget _ownershipBadge(Object? userId) {
    const cyan = Color(0xFF00F3FF);
    final uid = _client.auth.currentUser?.id;
    final isSystem = userId == null;
    final isPersonal = !isSystem && uid != null && userId.toString() == uid;
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

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await _client
        .from('recipes')
        .select(
          '*, recipe_ingredients(*, ingredients(name,protein_per_100g,carbs_per_100g,fat_per_100g,calories_per_100g))',
        )
        .order('name');
    return (data as List).cast<Map<String, dynamic>>();
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _refresh() => setState(() {
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00F3FF);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                snap.error.toString(),
                style: const TextStyle(color: cyan),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        final rows = List<Map<String, dynamic>>.from(snap.data!);
        _rows = rows;
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              'No recipes',
              style: TextStyle(color: cyan, fontFamily: 'monospace'),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final r = rows[index];
            final id = (r['id'] ?? '').toString();
            final name = (r['name'] ?? '').toString();
            final uid = _client.auth.currentUser?.id;
            final ownerId = r['user_id'];
            final isSystem = ownerId == null;
            final canEditDelete =
                !isSystem && uid != null && ownerId.toString() == uid;
            return ListTile(
              title: Text(
                name,
                style: const TextStyle(
                  color: cyan,
                  fontFamily: 'monospace',
                  letterSpacing: 0.6,
                ),
              ),
              subtitle: () {
                final ri = r['recipe_ingredients'];
                double tp = 0, tc = 0, tf = 0, tcal = 0;
                final parts = <String>[];
                double totalGrams = 0.0;
                if (ri is List) {
                  for (final x in ri) {
                    if (x is! Map<String, dynamic>) continue;
                    final ing = x['ingredients'];
                    final ingName = ing is Map<String, dynamic>
                        ? (ing['name'] ?? '').toString()
                        : '';
                    final g = MacroDisplay.asDouble(x['amount_grams']);
                    totalGrams += g;
                    if (ing is Map<String, dynamic>) {
                      final factor = g / 100.0;
                      tp += MacroDisplay.asDouble(ing['protein_per_100g']) * factor;
                      tc += MacroDisplay.asDouble(ing['carbs_per_100g']) * factor;
                      tf += MacroDisplay.asDouble(ing['fat_per_100g']) * factor;
                      tcal +=
                          MacroDisplay.asDouble(ing['calories_per_100g']) * factor;
                    }
                    if (ingName.isNotEmpty) {
                      parts.add(
                        '$ingName (${MacroDisplay.fmt(g)}g)',
                      );
                    }
                  }
                }
                final macroLine = MacroDisplay.macroLine(tp, tc, tf, tcal);
                final detail =
                    'Total weight: ${MacroDisplay.fmt(totalGrams)}g | ${parts.join(', ')}';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    _ownershipBadge(ownerId),
                    const SizedBox(height: 6),
                    Text(
                      'Recipe total: $macroLine',
                      style: const TextStyle(
                        color: Color(0xFF757575),
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    if (parts.isNotEmpty)
                      Text(
                        detail,
                        style: const TextStyle(
                          color: Color(0x6600F3FF),
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                  ],
                );
              }(),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canEditDelete) ...[
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () async {
                        const bg = Color(0xFF050510);
                        final changed = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: bg,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          builder: (_) => _RecipeBuilderSheet(existingRecipe: r),
                        );
                        if (changed == true) {
                          _refresh();
                          widget.onChanged();
                        }
                      },
                      icon: const Icon(Icons.edit, color: cyan),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: () async {
                        final ok = await _confirmDeleteDialog(
                          context,
                          title: 'DELETE RECIPE',
                          body: name,
                        );
                        if (!ok) return;
                        setState(() {
                          _rows = _rows
                              .where(
                                (x) => (x['id'] ?? '').toString() != id,
                              )
                              .toList(growable: false);
                          _future = Future.value(_rows);
                        });
                        await _client.from('recipes').delete().eq('id', id);
                        _refresh();
                        widget.onChanged();
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SupplementsTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _SupplementsTab({super.key, required this.onChanged});

  @override
  State<_SupplementsTab> createState() => _SupplementsTabState();
}

class _SupplementsTabState extends State<_SupplementsTab> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>> _rows = const [];

  Widget _ownershipBadge(Object? userId) {
    const cyan = Color(0xFF00F3FF);
    final uid = _client.auth.currentUser?.id;
    final isSystem = userId == null;
    final isPersonal = !isSystem && uid != null && userId.toString() == uid;
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

  Future<List<Map<String, dynamic>>> _load() async {
    final data =
        await _client.from('supplements').select().order('name');
    return (data as List).cast<Map<String, dynamic>>();
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _refresh() async {
    final data = await _load();
    if (!mounted) return;
    setState(() {
      _rows = data;
      _future = Future.value(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00F3FF);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                snap.error.toString(),
                style: const TextStyle(color: cyan),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        final rows = List<Map<String, dynamic>>.from(snap.data!);
        _rows = rows;
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              'No supplements',
              style: TextStyle(color: cyan, fontFamily: 'monospace'),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final r = rows[index];
            final id = (r['id'] ?? '').toString();
            final name = (r['name'] ?? '').toString();
            final dosage = (r['daily_dosage'] ?? '').toString();
            final unit = (r['unit_type'] ?? '').toString();
            final time = (r['scheduled_time'] ?? '').toString();
            final label = [
              if (time.isNotEmpty) time,
              name,
              if (dosage.isNotEmpty || unit.isNotEmpty) '$dosage $unit'.trim(),
            ].join(' - ');
            final sup = Supplement.fromJson(Map<String, dynamic>.from(r));
            final uid = _client.auth.currentUser?.id;
            final ownerId = r['user_id'];
            final isSystem = ownerId == null;
            final canEditDelete =
                !isSystem && uid != null && ownerId.toString() == uid;

            return ListTile(
              title: Text(
                label,
                style: const TextStyle(
                  color: cyan,
                  fontFamily: 'monospace',
                  letterSpacing: 0.6,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  _ownershipBadge(ownerId),
                  const SizedBox(height: 6),
                  Text(
                    MacroDisplay.macroLine(
                      sup.protein,
                      sup.carbs,
                      sup.fat,
                      sup.calories,
                    ),
                    style: const TextStyle(
                      color: Color(0xFF757575),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DietIndicatorBadges(
                    isGlutenFree: sup.isGlutenFree,
                    glycemicIndex: sup.lowGlycemicIndex ? 55 : null,
                    allergenLevel: sup.allergenLevel,
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canEditDelete) ...[
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () async {
                        final changed = await showDialog<bool>(
                          context: context,
                          builder: (_) => _SupplementDialog(existing: r),
                        );
                        if (changed == true) {
                          await _refresh();
                          widget.onChanged();
                        }
                      },
                      icon: const Icon(Icons.edit, color: cyan),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await _confirmDeleteDialog(
                          context,
                          title: 'DELETE SUPPLEMENT',
                          body: name,
                        );
                        if (!ok) return;
                        setState(() {
                          _rows = _rows
                              .where(
                                (x) => (x['id'] ?? '').toString() != id,
                              )
                              .toList(growable: false);
                          _future = Future.value(_rows);
                        });
                        try {
                          await _client
                              .from('supplements')
                              .delete()
                              .eq('id', r['id']);
                          if (mounted) _refresh();
                        } on PostgrestException catch (e) {
                          if (!mounted) return;
                          if (e.code == '23503') {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Грешка: Не може да изтриете добавка, която вече е записана в дневника ви с приеми.',
                                ),
                                backgroundColor: Colors.redAccent,
                                duration: Duration(seconds: 4),
                              ),
                            );
                          } else {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('DB Error: ${e.message}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _IngredientDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _IngredientDialog({this.existing});

  @override
  State<_IngredientDialog> createState() => _IngredientDialogState();
}

class _IngredientDialogState extends State<_IngredientDialog> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _cal;
  late final TextEditingController _p;
  late final TextEditingController _c;
  late final TextEditingController _f;
  late final TextEditingController _gi;

  bool _glutenFree = false;
  int _allergenLevel = 1;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: (e?['name'] ?? '').toString());
    _cal = TextEditingController(text: (e?['calories_per_100g'] ?? '').toString());
    _p = TextEditingController(text: (e?['protein_per_100g'] ?? '').toString());
    _c = TextEditingController(text: (e?['carbs_per_100g'] ?? '').toString());
    _f = TextEditingController(text: (e?['fat_per_100g'] ?? '').toString());
    _gi = TextEditingController(text: (e?['glycemic_index'] ?? '').toString());
    if (e != null) {
      final ing = Ingredient.fromJson(Map<String, dynamic>.from(e));
      _glutenFree = ing.isGlutenFree;
      _allergenLevel = ing.allergenLevel;
      _gi.text = (ing.glycemicIndex ?? '').toString();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _cal.dispose();
    _p.dispose();
    _c.dispose();
    _f.dispose();
    _gi.dispose();
    super.dispose();
  }

  double _d(String v) => double.tryParse(v.trim().replaceAll(',', '.')) ?? 0.0;

  int? _giOrNull() {
    final raw = _gi.text.trim();
    if (raw.isEmpty) return null;
    final v = int.tryParse(raw);
    if (v == null) return null;
    return v.clamp(0, 100);
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = {
        'name': _name.text.trim(),
        'calories_per_100g': _d(_cal.text),
        'protein_per_100g': _d(_p.text),
        'carbs_per_100g': _d(_c.text),
        'fat_per_100g': _d(_f.text),
        'is_gluten_free': _glutenFree,
        'glycemic_index': _giOrNull(),
        'allergen_level': _allergenLevel,
      };

      final id = widget.existing?['id'];
      if (id == null || id.toString().isEmpty) {
        final uid = _client.auth.currentUser?.id;
        await _client.from('ingredients').insert({
          ...payload,
          'user_id': uid,
        });
      } else {
        await _client.from('ingredients').update(payload).eq('id', id);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSaveError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final title = widget.existing == null ? 'ADD INGREDIENT' : 'EDIT INGREDIENT';
    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(title, style: const TextStyle(color: cyan, fontFamily: 'monospace')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _cal,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Calories per 100g'),
                validator: (v) => double.tryParse((v ?? '').trim().replaceAll(',', '.')) == null
                    ? 'Number'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _p,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Protein per 100g'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Carbs per 100g'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _f,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Fats per 100g'),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Gluten-Free',
                  style: TextStyle(color: cyan, fontFamily: 'monospace'),
                ),
                value: _glutenFree,
                onChanged: _saving ? null : (v) => setState(() => _glutenFree = v),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _gi,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Glycemic Index (0-100)'),
                validator: (v) {
                  final raw = (v ?? '').trim();
                  if (raw.isEmpty) return null;
                  final n = int.tryParse(raw);
                  if (n == null) return 'Number';
                  if (n < 0 || n > 100) return '0–100';
                  return null;
                },
              ),
              DropdownButtonFormField<int>(
                initialValue: _allergenLevel,
                decoration: const InputDecoration(
                  labelText: 'Allergen level (1–5)',
                ),
                items: List.generate(
                  5,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('${i + 1}'),
                  ),
                ),
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _allergenLevel = v ?? 1),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const Text('...') : const Text('SAVE'),
        ),
      ],
    );
  }
}

class _SupplementDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _SupplementDialog({this.existing});

  @override
  State<_SupplementDialog> createState() => _SupplementDialogState();
}

class _SupplementDialogState extends State<_SupplementDialog> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _dosage;
  String _unit = 'drops';
  static const List<String> allowedUnits = ['g', 'mg', 'ml', 'drops', 'capsules'];

  bool _glutenFree = false;
  bool _lowGlycemicIndex = false;
  int _allergenLevel = 1;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: (e?['name'] ?? '').toString());
    _dosage = TextEditingController(text: (e?['daily_dosage'] ?? '').toString());

    // Sanitize legacy DB values to prevent DropdownButton value crashes.
    String dbUnit = e?['unit_type']?.toString() ?? 'g';
    if (dbUnit == 'гр' || dbUnit == 'гр.') dbUnit = 'g';
    if (dbUnit == 'мл') dbUnit = 'ml';
    if (dbUnit == 'капки') dbUnit = 'drops';
    if (dbUnit == 'капсули' || dbUnit == 'табл') dbUnit = 'capsules';
    if (!allowedUnits.contains(dbUnit)) {
      dbUnit = 'g';
    }
    _unit = dbUnit;
    if (e != null) {
      final s = Supplement.fromJson(Map<String, dynamic>.from(e));
      _glutenFree = s.isGlutenFree;
      _lowGlycemicIndex = s.lowGlycemicIndex;
      _allergenLevel = s.allergenLevel;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    super.dispose();
  }

  double _d(String v) => double.tryParse(v.trim().replaceAll(',', '.')) ?? 0.0;

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() => _saving = true);
    try {
      final id = widget.existing?['id'];
      if (id != null && id.toString().isNotEmpty) {
        await _client.from('supplements').update({
          'name': _name.text.trim(),
          'is_gluten_free': _glutenFree,
          'low_glycemic_index': _lowGlycemicIndex,
          'allergen_level': _allergenLevel,
        }).eq('id', widget.existing!['id']);
      } else {
        final uid = _client.auth.currentUser?.id;
        await _client.from('supplements').insert({
          'name': _name.text.trim(),
          'daily_dosage': _d(_dosage.text),
          'unit_type': _unit,
          'is_gluten_free': _glutenFree,
          'low_glycemic_index': _lowGlycemicIndex,
          'allergen_level': _allergenLevel,
          'is_active': false,
          'user_id': uid,
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSaveError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final title = widget.existing == null ? 'ADD SUPPLEMENT' : 'EDIT SUPPLEMENT';
    return AlertDialog(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(title, style: const TextStyle(color: cyan, fontFamily: 'monospace')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _dosage,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Daily dosage'),
                validator: (v) => double.tryParse((v ?? '').trim().replaceAll(',', '.')) == null
                    ? 'Number'
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                items: allowedUnits
                    .map((u) => DropdownMenuItem<String>(
                          value: u,
                          child: Text(u),
                        ))
                    .toList(growable: false),
                onChanged: (v) => setState(() => _unit = v ?? _unit),
                decoration: const InputDecoration(labelText: 'Unit type'),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Gluten-Free',
                  style: TextStyle(color: cyan, fontFamily: 'monospace'),
                ),
                value: _glutenFree,
                onChanged: _saving ? null : (v) => setState(() => _glutenFree = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Low glycemic index',
                  style: TextStyle(color: cyan, fontFamily: 'monospace'),
                ),
                subtitle: const Text(
                  'Food with a low glycemic index (Low-GI).',
                  style: TextStyle(fontSize: 11, color: Color(0xFF757575)),
                ),
                value: _lowGlycemicIndex,
                onChanged: _saving ? null : (v) => setState(() => _lowGlycemicIndex = v),
              ),
              DropdownButtonFormField<int>(
                initialValue: _allergenLevel,
                decoration: const InputDecoration(
                  labelText: 'Allergen level (1–5)',
                ),
                items: List.generate(
                  5,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('${i + 1}'),
                  ),
                ),
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _allergenLevel = v ?? 1),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const Text('...') : const Text('SAVE'),
        ),
      ],
    );
  }
}

class _RecipeBuilderSheet extends StatefulWidget {
  final Map<String, dynamic>? existingRecipe;

  const _RecipeBuilderSheet({this.existingRecipe});

  @override
  State<_RecipeBuilderSheet> createState() => _RecipeBuilderSheetState();
}

class _RecipeBuilderSheetState extends State<_RecipeBuilderSheet> {
  final _client = Supabase.instance.client;
  final _name = TextEditingController();
  final _grams = TextEditingController();

  bool _loadingIngredients = true;
  bool _saving = false;
  bool _nameMissing = false;
  List<Map<String, dynamic>> _ingredients = const [];
  Map<String, dynamic>? _selectedIngredient;
  final List<Map<String, dynamic>> _pendingIngredients = [];

  void _onGramsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _grams.addListener(_onGramsChanged);
    _name.text = (widget.existingRecipe?['name'] ?? '').toString();
    _loadIngredients();
    _loadExistingRecipeIngredients();
  }

  @override
  void dispose() {
    _grams.removeListener(_onGramsChanged);
    _name.dispose();
    _grams.dispose();
    super.dispose();
  }

  Future<void> _loadIngredients() async {
    setState(() => _loadingIngredients = true);
    try {
      final data = await _client
          .from('ingredients')
          .select(
            'id,name,protein_per_100g,carbs_per_100g,fat_per_100g,calories_per_100g',
          )
          .order('name');
      final rows = (data as List).cast<Map<String, dynamic>>();
      final sorted = List<Map<String, dynamic>>.from(rows);
      sorted.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
      if (!mounted) return;
      setState(() {
        _ingredients = sorted;
        _loadingIngredients = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingIngredients = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  double _d(String v) => double.tryParse(v.trim().replaceAll(',', '.')) ?? 0.0;

  /// Macros already saved in the in-progress list (double precision).
  ({double p, double c, double f, double cal}) _pendingCommittedTotals() {
    double p = 0, c = 0, f = 0, cal = 0;
    for (final item in _pendingIngredients) {
      final grams = item['amount_grams'] is num
          ? (item['amount_grams'] as num).toDouble()
          : MacroDisplay.asDouble(item['amount_grams']);
      if (grams <= 0) continue;
      final factor = grams / 100.0;
      p += MacroDisplay.asDouble(item['protein_per_100g']) * factor;
      c += MacroDisplay.asDouble(item['carbs_per_100g']) * factor;
      f += MacroDisplay.asDouble(item['fat_per_100g']) * factor;
      cal += MacroDisplay.asDouble(item['calories_per_100g']) * factor;
    }
    return (p: p, c: c, f: f, cal: cal);
  }

  /// Macros for the selected ingredient at the amount in the field (not yet added).
  ({double p, double c, double f, double cal}) _currentIngredientLineTotals() {
    final sel = _selectedIngredient;
    if (sel == null) return (p: 0, c: 0, f: 0, cal: 0);
    final grams = _d(_grams.text);
    if (grams <= 0) return (p: 0, c: 0, f: 0, cal: 0);
    return MacroDisplay.scaledFromIngredientRow(sel, grams);
  }

  Widget _macroPreviewBar({
    required String title,
    required String macroLine,
  }) {
    const cyan = Color(0xFF00F3FF);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0x4400F3FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF757575),
              fontFamily: 'monospace',
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            macroLine,
            style: const TextStyle(
              color: cyan,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _addPending() {
    final ing = _selectedIngredient;
    if (ing == null) return;
    final grams = _d(_grams.text);
    if (grams <= 0) return;
    setState(() {
      _pendingIngredients.add({
        'ingredient_id': ing['id'],
        'ingredient_name': (ing['name'] ?? '').toString(),
        'amount_grams': grams,
        'protein_per_100g': MacroDisplay.asDouble(ing['protein_per_100g']),
        'carbs_per_100g': MacroDisplay.asDouble(ing['carbs_per_100g']),
        'fat_per_100g': MacroDisplay.asDouble(ing['fat_per_100g']),
        'calories_per_100g': MacroDisplay.asDouble(ing['calories_per_100g']),
      });
      _grams.clear();
    });
  }

  Future<void> _loadExistingRecipeIngredients() async {
    final existing = widget.existingRecipe;
    final recipeId = existing?['id'];
    if (recipeId == null) return;

    try {
      final data = await _client
          .from('recipe_ingredients')
          .select(
            'ingredient_id,amount_grams,ingredients(name,protein_per_100g,carbs_per_100g,fat_per_100g,calories_per_100g)',
          )
          .eq('recipe_id', recipeId);

      final rows = (data as List).cast<Map<String, dynamic>>();
      final pending = <Map<String, dynamic>>[];
      for (final r in rows) {
        final ing = r['ingredients'];
        final ingMap =
            ing is Map<String, dynamic> ? ing : <String, dynamic>{};
        final grams = (r['amount_grams'] is num)
            ? (r['amount_grams'] as num).toDouble()
            : double.tryParse((r['amount_grams'] ?? '').toString()) ?? 0.0;
        pending.add({
          'ingredient_id': r['ingredient_id'],
          'ingredient_name': (ingMap['name'] ?? '').toString(),
          'amount_grams': grams,
          'protein_per_100g': MacroDisplay.asDouble(ingMap['protein_per_100g']),
          'carbs_per_100g': MacroDisplay.asDouble(ingMap['carbs_per_100g']),
          'fat_per_100g': MacroDisplay.asDouble(ingMap['fat_per_100g']),
          'calories_per_100g':
              MacroDisplay.asDouble(ingMap['calories_per_100g']),
        });
      }

      if (!mounted) return;
      setState(() {
        _pendingIngredients
          ..clear()
          ..addAll(pending);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _saveRecipe() async {
    final recipeName = _name.text.trim();
    if (recipeName.isEmpty) {
      if (!mounted) return;
      setState(() => _nameMissing = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a recipe name.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_pendingIngredients.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one ingredient.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = widget.existingRecipe;
      final existingId = existing?['id'];

      if (existingId == null) {
        // NEW RECIPE (strict sequence)
        final uid = _client.auth.currentUser?.id;
        final recipeResponse = await _client
            .from('recipes')
            .insert({'name': recipeName, 'user_id': uid})
            .select('id')
            .single();
        final realRecipeId = recipeResponse['id'];

        for (final item in List<Map<String, dynamic>>.from(_pendingIngredients)) {
          await _client.from('recipe_ingredients').insert({
            'recipe_id': realRecipeId,
            'ingredient_id': item['ingredient_id'],
            'amount_grams': item['amount_grams'],
          });
        }
      } else {
        // EDIT RECIPE (strict sequence)
        await _client
            .from('recipes')
            .update({'name': recipeName})
            .eq('id', existingId);

        await _client.from('recipe_ingredients').delete().eq('recipe_id', existingId);

        for (final item in List<Map<String, dynamic>>.from(_pendingIngredients)) {
          await _client.from('recipe_ingredients').insert({
            'recipe_id': existingId,
            'ingredient_id': item['ingredient_id'],
            'amount_grams': item['amount_grams'],
          });
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);

    return SafeArea(
      child: Container(
        color: bg,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: cyan, width: 2)),
              ),
              child: const Text(
                'RECIPE BUILDER',
                style: TextStyle(
                  color: cyan,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              onChanged: (_) {
                if (_nameMissing && _name.text.trim().isNotEmpty) {
                  setState(() => _nameMissing = false);
                }
              },
              decoration: InputDecoration(
                labelText: 'Recipe name',
                errorText: (_nameMissing && _name.text.trim().isEmpty)
                    ? 'Please enter a recipe name.'
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            _loadingIngredients
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<Map<String, dynamic>>(
                    initialValue: _selectedIngredient,
                    items: _ingredients
                        .map(
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text((i['name'] ?? '').toString()),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) => setState(() => _selectedIngredient = v),
                    decoration: const InputDecoration(labelText: 'Ingredient'),
                  ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _grams,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Amount (grams)',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _addPending,
                    child: const Text('ADD INGREDIENT'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final cur = _currentIngredientLineTotals();
                final base = _pendingCommittedTotals();
                final runP = base.p + cur.p;
                final runC = base.c + cur.c;
                final runF = base.f + cur.f;
                final runCal = base.cal + cur.cal;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _macroPreviewBar(
                      title: 'Current ingredient total',
                      macroLine: MacroDisplay.macroLine(
                        cur.p,
                        cur.c,
                        cur.f,
                        cur.cal,
                      ),
                    ),
                    _macroPreviewBar(
                      title: 'Recipe total (with this line)',
                      macroLine: MacroDisplay.macroLine(
                        runP,
                        runC,
                        runF,
                        runCal,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _pendingIngredients.length,
                itemBuilder: (context, index) {
                  final p = _pendingIngredients[index];
                  final name = (p['ingredient_name'] ?? '').toString();
                  final grams = (p['amount_grams'] is num)
                      ? (p['amount_grams'] as num).toDouble()
                      : double.tryParse((p['amount_grams'] ?? '').toString()) ?? 0.0;
                  return ListTile(
                    title: Text(
                      '$name - ${grams.toStringAsFixed(0)}g',
                      style: const TextStyle(
                        color: cyan,
                        fontFamily: 'monospace',
                        letterSpacing: 0.6,
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: () =>
                          setState(() => _pendingIngredients.removeAt(index)),
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveRecipe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cyan,
                  foregroundColor: Colors.black,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                child: _saving ? const Text('...') : const Text('SAVE RECIPE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Pending ingredients are kept as Map<String, dynamic> with:
// { ingredient_id, amount_grams, ingredient_name, protein_per_100g, ... } (NO recipe_id stored locally).

