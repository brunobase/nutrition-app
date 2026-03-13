// lib/me.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'me_standard.dart'; // 1일 영양소 섭취기준 페이지

// ─────────────────────────────────────────────
// Typed 모델: 화면/저장 공용으로 사용
class ProfileData {
  final int year;                // 출생연도
  final double heightCm;         // 키(cm)
  final double weightKg;         // 몸무게(kg)
  final String gender;           // '남성' | '여성'
  final int waterOnceMl;         // 물 1회 섭취량(ml)
  final String activityLevel;    // '매우 적음'...'매우 많음'

  const ProfileData({
    required this.year,
    required this.heightCm,
    required this.weightKg,
    required this.gender,
    required this.waterOnceMl,
    required this.activityLevel,
  });

  // 초기 기본값 (기존 UI와 동일)
  factory ProfileData.initial() => const ProfileData(
    year: 2010,
    heightCm: 184,
    weightKg: 88,
    gender: '남성',
    waterOnceMl: 100,
    activityLevel: '보통',
  );

  ProfileData copyWith({
    int? year,
    double? heightCm,
    double? weightKg,
    String? gender,
    int? waterOnceMl,
    String? activityLevel,
  }) {
    return ProfileData(
      year: year ?? this.year,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      gender: gender ?? this.gender,
      waterOnceMl: waterOnceMl ?? this.waterOnceMl,
      activityLevel: activityLevel ?? this.activityLevel,
    );
  }

  factory ProfileData.fromMap(Map<String, dynamic> map) {
    return ProfileData(
      year: (map['year'] ?? 0) is int ? (map['year'] ?? 0) : int.tryParse('${map['year']}') ?? 0,
      heightCm: (map['heightCm'] ?? 0).toDouble(),
      weightKg: (map['weightKg'] ?? 0).toDouble(),
      gender: (map['gender'] ?? '남성').toString(),
      waterOnceMl: (map['waterOnceMl'] ?? 0) is int
          ? (map['waterOnceMl'] ?? 0)
          : int.tryParse('${map['waterOnceMl']}') ?? 0,
      activityLevel: (map['activityLevel'] ?? '보통').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'year': year,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'gender': gender,
    'waterOnceMl': waterOnceMl,
    'activityLevel': activityLevel,
  };
}
// ─────────────────────────────────────────────

class MePage extends StatefulWidget {
  const MePage({Key? key}) : super(key: key);

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  static const Color _accentGreen = Color(0xFF24C486);

  // 즉시 전환 라우트
  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  final List<String> _titles = const [
    '1일 영양소 섭취기준',
    '연도',
    '키',
    '몸무게',
    '성별',
    '물 1회 섭취량',
    '신체 활동',
  ];

  final Map<String, String> _units = const {
    '연도': '년',
    '키': 'cm',
    '몸무게': 'kg',
    '물 1회 섭취량': 'ml',
  };

  bool _saving = false;
  ProfileData _profile = ProfileData.initial();
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadProfile(); // Firestore에서 값 불러오기
  }

  Future<void> _loadProfile() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      final pMap = (data?['profile'] as Map<String, dynamic>?) ?? {};
      final settings = (data?['settings'] as Map<String, dynamic>?) ?? {};

      // settings에 저장된 1회 섭취량(ml)을 fallback으로 사용
      int? waterFromSettingsMl;
      final s1 = settings['waterPerIntakeMl'];
      final s2 = settings['waterIntakeUnitMl'];
      if (s1 is num && s1 > 0) {
        waterFromSettingsMl = s1.toInt();
      } else if (s2 is num && s2 > 0) {
        waterFromSettingsMl = s2.toInt();
      }

