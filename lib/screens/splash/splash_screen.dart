// lib/screens/splash/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/db/database.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    final done = await AppDatabase.instance.getSetting('onboarding_done');
    context.go(done != null ? '/' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg0,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color:  AppColors.goldDim,
          border: Border.all(color: AppColors.gold, width: 1.5)),
        child: const Center(child: Text('⚔️', style: TextStyle(fontSize: 32))),
      ).animate().fadeIn(duration: 600.ms).scale(begin: const Offset(.85, .85)),
      const SizedBox(height: 24),
      const Text('三省六部', style: TextStyle(
        fontFamily: 'NotoSerifSC', fontSize: 28, fontWeight: FontWeight.w900,
        color: AppColors.gold2, letterSpacing: 6,
      )).animate(delay: 300.ms).fadeIn(duration: 500.ms).slideY(begin: .15),
      const SizedBox(height: 6),
      const Text('× InkOS · AI 网文创作', style: TextStyle(
        fontFamily: 'JetBrainsMono', fontSize: 11,
        color: AppColors.text3, letterSpacing: 3,
      )).animate(delay: 500.ms).fadeIn(duration: 400.ms),
      const SizedBox(height: 40),
      const Text('本地运行 · 直连 LLM · 无需服务器', style: TextStyle(
        fontFamily: 'JetBrainsMono', fontSize: 9,
        color: AppColors.text3, letterSpacing: 2,
      )).animate(delay: 700.ms).fadeIn(duration: 400.ms),
    ])),
  );
}
