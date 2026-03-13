// lib/signup_1.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import 'onboarding_2.dart';
import 'signup_2.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({Key? key}) : super(key: key);
  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  // Controllers & FocusNodes
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _pwFocus = FocusNode();

  // UI State
  bool _nameFocused = false;
  bool _emailFocused = false;
  bool _pwFocused = false;
  bool _showPw = false;
  bool _isValid = false;
  bool _isLoading = false;
  bool _emailError = false;

  // Profile image
  File? _profileImage;
  final _picker = ImagePicker();

  static const _primaryColor = Color(0xFF24C486);

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() => setState(() => _nameFocused = _nameFocus.hasFocus));
    _emailFocus.addListener(() => setState(() => _emailFocused = _emailFocus.hasFocus));
    _pwFocus.addListener(() => setState(() => _pwFocused = _pwFocus.hasFocus));

    _nameCtrl.addListener(_validate);
    _pwCtrl.addListener(_validate);
    _emailCtrl.addListener(() {
      if (_emailError) setState(() => _emailError = false);
      _validate();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  void _validate() {
    final valid = _nameCtrl.text.trim().isNotEmpty &&
        _emailCtrl.text.trim().isNotEmpty &&
        _pwCtrl.text.trim().isNotEmpty;
    if (valid != _isValid) setState(() => _isValid = valid);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) setState(() => _profileImage = File(picked.path));
    Navigator.of(context).pop();
  }

  void _showPickOptions() {
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
              onPressed: () => _pickImage(ImageSource.camera),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: hp, vertical: vp),
                minimumSize: const Size(double.infinity, 50),
                elevation: 0,
                side: const BorderSide(color: Colors.grey),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.camera_alt, size: 24),
                  SizedBox(width: 12),
                  Text('사진 찍기', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _pickImage(ImageSource.gallery),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: hp, vertical: vp),
                minimumSize: const Size(double.infinity, 50),
                elevation: 0,
                side: const BorderSide(color: Colors.grey),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.photo_library, size: 24),
                  SizedBox(width: 12),
                  Text('갤러리에서 선택', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (!_isValid) return;

    setState(() {
      _isLoading = true;
      _emailError = false;
    });

    final email = _emailCtrl.text.trim();
    final password = _pwCtrl.text.trim();

    try {
      // 1) 계정 생성
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      // 2) 프로필 이름 업데이트
      await cred.user!.updateDisplayName(_nameCtrl.text.trim());

      // 3) 이메일 인증 메일 발송
      await cred.user!.sendEmailVerification();

      // 4) 인증 페이지로 이동
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => Signup2(profileImage: _profileImage),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('요청이 너무 많습니다. 잠시 후 다시 시도해주세요.')),
        );
      } else if (e.code == 'email-already-in-use') {
        setState(() => _emailError = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? '오류가 발생했습니다')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('서버 오류: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailBorderColor =
    _emailError ? Colors.red : (_emailFocused ? _primaryColor : Colors.grey);

    return Scaffold(
      // 키보드가 올라올 때 화면을 자동으로 올려서 가리지 않도록
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('계정 생성', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const Onboarding2()),
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        // ⬇️ 프로필 아이콘 주변 여백(특히 상단)을 줄여서 전체 레이아웃을 위로 올림
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
        child: Column(
          children: [
            // ⬇️ 원래 32였던 상단 공백 제거
            const SizedBox(height: 8),
            // 프로필 선택 UI
            GestureDetector(
              onTap: _showPickOptions,
              child: Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[200],
                      backgroundImage:
                      _profileImage != null ? FileImage(_profileImage!) : null,
                      child: _profileImage == null
                          ? const Icon(Icons.person, size: 60, color: Colors.grey)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.camera_alt,
                          color: Colors.grey[800],
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ⬇️ 아이콘 아래 여백도 살짝 줄임(기존 32 → 16)
            const SizedBox(height: 16),
            // 이름 입력
            TextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '이름',
                labelStyle:
                TextStyle(color: _nameFocused ? _primaryColor : Colors.grey),
                prefixIcon: Icon(Icons.person,
                    color: _nameFocused ? _primaryColor : Colors.grey),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primaryColor),
                ),
              ),
              cursorColor: _primaryColor,
            ),
            const SizedBox(height: 16),
            // 이메일 입력
            TextField(
              controller: _emailCtrl,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '이메일',
                labelStyle: TextStyle(color: emailBorderColor),
                prefixIcon: Icon(Icons.email, color: emailBorderColor),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: emailBorderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: emailBorderColor),
                ),
              ),
              cursorColor: _primaryColor,
            ),
            if (_emailError) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '이미 사용 중인 이메일입니다',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // 비밀번호 입력
            TextField(
              controller: _pwCtrl,
              focusNode: _pwFocus,
              obscureText: !_showPw,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '비밀번호',
                labelStyle:
                TextStyle(color: _pwFocused ? _primaryColor : Colors.grey),
                prefixIcon:
                Icon(Icons.lock, color: _pwFocused ? _primaryColor : Colors.grey),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPw ? Icons.visibility : Icons.visibility_off,
                    color: _pwFocused ? _primaryColor : Colors.grey,
                  ),
                  onPressed: () => setState(() => _showPw = !_showPw),
                ),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _primaryColor),
                ),
              ),
              cursorColor: _primaryColor,
            ),
            // 하단 여백은 유지하되, 너무 크지 않게 약간만 확보
            const SizedBox(height: 120),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isValid && !_isLoading ? _register : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isValid ? _primaryColor : Colors.grey[400],
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('계정 생성하기',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
