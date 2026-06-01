import 'package:flutter/material.dart';

class AppTypography {
  const AppTypography._();

  static const TextStyle heroAmount = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  static const TextStyle primaryAmount = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static const TextStyle emphasizedBody = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static const TextStyle smallCaption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static TextTheme textTheme({
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    return TextTheme(
      displayLarge: heroAmount.copyWith(color: primaryColor),
      displayMedium: primaryAmount.copyWith(color: primaryColor),
      headlineSmall: pageTitle.copyWith(color: primaryColor),
      titleLarge: sectionTitle.copyWith(color: primaryColor),
      titleMedium: cardTitle.copyWith(color: primaryColor),
      bodyLarge: body.copyWith(color: primaryColor),
      bodyMedium: body.copyWith(color: primaryColor),
      bodySmall: caption.copyWith(color: secondaryColor),
      labelLarge: button.copyWith(color: primaryColor),
      labelMedium: label.copyWith(color: secondaryColor),
      labelSmall: smallCaption.copyWith(color: secondaryColor),
    );
  }
}
