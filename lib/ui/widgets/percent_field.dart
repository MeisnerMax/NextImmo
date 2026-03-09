import 'package:flutter/material.dart';

class PercentField extends StatelessWidget {
  const PercentField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: false,
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: '%',
        prefixIcon: const Icon(Icons.percent, size: 18),
      ),
      onChanged: onChanged,
    );
  }
}
