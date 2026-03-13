// lib/onboarding_flow.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';             // NutritionHomePage

void main() {
  runApp(const MaterialApp(
    home: OnboardingFlowPage(),
    debugShowCheckedModeBanner: false,
  ));
}

class OnboardingFlowPage extends StatefulWidget {
  const OnboardingFlowPage({Key? key}) : super(key: key);

  @override
  State<OnboardingFlowPage> createState() => _OnboardingFlowPageState();
}

class _OnboardingFlowPageState extends State<OnboardingFlowPage> {
  final PageController _pageController = PageController();
  int _current = 0;

  int?    _birthYear;
  double? _height;
  double? _weight;
  String? _gender;          // '남성' | '여성'
  String? _activityLevel;

  late final List<Widget> _steps;

  // ▶ 애니메이션 없는 라우트
  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  @override
  void initState() {
    super.initState();
    _steps = [
      _YearStep(
        onSaved: (year) => _birthYear = year,
        onNext: _next,
      ),
      _HeightStep(
        onSaved: (h) => _height = h,
        onPrev: _prev,
        onNext: _next,
      ),
      _WeightStep(
        onSaved: (w) => _weight = w,
        onPrev: _prev,
        onNext: _next,
      ),
      _GenderStep(
        onSaved: (g) => _gender = g, // '남성' 또는 '여성'
        onPrev: _prev,
        onNext: _next,
      ),
      _ActiveStep(
        onSaved: (a) => _activityLevel = a,
        onPrev: _prev,
        onNext: _finish,
      ),
    ];
  }

  // ▶ 스텝 이동도 즉시 전환
  void _next() {
    FocusScope.of(context).unfocus();
    if (_current < _steps.length - 1) {
      _pageController.jumpToPage(_current + 1);
    }
  }

  void _prev() {
    if (_current > 0) {
      _pageController.jumpToPage(_current - 1);
    }
  }

  /// -----------------------------
  /// ✅ 온보딩 완료 → 기준 계산 & 저장
  /// -----------------------------
  Future<void> _finish() async {
    FocusScope.of(context).unfocus();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 입력값 가드
    final birthYear = _birthYear ?? DateTime.now().year - 30;
    final heightCm  = _height ?? 170.0;
    final weightKg  = _weight ?? 65.0;
    final gender    = _gender ?? '남성';
    final activity  = _activityLevel ?? '보통';

    // 1) 개인화 영양 기준(비타민 포함) 계산
    final standard = NutritionStandard.compute(
      birthYear: birthYear,
      heightCm: heightCm,
      weightKg: weightKg,
      genderKo: gender,        // '남성' | '여성'
      activityKo: activity,    // '매우 적음'..'매우 많음'
    );

    // 2) 물 목표(개인화) 계산
    final waterGoalMl = HydrationStandard.computeWaterGoalMl(
      weightKg: weightKg,
      activityKo: activity,
    );

    // 3) 사용자 프로필(호환 키 포함)
    final profile = {
      'year': birthYear,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'gender': gender,            // '남성' | '여성'
      'waterOnceMl': 200,          // 기본값
      'activityLevel': activity,
    };

    // 4) Firestore 저장 (기존 스키마 + 기준 추가)
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      // 호환 필드(기존 코드 대비)
      'birthYear': birthYear,
      'height': heightCm,
      'weight': weightKg,
      'gender': gender,
      'activityLevel': activity,

      // MePage 연동용
      'profile': profile,
      'onboardingComplete': true,

      // ✅ 개인화 영양 기준(비타민 포함, API 필드명 기준)
      'nutritionStandard': standard.toApiFieldMap(),

      // ✅ 물 섭취 목표: 개인화 결과 저장
      'waterGoalMl': waterGoalMl,
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.pushReplacement(context, _noAnim(const NutritionHomePage()));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(), // ▶ 스와이프 애니도 차단
          itemCount: _steps.length,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder: (_, i) => _steps[i],
        ),
      ),
    );
  }
}

