// lib/login.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'onboarding_2.dart';     // 환영합니다 페이지
import 'request_email.dart';   // 비밀번호 재설정 이메일 요청 페이지
import 'onboarding_flow.dart'; // 온보딩 플로우 페이지
import 'main.dart';            // NutritionHomePage

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl    = TextEditingController();
  final _pwCtrl       = TextEditingController();
  final _emailFocus   = FocusNode();
  final _passwordFocus= FocusNode();

  bool _emailFocused      = false;
  bool _passwordFocused   = false;
  bool _isPasswordVisible = false;
  bool _isLoading         = false;

  static const Color primaryColor = Color(0xFF24C486);

  // ▶ 애니메이션 없는 라우트 헬퍼
  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(() => setState(() => _emailFocused = _emailFocus.hasFocus));
    _passwordFocus.addListener(() => setState(() => _passwordFocused = _passwordFocus.hasFocus));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (_isLoading) return;
    final email = _emailCtrl.text.trim();
    final pw    = _pwCtrl.text;
    if (email.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일과 비밀번호를 모두 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pw);
      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'no-user', message: '유저 정보를 불러올 수 없습니다.');
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final completed = data != null && data['onboardingComplete'] == true;

      if (completed) {
        Navigator.pushReplacement(context, _noAnim(const NutritionHomePage()));
      } else {
        Navigator.pushReplacement(context, _noAnim(const OnboardingFlowPage()));
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
        if (methods.contains('google.com')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이 이메일은 구글 계정으로 이미 등록되어 있습니다.\n구글로 로그인해주세요.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('등록된 계정이 없습니다.')),
          );
        }
      } else if (e.code == 'wrong-password') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비밀번호가 틀렸습니다.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? '로그인에 실패했습니다')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류 발생: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pushReplacement(
            context,
            _noAnim(const Onboarding2()), // ▶ 즉시 전환
          ),
        ),
        title: const SizedBox.shrink(),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '로그인',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w400, color: Colors.black),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailCtrl,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                labelText: '이메일',
                labelStyle: TextStyle(color: _emailFocused ? primaryColor : Colors.grey),
                prefixIcon: Icon(Icons.email, color: _emailFocused ? primaryColor : Colors.grey),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: primaryColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              cursorColor: primaryColor,
              style: const TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pwCtrl,
              focusNode: _passwordFocus,
              obscureText: !_isPasswordVisible,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                labelText: '비밀번호',
                labelStyle: TextStyle(color: _passwordFocused ? primaryColor : Colors.grey),
                prefixIcon: Icon(Icons.lock, color: _passwordFocused ? primaryColor : Colors.grey),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    color: _passwordFocused ? primaryColor : Colors.grey,
                  ),
                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: primaryColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              cursorColor: primaryColor,
              style: const TextStyle(color: Colors.black),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('로그인', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                _noAnim(const RequestEmailPage()), // ▶ 즉시 전환
              ),
              child: const Text('비밀번호를 잊으셨나요?', style: TextStyle(color: primaryColor)),
            ),
          ],
        ),
      ),
    );
  }
}
