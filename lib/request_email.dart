// lib/request_email.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'onboarding_2.dart'; // 환영합니다 페이지 import

/// 비밀번호 재설정 이메일 요청 페이지
class RequestEmailPage extends StatefulWidget {
  const RequestEmailPage({super.key});

  @override
  State<RequestEmailPage> createState() => _RequestEmailPageState();
}

class _RequestEmailPageState extends State<RequestEmailPage> {
  final _emailFocus = FocusNode();
  final _emailCtrl = TextEditingController();
  bool _emailFocused = false;
  bool _isLoading = false;

  static const Color primaryColor = Color(0xFF24C486);

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(() {
      setState(() {
        _emailFocused = _emailFocus.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _emailFocus.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일을 입력해주세요')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호 재설정 링크를 보냈습니다')),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Onboarding2()),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? '링크 전송에 실패했습니다')),
      );
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text(
          '비밀번호 재설정',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '이메일로 비밀번호 재설정 링크를\n전송합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black),
              ),
              const SizedBox(height: 32),
              // 이메일 입력 필드
              TextField(
                controller: _emailCtrl,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  labelText: '이메일',
                  labelStyle: TextStyle(
                    color: _emailFocused ? primaryColor : Colors.grey,
                  ),
                  prefixIcon: Icon(
                    Icons.email,
                    color: _emailFocused ? primaryColor : Colors.grey,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: primaryColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                cursorColor: primaryColor,
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 40),
              // 링크 보내기 버튼 → Onboarding2 로 이동
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendResetLink,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Colors.white))
                      : const Text(
                    '링크 보내기',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
