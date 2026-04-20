import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Semi-transparent search field aligned with Library / Bio-Cyber styling.
class BioCyberSearchBar extends StatelessWidget {
  const BioCyberSearchBar({
    super.key,
    required this.controller,
    this.hintText = 'SEARCH…',
    this.onChanged,
    this.suffix,
    this.isLookupBusy = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  /// Optional trailing control (e.g. barcode scan).
  final Widget? suffix;
  /// When true, shows a small spinner beside the suffix (barcode lookup in progress).
  final bool isLookupBusy;

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00F3FF);
    Widget? suffixIcon;
    if (isLookupBusy && suffix != null) {
      suffixIcon = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.cyberGold.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(width: 6),
          suffix!,
        ],
      );
    } else if (isLookupBusy) {
      suffixIcon = Padding(
        padding: const EdgeInsetsDirectional.only(end: 10),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.cyberGold.withValues(alpha: 0.9),
          ),
        ),
      );
    } else {
      suffixIcon = suffix;
    }

    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(
        color: cyan,
        fontFamily: 'monospace',
        fontSize: 13,
        letterSpacing: 0.5,
      ),
      cursorColor: AppColors.cyberGold,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: cyan.withValues(alpha: 0.32),
          fontFamily: 'monospace',
          letterSpacing: 0.6,
        ),
        isDense: true,
        filled: true,
        fillColor: const Color(0x1400F3FF),
        prefixIcon: Icon(
          Icons.search,
          color: AppColors.cyberGold.withValues(alpha: 0.88),
          size: 22,
        ),
        suffixIcon: suffixIcon == null
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: suffixIcon,
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: cyan.withValues(alpha: 0.22), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
            color: AppColors.cyberGold.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}
