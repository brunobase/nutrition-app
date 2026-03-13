// lib/signup_2.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login.dart';
import 'signup_1.dart';

class Signup2 extends StatefulWidget {
  final File? profileImage;
  const Signup2({Key? key, this.profileImage}) : super(key: key);

  @override
  State<Signup2> createState() => _Signup2State();
}

class _Signup2State extends State<Signup2> {
  final _auth = FirebaseAuth.instance;
  late final FirebaseFirestore _firestore;
  User? _user;
  bool _isChecking = false;
  bool _isSending = false;
  bool _savedOnce = false;                // ✅ 중복 저장 방지
  DateTime? _lastResendTime;
  static const _primaryColor = Color(0xFF24C486);

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _firestore = FirebaseFirestore.instance;

    if (_user != null && !_user!.emailVerified) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _user!.sendEmailVerification();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('인증 메일을 발송했습니다.')),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('메일 발송 실패: $e')),
          );
        }
      });
    }
  }

  Future<void> _handleBack() async {
    try { await _auth.signOut(); } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SignupPage()),
    );
  }

  Future<void> _checkVerification() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    await _user?.reload();
    _user = _auth.currentUser;

    final verified = _user?.emailVerified == true;
    if (verified) {
      // ✅ 보안: 인증 + 중복 방지
      if (_savedOnce) {
        setState(() => _isChecking = false);
        return;
      }
      _savedOnce = true;

      final uid = _user!.uid;
      String? profileUrl;

      if (widget.profileImage != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('user_profiles')
            .child('$uid.jpg');
        await ref.putFile(widget.profileImage!);
        profileUrl = await ref.getDownloadURL();
        await _user!.updatePhotoURL(profileUrl);
      }

      await _firestore.collection('users').doc(uid).set({
        'name': _user!.displayName ?? '',
        'email': _user!.email ?? '',
        if (profileUrl != null) 'profileUrl': profileUrl,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메일함에서 인증 링크를 눌러주세요.')),
        );
      }
    }

    if (mounted) setState(() => _isChecking = false);
  }

  Future<void> _resendEmail() async {
    final now = DateTime.now();
    if (_lastResendTime != null &&
        now.difference(_lastResendTime!).inMinutes < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('잠시 후 다시 시도해주세요.')),
      );
      return;
    }
    if (_isSending) return;
    setState(() => _isSending = true);

    try {
      await _user?.sendEmailVerification();
      _lastResendTime = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증 메일을 다시 보냈습니다.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'too-many-requests') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('요청이 많아 잠시 차단되었습니다. 나중에 시도해주세요.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('재전송 실패: ${e.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('재전송 오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? '';
    return WillPopScope(
      onWillPop: () async { await _handleBack(); return false; },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('이메일 인증',
              style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500)),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: _handleBack,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '가입하신 이메일로 계정 활성화 링크를 보냈습니다.\n메일함에서 링크를 클릭한 뒤 아래 버튼을 눌러 인증을 완료해주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black),
              ),
              const SizedBox(height: 24),
              Text(email,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _primaryColor),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _checkVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isChecking
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('인증 완료 확인', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isSending ? null : _resendEmail,
                child: _isSending
                    ? const CircularProgressIndicator()
                    : const Text('다시 보내기', style: TextStyle(fontSize: 14, color: _primaryColor)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
