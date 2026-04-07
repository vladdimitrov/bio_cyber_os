import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bio_cyber_os/l10n/app_localizations.dart';

class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key});

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatsController = TextEditingController();
  final _fiberController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatsController.dispose();
    _fiberController.dispose();
    super.dispose();
  }

  int _parseInt(String v) => int.tryParse(v.trim()) ?? 0;
  double _parseDouble(String v) => double.tryParse(v.trim()) ?? 0.0;

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _saving = true);
    try {
      await _client.from('food_items').insert({
        'name': _nameController.text.trim(),
        'is_recipe': false,
        'calories': _parseInt(_caloriesController.text),
        'protein_g': _parseDouble(_proteinController.text),
        'carbs_g': _parseDouble(_carbsController.text),
        'fats_g': _parseDouble(_fatsController.text),
        'fiber_g': _parseDouble(_fiberController.text),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DATA INJECTED')),
      );
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

  InputDecoration _decoration(String label) {
    const cyan = Color(0xFF00F3FF);
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: cyan, fontFamily: 'monospace'),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF050510);
    const cyan = Color(0xFF00F3FF);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: Text(l10n.addFood)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration('Name'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _caloriesController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration('Calories'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (int.tryParse(v.trim()) == null) return 'Number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _proteinController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration('Protein'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) return 'Number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _carbsController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration('Carbs'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) return 'Number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _fatsController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration('Fats'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) return 'Number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _fiberController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: _decoration('Fiber'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) return 'Number';
                        return null;
                      },
                      onFieldSubmitted: (_) => _saving ? null : _save(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cyan,
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(l10n.saveData),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

