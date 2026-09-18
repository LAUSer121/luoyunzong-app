/// 行内数字输入框：值变化时回调，外部值变化时自动同步（未聚焦时）。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class NumberField extends StatefulWidget {
  const NumberField({
    required this.value,
    required this.onChanged,
    this.width = 88,
    this.enabled = true,
    this.label,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double width;
  final bool enabled;
  final String? label;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.text, fontSize: 13),
        decoration: InputDecoration(labelText: widget.label, isDense: true),
        onChanged: (String v) => widget.onChanged(int.tryParse(v.trim()) ?? 0),
      ),
    );
  }
}
