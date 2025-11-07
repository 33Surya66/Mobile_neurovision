import 'package:flutter/material.dart';

class AppColors {
  // Primary colors
  static const Color primary = Color(0xFF4A80F0);
  static const Color primaryDark = Color(0xFF3A6BDC);
  static const Color primaryLight = Color(0xFFE3ECFF);
  
  // Secondary colors
  static const Color secondary = Color(0xFF7C4DFF);
  static const Color secondaryDark = Color(0xFF651FFF);
  static const Color secondaryLight = Color(0xFFB388FF);
  
  // Status colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);
  
  // Text colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textLight = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Colors.white;
  
  // Background colors
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color divider = Color(0xFFE0E0E0);
  
  // Other colors
  static const Color disabled = Color(0xFFE0E0E0);
  static const Color shadow = Color(0x1F000000);
  
  // Attention level colors
  static const Color attentionHigh = Color(0xFF4CAF50);
  static const Color attentionMedium = Color(0xFFFFC107);
  static const Color attentionLow = Color(0xFFF44336);
  
  // Gradient for cards
  static LinearGradient get cardGradient => const LinearGradient(
        colors: [primary, secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      
  // Get attention color based on level (0.0 to 1.0)
  static Color getAttentionColor(double level) {
    if (level > 0.7) return attentionHigh;
    if (level > 0.4) return attentionMedium;
    return attentionLow;
  }
  
  // Get attention color with opacity
  static Color getAttentionColorWithOpacity(double level, {double opacity = 0.2}) {
    return getAttentionColor(level).withOpacity(opacity);
  }
}
