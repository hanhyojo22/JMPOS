import 'package:flutter/material.dart';

class MessageBanner extends StatelessWidget {
  final String message;
  final bool success;

  const MessageBanner({super.key, required this.message, this.success = false});

  @override
  Widget build(BuildContext context) {
    final bgColor = success ? const Color(0xFF22C55E) : const Color(0xFFDC2626);
    final icon = success ? Icons.check_circle_outline : Icons.error_outline;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
