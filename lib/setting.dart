// lib/setting.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'request_email.dart'; // 비밀번호 재설정 이메일 전송 화면
import 'onboarding_2.dart';  // 탈퇴 후 이동

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  static const Color accentGreen = Color(0xFF24C486);

  // 애니메이션 없는 라우트
  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  // ====== 공통 다이얼로그 UI (nutrition.dart 스타일) ======
  Future<T?> _showStyledDialog<T>({
    required Widget child,
    bool barrierDismissible = true,
    String? barrierLabel,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierLabel: barrierLabel ?? 'dialog',
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: child,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, __, ___, child) => child,
    );
  }

  Future<String?> _showTextInputDialog({
    required String title,
    required String hint,
    String initial = '',
    bool obscure = false,
    String confirmText = '확인',
    String cancelText = '취소',
  }) async {
    final ctrl = TextEditingController(text: initial);
    final focus = FocusNode();
    String value = initial;

    return _showStyledDialog<String?>(
      barrierDismissible: false,
      barrierLabel: 'input',
      child: StatefulBuilder(builder: (dCtx, setD) {
        final focused = focus.hasFocus;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              focusNode: focus,
              obscureText: obscure,
              onChanged: (v) => value = v,
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: accentGreen, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: accentGreen, width: 2),
                ),
                prefixIcon: Icon(
                  obscure ? Icons.lock : Icons.badge,
                  color: focused ? accentGreen : Colors.grey,
                ),
              ),
              cursorColor: accentGreen,
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dCtx).pop(null),
                  child: const Text('취소', style: TextStyle(color: Colors.black54)),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () => Navigator.of(dCtx).pop(value.trim()),
                  child: const Text('확인', style: TextStyle(color: Colors.black87)),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    String confirmText = '확인',
    String cancelText = '취소',
    Color confirmColor = Colors.red,
  }) async {
    final ok = await _showStyledDialog<bool>(
      barrierDismissible: true,
      barrierLabel: 'confirm',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소', style: TextStyle(color: Colors.black54)),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  confirmText,
                  style: TextStyle(color: confirmColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ───────────────── 이름 변경 ─────────────────
  Future<void> _changeDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }

    final current = user.displayName ?? user.email ?? '';
    final newName = await _showTextInputDialog(
      title: '이름 변경',
      hint: '새 이름을 입력하세요',
      initial: current,
      obscure: false,
      confirmText: '저장',
      cancelText: '취소',
    );
    if (newName == null) return;
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이름을 입력해주세요.')));
      return;
    }

    try {
      await user.updateDisplayName(newName); // Auth
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'displayName': newName,
        'profile': {'displayName': newName}
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이름이 변경되었습니다.')));
      setState(() {});
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? '변경 실패')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  // ───────────────── 비밀번호 재설정 화면 이동 ─────────────────
  void _goToPasswordReset() {
    Navigator.push(context, _noAnim(const RequestEmailPage()));
  }

  // ───────────────── 계정/데이터 “완전 삭제” ─────────────────
  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }

    final ok = await _showConfirmDialog(
      title: '계정 삭제',
      message: '정말 계정을 삭제하시겠어요? 이 작업은 되돌릴 수 없습니다.',
      confirmText: '삭제',
      cancelText: '취소',
      confirmColor: Colors.red,
    );
    if (!ok) return;

    final needPasswordReauth = user.providerData.any((p) => p.providerId == 'password');
    if (needPasswordReauth) {
      final pw = await _askPassword();
      if (pw == null) return;
      try {
        final email = user.email!;
        final cred = EmailAuthProvider.credential(email: email, password: pw);
        await user.reauthenticateWithCredential(cred);
      } on FirebaseAuthException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? '재인증에 실패했습니다.')),
        );
        return;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _deleteUserTree(user.uid);
      await user.delete();

      if (!mounted) return;
      Navigator.of(context).pop(); // progress
      Navigator.of(context).pushAndRemoveUntil(
        _noAnim(const Onboarding2()),
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) Navigator.of(context).pop();
      final msg = (e.code == 'requires-recent-login')
          ? '보안을 위해 최근 로그인 후 다시 시도해주세요.'
          : (e.message ?? '계정 삭제에 실패했습니다.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  /// 비밀번호 입력 다이얼로그(커스텀)
  Future<String?> _askPassword() async {
    return _showTextInputDialog(
      title: '재인증',
      hint: '현재 비밀번호',
      initial: '',
      obscure: true,
      confirmText: '확인',
      cancelText: '취소',
    );
  }

  /// users/{uid} 트리를 전부 삭제
  Future<void> _deleteUserTree(String uid) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    // daily
    final dailySnap = await userRef.collection('daily').get();
    for (final d in dailySnap.docs) {
      await _deleteAllDocs(d.reference.collection('foods'));
      final mealsSnap = await d.reference.collection('meals').get();
      for (final m in mealsSnap.docs) {
        await _deleteAllDocs(m.reference.collection('foods'));
        await m.reference.delete();
      }
      await d.reference.delete();
    }

    // meals(루트)
    final mealsRoot = await userRef.collection('meals').get();
    for (final m in mealsRoot.docs) {
      await _deleteAllDocs(m.reference.collection('foods'));
      await m.reference.delete();
    }

    // (있으면) users/{uid}/foods/*
    await _deleteAllDocs(userRef.collection('foods'));

    // 마지막에 users/{uid} 문서 삭제
    await userRef.delete();
  }

  /// 컬렉션 내 모든 문서 삭제(batch)
  Future<void> _deleteAllDocs(CollectionReference col, {int batchSize = 300}) async {
    while (true) {
      final qs = await col.limit(batchSize).get();
      if (qs.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in qs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black87),
        centerTitle: true,
        title: const Text(
          '설정',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),

            // profile.dart 톤과 맞춘 타일 / 아이콘 색상 규칙 적용
            ListTile(
              leading: _svgOrIcon(
                'assets/profile_edit.svg',
                color: accentGreen,
                fallback: Icon(Icons.badge, color: accentGreen), // << const 제거
              ),
              title: const Text('이름 변경'),
              trailing: const Icon(Icons.chevron_right, color: Colors.black38),
              onTap: _changeDisplayName,
            ),
            ListTile(
              leading: _svgOrIcon(
                'assets/lock.svg',
                color: accentGreen,
                fallback: Icon(Icons.lock_reset, color: accentGreen), // << const 제거
              ),
              title: const Text('비밀번호 재설정'),
              trailing: const Icon(Icons.chevron_right, color: Colors.black38),
              onTap: _goToPasswordReset,
            ),
            ListTile(
              leading: _svgOrIcon(
                'assets/logout.svg',
                color: Colors.red,
                fallback: const Icon(Icons.delete_forever, color: Colors.red),
              ),
              title: const Text('계정 삭제', style: TextStyle(color: Colors.red)),
              onTap: _deleteAccount,
            ),

            const Spacer(),
            const Text('Version: 0.0.1', style: TextStyle(color: Colors.black38)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // 색상 지정 가능한 SVG 헬퍼 (없으면 fallback)
  Widget _svgOrIcon(String asset, {required Color color, required Widget fallback}) {
    return SvgPicture.asset(
      asset,
      width: 24,
      height: 24,
      color: color,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => fallback,
    );
  }
}