/// ------------------------------------------------------
/// ✅ NutritionStandard: 비타민 포함 개인화 기준 계산 모듈
/// ------------------------------------------------------
class NutritionStandard {
  final int enerc;           // kcal
  final double chocdf;       // 탄수화물 g
  final double prot;         // 단백질 g
  final double fatce;        // 지방 g
  final double fibtg;        // 식이섬유 g
  final double sugar;        // 당류 g (상한)
  final int nat;             // 나트륨 mg (상한)
  final int ca;              // 칼슘 mg
  final int fe;              // 철 mg (여성 가중)
  final int k;               // 칼륨 mg
  final int p;               // 인 mg
  final int chole;           // 콜레스테롤 mg (상한)
  final double fasat;        // 포화지방 g (상한)
  final double fatrn;        // 트랜스지방 g (상한)

  // 비타민(권장량)
  final double vitaRae;      // 비타민A μgRAE
  final double retol;        // 레티놀 μg (참조용 0)
  final double cartb;        // 베타카로틴 μg (참조용 0)
  final double thia;         // B1 mg
  final double ribf;         // B2 mg
  final double nia;          // 니아신 mgNE
  final double vitc;         // C mg
  final double vitd;         // D μg

  // 참조용 매크로 비율(퍼센트)
  final int carbPct;
  final int proteinPct;
  final int fatPct;

  NutritionStandard({
    required this.enerc,
    required this.chocdf,
    required this.prot,
    required this.fatce,
    required this.fibtg,
    required this.sugar,
    required this.nat,
    required this.ca,
    required this.fe,
    required this.k,
    required this.p,
    required this.chole,
    required this.fasat,
    required this.fatrn,
    required this.vitaRae,
    required this.retol,
    required this.cartb,
    required this.thia,
    required this.ribf,
    required this.nia,
    required this.vitc,
    required this.vitd,
    required this.carbPct,
    required this.proteinPct,
    required this.fatPct,
  });

