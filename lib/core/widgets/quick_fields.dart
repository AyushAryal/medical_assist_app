import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../clinical/validators.dart';
import '../theme/theme_scope.dart';

/// A labelled text field with consistent spacing and helper placement.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.suffix,
    this.prefix,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction,
    this.focusNode,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final Widget? suffix;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? minLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      minLines: minLines,
      validator: validator,
      onChanged: onChanged,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        suffixIcon: suffix,
        prefixIcon: prefix,
      ),
    );
  }
}

/// Numeric entry tuned for bedside speed.
///
/// Three deliberate choices: the numeric keypad opens immediately, the unit is
/// shown inside the field so nobody has to remember whether temperature is in
/// C or F, and `selectAllOnFocus` means correcting a mistyped value is one tap
/// and a retype rather than a fight with the cursor.
class NumericField extends StatefulWidget {
  const NumericField({
    super.key,
    required this.label,
    required this.controller,
    this.unit,
    this.helper,
    this.allowDecimal = false,
    this.maxLength = 6,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.focusNode,
    this.textInputAction = TextInputAction.next,
    this.trailing,
    this.check,
  });

  final String label;
  final TextEditingController controller;
  final String? unit;
  final String? helper;
  final bool allowDecimal;
  final int maxLength;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final FocusNode? focusNode;
  final TextInputAction textInputAction;
  final Widget? trailing;

  /// Live plausibility check, run on every keystroke. Returns a warning for a
  /// value that is almost certainly a typing or unit error — never for one
  /// that is merely abnormal, because the sickest patients produce the most
  /// abnormal numbers and the form must still accept them.
  final FieldCheck? Function(String?)? check;

  @override
  State<NumericField> createState() => _NumericFieldState();
}

class _NumericFieldState extends State<NumericField> {
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  bool _ownsFocusNode = false;
  FieldCheck? _check;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) return;
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.text.length,
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _runCheck(String value) {
    final result = widget.check?.call(value);
    if (result?.message != _check?.message) {
      setState(() => _check = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final check = _check;
    final tone = check == null
        ? null
        : check.isBlocking
            ? palette.critical
            : palette.caution;

    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      textAlign: TextAlign.start,
      style: context.texts.bodyLarge?.copyWith(
        fontSize: context.typography.dataSize,
        fontWeight: FontWeight.w600,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.allowDecimal,
        signed: false,
      ),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(
          widget.allowDecimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
        LengthLimitingTextInputFormatter(widget.maxLength),
      ],
      textInputAction: widget.textInputAction,
      validator: (value) {
        final blocking = widget.check?.call(value);
        if (blocking != null && blocking.isBlocking) return blocking.message;
        return widget.validator?.call(value);
      },
      onChanged: (value) {
        _runCheck(value);
        widget.onChanged?.call(value);
      },
      decoration: InputDecoration(
        labelText: widget.label,
        // The plausibility message replaces the reference-range hint while it
        // is showing, so the field never presents two competing helper lines.
        helperText: check?.message ?? widget.helper,
        helperMaxLines: 3,
        helperStyle: tone == null
            ? null
            : context.texts.bodySmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w600,
              ),
        suffixIcon: widget.trailing ??
            (check == null
                ? null
                : Icon(
                    check.isBlocking
                        ? Icons.error_outline
                        : Icons.warning_amber_rounded,
                    size: 18,
                    color: tone,
                  )),
        suffixText: widget.unit,
        suffixStyle: context.texts.labelMedium?.copyWith(
          color: palette.onSurfaceMuted,
        ),
      ),
    );
  }
}

/// Single-select chip row. Faster than a dropdown for short option sets, and
/// it shows every choice at once — which matters when the options are
/// clinically meaningful rather than cosmetic.
class ChoiceChipRow<T> extends StatelessWidget {
  const ChoiceChipRow({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onSelected,
    this.label,
    this.allowDeselect = false,
  });

  final List<T> values;
  final String Function(T) labelOf;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final String? label;
  final bool allowDeselect;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(label!, style: context.texts.labelMedium),
          SizedBox(height: m.spaceSm),
        ],
        Wrap(
          spacing: m.spaceSm,
          runSpacing: m.spaceSm,
          children: values.map((value) {
            final isSelected = value == selected;
            return ChoiceChip(
              label: Text(labelOf(value)),
              selected: isSelected,
              onSelected: (chosen) {
                if (!chosen && !allowDeselect) return;
                onSelected(chosen ? value : null);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
