// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:async/async.dart' show StreamGroup; // 여러 스트림 병합

import 'profile.dart';       // ProfilePage
import 'statistics_page.dart';
import 'nutrition.dart';     // MealDetailPage
import 'barcode.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// 공용 상수/유틸
/// ─────────────────────────────────────────────────────────────────────────
const Color kBackgroundMint = Color(0xFFDBFBED);
const Color kAccentGreen    = Color(0xFF24C486);
const TextStyle kLastTimeTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: kAccentGreen,
);

String formatKoreanApHm(DateTime dt) {
  final local = dt.toLocal();
  final isAm = local.hour < 12;
  var h = local.hour % 12;
  if (h == 0) h = 12;
  final mm = local.minute.toString().padLeft(2, '0');
  return '${isAm ? '오전' : '오후'} $h시$mm분';
}

String formatLitersFromMl(double ml, {double? stepMl}) {
  final l = ml / 1000.0;
  final useTwo = (stepMl != null && stepMl % 100 != 0);
  return useTwo ? l.toStringAsFixed(2) : l.toStringAsFixed(1);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // ✅ 익명 로그인 보장
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const NutritionHomePage(),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// NutritionHomePage
/// ─────────────────────────────────────────────────────────────────────────
class NutritionHomePage extends StatefulWidget {
  const NutritionHomePage({Key? key}) : super(key: key);

  @override
  _NutritionHomePageState createState() => _NutritionHomePageState();
}

class _NutritionHomePageState extends State<NutritionHomePage> {
  final Color _cardGray = Colors.grey.shade100;

  Widget _userHeader() {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    if (uid == null) {
      return Row(children: const [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey,
          child: Icon(Icons.person, size: 32, color: Colors.white),
        ),
        SizedBox(width: 8),
        Text('user', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ]);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        String name =
        user?.displayName?.trim().isNotEmpty == true ? user!.displayName! : 'user';
        String? photoUrl = user?.photoURL;

        if (snap.hasData) {
          final data = snap.data!.data() ?? {};
          final profile = (data['profile'] as Map<String, dynamic>?) ?? {};
          name = (profile['displayName'] ??
              profile['name'] ??
              data['displayName'] ??
              user?.displayName ??
              'user')
              .toString();
          final fromDb = (profile['photoUrl'] ?? data['photoUrl'])?.toString();
          if (fromDb != null && fromDb.isNotEmpty) photoUrl = fromDb;
        }

        return Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey,
            backgroundImage:
            (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
            child: (photoUrl == null || photoUrl!.isEmpty)
                ? const Icon(Icons.person, size: 32, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 8),
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]);
      },
    );
  }

  // 내부 기본값
  double _energyTargetKcal = 3400.0;
  double _waterTargetMl    = 2500.0;
  double _waterStepMl      = 100.0;

  DateTime _selectedDate = DateTime.now();
  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
  StreamSubscription? _foodsMergeSub;

  // ✅ 무애니 라우트
  Route _noAnim(Widget page) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  // ──────────────── 📌 숫자/영양 추출 헬퍼 (enerc/chocdf/prot/fatce 우선) ────────────────
  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  double _fromNutrients(Map<String, dynamic> m, String key) {
    final n = m['nutrients'];
    if (n is Map) {
      final vv = n[key];
      if (vv is num || vv is String) return _asDouble(vv);
    }
    return 0.0;
  }

  double _pickEnerc(Map<String, dynamic> m) {
    // nutrients.enerc → enerc → kcal/energy → energy_kcal
    final n = _fromNutrients(m, 'enerc');
    if (n != 0.0) return n;
    final direct = _asDouble(m['enerc']);
    if (direct != 0.0) return direct;
    final kcal = _asDouble(m['kcal']);
    if (kcal != 0.0) return kcal;
    final energy = _asDouble(m['energy']);
    if (energy != 0.0) return energy;
    return _asDouble(m['energy_kcal']);
  }

  double _pickChocdf(Map<String, dynamic> m) {
    final n = _fromNutrients(m, 'chocdf');
    if (n != 0.0) return n;
    final direct = _asDouble(m['chocdf']);
    if (direct != 0.0) return direct;
    final carbs = _asDouble(m['carbs']);
    if (carbs != 0.0) return carbs;
    final carb = _asDouble(m['carb']);
    if (carb != 0.0) return carb;
    final cho = _asDouble(m['cho']);
    if (cho != 0.0) return cho;
    return _asDouble(m['carbohydrate']);
  }

  double _pickProt(Map<String, dynamic> m) {
    final n = _fromNutrients(m, 'prot');
    if (n != 0.0) return n;
    final direct = _asDouble(m['prot']);
    if (direct != 0.0) return direct;
    return _asDouble(m['protein']);
  }

  double _pickFatce(Map<String, dynamic> m) {
    final n = _fromNutrients(m, 'fatce');
    if (n != 0.0) return n;
    final direct = _asDouble(m['fatce']);
    if (direct != 0.0) return direct;
    final fat = _asDouble(m['fat']);
    if (fat != 0.0) return fat;
    return _asDouble(m['lipid']);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadTargetsFromStandard();
      await _loadWaterStepFromSettings();
      await _initializeDailyRecord();
      await _refreshDailyAggregates();
      _attachLiveAggregates();
    });
  }

  @override
  void dispose() {
    _cancelLiveAggregates();
    super.dispose();
  }

  // ── Firestore helper
  Future<void> _safeSet(DocumentReference ref, Map<String, dynamic> data) async {
    try {
      await ref.set(data, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      // ignore: avoid_print
      print('Firestore set error: $e');
    }
  }

  Future<void> _loadTargetsFromStandard() async {
    try {
      final uref = FirebaseFirestore.instance.collection('users').doc(_userId);
      final snap = await uref.get();
      final std = (snap.data()?['nutritionStandard'] as Map<String, dynamic>?) ?? {};
      final enerc = (std['enerc'] as num?)?.toDouble();
      final waterMl = (std['waterGoalMl'] as num?)?.toDouble();

      setState(() {
        if (enerc != null && enerc > 0) _energyTargetKcal = enerc;
        if (waterMl != null && waterMl > 0) _waterTargetMl = waterMl;
      });
    } catch (_) {}
  }

  Future<void> _loadWaterStepFromSettings() async {
    try {
      final uref = FirebaseFirestore.instance.collection('users').doc(_userId);
      final snap = await uref.get();
      final data = snap.data() ?? {};
      final settings = (data['settings'] as Map<String, dynamic>?) ?? {};
      double? stepMl =
          (settings['waterPerIntakeMl'] as num?)?.toDouble() ??
              (settings['waterIntakeUnitMl'] as num?)?.toDouble() ??
              (data['waterPerIntakeMl'] as num?)?.toDouble() ??
              (((data['profile'] as Map?)?['waterOnceMl']) as num?)?.toDouble();
      if (stepMl != null && stepMl > 0) {
        setState(() => _waterStepMl = stepMl!.toDouble());
      }
    } catch (e) {
      print('loadWaterStep error: $e');
    }
  }

  void _attachLiveAggregates() {
    _cancelLiveAggregates();
    final merged = StreamGroup.merge([
      _foodsRef('아침식사').snapshots(),
      _foodsRef('점심식사').snapshots(),
      _foodsRef('저녁식사').snapshots(),
      _foodsRef('간식').snapshots(),
      _dailyFoodsRef().snapshots(), // 새 스키마
    ]);
    _foodsMergeSub = merged.listen((_) async {
      await _refreshDailyAggregates(); // 실시간 합산
    });
  }

  void _cancelLiveAggregates() {
    _foodsMergeSub?.cancel();
    _foodsMergeSub = null;
  }

  /// 문서 초기화(+ 마이그레이션)
  Future<void> _initializeDailyRecord() async {
    final ref = _dailyDocRef();
    final snap = await ref.get();
    if (!snap.exists) {
      await _safeSet(ref, {
        'weekday': _weekdayString(_selectedDate),
        'waterIntake': {'amountMl': 0.0, 'lastTime': ''},
      });
      return;
    }
    final data = snap.data() ?? {};
    final patch = <String, dynamic>{};
    if (data['weekday'] == null) {
      patch['weekday'] = _weekdayString(_selectedDate);
    }
    final water = (data['waterIntake'] as Map?)?.cast<String, dynamic>() ?? {};
    if (water.isNotEmpty) {
      if (water['amountMl'] == null && water['amount'] != null) {
        final amtL = (water['amount'] as num?)?.toDouble() ?? 0.0;
        patch['waterIntake'] = {
          'amountMl': (amtL * 1000.0),
          'lastTime': water['lastTime'] ?? '',
        };
      } else if (water['amountMl'] == null) {
        patch['waterIntake'] = {'amountMl': 0.0, 'lastTime': water['lastTime'] ?? ''};
      }
    } else {
      patch['waterIntake'] = {'amountMl': 0.0, 'lastTime': ''};
    }
    if (patch.isNotEmpty) await _safeSet(ref, patch);
  }

  /// ─────────────────────────────────────────────────────────────
  /// 🔎 모든 영양소 집계 (알림 로직 제거)
  ///    - A(meals/*/foods) 우선, 없으면 B(daily/foods)
  ///    - enerc/chocdf/prot/fatce 우선, 레거시(kcal/carbs/protein/fat) 폴백
  /// ─────────────────────────────────────────────────────────────
  Future<void> _refreshDailyAggregates() async {
    final meals = ['아침식사', '점심식사', '저녁식사', '간식'];
    final Map<String, dynamic> toMerge = {
      'weekday': _weekdayString(_selectedDate),
      'meals': {},
    };

    // 표시에 쓰는 합계
    double dayEnergy = 0, dayCarbs = 0, dayProtein = 0, dayFat = 0;

    // ✅ 모든 영양소 합계 맵
    final Map<String, double> nutrientTotals = {};
    double _sum(String key, double add) =>
        (nutrientTotals[key] = (nutrientTotals[key] ?? 0.0) + add);

    final dailyFoodsRef = _dailyFoodsRef();

    for (final mealName in meals) {
      // A 경로(원본)
      final qsA = await _foodsRef(mealName).orderBy('createdAt', descending: true).get();

      double kcalA = 0, carbsA = 0, protA = 0, fatA = 0;
      final foodNamesA = <String>[];
      DateTime? latestA;

      for (final d in qsA.docs) {
        final m = d.data();
        // 합계(표시용)
        final e = _pickEnerc(m);
        final c = _pickChocdf(m);
        final p = _pickProt(m);
        final f = _pickFatce(m);

        dayEnergy += e;
        dayCarbs  += c;
        dayProtein+= p;
        dayFat    += f;

        kcalA += e;
        carbsA += c;
        protA  += p;
        fatA   += f;

        // 전체영양 토탈(키 정규화 없이, 사람이 읽을 키로 저장)
        _collectAllNutrients(m, _sum); // (아래에서 nutrients 맵도 처리하도록 개선)

        final name = m['name']?.toString() ?? m['foodName']?.toString();
        if (name != null && name.isNotEmpty) foodNamesA.add(name);

        final ts = m['createdAt'];
        if (ts is Timestamp) {
          final dt = ts.toDate().toLocal();
          if (latestA == null || dt.isAfter(latestA)) latestA = dt;
        }
      }

      double kcal = 0;
      List<String> foodNames = [];
      DateTime? latest;

      if (qsA.docs.isNotEmpty) {
        // A가 있으면 A만 사용 (중복 방지)
        kcal = kcalA;
        foodNames = foodNamesA;
        latest = latestA;
      } else {
        // B 경로(미러)
        final qsB1 = await dailyFoodsRef.where('meal', isEqualTo: mealName).get();
        final qsB2 = await dailyFoodsRef.where('mealName', isEqualTo: mealName).get();
        final Map<String, Map<String, dynamic>> dailyFoods = {};
        for (final d in qsB1.docs) dailyFoods[d.id] = d.data();
        for (final d in qsB2.docs) dailyFoods[d.id] = d.data();

        for (final m in dailyFoods.values) {
          final e = _pickEnerc(m);
          final c = _pickChocdf(m);
          final p = _pickProt(m);
          final f = _pickFatce(m);

          dayEnergy += e;
          dayCarbs  += c;
          dayProtein+= p;
          dayFat    += f;

          kcal += e;
          _collectAllNutrients(m, _sum);

          final name = m['name']?.toString() ?? m['foodName']?.toString();
          if (name != null && name.isNotEmpty) foodNames.add(name);

          final ts = m['createdAt'];
          if (ts is Timestamp) {
            final dt = ts.toDate().toLocal();
            if (latest == null || dt.isAfter(latest)) latest = dt;
          }
        }
      }

      final key = _mealKeyFromName(mealName);
      toMerge['meals'][key] = {
        'kcal': kcal.round(), // UI는 그대로 kcal 필드 사용
        'time': (latest == null) ? '' : formatKoreanApHm(latest!),
        'foods': foodNames,
      };
    }

    // 표시용 합계
    toMerge['nutritionTotals'] = {
      'energy': dayEnergy,
      'carbs': dayCarbs,
      'protein': dayProtein,
      'fat': dayFat,
    };

    // ✅ 디버깅/후속UI용: 일일 모든 영양소 합계 저장
    toMerge['nutrientTotals'] = nutrientTotals;

    // 최종 저장
    await _safeSet(_dailyDocRef(), toMerge);
  }

  /// 음식 문서의 모든 숫자 필드를 훑어 합산한다.
  /// - 키를 정규화해서(동의어 통합) totals 에 더한다.
  /// - ✅ nutrients 맵도 함께 스캔하도록 보강.
  void _collectAllNutrients(Map<String, dynamic> m, double Function(String, double) add) {
    const skipKeys = {
      'id','docId','name','brand','barcode','meal','mealName',
      'createdAt','updatedAt','source','imageUrl','thumbUrl',
    };

    String norm(String raw) {
      final k = raw.trim().toLowerCase();
      switch (k) {
        case 'enerc':
        case 'energy':
        case 'kcal':
        case 'energy_kcal':
          return 'energy_kcal';
        case 'prot':
        case 'protein':
          return 'protein_g';
        case 'fatce':
        case 'fat':
        case 'lipid':
          return 'fat_g';
        case 'chocdf':
        case 'carbs':
        case 'carb':
        case 'carbohydrate':
        case 'carbohydrates':
        case 'cho':
          return 'carbs_g';
        case 'sugar':
        case 'sugars':
        case 'sugars_total':
          return 'sugars_g';
        case 'fasat':
        case 'satfat':
        case 'saturated_fat':
          return 'saturated_fat_g';
        case 'transfat':
        case 'fat_trans':
        case 'trans_fat':
          return 'trans_fat_g';
        case 'na':
        case 'sodium':
          return 'sodium_mg';
        case 'k':
        case 'potassium':
          return 'potassium_mg';
        case 'fiber':
        case 'dietary_fiber':
        case 'fibtg':
          return 'fiber_g';
        case 'ca':
        case 'calcium':
          return 'calcium_mg';
        case 'fe':
        case 'iron':
          return 'iron_mg';
        case 'mg':
        case 'magnesium':
          return 'magnesium_mg';
        case 'zn':
        case 'zinc':
          return 'zinc_mg';
        case 'p':
        case 'phosphorus':
          return 'phosphorus_mg';
        case 'vita_rae':
        case 'vitamin_a':
          return 'vitamin_a_rae_ug';
        case 'vitc':
        case 'vitamin_c':
          return 'vitamin_c_mg';
        case 'thia':
        case 'thiamin':
        case 'vitamin_b1':
        case 'vitb1':
          return 'vitamin_b1_mg';
        case 'ribf':
        case 'riboflavin':
        case 'vitamin_b2':
        case 'vitb2':
          return 'vitamin_b2_mg';
        case 'nia':
        case 'niacin':
        case 'vitb3':
        case 'vitamin_b3':
          return 'niacin_mg';
        case 'vitb6':
          return 'vitamin_b6_mg';
        case 'vitb12':
          return 'vitamin_b12_ug';
        case 'folate':
        case 'folic_acid':
          return 'folate_dfe_ug';
        default:
          return k;
      }
    }

    void scanMap(Map mapObj) {
      mapObj.forEach((rawKey, v) {
        if (skipKeys.contains(rawKey)) return;
        final nkey = norm(rawKey.toString());
        final num? n = (v is num) ? v : (v is String ? num.tryParse(v) : null);
        if (n == null) return;
        add(nkey, n.toDouble());
      });
    }

    // 최상위 스캔
    scanMap(m);

    // nutrients 맵 추가 스캔
    final n = m['nutrients'];
    if (n is Map) scanMap(n as Map);
  }

  String _docIdFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DocumentReference<Map<String, dynamic>> _dailyDocRef() =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('daily')
          .doc(_docIdFor(_selectedDate));

  CollectionReference<Map<String, dynamic>> _dailyFoodsRef() =>
      _dailyDocRef().collection('foods');

  String _mealDocId(DateTime d, String mealName) =>
      '${d.year}-${d.month}-${d.day}_$mealName';

  String _weekdayString(DateTime date) {
    const wk = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    return wk[date.weekday - 1];
  }

  String _mealKeyFromName(String mealName) {
    switch (mealName) {
      case '아침식사':
        return 'breakfast';
      case '점심식사':
        return 'lunch';
      case '저녁식사':
        return 'dinner';
      default:
        return 'snack';
    }
  }

  // (A) 기존 경로
  CollectionReference<Map<String, dynamic>> _foodsRef(String mealName) {
    final mealKey = _mealDocId(_selectedDate, mealName);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .collection('meals')
        .doc(mealKey)
        .collection('foods');
  }

  Future<void> _showDatePicker() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(today) ? today : _selectedDate,
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (picked != null && picked != _selectedDate) {
      _cancelLiveAggregates();
      setState(() => _selectedDate = picked);
      await _loadTargetsFromStandard();
      await _loadWaterStepFromSettings();
      await _initializeDailyRecord();
      await _refreshDailyAggregates();
      _attachLiveAggregates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        '${_selectedDate.year}년 ${_selectedDate.month.toString().padLeft(2, '0')}월 ${_selectedDate.day.toString().padLeft(2, '0')}일';
    final dailyRef = _dailyDocRef();
    final userRef  = FirebaseFirestore.instance.collection('users').doc(_userId);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.push(context, _noAnim(const ProfilePage())),
                    child: _userHeader(),
                  ),
                  const Spacer(),
                  Text(formattedDate,
                      style: const TextStyle(fontSize: 16, color: Colors.black54)),
                  IconButton(
                    icon: SvgPicture.asset('assets/calendar.svg',
                        width: 32, height: 32, color: kAccentGreen),
                    onPressed: _showDatePicker,
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // 영양지표
                    const Text('영양지표',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),

                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: userRef.snapshots(),
                      builder: (context, usnap) {
                        final udata = usnap.data?.data() ?? {};
                        final std = (udata['nutritionStandard'] as Map?) ?? {};
                        final targetEnergy =
                            (std['enerc'] as num?)?.toDouble() ?? _energyTargetKcal;

                        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: dailyRef.snapshots(),
                          builder: (context, snap) {
                            final data = snap.data?.data() ?? {};
                            final totals = (data['nutritionTotals'] as Map?) ?? {};
                            final energy =
                                (totals['energy'] as num?)?.toDouble() ?? 0.0;
                            final carbs =
                                (totals['carbs'] as num?)?.toDouble() ?? 0.0;
                            final protein =
                                (totals['protein'] as num?)?.toDouble() ?? 0.0;
                            final fat = (totals['fat'] as num?)?.toDouble() ?? 0.0;

                            return _buildNutritionCard(
                              energy: energy,
                              carbs: carbs,
                              protein: protein,
                              fat: fat,
                              targetEnergyKcal: targetEnergy,
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // 수분
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: userRef.snapshots(),
                      builder: (context, usnap) {
                        final udata = usnap.data?.data() ?? {};
                        final settings = (udata['settings'] as Map?) ?? {};
                        final waterEnabled =
                            (settings['waterTrackingEnabled'] as bool?) ?? true;

                        final liveStepMl = ((settings['waterPerIntakeMl'] as num?) ??
                            (settings['waterIntakeUnitMl'] as num?) ??
                            (udata['waterPerIntakeMl'] as num?) ??
                            (((udata['profile'] as Map?)?['waterOnceMl']) as num?))
                            ?.toDouble();

                        final stepMl = (liveStepMl != null && liveStepMl > 0)
                            ? liveStepMl
                            : _waterStepMl;
                        final std = (udata['nutritionStandard'] as Map?) ?? {};
                        final targetMl =
                            (std['waterGoalMl'] as num?)?.toDouble() ?? _waterTargetMl;

                        if (!waterEnabled) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('수분 섭취량',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 16),
                            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: dailyRef.snapshots(),
                              builder: (context, dsnap) {
                                final data = dsnap.data?.data() ?? {};
                                final water =
                                    (data['waterIntake'] as Map<String, dynamic>?) ??
                                        {};
                                double amtMl =
                                    (water['amountMl'] as num?)?.toDouble() ??
                                        (((water['amount'] as num?)?.toDouble() ??
                                            0.0) *
                                            1000.0);
                                final last = water['lastTime'] as String? ?? '';
                                return _buildWaterCard(
                                  amountMl: amtMl,
                                  lastTime: last,
                                  stepMl: stepMl,
                                  targetMl: targetMl,
                                );
                              },
                            ),
                            const SizedBox(height: 32),
                          ],
                        );
                      },
                    ),

                    // 식사
                    const Text('식사',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: dailyRef.snapshots(),
                      builder: (context, snap) {
                        final data = snap.data?.data() ?? {};
                        final meals = data['meals'] as Map<String, dynamic>? ?? {};
                        final bf = meals['breakfast'] as Map<String, dynamic>? ?? {};
                        final lu = meals['lunch'] as Map<String, dynamic>? ?? {};
                        final di = meals['dinner'] as Map<String, dynamic>? ?? {};
                        final sn = meals['snack'] as Map<String, dynamic>? ?? {};

                        return Column(
                          children: [
                            _buildMealTile('아침식사',
                                (bf['kcal'] as num?)?.toInt() ?? 0,
                                bf['time']?.toString() ?? ''),
                            const SizedBox(height: 16),
                            _buildMealTile('점심식사',
                                (lu['kcal'] as num?)?.toInt() ?? 0,
                                lu['time']?.toString() ?? ''),
                            const SizedBox(height: 16),
                            _buildMealTile('저녁식사',
                                (di['kcal'] as num?)?.toInt() ?? 0,
                                di['time']?.toString() ?? ''),
                            const SizedBox(height: 16),
                            _buildMealTile('간식',
                                (sn['kcal'] as num?)?.toInt() ?? 0,
                                sn['time']?.toString() ?? ''),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // 바텀 네비 (동일)
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 64,
          decoration: const BoxDecoration(
            color: kBackgroundMint,
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navButton(icon: Icons.camera_alt, label: '인식', onTap: () {}),
                  SvgPicture.asset('assets/home_round.svg', width: 56, height: 56),
                  _navButtonSvg(
                      assetPath: 'assets/static_icon.svg',
                      label: '통계',
                      onTap: () {}),
                ],
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          await Navigator.push(
                              context,
                              _noAnim(const BarcodePage(mealName: 'none')));
                          await _refreshDailyAggregates();
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const Expanded(child: SizedBox.expand()),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.push(
                            context, _noAnim(const StatisticsPage())),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── UI helpers (동일) ─────────────────────────────────────────
  Widget _buildMealTile(String mealName, int kcal, String time) {
    final displayTime = (time.isEmpty) ? '기록 없음' : time;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
            context, _noAnim(MealDetailPage(mealName: mealName)));
        await _refreshDailyAggregates();
      },
      child: _buildMealCard(mealName, kcal, displayTime),
    );
  }

  Widget _navButton(
      {required IconData icon,
        required String label,
        required VoidCallback onTap}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 64),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: kAccentGreen.withOpacity(0.5)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: kAccentGreen.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _navButtonSvg(
      {required String assetPath,
        required String label,
        required VoidCallback onTap}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 64),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(assetPath, width: 24, height: 24,
              colorFilter: ColorFilter.mode(
                  kAccentGreen.withOpacity(0.5), BlendMode.srcIn)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: kAccentGreen.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildNutritionCard({
    required double energy,
    required double carbs,
    required double protein,
    required double fat,
    required double targetEnergyKcal,
  }) {
    final target = targetEnergyKcal > 0 ? targetEnergyKcal : 1.0;
    final energyRatio = ((energy / target).clamp(0.0, 1.0) as num).toDouble();

    return Container(
      decoration:
      BoxDecoration(color: _cardGray, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(16),
      child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _nutriCol('${carbs.toStringAsFixed(0)} g', '탄수화물', Colors.redAccent),
          _nutriCol('${protein.toStringAsFixed(0)} g', '단백질', Colors.orangeAccent),
          _nutriCol('${fat.toStringAsFixed(0)} g', '지방', Colors.green),
        ]),
        const SizedBox(height: 20),
        Center(
            child: Text(
                '${energy.toStringAsFixed(0)} / ${targetEnergyKcal.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600))),
        const SizedBox(height: 8),
        Stack(children: [
          Container(
              width: double.infinity,
              height: 10,
              decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(5))),
          FractionallySizedBox(
            widthFactor: energyRatio,
            child: Container(
                height: 10,
                decoration: BoxDecoration(
                    color: kAccentGreen,
                    borderRadius: BorderRadius.circular(5))),
          ),
        ]),
        const SizedBox(height: 8),
        const Center(
            child:
            Text('에너지', style: TextStyle(fontSize: 14, color: Colors.black54))),
      ]),
    );
  }

  Widget _nutriCol(String value, String label, Color color) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: color)),
      const SizedBox(height: 6),
      const Text('',
          style: TextStyle(
              fontSize: 0, fontWeight: FontWeight.w500, color: Colors.transparent)),
      Text(label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black54)),
    ]);
  }

  Widget _buildMealCard(String name, int kcal, String time) {
    final displayTime = (time.isEmpty) ? '기록 없음' : time;
    return Container(
      decoration:
      BoxDecoration(color: _cardGray, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(name,
              style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text('$kcal kcal',
              style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.access_time, size: 14, color: kAccentGreen),
          const SizedBox(width: 6),
          Text(displayTime, style: kLastTimeTextStyle),
        ]),
      ]),
    );
  }

  Widget _buildWaterCard({
    required double amountMl,
    required String lastTime,
    required double stepMl,
    required double targetMl,
  }) {
    final displayTime = (lastTime.isEmpty) ? '기록 없음' : lastTime;
    final denom = targetMl > 0 ? targetMl : 1.0;
    final ratio = ((amountMl / denom).clamp(0.0, 1.0) as num).toDouble();
    final amountLStr = formatLitersFromMl(amountMl, stepMl: stepMl);
    final targetLStr = formatLitersFromMl(targetMl, stepMl: stepMl);

    return Container(
      decoration:
      BoxDecoration(color: _cardGray, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('물',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            RichText(
                text: TextSpan(style: const TextStyle(color: Colors.black), children: [
                  TextSpan(
                      text: amountLStr,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: ' / $targetLStr L',
                      style: const TextStyle(fontSize: 14)),
                ])),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.access_time, size: 14, color: kAccentGreen),
              const SizedBox(width: 6),
              Text(displayTime, style: kLastTimeTextStyle),
            ]),
          ]),
          const Spacer(),
          Column(children: [
            _circleBtn(Icons.add, () async {
              final newAmt = (amountMl + stepMl).clamp(0.0, targetMl) as double;
              await _updateWaterIntakeMl(newAmt);
            }),
            const SizedBox(height: 12),
            _circleBtn(Icons.remove, () async {
              final newAmt = (amountMl - stepMl).clamp(0.0, targetMl) as double;
              await _updateWaterIntakeMl(newAmt);
            }),
          ]),
          const SizedBox(width: 20),
          WaterProgressBar(fillRatio: ratio),
        ],
      ),
    );
  }

  Future<void> _updateWaterIntakeMl(double amountMl) async {
    final nowText = formatKoreanApHm(DateTime.now());
    await _safeSet(_dailyDocRef(), {
      'weekday': _weekdayString(_selectedDate),
      'waterIntake': {'amountMl': amountMl, 'lastTime': nowText},
    });
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration:
        BoxDecoration(color: Colors.grey.shade300, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: Colors.black),
      ),
    );
  }
}

/// ── 물 게이지 위젯 ───────────────────────────────────────────────
class WaterProgressBar extends StatelessWidget {
  final double fillRatio;
  final double width;
  final double height;
  const WaterProgressBar(
      {Key? key, required this.fillRatio, this.width = 40, this.height = 100})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    final ratio = (fillRatio.clamp(0.0, 1.0) as num).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(width / 2),
      child: Stack(alignment: Alignment.bottomCenter, children: [
        Container(width: width, height: height, color: const Color(0xFFE0F7FF)),
        Positioned(
          bottom: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(width / 2),
              top: ratio == 1.0 ? Radius.circular(width / 2) : Radius.zero,
            ),
            child: Container(
              width: width,
              height: height * ratio,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFF4F9EFF), Color(0xFF80DCFF)],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: width,
          height: height,
          child: Center(
              child: Text('${(ratio * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black))),
        ),
      ]),
    );
  }
}
