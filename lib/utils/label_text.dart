import 'package:flutter/material.dart';

/// A reusable label widget for consistent text styling across the app.
class LabelText extends StatelessWidget {
  final String text;
  final Color? color;
  final double? fontSize;
  final FontWeight? fontWeight;
  final TextAlign? align;

  const LabelText(
    this.text, {
    super.key,
    this.color,
    this.fontSize,
    this.fontWeight,
    this.align,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align ?? TextAlign.start,
      style: TextStyle(
        color: color ?? Colors.grey[800],
        fontSize: fontSize ?? 14,
        fontWeight: fontWeight ?? FontWeight.w500,
      ),
    );
  }
}
