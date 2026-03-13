// lib/start.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

import 'onboarding_1.dart';
import 'onboarding_flow.dart';
import 'main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 기본: 네비바/상태바 숨김, 스와이프 시 잠깐 보였다가 자동 숨김
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashDecider(),
    );
  }
}

class SplashDecider extends StatefulWidget {
  const SplashDecider({super.key});
  @override
  State<SplashDecider> createState() => _SplashDeciderState();
}

class _SplashDeciderState extends State<SplashDecider>
    with WidgetsBindingObserver {
  bool _navigated = false; // 중복 네비게이션 방지

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _applyImmersive(); // 혹시 모를 복원 대비
    // 첫 프레임 이후에 체크 (Timer 대신 안전하게)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLoginAndNavigate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyImmersive();
    }
  }

  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  Future<void> _checkLoginAndNavigate() async {
    // 어떤 경우에도 반드시 한 번만 이동
    void safeReplace(Widget page) {
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
    }

    try {
      final user = FirebaseAuth.instance.currentUser;

      // 미로그인 → 온보딩(첫 페이지)
      if (user == null) {
        safeReplace(const OnboardingPage());
        return;
      }

      // 로그인됨 → users/{uid} 문서 확인
      final ref =
      FirebaseFirestore.instance.collection('users').doc(user.uid);

      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await ref.get();
      } on FirebaseException catch (e) {
        // 권한 거부 등 발생 시 온보딩 플로우로 유도 (앱이 멈추지 않도록)
        debugPrint('Firestore get() error: ${e.code} ${e.message}');
        safeReplace(const OnboardingFlowPage());
        return;
      }

      final data = snap.data();
      final completed = (data != null && data['onboardingComplete'] == true);

      // 문서가 없으면 만들어두고(실패해도 무시) 온보딩 플로우로
      if (!snap.exists) {
        try {
          await ref.set({
            'onboardingComplete': false,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('users doc create skipped: $e');
        }
        safeReplace(const OnboardingFlowPage());
        return;
      }

      // 완료 여부에 따라 분기
      if (completed) {
        safeReplace(const NutritionHomePage());
      } else {
        safeReplace(const OnboardingFlowPage());
      }
    } catch (e) {
      // 어떤 예외든 마지막 안전망: 온보딩 플로우로 이동
      debugPrint('SplashDecider fatal: $e');
      safeReplace(const OnboardingFlowPage());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 로고 스플래시
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SvgPicture.asset(
          'assets/apple.svg',
          width: 120,
          height: 120,
        ),
      ),
    );
  }
}
