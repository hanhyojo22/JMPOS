import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  const AppTypography._();

  static TextStyle get pageTitle =>
      GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, height: 1.2);

  static TextStyle get largePageTitle =>
      GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2);

  static TextStyle get sectionTitle => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static TextStyle get cardTitle => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static TextStyle get productName =>
      GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, height: 1.3);

  static TextStyle get body => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static TextStyle get emphasizedBody => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static TextStyle get price =>
      GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, height: 1.2);

  static TextStyle get largePrice =>
      GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, height: 1.2);

  static TextStyle get total => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );

  static TextStyle get largeTotal => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );

  static TextStyle get label => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static TextStyle get helperText => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  static TextStyle get smallCaption => helperText;

  static TextStyle get button =>
      GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2);

  static TextStyle get heroAmount => largeTotal;

  static TextStyle get primaryAmount => largeTotal;

  static TextTheme textTheme({
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    final base = GoogleFonts.interTextTheme();
    return base.copyWith(
      displayLarge: largeTotal.copyWith(color: primaryColor),
      displayMedium: total.copyWith(color: primaryColor),
      headlineMedium: largePageTitle.copyWith(color: primaryColor),
      headlineSmall: pageTitle.copyWith(color: primaryColor),
      titleLarge: sectionTitle.copyWith(color: primaryColor),
      titleMedium: cardTitle.copyWith(color: primaryColor),
      titleSmall: productName.copyWith(color: primaryColor),
      bodyLarge: body.copyWith(color: primaryColor),
      bodyMedium: body.copyWith(color: primaryColor),
      bodySmall: caption.copyWith(color: secondaryColor),
      labelLarge: button.copyWith(color: primaryColor),
      labelMedium: label.copyWith(color: secondaryColor),
      labelSmall: helperText.copyWith(color: secondaryColor),
    );
  }
}
