// lib/statistics_page.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'result.dart';
import 'main.dart';       // NutritionHomePage
import 'profile.dart';   // ProfilePage
import 'barcode.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({Key? key}) : super(key: key);

  @override
  _StatisticsPageState createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  // ───────── Firestore ─────────
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _userSub;
  StreamSubscription<QuerySnapshot>? _dailySub;

  // ───────── 상태 ─────────
  String _userName = 'user';
  String? _photoUrl;

  Map<String, dynamic>? _standard;     // users/{uid}.nutritionStandard
  List<_DayNutri> _window7 = [];       // 기준일 기준 7일 (start..end)

  Map<String, String> _labelToKey = {}; // "단백질" -> "prot"
  List<String> _labels = [];
  String? _selectedLabel;

  List<FlSpot> _series = [];           // 0~120%
  List<Map<String, String>> _results = []; // {'date': 'yyyy년 m월 d일', 'cal': '123 kcal'}

  DateTime? _pinnedDate;               // +로 고른 날짜(창 밖이어도 표시)
  Map<String, String>? _pinnedItem;

  bool _loading = true;
  String? _error;

  // 스키마
  static const String COLL_USERS = 'users';
  static const String COLL_DAILY = 'daily'; // users/{uid}/daily/{yyyy-MM-dd}

  // 차트 데이터 기준일(“오늘” 역할) — 7일 창의 끝
  DateTime _chartEnd = _startOfDayStatic(DateTime.now());

  // 하단 라벨용 개별 날짜(1일 간격 7개: 0~6축 전용)
  List<DateTime> _tickDates = []; // 길이 7 유지

  // 제외할 키(집계/표시 제외)
  static const Set<String> _EXCLUDED_KEYS = {
    'watergoalmi', 'water_goal_ml', 'waterGoalMl', 'water_goal_mi', 'water',
    'fatrn', // ❌ 트랜스지방 제외
  };

  // ───────── 라벨/단위 매핑 ─────────
  static const Map<String, String> _kKeyToLabel = {
    // 에너지(피커에는 안 보이지만 합계/축 계산에 사용)
    'enerc': '칼로리',

    // 탄·단·지
    'chocdf': '탄수화물',
    'prot': '단백질',
    'fatce': '지방',

    // 나머지
    'fibtg': '식이섬유',
    'sugar': '당류',
    'fasat': '포화지방',
    'chole': '콜레스테롤',

    // 비타민
    'vita_rae': '비타민A',
    'vitc': '비타민C',
    'vitd': '비타민D',
    'vite': '비타민E',
    'vitk': '비타민K',
    'vitb1': '비타민B1',
    'vitb2': '비타민B2',
    'vitb3': '비타민B3',
    'vitb6': '비타민B6',
    'vitb12': '비타민B12',
    'folate': '엽산',
    'biotin': '비오틴',
    'pantothenic': '비타민B5',

    // 무기질
    'na': '나트륨',
    'k': '칼륨',
    'p': '인',
    'mg': '마그네슘',
    'ca': '칼슘',
    'fe': '철',
    'zn': '아연',
  };

  static const Map<String, String> _kUnit = {
    'enerc': 'kcal',
    'prot': 'g',
    'chocdf': 'g',
    'fatce': 'g',
    'sugar': 'g',
    'fasat': 'g',
    'fibtg': 'g',
    'ca': 'mg',
    'fe': 'mg',
    'na': 'mg',
    'k': 'mg',
    'mg': 'mg',
    'zn': 'mg',
    'chole': 'mg',
    'vita_rae': 'µg RAE',
    'vitc': 'mg',
    'vitd': 'µg',
    'vite': 'mg',
    'vitk': 'µg',
    'vitb1': 'mg',
    'vitb2': 'mg',
    'vitb3': 'mg',
    'vitb6': 'mg',
    'folate': 'µg',
    'vitb12': 'µg',
    'biotin': 'µg',
    'pantothenic': 'mg',
    'p': 'mg',
  };

  // ▶ 정렬 그룹: 탄단지 → 나머지 → 비타민 → 무기질
  static const List<String> _GROUP_MACROS = ['chocdf', 'prot', 'fatce'];
  static const List<String> _GROUP_OTHERS = ['fibtg', 'sugar', 'fasat', 'chole'];
  static const List<String> _GROUP_VITS = [
    'vita_rae','vitb1','vitb2','vitb3','vitb6','vitb12','vitc','vitd','vite','vitk','folate','biotin','pantothenic'
  ];
  static const List<String> _GROUP_MINERALS = ['na','k','p','mg','ca','fe','zn'];

  int _groupIndex(String k) {
    if (_GROUP_MACROS.contains(k)) return 0;
    if (_GROUP_OTHERS.contains(k)) return 1;
    if (_GROUP_VITS.contains(k)) return 2;
    if (_GROUP_MINERALS.contains(k)) return 3;
    return 4;
  }

  int _orderInGroup(String k) {
    int idx = _GROUP_MACROS.indexOf(k);
    if (idx != -1) return idx;
    idx = _GROUP_OTHERS.indexOf(k);
    if (idx != -1) return idx;
    idx = _GROUP_VITS.indexOf(k);
    if (idx != -1) return idx;
    idx = _GROUP_MINERALS.indexOf(k);
    if (idx != -1) return idx;
    return 999;
  }

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _dailySub?.cancel();
    super.dispose();
  }

  // ───────── 날짜 유틸 ─────────
  static DateTime _startOfDayStatic(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _startOfDay(DateTime d) => _startOfDayStatic(d);

  String _docId(DateTime d) {
    final sd = _startOfDay(d);
    final mm = sd.month.toString().padLeft(2, '0');
    final dd = sd.day.toString().padLeft(2, '0');
    return '${sd.year}-$mm-$dd';
  }

  String _labelDate(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';
  String _mmdd(DateTime d) => '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  DateTime _parseLabelDate(String s) {
    final p = s.split(RegExp(r'[년월일]')).where((e) => e.isNotEmpty).toList();
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  // ───────── 라우트: 애니메이션 없음 ─────────
  Route _noAnim(Widget page) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  // ───────── Firestore 구독 ─────────
  Future<void> _initStreams() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _error = '로그인이 필요합니다.';
        _loading = false;
      });
      return;
    }
    final uid = user.uid;

    // 사용자 문서(이름/사진 + 표준) 실시간
    _userSub = _db.collection(COLL_USERS).doc(uid).snapshots().listen((snap) {
      final u = snap.data() ?? {};
      final name = (u['name'] ??
          u['displayName'] ??
          _auth.currentUser?.displayName ??
          _auth.currentUser?.email ??
          'user').toString();
      final photo = (u['photoURL'] ??
          u['photoUrl'] ??
          u['avatarUrl'] ??
          _auth.currentUser?.photoURL)?.toString();
      final std = (u['nutritionStandard'] as Map?)?.cast<String, dynamic>();

      setState(() {
        _userName = name;
        _photoUrl = (photo != null && photo.isNotEmpty) ? photo : null;
        _standard = std;
        _rebuildNutrientOptions(); // ✅ 표준 있는 영양소만, 요청한 순서로
        _rebuildSeries();
      });
    });

    _subscribeDaily7();
  }

  void _ensureTickDates() {
    if (_tickDates.length == 7) return;
    final start = _chartEnd.subtract(const Duration(days: 6));
    _tickDates = List.generate(7, (i) => start.add(Duration(days: i)));
  }

  void _subscribeDaily7() {
    _dailySub?.cancel();

    final user = _auth.currentUser;
    if (user == null) return;

    final end = _startOfDay(_chartEnd);
    final start = end.subtract(const Duration(days: 6));
    final endExclusive = end.add(const Duration(days: 1)); // < end+1day

    _dailySub = _db
        .collection(COLL_USERS)
        .doc(user.uid)
        .collection(COLL_DAILY)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(endExclusive))
        .orderBy('date')
        .snapshots()
        .listen((qs) async {
      // 우선 문서 스냅샷의 숫자들만 맵에 수집(빈 날짜 채우는 용)
      final byDay = <String, _DayNutri>{};
      for (final doc in qs.docs) {
        final dMap = doc.data();
        final ts = dMap['date'] as Timestamp?;
        final date = ts?.toDate() ?? _startOfDay(DateTime.parse(doc.id));

        final base = <String, double>{};
        dMap.forEach((k, v) {
          if (k == 'date') return;
          if (v is int) base[_normalizeKey(k)] = v.toDouble();
          if (v is double) base[_normalizeKey(k)] = v;
        });

        byDay[_docId(date)] = _DayNutri(date: _startOfDay(date), vals: base);
      }

      // 7일 창 완성(start..end)
      final base7 = <_DayNutri>[];
      for (int i = 0; i < 7; i++) {
        final d = start.add(Duration(days: i));
        final id = _docId(d);
        base7.add(byDay[id] ?? _DayNutri(date: d, vals: const {}));
      }

      // ✅ 각 날짜의 “해당 날짜 합계(중복방지)”로 재계산
      final totals7 = await _recomputeTotals(base7);
      _window7 = totals7;

      // 최신순 결과 7개(칼로리=해당 날짜 합계)
      final baseResults = totals7.reversed
          .map((e) => {
        'date': _labelDate(e.date),
        'cal': '${e.v('enerc').toInt()} kcal',
      })
          .toList();

      // 핀(플러스로 고른 날짜) 유지
      List<Map<String, String>> finalResults = List.of(baseResults);
      if (_pinnedDate != null && _pinnedItem != null) {
        final label = _labelDate(_pinnedDate!);
        final idx = finalResults.indexWhere((it) => it['date'] == label);
        if (idx == -1) {
          finalResults.insert(0, _pinnedItem!);
          if (finalResults.length > 7) finalResults.removeLast();
        } else {
          // 최신 kcal로 갱신
          final d = totals7.firstWhere(
                (e) => _labelDate(e.date) == label,
            orElse: () => _DayNutri(date: _pinnedDate!, vals: const {}),
          );
          finalResults[idx] = {'date': label, 'cal': '${d.v('enerc').toInt()} kcal'};
        }
      }

      setState(() {
        _results = finalResults;
        _rebuildSeries(); // DB 값 바뀌면 그래프 즉시 갱신(=합계 기준)
        _ensureTickDates(); // 초기화시 1일 간격 7개 기본값 세팅
        _loading = false;
      });
    }, onError: (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    });
  }

  // ───────── “해당 날짜 합계(중복방지)”로 7일치 재계산 ─────────
  Future<List<_DayNutri>> _recomputeTotals(List<_DayNutri> days) async {
    final user = _auth.currentUser;
    if (user == null) return days;

    final out = <_DayNutri>[];
    for (final d in days) {
      final totals = await _resolveDailyTotalsMap(user.uid, d.date);
      out.add(_DayNutri(date: d.date, vals: totals));
    }
    return out;
  }

  /// 한 날짜의 “모든 식사 합계”를 작성 (반드시 해당 날짜만, 2중집계 방지)
  /// 우선순위:
  /// 1) users/{uid}/meals/<yyyy-M-d_끼니>/foods (원천 데이터)
  /// 2) users/{uid}/daily/{date}/foods
  /// 3) daily/meals/*/foods
  /// 4) daily.summary → daily 탑레벨 → daily.meals 요약
  Future<Map<String, double>> _resolveDailyTotalsMap(String uid, DateTime date) async {
    try {
      // 1) ✅ meals 루트 foods(해당 날짜만) 우선 사용
      final foodsFromMealsRoot = await _gatherFoodsFromMealsRoot(uid, date);
      if (foodsFromMealsRoot.isNotEmpty) {
        final acc = <String, double>{};
        for (final f in foodsFromMealsRoot) {
          _addFoodToAcc(f, acc); // 중복 방지 합산
        }
        return _keepUsefulKeys(acc);
      }

      final id = _docId(date);
      final ref = _db.collection(COLL_USERS).doc(uid).collection(COLL_DAILY).doc(id);

      // 2) daily/foods
      final foodsRoot = await ref.collection('foods').get();
      if (foodsRoot.docs.isNotEmpty) {
        final acc = <String, double>{};
        for (final d in foodsRoot.docs) {
          _addFoodToAcc(d.data(), acc); // 중복 방지 합산
        }
        return _keepUsefulKeys(acc);
      }

      // 3) daily/meals/*/foods
      final meals = await ref.collection('meals').get();
      bool hadFoods = false;
      final acc3 = <String, double>{};
      for (final m in meals.docs) {
        final mfoods = await ref.collection('meals').doc(m.id).collection('foods').get();
        if (mfoods.docs.isNotEmpty) {
          hadFoods = true;
          for (final f in mfoods.docs) {
            _addFoodToAcc(f.data(), acc3); // 중복 방지 합산
          }
        }
      }
      if (hadFoods && acc3.isNotEmpty) {
        return _keepUsefulKeys(acc3);
      }

      // 4) 요약/탑레벨 숫자(이미 합쳐진 수치라 미세 중복제거 불가)
      final snap = await ref.get();
      final data = snap.data() ?? {};

      // 4-1) daily.summary
      final summary = data['summary'];
      if (summary is Map) {
        final accS = <String, double>{};
        _sumNumericFromMap(Map<String, dynamic>.from(summary), accS);
        if (accS.isNotEmpty) return _keepUsefulKeys(accS);
      }

      // 4-2) daily 문서 탑레벨 숫자
      final accTop = <String, double>{};
      _sumNumericFromMap(data, accTop);
      if (accTop.isNotEmpty) return _keepUsefulKeys(accTop);

      // 4-3) 마지막으로 daily/meals 문서 숫자 필드(요약값) 합산
      final accMeals = <String, double>{};
      for (final m in meals.docs) {
        _sumNumericFromMap(m.data(), accMeals);
        final n = m.data()['nutrients'];
        if (n is Map) _sumNumericFromMap(Map<String, dynamic>.from(n), accMeals);
      }
      if (accMeals.isNotEmpty) return _keepUsefulKeys(accMeals);

      return {};
    } catch (_) {
      return {};
    }
  }

  // meals 루트(아침/점심/저녁/간식)에서 해당 날짜의 foods 모으기 (nutrition.dart 형식: 0패딩 없음)
  Future<List<Map<String, dynamic>>> _gatherFoodsFromMealsRoot(
      String uid, DateTime date) async {
    final out = <Map<String, dynamic>>[];
    final mealsRoot = _db.collection('users').doc(uid).collection('meals');
    final names = ['아침식사', '점심식사', '저녁식사', '간식'];
    final docIdPrefix = '${date.year}-${date.month}-${date.day}_'; // 0패딩 없음
    for (final name in names) {
      final foodsSnap = await mealsRoot.doc('$docIdPrefix$name').collection('foods').get();
      for (final f in foodsSnap.docs) {
        out.add(f.data());
      }
    }
    return out;
  }

  // 숫자 필드만 누적(키 정규화해서 공통키로 합산) — 요약 레벨에 사용
  void _sumNumericFromMap(Map<String, dynamic> src, Map<String, double> acc) {
    src.forEach((k, v) {
      if (v is! num) return;
      final key = _normalizeKey(k);
      if (key.isEmpty) return;
      acc[key] = (acc[key] ?? 0) + v.toDouble();
    });
  }

  // 합산 헬퍼
  void _acc(Map<String, double> acc, String key, double v) {
    if (v == 0) return;
    acc[key] = (acc[key] ?? 0) + v;
  }

  /// 음식 1개에서 상단 매크로(kcal, carbs, protein, fat)와
  /// nutrients/extraNutrients를 합치되, 동의어/중복 키는 1번만 합산
  void _addFoodToAcc(Map<String, dynamic> food, Map<String, double> acc) {
    final seen = <String>{};

    // 상단 매크로
    final kcal = food['kcal'];
    if (kcal is num) {
      _acc(acc, 'enerc', kcal.toDouble());
      seen.add('enerc');
    }
    final carbs = food['carbs'];
    if (carbs is num) {
      _acc(acc, 'chocdf', carbs.toDouble());
      seen.add('chocdf');
    }
    final prot = food['protein'];
    if (prot is num) {
      _acc(acc, 'prot', prot.toDouble());
      seen.add('prot');
    }
    final fat = food['fat'];
    if (fat is num) {
      _acc(acc, 'fatce', fat.toDouble());
      seen.add('fatce');
    }

    // 영양소 맵(상단에 이미 본 키는 스킵)
    void addMap(Map src) {
      src.forEach((k, v) {
        if (v is! num) return;
        final nk = _normalizeKey(k.toString());
        if (nk.isEmpty) return;
        if (seen.contains(nk)) return;
        _acc(acc, nk, v.toDouble());
        seen.add(nk);
      });
    }

    final n = food['nutrients'];
    if (n is Map) addMap(n);

    final ex = food['extraNutrients'];
    if (ex is Map) addMap(ex);
  }

  // 키 표준화(공통키로 매핑). 제외키 처리 포함.
  String _normalizeKey(String raw) {
    var k = raw.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (_EXCLUDED_KEYS.contains(k)) return '';

    // 에너지
    const kcalKeys = {
      'kcal', 'calorie', 'calories', 'energy', 'energykcal', 'enerc_kcal', 'enerc'
    };
    if (kcalKeys.contains(k)) return 'enerc';

    // 탄수화물
    const carbKeys = {
      'carb', 'carbs', 'carbohydrate', 'carbohydrates', 'cho', 'chocdf'
    };
    if (carbKeys.contains(k)) return 'chocdf';

    // 단백질
    const protKeys = {'protein', 'proteins', 'prot'};
    if (protKeys.contains(k)) return 'prot';

    // 지방
    const fatKeys = {'fat', 'fats', 'totalfat', 'fatce', 'lipid'};
    if (fatKeys.contains(k)) return 'fatce';

    // 포화지방
    const sfaKeys = {'saturatedfat', 'satfat', 'fasat', 'fat_sat'};
    if (sfaKeys.contains(k)) return 'fasat';

    // 당류
    const sugarKeys = {'sugar', 'sugars', 'added_sugar'};
    if (sugarKeys.contains(k)) return 'sugar';

    // 식이섬유 → fibtg 로 통일
    const fiberKeys = {'fiber', 'dietaryfiber', 'fibtg'};
    if (fiberKeys.contains(k)) return 'fibtg';

    // 나트륨 nat → na
    const sodiumSynonyms = {'nat', 'sodium', 'sod', 'na'};
    if (sodiumSynonyms.contains(k)) return 'na';

    // 미네랄/비타민 대표 키
    const direct = {
      'k', 'mg', 'ca', 'fe', 'zn', 'chole', 'p',
      'vita_rae', 'vitc', 'vitd', 'vite', 'vitk',
      'vitb1', 'vitb2', 'vitb3', 'vitb6', 'vitb12',
      'folate', 'biotin', 'pantothenic',
    };
    if (direct.contains(k)) return k;

    // vit* 패턴
    if (k.startsWith('vitb')) return 'vitb${k.substring(4)}'; // vitb1~12
    if (k.startsWith('vit')) return 'vit${k.substring(3)}';   // vitc, vitd, vite, vitk

    return k;
  }

  // 유효한(표준/유닛/일반 영양소) 키만 유지
  Map<String, double> _keepUsefulKeys(Map<String, double> src) {
    final allowed = <String>{
      ..._kUnit.keys,
      ...?_standard?.keys.whereType<String>().map((e) => _normalizeKey(e)),
    };
    final out = <String, double>{};
    src.forEach((k, v) {
      if (_EXCLUDED_KEYS.contains(k)) return;
      final kk = _normalizeKey(k);
      if (allowed.contains(kk) || kk == 'enerc') {
        out[kk] = (out[kk] ?? 0) + v;
      }
    });
    return out;
  }

  // 표준값 안전 조회( nat 포함 동의어/정규화 )
  double _stdValue(String key) {
    final std = _standard ?? const {};
    // 직접키
    final direct = std[key];
    if (direct is num) return direct.toDouble();

    // 동의어
    List<String> syns;
    switch (key) {
      case 'enerc':
        syns = const ['kcal', 'calorie', 'calories', 'energy', 'enerc_kcal'];
        break;
      case 'chocdf':
        syns = const ['carb', 'carbs', 'carbohydrate', 'carbohydrates', 'cho'];
        break;
      case 'prot':
        syns = const ['protein', 'proteins'];
        break;
      case 'fatce':
        syns = const ['fat', 'fats', 'totalfat', 'lipid'];
        break;
      case 'fasat':
        syns = const ['saturatedfat', 'satfat', 'fat_sat'];
        break;
      case 'sugar':
        syns = const ['sugars', 'added_sugar'];
        break;
      case 'fibtg':
        syns = const ['fiber', 'dietaryfiber'];
        break;
      case 'na':
        syns = const ['nat', 'sodium', 'sod'];
        break;
      default:
        syns = const [];
    }
    for (final s in syns) {
      final v = std[s];
      if (v is num) return v.toDouble();
    }

    // 전체 스캔(정규화 일치)
    for (final e in std.entries) {
      if (e.value is! num) continue;
      if (_normalizeKey(e.key) == key) return (e.value as num).toDouble();
    }
    return 0.0;
  }

  // ───────── 영양소 옵션/차트 ─────────
  void _rebuildNutrientOptions() {
    final std = _standard ?? const {};

    // 1) nutritionStandard 안에서 숫자값이 있는 키만 추출 + 정규화
    final avail = <String>{
      for (final e in std.entries)
        if (e.value is num)
          _normalizeKey(e.key)
    }
      ..removeWhere((k) => k.isEmpty || k == 'enerc' || k == 'fatrn');

    // 2) 우리가 지원하는 키만 남기기
    final supported = avail.where((k) => _kKeyToLabel.containsKey(k)).toSet();

    // 3) 요청한 그룹 순서대로 정렬
    List<String> sorted = supported.toList()..sort((a, b) {
      int ga = _groupIndex(a), gb = _groupIndex(b);
      if (ga != gb) return ga.compareTo(gb);
      int oa = _orderInGroup(a), ob = _orderInGroup(b);
      if (oa != ob) return oa.compareTo(ob);
      return _kKeyToLabel[a]!.compareTo(_kKeyToLabel[b]!);
    });

    // 4) 라벨→키 맵 구성
    final map = <String, String>{};
    for (final k in sorted) {
      map[_labelForKey(k)] = k;
    }

    // 안전 가드
    if (map.isEmpty) {
      for (final k in _GROUP_MACROS) {
        if (supported.contains(k)) map[_labelForKey(k)] = k;
      }
    }

    _labelToKey = map;
    _labels = _labelToKey.keys.toList();
    _selectedLabel ??= _labels.first;
    if (!_labelToKey.containsKey(_selectedLabel)) {
      _selectedLabel = _labels.first;
    }
  }

  void _rebuildSeries() {
    if (_labels.isEmpty) {
      _series = List.generate(7, (i) => FlSpot(i.toDouble(), 0));
      return;
    }
    final key = _labelToKey[_selectedLabel]!;
    double target = _stdValue(key); // 정규화 표준값

    // 표준이 없을 때: 최근 7일 “합계” 최대값으로 스케일
    if (target <= 0) {
      double maxActual = 0;
      for (final d in _window7) {
        if (d.v(key) > maxActual) maxActual = d.v(key);
      }
      target = maxActual > 0 ? maxActual : 1.0;
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < 7; i++) {
      final d = (i < _window7.length) ? _window7[i] : null;
      final actual = d?.v(key) ?? 0.0; // 이미 “해당 날짜 합계”
      double pct = (actual / target) * 100.0;
      if (pct.isNaN || pct.isInfinite) pct = 0.0;
      pct = pct.clamp(0.0, 120.0);
      spots.add(FlSpot(i.toDouble(), pct));
    }
    _series = spots;
  }

  // ───────── 날짜 선택(하단 라벨 0~6 각각 독립) ─────────
  Future<void> _pickTickDate(int index) async {
    _ensureTickDates();
    final initial = _tickDates[index];
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: _startOfDay(DateTime.now()),
    );
    if (picked == null) return;

    DateTime d = _startOfDay(picked);

    // 예외 규칙: 두 번째(인덱스 1)가 첫 번째보다 뒤(나중)라면 → 첫 번째의 하루 전으로 설정
    if (index == 1) {
      final first = _tickDates[0];
      if (d.isAfter(first)) {
        d = first.subtract(const Duration(days: 1));
      }
    }

    setState(() {
      _tickDates[index] = d;
    });
  }

  // 상단 "변경" 버튼(창의 끝 날짜만 바꿈 — 그래프 데이터 범위 조정)
  Future<void> _pickChartEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _chartEnd,
      firstDate: DateTime(1900),
      lastDate: _startOfDay(DateTime.now()),
    );
    if (picked == null) return;
    final today = _startOfDay(DateTime.now());
    var newEnd = _startOfDay(picked);
    if (newEnd.isAfter(today)) newEnd = today;

    setState(() {
      _chartEnd = newEnd;
      // 하단 라벨은 사용자가 따로 바꾼 값은 유지; 최초라면 1일 간격 7개로 세팅
      if (_tickDates.isEmpty) {
        final start = newEnd.subtract(const Duration(days: 6));
        _tickDates = List.generate(7, (i) => start.add(Duration(days: i)));
      }
    });
    _subscribeDaily7();
  }

  // ───────── 결과(+) 선택 ─────────
  Future<void> _addDate() async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 후 이용해주세요.')),
      );
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _chartEnd,
      firstDate: DateTime(1900),
      lastDate: _startOfDay(DateTime.now()),
    );
    if (picked == null) return;

    final d0 = _startOfDay(picked);
    final id = _docId(d0);
    final ref = _db
        .collection(COLL_USERS)
        .doc(user.uid)
        .collection(COLL_DAILY)
        .doc(id);

    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'date': Timestamp.fromDate(d0),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final totals = await _resolveDailyTotalsMap(user.uid, d0);
    final kcal = (totals['enerc'] ?? 0).toInt();
    final label = _labelDate(d0);

    _pinnedDate = d0;
    _pinnedItem = {'date': label, 'cal': '$kcal kcal'};

    final newResults = List<Map<String, String>>.from(_results);
    final dupIdx = newResults.indexWhere((e) => e['date'] == label);
    if (dupIdx != -1) newResults.removeAt(dupIdx);
    newResults.insert(0, _pinnedItem!);
    while (newResults.length > 7) newResults.removeLast();

    if (mounted) {
      setState(() {
        _results = newResults;
      });
    }
  }

  // ───────── UI ─────────
  @override
  Widget build(BuildContext context) {
    const accentGreen = Color(0xFF24C486);
    const backgroundMint = Color(0xFFDBFBED);

    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(child: Text(_error!, style: TextStyle(color: Colors.red))),
        ),
      );
    }

    final selectedKey = _labelToKey[_selectedLabel]!;
    _ensureTickDates(); // 안전 보장

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 1) 프로필
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: InkWell(
                onTap: () => Navigator.push(context, _noAnim(const ProfilePage())),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.grey[300],
                      backgroundImage:
                      (_photoUrl != null) ? NetworkImage(_photoUrl!) : null,
                      child: (_photoUrl == null)
                          ? const Icon(Icons.person, size: 32, color: Colors.grey)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _userName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            // 2) 섹션 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  const Text('영양 변화',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  InkWell(
                    onTap: _pickChartEnd,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: Colors.black54),
                          const SizedBox(width: 6),
                          Text(
                            _labelDate(_chartEnd),
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                          const SizedBox(width: 4),
                          const Text('변경', style: TextStyle(fontSize: 12, color: Colors.black45)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3) 영양 변화 카드(차트 + 영양소 선택)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Spacer(),
                        _NutrientPickerButton(
                          label: _selectedLabel ?? '',
                          onTap: _showNutrientSheet,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        LineChartData(
                          backgroundColor: Colors.transparent,
                          gridData: FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
                                interval: 1,
                                getTitlesWidget: (val, meta) {
                                  final i = val.toInt();
                                  if (i < 0 || i > 6) return const SizedBox.shrink();
                                  final labelDate = _tickDates[i];
                                  return GestureDetector(
                                    onTap: () async => _pickTickDate(i),
                                    behavior: HitTestBehavior.opaque,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        _mmdd(labelDate),
                                        style: const TextStyle(
                                            color: Colors.black54, fontSize: 12),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 56,
                                interval: 20,
                                getTitlesWidget: (val, meta) {
                                  final pct = val.toInt();
                                  if (pct == 0 || pct == 120) return const SizedBox.shrink();
                                  final key = _labelToKey[_selectedLabel]!;
                                  double target = _stdValue(key); // 보정
                                  if (target <= 0) {
                                    double maxActual = 0;
                                    for (final d in _window7) {
                                      if (d.v(key) > maxActual) maxActual = d.v(key);
                                    }
                                    target = maxActual > 0 ? maxActual : 1.0;
                                  }
                                  final amount = (target * (pct / 100.0));
                                  final text = _formatAmountWithUnit(key, amount);
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: SizedBox(
                                      width: 52,
                                      child: Text(
                                        text,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            topTitles:
                            AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles:
                            AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          minX: 0,
                          maxX: 6,
                          minY: 0,
                          maxY: 120,
                          lineBarsData: [
                            LineChartBarData(
                              spots: _series.isEmpty
                                  ? const [
                                FlSpot(0, 0),
                                FlSpot(1, 0),
                                FlSpot(2, 0),
                                FlSpot(3, 0),
                                FlSpot(4, 0),
                                FlSpot(5, 0),
                                FlSpot(6, 0),
                              ]
                                  : _series,
                              isCurved: true,
                              color: const Color(0xFF49D199),
                              barWidth: 3,
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // ✅ 요청: 범위 텍스트 제거
                  ],
                ),
              ),
            ),

            // 4) 결과 헤더 + 플러스
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('결과',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.black54, size: 24),
                    onPressed: _addDate,
                  ),
                ],
              ),
            ),

            // 5) 결과 리스트
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final item = _results[i];
                  final isPinned = (_pinnedDate != null &&
                      item['date'] == _labelDate(_pinnedDate!));
                  return GestureDetector(
                    onTap: () {
                      final d = _parseLabelDate(item['date']!);
                      Navigator.push(context, _noAnim(ResultPage(date: d)));
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                        border: isPinned
                            ? Border.all(color: const Color(0xFF49D199), width: 1.5)
                            : null,
                      ),
                      padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(item['date']!, style: const TextStyle(fontSize: 14)),
                          Text(item['cal']!,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // 6) 하단 네비게이션 바
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: backgroundMint,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Stack(
            children: [
              // 인식(좌)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 70),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt,
                          size: 24, color: accentGreen.withOpacity(0.5)),
                      const SizedBox(height: 4),
                      Text('인식',
                          style: TextStyle(
                              fontSize: 12, color: accentGreen.withOpacity(0.5))),
                    ],
                  ),
                ),
              ),
              // 홈(중앙)
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset('assets/home_icon.svg',
                        width: 24,
                        height: 24,
                        color: accentGreen.withOpacity(0.5)),
                    const SizedBox(height: 4),
                    Text('홈',
                        style: TextStyle(
                            fontSize: 12, color: accentGreen.withOpacity(0.5))),
                  ],
                ),
              ),
              // 통계(우)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 52),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/static_round.svg',
                        width: 56,
                        height: 56,
                      ),
                    ),
                  ),
                ),
              ),
              // 클릭 오버레이
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.push(
                          context,
                          _noAnim(BarcodePage(mealName: '아침식사')),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.push(
                          context,
                          _noAnim(const NutritionHomePage()),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: null,
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

  // ───────── 영양소 선택 바텀시트 ─────────
  Future<void> _showNutrientSheet() async {
    final sel = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final items = _labels;
        final maxHeight = 56.0 * math.min(6, items.length) + 16.0;
        return SizedBox(
          height: maxHeight,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final label = items[i];
              final selected = label == _selectedLabel;
              return ListTile(
                dense: true,
                title: Text(label),
                trailing: selected
                    ? const Icon(Icons.check, size: 18, color: Color(0xFF24C486))
                    : null,
                onTap: () => Navigator.pop(ctx, label),
              );
            },
          ),
        );
      },
    );

    if (sel != null && sel != _selectedLabel) {
      setState(() {
        _selectedLabel = sel;
        _rebuildSeries();
      });
    }
  }

  // ───────── 헬퍼 ─────────
  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return 0.0;
  }

  String _labelForKey(String key) {
    if (_kKeyToLabel.containsKey(key)) return _kKeyToLabel[key]!;
    final k = key.toLowerCase();
    if (_EXCLUDED_KEYS.contains(k)) return '';
    if (k.startsWith('vitb')) return '비타민B${k.substring(4)}';
    if (k.startsWith('vit')) return '비타민${k.substring(3).toUpperCase()}';
    if (k.contains('fiber') || k == 'fibtg') return '식이섬유';
    return key;
  }

  String _formatAmountWithUnit(String key, double amount) {
    final unit = _kUnit[key] ?? '';
    String n;
    if (unit == 'g') {
      n = amount >= 100 ? amount.round().toString() : amount.toStringAsFixed(1);
    } else if (unit == 'kcal' || unit == 'mg' || unit.contains('µg')) {
      n = amount.round().toString();
    } else {
      n = amount.toStringAsFixed(1);
    }
    return unit.isEmpty ? n : '$n $unit';
  }
}

// ───────── 내부 모델 ─────────
class _DayNutri {
  final DateTime date;
  final Map<String, double> vals;
  _DayNutri({required this.date, required this.vals});
  double v(String key) => vals[key] ?? 0.0;
}

// ───────── 영양소 선택 버튼 ─────────
class _NutrientPickerButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NutrientPickerButton({required this.label, required this.onTap, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: Colors.black87)),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}