  Map<String, dynamic> toApiFieldMap() => {
    'enerc': enerc,
    'chocdf': _round1(chocdf),
    'prot': _round1(prot),
    'fatce': _round1(fatce),
    'fibtg': _round1(fibtg),
    'sugar': _round1(sugar),
    'nat': nat,
    'ca': ca,
    'fe': fe,
    'k': k,
    'p': p,
    'chole': chole,
    'fasat': _round1(fasat),
    'fatrn': _round1(fatrn),

    // 비타민
    'vita_rae': _round1(vitaRae), // 비타민A(RAE)
    'vitb1': _round1(thia),
    'vitb2': _round1(ribf),
    'vitb3': _round1(nia),
    'vitc': _round1(vitc),
    'vitd': _round1(vitd),

    // 참고용 비율
    'macroRatio': {
      'carb': carbPct,
      'protein': proteinPct,
      'fat': fatPct,
    },

    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// 메인 계산
  static NutritionStandard compute({
    required int birthYear,
    required double heightCm,
    required double weightKg,
    required String genderKo,     // '남성' | '여성'
    required String activityKo,   // '매우 적음'..'매우 많음'
  }) {
    final nowYear = DateTime.now().year;
    final age = (nowYear - birthYear).clamp(10, 100); // 안전 가드

    // 1) BMR (Mifflin-St Jeor)
    final bool isMale = genderKo == '남성';
    final bmr = isMale
        ? 10 * weightKg + 6.25 * heightCm - 5 * age + 5
        : 10 * weightKg + 6.25 * heightCm - 5 * age - 161;

    // 2) 활동계수
    final activityFactor = _activityFactor(activityKo);

    // 3) TDEE
    final tdee = (bmr * activityFactor);
    final enerc = _round10(tdee); // 10kcal 단위 반올림

    // 4) 활동량별 매크로 비율
    final (carbPct, proteinPct, fatPct) = _macroRatio(activityKo);

    // 5) g 환산
    final carbG = enerc * (carbPct / 100) / 4.0;
    final proteinG = enerc * (proteinPct / 100) / 4.0;
    final fatG = enerc * (fatPct / 100) / 9.0;

    // 6) 기타 권장/상한
    final fiberG = enerc * 0.014;                 // 14 g / 1000 kcal
    final sugarG = enerc * 0.10 / 4.0;            // 당류 10% kcal 상한
    final satFatG = enerc * 0.10 / 9.0;           // 포화지방 10% kcal 상한
    final transFatG = enerc * 0.01 / 9.0;         // 트랜스지방 1% kcal 상한
    final cholesterolMg = 300;                    // 상한 가이드
    final sodiumMg = 2000;                        // 나트륨 상한
    final calciumMg = 700;                        // 권장
    final ironMg = isMale ? 10 : 14;              // 여성 상향
    final potassiumMg = 3500;                     // 권장
    final phosphorusMg = 700;                     // 권장

    // 비타민 간단 테이블
    final vitA_rae = _vitaminArae(isMale, age);   // μg RAE
    final b1 = isMale ? 1.2 : 1.1;                // mg
    final b2 = isMale ? 1.3 : 1.1;                // mg
    final nia = isMale ? 16.0 : 14.0;             // mg NE
    final vitC = 100.0;                           // mg
    final vitD = (age >= 65) ? 15.0 : 10.0;       // μg

    return NutritionStandard(
      enerc: enerc,
      chocdf: carbG,
      prot: proteinG,
      fatce: fatG,
      fibtg: fiberG,
      sugar: sugarG,
      nat: sodiumMg,
      ca: calciumMg,
      fe: ironMg,
      k: potassiumMg,
      p: phosphorusMg,
      chole: cholesterolMg,
      fasat: satFatG,
      fatrn: transFatG,
      vitaRae: vitA_rae,
      retol: 0.0,
      cartb: 0.0,
      thia: b1,
      ribf: b2,
      nia: nia,
      vitc: vitC,
      vitd: vitD,
      carbPct: carbPct,
      proteinPct: proteinPct,
      fatPct: fatPct,
    );
  }

  // 활동계수 매핑
  static double _activityFactor(String level) {
    switch (level) {
      case '매우 적음': return 1.2;
      case '적음':     return 1.375;
      case '보통':     return 1.55;
      case '많음':     return 1.725;
      case '매우 많음': return 1.9;
      default:         return 1.55;
    }
  }

  // 활동량별 매크로 비율(탄:단:지 %)
  static (int, int, int) _macroRatio(String level) {
    switch (level) {
      case '매우 적음': return (45, 20, 35);
      case '적음':     return (50, 20, 30);
      case '보통':     return (50, 20, 30);
      case '많음':     return (55, 20, 25);
      case '매우 많음': return (55, 20, 25);
      default:         return (50, 20, 30);
    }
  }

  // 간단 비타민A(μgRAE) 권장량
  static double _vitaminArae(bool isMale, int age) {
    return isMale ? 900.0 : 700.0;
  }

  static int _round10(double v) => (v / 10).round() * 10;
  static double _round1(double v) => (v * 10).roundToDouble() / 10.0;
}

/// ------------------------------------------------------
/// ✅ HydrationStandard: 개인화 물 섭취 목표 계산
/// ------------------------------------------------------
class HydrationStandard {
  static int computeWaterGoalMl({
    required double weightKg,
    required String activityKo,
  }) {
    final base = weightKg * 35.0;                 // mL
    final addon = _activityAddon(activityKo);     // mL
    final raw = base + addon;
    final clamped = raw.clamp(1800.0, 4000.0);    // 가드
    return _roundTo50(clamped).toInt();
  }

  static double _activityAddon(String level) {
    switch (level) {
      case '매우 적음': return 0;
      case '적음':     return 250;
      case '보통':     return 500;
      case '많음':     return 750;
      case '매우 많음': return 1000;
      default:         return 500;
    }
  }

  static double _roundTo50(double v) => (v / 50.0).round() * 50.0;
}

// --- Year Step ---
class _YearStep extends StatefulWidget {
  final ValueChanged<int> onSaved;
  final VoidCallback onNext;
  const _YearStep({required this.onSaved, required this.onNext, Key? key})
      : super(key: key);

  @override
  State<_YearStep> createState() => _YearStepState();
}

class _YearStepState extends State<_YearStep> {
  static const int currentYear = 2025; // 필요시 DateTime.now().year 로 변경

  final _focus = FocusNode();
  final _ctrl = TextEditingController();
  bool _focused = false;
  bool _isValid = false;
  int? _parsedYear;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
    _ctrl.addListener(_validate);
  }

