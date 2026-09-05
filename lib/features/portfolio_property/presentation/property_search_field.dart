import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/theme/app_theme.dart';

/// The workspace-wide property search input (`PROPERTY-LOOKUP-01`), shared by
/// the property list and the property switcher.
///
/// Three behaviours are here rather than at the call sites, because getting
/// any of them wrong turns a server search into a bad one:
///
///   * **Debounced.** Every accepted keystroke is a server round trip, so the
///     field waits until typing pauses instead of searching per character.
///   * **A minimum length.** One character matches most of a portfolio and
///     cannot use the trigram index either, so a single character is not
///     submitted — and the field says so instead of silently ignoring it.
///   * **Clearing is immediate.** Removing a filter is not a search and must
///     not wait: clearing cancels the pending submit and restores the
///     unfiltered list at once.
class PropertySearchField extends StatefulWidget {
  const PropertySearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.autofocus = false,
    this.label = 'Objekte suchen',
    this.debounce = const Duration(milliseconds: 350),
    this.minLength = 2,
  });

  /// The term currently in effect. The field follows it when it changes from
  /// the outside — a workspace switch clears the search, and the input must
  /// not keep showing a term that is no longer applied.
  final String value;

  /// Submits a normalized term, or an empty string to drop the filter.
  final ValueChanged<String> onChanged;

  final bool enabled;
  final bool autofocus;
  final String label;
  final Duration debounce;
  final int minLength;

  @override
  State<PropertySearchField> createState() => _PropertySearchFieldState();
}

class _PropertySearchFieldState extends State<PropertySearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  Timer? _debounce;
  bool _tooShort = false;

  @override
  void didUpdateWidget(covariant PropertySearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _debounce?.cancel();
      _controller.text = widget.value;
      _tooShort = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final term = raw.trim();
    if (term.isEmpty) {
      // Dropping the filter is not a search: it happens now.
      setState(() => _tooShort = false);
      widget.onChanged('');
      return;
    }
    if (term.length < widget.minLength) {
      setState(() => _tooShort = true);
      return;
    }
    if (_tooShort) {
      setState(() => _tooShort = false);
    }
    _debounce = Timer(widget.debounce, () => widget.onChanged(term));
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _tooShort = false);
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    // Listening to the controller rather than calling setState per keystroke:
    // the clear affordance has to appear with the first character, and an
    // external reset (workspace switch) must not schedule a build from inside
    // didUpdateWidget to make it disappear again.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) => _field(value.text.isNotEmpty),
    );
  }

  Widget _field(bool hasText) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: TextField(
        key: const Key('property-search-field'),
        controller: _controller,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        onSubmitted: (raw) {
          // Enter means now, not in 350 ms.
          _debounce?.cancel();
          final term = raw.trim();
          if (term.isEmpty || term.length >= widget.minLength) {
            widget.onChanged(term);
          }
        },
        decoration: InputDecoration(
          isDense: true,
          labelText: widget.label,
          hintText: 'Name, Adresse, PLZ oder Ort',
          prefixIcon: const Icon(Icons.search, size: 20),
          // The rule is stated where it applies, not after a failed search.
          helperText:
              _tooShort
                  ? 'Mindestens ${widget.minLength} Zeichen eingeben.'
                  : null,
          suffixIcon:
              !hasText
                  ? null
                  : IconButton(
                    key: const Key('property-search-clear'),
                    tooltip: 'Suche zurücksetzen',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.enabled ? _clear : null,
                  ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
        ),
      ),
    );
  }
}
