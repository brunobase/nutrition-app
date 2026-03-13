// lib/onboarding_2.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login.dart';             // LoginPage 연결
import 'signup_1.dart';         // SignupPage 연결
import 'onboarding_flow.dart';  // 온보딩 플로우 진입
import 'main.dart';             // NutritionHomePage 정의된 파일

// ✅ Firebase 콘솔(웹앱)에서 발급된 "웹 클라이언트 ID"로 교체하세요.
// 예: 1234567890-abc...def.apps.googleusercontent.com
const String kWebClientId = '218026747503-eku01ge2jt57aep2iiiuhqikr579m8dd.apps.googleusercontent.com';

class Onboarding2 extends StatefulWidget {
  const Onboarding2({super.key});

  @override
  State<Onboarding2> createState() => _Onboarding2State();
}

class _Onboarding2State extends State<Onboarding2> {
  final _auth = FirebaseAuth.instance;
  late final GoogleSignIn _googleSignIn;

  @override
  void initState() {
    super.initState();
    // ✅ serverClientId 지정 (idToken null 방지). Android는 없어도 되지만, 구성이 맞지 않으면 필요한 경우가 많음.
    _googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId: kWebClientId, // 올바른 Web Client ID 없으면 에러 10 유발 가능
    );
  }

  // ▶ 애니메이션 없는 라우트 헬퍼
  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  /// 구글 로그인 처리 후 DB에 onboardingComplete 확인
  Future<void> _signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // 사용자가 취소

      final googleAuth = await googleUser.authentication;

      // ✅ 가장 흔한 실패: idToken == null → SHA/구성/웹 클라이언트 ID 문제
      if (googleAuth.idToken == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '구글 로그인 구성 오류: idToken이 없습니다.\n'
                  'Firebase에 SHA 지문을 등록하고 google-services.json을 교체한 뒤,\n'
                  '웹 클라이언트 ID를 확인하세요.',
            ),
          ),
        );
        return;
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await _auth.signInWithCredential(credential);
      final uid = userCred.user?.uid;
      if (uid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증에 실패했습니다. 다시 시도해주세요.')),
        );
        return;
      }

      // Firestore에서 온보딩 완료 여부 확인
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      final hasBodyInfo =
          data != null && data['onboardingComplete'] == true;

      if (!mounted) return;
      if (hasBodyInfo) {
        Navigator.pushReplacement(
            context, _noAnim(const NutritionHomePage()));
      } else {
        Navigator.pushReplacement(
            context, _noAnim(const OnboardingFlowPage()));
      }
    } on FirebaseAuthException catch (e) {
      final msg = _mapAuthErrorToKo(e.code, e.message);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      // ApiException: 10 → DEVELOPER_ERROR (SHA/패키지명/클라이언트ID 불일치)
      final isDevErr = e.toString().contains('ApiException: 10');
      final msg = isDevErr
          ? '구글 로그인 설정 오류(코드 10). SHA-1/256 등록, google-services.json 교체,\n'
          '웹 클라이언트 ID(serverClientId) 확인 후 다시 빌드하세요.'
          : '구글 로그인 에러: $e';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _mapAuthErrorToKo(String? code, String? message) {
    switch (code) {
      case 'account-exists-with-different-credential':
        return '해당 이메일로 다른 로그인 방식이 이미 연결되어 있습니다.';
      case 'invalid-credential':
        return '자격 증명이 유효하지 않습니다. 다시 시도해주세요.';
      case 'operation-not-allowed':
        return '구글 로그인이 비활성화되어 있습니다. 콘솔 설정을 확인하세요.';
      case 'user-disabled':
        return '이 계정은 사용 중지되었습니다.';
      case 'network-request-failed':
        return '네트워크 오류가 발생했습니다. 연결을 확인해주세요.';
      default:
        return '인증 오류(${code ?? 'unknown'}): ${message ?? ''}';
    }
  }

  void _showLoginOptions(BuildContext context) {
    const hp = 20.0, vp = 16.0;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withAlpha(102),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: _signInWithGoogle,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding:
                const EdgeInsets.symmetric(horizontal: hp, vertical: vp),
                minimumSize: const Size(double.infinity, 50),
                elevation: 0,
                side: const BorderSide(color: Colors.grey),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset('assets/google_logo.svg',
                      width: 24, height: 24),
                  const SizedBox(width: 12),
                  const Text('구글로 로그인', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context); // 바텀시트 닫기
                Navigator.push(
                    context, _noAnim(const LoginPage())); // 즉시 전환
              },
              icon: const Icon(Icons.mail_outline, size: 28),
              label: const Text('이메일로 로그인'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding:
                const EdgeInsets.symmetric(horizontal: hp, vertical: vp),
                minimumSize: const Size(double.infinity, 50),
                elevation: 0,
                side: const BorderSide(color: Colors.grey),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF24C486);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/apple.svg',
                      width: 100,
                      height: 100,
                      colorFilter: const ColorFilter.mode(
                          primaryColor, BlendMode.srcIn),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '환영합니다',
                      style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '계정을 생성하거나 로그인하세요',
                      style:
                      TextStyle(fontSize: 14, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // ▶ 변경: 상단 큰 버튼 = "로그인" (로그인 옵션 바텀시트)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _showLoginOptions(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text(
                    '로그인',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('계정이 없으신가요?'),
                  // ▶ 변경: 하단 텍스트 버튼 = "회원가입"
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                          context, _noAnim(const SignupPage()));
                    },
                    child: const Text('회원가입',
                        style: TextStyle(color: primaryColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