  void _validate() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() { _isValid = false; _errorText = null; });
      return;
    }
    final y = int.tryParse(text);
    if (y == null) {
      setState(() { _isValid = false; _errorText = '숫자만 입력하세요'; });
      return;
    }
    if (y < 1900 || y > currentYear) {
      setState(() {
        _isValid = false;
        _errorText = '유효한 연도를 입력하세요 (1900~$currentYear)';
      });
    } else {
      setState(() { _isValid = true; _errorText = null; _parsedYear = y; });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '태어난 연도는 무엇인가요?',
      subtitle: '연도를 입력해주세요.',
      onNext: _isValid
          ? () { widget.onSaved(_parsedYear!); widget.onNext(); }
          : null,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  focusNode: _focus,
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: _focused ? _StepScaffold.primaryColor : Colors.grey,
                        width: 2,
                      ),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: _StepScaffold.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  cursorColor: _StepScaffold.primaryColor,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '년',
                style: TextStyle(
                  fontSize: 16,
                  color: _focused ? _StepScaffold.primaryColor : Colors.grey,
                ),
              ),
            ],
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(_errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

// --- Height Step ---
class _HeightStep extends StatefulWidget {
  final ValueChanged<double> onSaved;
  final VoidCallback onPrev, onNext;
  const _HeightStep({
    required this.onSaved,
    required this.onPrev,
    required this.onNext,
    Key? key,
  }) : super(key: key);

  @override
  State<_HeightStep> createState() => _HeightStepState();
}

class _HeightStepState extends State<_HeightStep> {
  final _focus = FocusNode();
  final _ctrl = TextEditingController();
  bool _focused = false;

  bool _isValid = false;
  String? _errorText;
  double? _parsed;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
    _ctrl.addListener(_validate);
  }

  void _validate() {
    final text = _ctrl.text.trim();
    final v = double.tryParse(text);
    if (v == null || v <= 0) {
      setState(() {
        _isValid = false;
        _errorText = text.isEmpty ? null : '유효한 숫자를 입력하세요';
      });
    } else {
      setState(() {
        _isValid = true;
        _errorText = null;
        _parsed = v;
      });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '키는 무엇인가요?',
      subtitle: 'cm 단위로 입력해주세요.',
      onPrev: widget.onPrev,
      onNext: _isValid ? () { widget.onSaved(_parsed!); widget.onNext(); } : null,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  focusNode: _focus,
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: _focused ? _StepScaffold.primaryColor : Colors.grey,
                        width: 2,
                      ),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: _StepScaffold.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  cursorColor: _StepScaffold.primaryColor,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'cm',
                style: TextStyle(
                  fontSize: 16,
                  color: _focused ? _StepScaffold.primaryColor : Colors.grey,
                ),
              ),
            ],
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(_errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

// --- Weight Step ---
class _WeightStep extends StatefulWidget {
  final ValueChanged<double> onSaved;
  final VoidCallback onPrev, onNext;
  const _WeightStep({
    required this.onSaved,
    required this.onPrev,
    required this.onNext,
    Key? key,
  }) : super(key: key);

  @override
  State<_WeightStep> createState() => _WeightStepState();
}

class _WeightStepState extends State<_WeightStep> {
  final _focus = FocusNode();
  final _ctrl = TextEditingController();
  bool _focused = false;

  bool _isValid = false;
  String? _errorText;
  double? _parsed;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
    _ctrl.addListener(_validate);
  }

  void _validate() {
    final text = _ctrl.text.trim();
    final v = double.tryParse(text);
    if (v == null || v <= 0) {
      setState(() {
        _isValid = false;
        _errorText = text.isEmpty ? null : '유효한 숫자를 입력하세요';
      });
    } else {
      setState(() {
        _isValid = true;
        _errorText = null;
        _parsed = v;
      });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '몸무게는 무엇인가요?',
      subtitle: 'kg 단위로 입력해주세요.',
      onPrev: widget.onPrev,
      onNext: _isValid ? () { widget.onSaved(_parsed!); widget.onNext(); } : null,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  focusNode: _focus,
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: _focused ? _StepScaffold.primaryColor : Colors.grey,
                        width: 2,
                      ),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: _StepScaffold.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  cursorColor: _StepScaffold.primaryColor,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'kg',
                style: TextStyle(
                  fontSize: 16,
                  color: _focused ? _StepScaffold.primaryColor : Colors.grey,
                ),
              ),
            ],
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(_errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

// --- Gender Step (값을 '남성'/'여성'으로 저장) ---
class _GenderStep extends StatefulWidget {
  final ValueChanged<String> onSaved;
  final VoidCallback onPrev, onNext;
  const _GenderStep({
    required this.onSaved,
    required this.onPrev,
    required this.onNext,
    Key? key,
  }) : super(key: key);

  @override
  State<_GenderStep> createState() => _GenderStepState();
}

class _GenderStepState extends State<_GenderStep> {
  String? _sel; // '남성' | '여성'

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '성별은 무엇인가요?',
      subtitle: '성별에 따라 맞춤형 정보를 제공합니다.',
      onPrev: widget.onPrev,
      onNext: _sel == null
          ? null
          : () { widget.onSaved(_sel!); widget.onNext(); },
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _sel = '남성'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(20),
                backgroundColor:
                _sel == '남성' ? _StepScaffold.primaryColor : Colors.grey[200],
                side: BorderSide(
                  color: _sel == '남성' ? _StepScaffold.primaryColor : Colors.grey,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                '남성',
                style: TextStyle(color: _sel == '남성' ? Colors.white : Colors.black),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _sel = '여성'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(20),
                backgroundColor:
                _sel == '여성' ? _StepScaffold.primaryColor : Colors.grey[200],
                side: BorderSide(
                  color: _sel == '여성' ? _StepScaffold.primaryColor : Colors.grey,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                '여성',
                style: TextStyle(color: _sel == '여성' ? Colors.white : Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Active Step (풀폭 · 일정 높이 버튼) ---
class _ActiveStep extends StatefulWidget {
  final ValueChanged<String> onSaved;
  final VoidCallback onPrev, onNext;
  const _ActiveStep({
    required this.onSaved,
    required this.onPrev,
    required this.onNext,
    Key? key,
  }) : super(key: key);

  @override
  State<_ActiveStep> createState() => _ActiveStepState();
}

class _ActiveStepState extends State<_ActiveStep> {
  String? _sel;

  // ▶ 주간 땀나는 운동 횟수
  static const Map<String, String> _freq = {
    '매우 적음': '주 0회',
    '적음':     '주 1–2회',
    '보통':     '주 3–4회',
    '많음':     '주 5–6회',
    '매우 많음': '주 7회 이상',
  };

  @override
  Widget build(BuildContext context) {
    final items = ['매우 적음', '적음', '보통', '많음', '매우 많음'];

    return _StepScaffold(
      title: '하루 활동량은 어느 정도인가요?',
      subtitle: '주간 땀나는 운동 횟수 기준으로 선택하세요.',
      onPrev: widget.onPrev,
      onNext: _sel == null ? null : () { widget.onSaved(_sel!); widget.onNext(); },
      child: Column(
        children: [
          for (final lbl in items) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => setState(() => _sel = lbl),
                  style: OutlinedButton.styleFrom(
                    backgroundColor:
                    _sel == lbl ? _StepScaffold.primaryColor : Colors.grey[200],
                    side: BorderSide(
                      color: _sel == lbl ? _StepScaffold.primaryColor : Colors.grey,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        lbl,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _sel == lbl ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        _freq[lbl]!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _sel == lbl ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- 공통 스텝 스캐폴드(오버플로우 방지: 스크롤러 적용) ---
class _StepScaffold extends StatelessWidget {
  static const Color primaryColor = Color(0xFF24C486);

  final String title;
  final String subtitle;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final Widget child;

  const _StepScaffold({
    required this.title,
    required this.subtitle,
    this.onPrev,
    this.onNext,
    required this.child,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 24),
          // ▶ 내용부 스크롤 가능하게 (작은 화면에서 overflow 방지)
          Expanded(
            child: SingleChildScrollView(
              child: child,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (onPrev != null)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onPrev,
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: primaryColor,
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                )
              else
                const SizedBox(width: 48, height: 48),
              SizedBox(
                width: 48,
                height: 48,
                child: ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: primaryColor,
                    padding: EdgeInsets.zero,
                    elevation: 0,
                  ),
                  child: const Icon(Icons.arrow_forward, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
