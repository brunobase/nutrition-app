// lib/profile.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'me.dart';
import 'onboarding_2.dart';  // '환영합니다' 페이지
import 'setting.dart';       // ✅ 설정 페이지로 이동

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key}); // ✅ super.key 사용(경고도 사라짐)

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const accentGreen = Color(0xFF24C486);

  // ▼ DB/Auth를 보고 프로필 이미지를 보여주는 위젯
  Widget _userAvatar() {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    // 로그인 전/익명일 땐 기본 아이콘
    if (uid == null) {
      return const CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey,
        child: Icon(Icons.person, size: 32, color: Colors.white),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        String? photoUrl = user?.photoURL; // 1순위: Auth 사진
        if (snap.hasData) {
          final data = snap.data!.data() ?? {};
          final profile = (data['profile'] as Map<String, dynamic>?) ?? {};
          // 2순위: Firestore profile.photoUrl -> 3순위: users.photoUrl
          final fromDb = (profile['photoUrl'] ?? data['photoUrl'])?.toString();
          if (fromDb != null && fromDb.isNotEmpty) {
            photoUrl = fromDb;
          }
        }

        return CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey,
          backgroundImage:
          (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
          child: (photoUrl == null || photoUrl.isEmpty)
              ? const Icon(Icons.person, size: 32, color: Colors.white)
              : null,
        );
      },
    );
  }

  // ✅ 알림 토글 제거됨
  bool _waterEnabled = true;
  bool _loadingSettings = true;

  String _displayName = 'user';

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // 애니메이션 없는 라우트
  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  @override
  void initState() {
    super.initState();
    _loadSettingsAndProfile();
  }

  Future<void> _loadSettingsAndProfile() async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _loadingSettings = false);
      return;
    }
    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      final settings = (data['settings'] as Map<String, dynamic>?) ?? {};

      // 이름 우선순위
      final profile = (data['profile'] as Map<String, dynamic>?) ?? {};
      String? name =
          (profile['displayName'] as String?) ??
              (profile['name'] as String?) ??
              (data['displayName'] as String?) ??
              FirebaseAuth.instance.currentUser?.displayName;

      name ??= 'user';

      setState(() {
        _displayName = name!;
        // ✅ 알림 설정 로드 제거됨
        _waterEnabled =
            (settings['waterTrackingEnabled'] as bool?) ?? _waterEnabled;
        _loadingSettings = false;
      });
    } catch (e) {
      setState(() => _loadingSettings = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('설정을 불러오지 못했습니다: $e')),
      );
    }
  }

  Future<bool> _updateSetting(String key, bool value) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'settings': {key: value}}, SetOptions(merge: true));
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
      return false;
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      _noAnim(const Onboarding2()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final emailText =
    (user?.email?.isNotEmpty == true) ? user!.email! : '익명 사용자';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black87),
        title: const Text(
          '프로필',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),

            _userAvatar(),
            const SizedBox(height: 12),

            Text(
              _displayName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),

            Text(
              emailText,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 24),

            // “나” 항목
            GestureDetector(
              onTap: () {
                Navigator.push(context, _noAnim(const MePage())); // 즉시 전환
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: accentGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: const [
                    Expanded(
                      child: Text(
                        '나',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_loadingSettings)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ),

            // 설정
            ListTile(
              leading: SvgPicture.asset('assets/setting.svg', width: 24, height: 24),
              title: const Text('설정'),
              onTap: () {
                // ✅ setting.dart의 SettingPage로 이동
                Navigator.push(context, _noAnim(const SettingPage()));
              },
            ),

            // ✅ 알림 설정 타일 제거됨

            // 물 섭취량 기록 (DB 연동)
            ListTile(
              leading: SvgPicture.asset('assets/water.svg', width: 24, height: 24),
              title: const Text('물 섭취량 기록'),
              trailing: Text(
                _waterEnabled ? '활성' : '비활성',
                style: TextStyle(
                  color: _waterEnabled ? accentGreen : Colors.grey.shade400,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                final next = !_waterEnabled;
                setState(() => _waterEnabled = next); // 낙관적 업데이트
                final ok = await _updateSetting('waterTrackingEnabled', next);
                if (!ok && mounted) setState(() => _waterEnabled = !next); // 실패 시 원복
              },
            ),

            // 로그아웃
            ListTile(
              leading: SvgPicture.asset('assets/logout.svg', width: 24, height: 24),
              title: const Text('로그아웃', style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),

            const Spacer(),
            const Text('Version: 0.0.1', style: TextStyle(color: Colors.black38)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