      final loaded = ProfileData.fromMap(pMap);
      setState(() {
        _profile = ProfileData.initial().copyWith(
          year: loaded.year == 0 ? null : loaded.year,
          heightCm: loaded.heightCm == 0 ? null : loaded.heightCm,
          weightKg: loaded.weightKg == 0 ? null : loaded.weightKg,
          gender: loaded.gender.isEmpty ? null : loaded.gender,
          waterOnceMl: (loaded.waterOnceMl == 0 && waterFromSettingsMl != null)
              ? waterFromSettingsMl
              : (loaded.waterOnceMl == 0 ? null : loaded.waterOnceMl),
          activityLevel: loaded.activityLevel.isEmpty ? null : loaded.activityLevel,
        );
      });
    } catch (e) {
      debugPrint('Profile load error: $e'); // 조용히 패스
    }
  }

  // ───────── 개인화 계산(비타민 제외) ─────────
  double _activityFactor(String a) {
    switch (a) {
      case '매우 적음':
        return 1.2;
      case '적음':
        return 1.375;
      case '보통':
        return 1.55;
      case '많음':
        return 1.725;
      case '매우 많음':
        return 1.9;
      default:
        return 1.55;
    }
  }

  int _waterGoalMl(double weightKg, String activity) {
    final base = (weightKg * 30).round();
    final add = switch (activity) {
      '매우 적음' => 0,
      '적음' => 250,
      '보통' => 500,
      '많음' => 750,
      '매우 많음' => 1000,
      _ => 500,
    };
    return base + add;
  }

  Map<String, dynamic> _makeNutritionStandard(ProfileData p) {
    final now = DateTime.now().year;
    final age = (p.year > 0 && p.year <= now) ? (now - p.year) : 30;
    final isMale = p.gender == '남성';

    // Mifflin-St Jeor BMR
    final bmr = (10 * p.weightKg) + (6.25 * p.heightCm) - (5 * age) + (isMale ? 5 : -161);

    // 유지 칼로리(TDEE)
    final tdee = (bmr * _activityFactor(p.activityLevel)).round();

    // 매크로: 단백질 1.6 g/kg(여성 1.4), 지방 0.8 g/kg, 탄수는 나머지
    final prot = (p.weightKg * (isMale ? 1.6 : 1.4));
    final fat = (p.weightKg * 0.8);
    final carb = ((tdee - (prot * 4 + fat * 9)) / 4).clamp(0, 10000);

    final waterGoalMl = _waterGoalMl(p.weightKg, p.activityLevel);

    return {
      'enerc': tdee,                                     // kcal
      'prot': double.parse(prot.toStringAsFixed(1)),     // g
      'chocdf': double.parse(carb.toStringAsFixed(1)),   // g
      'fatce': double.parse(fat.toStringAsFixed(1)),     // g
      'waterGoalMl': waterGoalMl,                        // 하루 총 물 목표(ml)
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _saveProfile() async {
    final uid = _uid;
    if (uid == null || _saving) return;
    setState(() => _saving = true);
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      // 1) profile 저장
      await userRef.set({'profile': _profile.toMap()}, SetOptions(merge: true));

      // 2) 개인화 기준 저장(비타민 제외)
      final standard = _makeNutritionStandard(_profile);
      await userRef.set({'nutritionStandard': standard}, SetOptions(merge: true));

      // 3) ✅ main.dart가 읽는 키로 1회 섭취량 저장(settings.*)
      await userRef.set({
        'settings': {
          'waterPerIntakeMl': _profile.waterOnceMl,
          'waterIntakeUnitMl': _profile.waterOnceMl, // 호환키도 함께
        }
      }, SetOptions(merge: true));

      // ✅ 요구사항: 저장 후 아무 메시지도 띄우지 않음 (SnackBar 제거)
      // (필요 시 debugPrint 정도만 남김)
      debugPrint('Profile saved (silent).');
    } catch (e) {
      // 에러도 메시지 없이 조용히 처리
      debugPrint('Save profile error (silent): $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ───────── 입력/선택 시트 ─────────
  void _showInputSheet(String title) {
    String text = switch (title) {
      '연도' => _profile.year.toString(),
      '키' => _trimZero(_profile.heightCm),
      '몸무게' => _trimZero(_profile.weightKg),
      '물 1회 섭취량' => _profile.waterOnceMl.toString(),
      _ => '',
    };
    final controller = TextEditingController(text: text);
    final unit = _units[title] ?? '';
    final isDecimal = (title == '키' || title == '몸무게');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 0),
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
                    decoration: const InputDecoration(
                      suffixStyle: TextStyle(color: Colors.black54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.transparent),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.transparent),
                      ),
                    ).copyWith(suffixText: unit),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          switch (title) {
                            case '연도':
                              _profile = _profile.copyWith(
                                year: int.tryParse(controller.text) ?? _profile.year,
                              );
                              break;
                            case '키':
                              _profile = _profile.copyWith(
                                heightCm: double.tryParse(controller.text) ?? _profile.heightCm,
                              );
                              break;
                            case '몸무게':
                              _profile = _profile.copyWith(
                                weightKg: double.tryParse(controller.text) ?? _profile.weightKg,
                              );
                              break;
                            case '물 1회 섭취량':
                              _profile = _profile.copyWith(
                                waterOnceMl: int.tryParse(controller.text) ?? _profile.waterOnceMl,
                              );
                              break;
                          }
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '완료',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOptionSheet(String title, List<String> options) {
    String current = switch (title) {
      '성별' => _profile.gender,
      '신체 활동' => _profile.activityLevel,
      _ => '',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 0),
        curve: Curves.linear,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
            child: StatefulBuilder(
              builder: (ctx2, setSheetState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 100,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...options.map((opt) {
                      final sel = current == opt;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: InkWell(
                          onTap: () {
                            setSheetState(() => current = opt);
                            setState(() {
                              if (title == '성별') {
                                _profile = _profile.copyWith(gender: opt);
                              } else if (title == '신체 활동') {
                                _profile = _profile.copyWith(activityLevel: opt);
                              }
                            });
                          },
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: sel ? _accentGreen : Colors.grey.shade300,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              opt,
                              style: TextStyle(
                                fontSize: 14,
                                color: sel ? _accentGreen : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            '완료',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ───────── 표시 helpers ─────────
  String _displayValue(String title) {
    final unit = _units[title];
    final core = switch (title) {
      '연도' => _profile.year.toString(),
      '키' => _trimZero(_profile.heightCm),
      '몸무게' => _trimZero(_profile.weightKg),
      '성별' => _profile.gender,
      '물 1회 섭취량' => _profile.waterOnceMl.toString(),
      '신체 활동' => _profile.activityLevel,
      _ => '',
    };
    return unit == null || unit.isEmpty ? core : '$core $unit';
  }

  String _trimZero(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black87),
        title: const Text(
          '나',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // 🔹 회색 구분선 제거: ListView.builder (Separator 없음)
              child: ListView.builder(
                itemCount: _titles.length,
                itemBuilder: (ctx, idx) {
                  final title = _titles[idx];
                  final isStandard = title == '1일 영양소 섭취기준';
                  final isGender = title == '성별';
                  final isActivity = title == '신체 활동';

                  return InkWell(
                    onTap: isStandard
                        ? () => Navigator.push(
                      context,
                      _noAnim(const MeStandardPage()), // 즉시 전환
                    )
                        : isGender
                        ? () => _showOptionSheet('성별', ['남성', '여성'])
                        : isActivity
                        ? () => _showOptionSheet(
                      '신체 활동',
                      ['매우 적음', '적음', '보통', '많음', '매우 많음'],
                    )
                        : () => _showInputSheet(title),
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      color: Colors.white,
                      child: Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontSize: 16, color: Colors.black87),
                          ),
                          const Spacer(),
                          if (!isStandard)
                            Text(
                              _displayValue(title),
                              style: const TextStyle(fontSize: 16, color: _accentGreen),
                            ),
                          if (isStandard)
                            const Icon(Icons.chevron_right, size: 20, color: _accentGreen),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveProfile, // Firestore 저장 + 기준 반영
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                      : const Text(
                    '저장',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
