// lib/result.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'statistics_page.dart'; // 통계 페이지
import 'profile.dart';         // 프로필
import 'main.dart';            // NutritionHomePage
import 'barcode.dart';         // 바코드 인식
import 'food.dart';            // 추천음식 페이지

class ResultPage extends StatefulWidget {
  final DateTime date;
  const ResultPage({Key? key, required this.date}) : super(key: key);

  @override
  _ResultPageState createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  static const accentGreen = Color(0xFF24C486);
  static const backgroundMint = Color(0xFFDBFBED);

  // ─────────────────────── Firestore & 상태 ───────────────────────
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  // 사용자
  String _userName = 'user';
  String? _photoUrl;

  // 표준(목표치) — users/{uid}/nutritionStandard
  Map<String, dynamic> _std = {};

  // 일일 총섭취치 — users/{uid}/daily/{yyyy-MM-dd}
  Map<String, dynamic> _day = {};

  // 음식 리스트 — users/{uid}/daily/{yyyy-MM-dd}/foods
  List<Map<String, dynamic>> _foods = [];

  // ─────────────────────── 영양소 선택(팝업) 관련 ───────────────────────
  static const Set<String> _EXCLUDED_KEYS = {
    'watergoalmi', 'water_goal_ml', 'waterGoalMl', 'water_goal_mi', 'water'
  };

  // 한글 라벨(기본)
  static const Map<String, String> _kKeyToLabel = {
    'enerc': '칼로리',
    'prot': '단백질',
    'chocdf': '탄수화물',
    'fatce': '지방',
    'sugar': '당류',
    'fasat': '포화지방',
    'fatrn': '트랜스지방',
    'fibtg': '식이섬유',
    'fiber': '식이섬유',
    'na': '나트륨',
    'k': '칼륨',
    'p': '인',
    'mg': '마그네슘',
    'ca': '칼슘',
    'fe': '철',
    'zn': '아연',
    'chole': '콜레스테롤',
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
    'pantothenic': '판토텐산(B5)',
  };

  // 단위
  static const Map<String, String> _kUnit = {
    'enerc': 'kcal',
    'prot': 'g',
    'chocdf': 'g',
    'fatce': 'g',
    'sugar': 'g',
    'fasat': 'g',
    'fatrn': 'g',
    'fibtg': 'g',
    'fiber': 'g',
    'na': 'mg',
    'k': 'mg',
    'p': 'mg',
    'mg': 'mg',
    'ca': 'mg',
    'fe': 'mg',
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
    'vitb12': 'µg',
    'folate': 'µg',
    'biotin': 'µg',
    'pantothenic': 'mg',
  };

  // 팝업 선택 옵션
  Map<String, String> _labelToKey = {};            // "단백질" -> "prot"
  Map<String, String> _keyLabelFromOptions = {};   // "prot"  -> "단백질" (팝업 기준 라벨)
  List<String> _labels = [];
  String? _selectedLabel;                          // 현재 선택(라벨)
  String get _selectedKey => _labelToKey[_selectedLabel] ?? 'enerc';

  // 레이더 차트용 키 목록(표준이 있는 키만)
  List<String> _radarKeys = [];

  // 분류 파라미터(경계 완화)
  static const double _LOW_RATIO = 0.90;  // 90% 미만 → 부족
  static const double _HIGH_RATIO = 1.10; // 110% 초과 → 과다
  static const int _MAX_BADGES = 6;

  // ─────────────────────── 유틸 ───────────────────────
  String get _docId {
    final d = DateTime(widget.date.year, widget.date.month, widget.date.day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String get formattedDate {
    final d = widget.date;
    return '${d.year}년 ${d.month}월 ${d.day}일';
  }

  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribeUser(); // 아이콘/이름 실시간 업데이트
  }

  void _subscribeUser() {
    final user = _auth.currentUser;
    if (user == null) return;
    _db.collection('users').doc(user.uid).snapshots().listen((snap) {
      final u = snap.data() ?? {};
      final name = (u['name'] ??
          u['displayName'] ??
          _auth.currentUser?.displayName ??
          _auth.currentUser?.email ??
          'user')
          .toString();
      final photo = (u['photoURL'] ??
          u['photoUrl'] ??
          u['avatarUrl'] ??
          _auth.currentUser?.photoURL)
          ?.toString();

      if (!mounted) return;
      setState(() {
        _userName = name;
        _photoUrl = (photo != null && photo.isNotEmpty) ? photo : null;
      });
    });
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) throw '로그인이 필요합니다.';
      final uid = user.uid;

      final userRef = _db.collection('users').doc(uid);
      final dailyRef = userRef.collection('daily').doc(_docId);

      // 1) 표준 로드
      final uSnap = await userRef.get();
      _std =
          (uSnap.data()?['nutritionStandard'] as Map<String, dynamic>?) ?? {};

      // 2) 일일 합계 로드(필요 시 표시용 폴백으로 사용)
      final dSnap = await dailyRef.get();
      _day = dSnap.data() ?? {};

      // 3) 음식 리스트 로드 (해당 날짜만)
      final fSnap = await dailyRef.collection('foods').get();
      _foods = fSnap.docs.map((e) => e.data()).toList();

      // 폴백: daily/foods가 비어 있으면 meals 루트에서 "해당 날짜"만
      if (_foods.isEmpty) {
        _foods = await _gatherFoodsFromMealsRoot(
          uid,
          DateTime(widget.date.year, widget.date.month, widget.date.day),
        );
      }

      // 4) foods 로부터 합계 파생(일일문서가 비어도 화면 표시용으로 사용)
      final derived = _totalsFromFoods(_foods);
      if (derived.isNotEmpty) {
        _day = {..._day, ...derived}; // 로컬 병합(표시용) — 파생값이 우선
      }

      // 5) 선택 옵션 & 레이더 키 구성 (정규화 기반)
      _rebuildNutrientOptions();
      _rebuildRadarKeys();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  // meals 루트(아침/점심/저녁/간식)에서 해당 날짜의 foods 모으기 (해당 날짜만)
  Future<List<Map<String, dynamic>>> _gatherFoodsFromMealsRoot(
      String uid, DateTime date) async {
    final out = <Map<String, dynamic>>[];
    final mealsRoot = _db.collection('users').doc(uid).collection('meals');
    final names = ['아침식사', '점심식사', '저녁식사', '간식'];
    final docIdPrefix = '${date.year}-${date.month}-${date.day}_'; // 0패딩 없음
    for (final name in names) {
      final foodsSnap =
      await mealsRoot.doc('$docIdPrefix$name').collection('foods').get();
      for (final f in foodsSnap.docs) {
        out.add(f.data());
      }
    }
    return out;
  }

  // ───────── DB에서 "음식 문서"의 영양소 값을 안전하게 꺼내기(우선순위: nutrients → extraNutrients → top-level) ─────────
  double _pickFoodField(Map<String, dynamic> food, String wantedKey) {
    final want = _normalizeKey(wantedKey);

    // 1) nutrients 맵
    final n = food['nutrients'];
    if (n is Map) {
      for (final e in n.entries) {
        if (e.value is! num) continue;
        if (_normalizeKey(e.key) == want) return (e.value as num).toDouble();
      }
    }

    // 2) extraNutrients 맵
    final ex = food['extraNutrients'];
    if (ex is Map) {
      for (final e in ex.entries) {
        if (e.value is! num) continue;
        if (_normalizeKey(e.key) == want) return (e.value as num).toDouble();
      }
    }

    // 3) 최후: top-level
    for (final e in food.entries) {
      if (e.value is! num) continue;
      if (_normalizeKey(e.key) == want) return (e.value as num).toDouble();
    }

    return 0.0;
  }

  // foods 배열에서 각 영양소 합계 만들기 — 중복 키(상단+맵)로 2중집계되지 않도록 nutrients/extraNutrients 우선 사용
  Map<String, double> _totalsFromFoods(List<Map<String, dynamic>> foods) {
    final acc = <String, double>{};

    for (final f in foods) {
      // 우선 합치기: nutrients
      final seenKeys = <String>{};
      final n = f['nutrients'];
      if (n is Map) {
        n.forEach((k, v) {
          if (v is! num) return;
          final key = _normalizeKey(k);
          if (key.isEmpty) return;
          acc[key] = (acc[key] ?? 0) + v.toDouble();
          seenKeys.add(key);
        });
      }
      // extraNutrients (아직 안 본 키만)
      final ex = f['extraNutrients'];
      if (ex is Map) {
        ex.forEach((k, v) {
          if (v is! num) return;
          final key = _normalizeKey(k);
          if (key.isEmpty || seenKeys.contains(key)) return;
          acc[key] = (acc[key] ?? 0) + v.toDouble();
          seenKeys.add(key);
        });
      }
      // top-level (맵에서 못 본 키만)
      f.forEach((k, v) {
        if (v is! num) return;
        final key = _normalizeKey(k);
        if (key.isEmpty || seenKeys.contains(key)) return;
        acc[key] = (acc[key] ?? 0) + v.toDouble();
      });
    }

    // 표시 가능한 키만 유지
    final allowed = <String>{..._kUnit.keys, ..._std.keys.whereType<String>()};
    final out = <String, double>{};
    acc.forEach((k, v) {
      if (_EXCLUDED_KEYS.contains(k)) return;
      if (allowed.contains(k) || k == 'enerc') out[k] = v;
    });
    return out;
  }

  // 키 정규화(표시용 공통키) — ★ 약어/변형 매핑 추가
  String _normalizeKey(String raw) {
    var k = raw.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (_EXCLUDED_KEYS.contains(k)) return '';

    // kcal 계열 → enerc
    const kcalKeys = {
      'kcal', 'calorie', 'calories', 'energy', 'energykcal', 'enerc_kcal', 'enerc'
    };
    if (kcalKeys.contains(k)) return 'enerc';

    // 탄/단/지
    const carbKeys = {'carb', 'carbs', 'carbohydrate', 'carbohydrates', 'cho', 'chocdf'};
    if (carbKeys.contains(k)) return 'chocdf';

    const protKeys = {'protein', 'proteins', 'prot'};
    if (protKeys.contains(k)) return 'prot';

    const fatKeys = {'fat', 'fats', 'totalfat', 'fatce', 'lipid'};
    if (fatKeys.contains(k)) return 'fatce';

    const sfaKeys = {'saturatedfat', 'satfat', 'fasat', 'fat_sat'};
    if (sfaKeys.contains(k)) return 'fasat';

    const sugarKeys = {'sugar', 'sugars', 'added_sugar'};
    if (sugarKeys.contains(k)) return 'sugar';

    const fiberKeys = {'fiber', 'dietaryfiber', 'fibtg'};
    if (fiberKeys.contains(k)) return 'fiber';

    // nat → na
    const sodiumSynonyms = {'nat', 'sodium', 'sod', 'na'};
    if (sodiumSynonyms.contains(k)) return 'na';

    // ───── 추가: 약어/변형 → 표준 키 ─────
    // 비타민 B1 (Thiamin)
    const b1Keys = {'thia', 'thiamin', 'thiamine', 'vitaminb1', 'vitamin_b1', 'vitb1'};
    if (b1Keys.contains(k)) return 'vitb1';

    // 비타민 B2 (Riboflavin)
    const b2Keys = {'ribf', 'riboflavin', 'vitaminb2', 'vitamin_b2', 'vitb2'};
    if (b2Keys.contains(k)) return 'vitb2';

    // 비타민 B3 (Niacin)
    const b3Keys = {'nia', 'niacin', 'niac', 'vitaminb3', 'vitamin_b3', 'vitb3'};
    if (b3Keys.contains(k)) return 'vitb3';

    // 비타민 A (RAE) — 다양한 표기 흡수
    const aKeys = {
      'retol', 'retinol', 'vita_rae', 'vitarae', 'vitaminarae', 'vitamin_a_rae', 'arae', 'cartb'
    };
    if (aKeys.contains(k)) return 'vita_rae';

    // 그대로 쓰는 키들
    const direct = {
      'na','k','p','mg','ca','fe','zn','chole',
      'vita_rae','vitc','vitd','vite','vitk',
      'vitb1','vitb2','vitb3','vitb6','vitb12',
      'folate','biotin','pantothenic','fatrn'
    };
    if (direct.contains(k)) return k;

    if (k.startsWith('vitb')) return 'vitb${k.substring(4)}';
    if (k.startsWith('vit')) return 'vit${k.substring(3)}';
    return k;
  }

  // 표준값 안전 조회( nat 포함 동의어/정규화 )
  double _stdValue(String key) {
    final std = _std;
    // 직접키
    final direct = std[key];
    if (direct is num) return direct.toDouble();

    // 동의어 처리
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
      case 'fiber':
        syns = const ['fibtg', 'dietaryfiber'];
        break;
      case 'na':
        syns = const ['nat', 'sodium', 'sod'];
        break;
    // ↓ 추가된 비타민 동의어들도 안전 조회되도록
      case 'vitb1':
        syns = const ['thia', 'thiamin', 'thiamine', 'vitaminb1', 'vitamin_b1'];
        break;
      case 'vitb2':
        syns = const ['ribf', 'riboflavin', 'vitaminb2', 'vitamin_b2'];
        break;
      case 'vitb3':
        syns = const ['nia', 'niacin', 'niac', 'vitaminb3', 'vitamin_b3'];
        break;
      case 'vita_rae':
        syns = const ['retol', 'retinol', 'vitarae', 'vitaminarae', 'vitamin_a_rae', 'arae', 'cartb'];
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

  // 표준의 키들 중 허용/라벨 가능한 것만 옵션으로 (정규화해서 표시)
  void _rebuildNutrientOptions() {
    final map = <String, String>{};

    final keys = _std.keys
        .where((k) =>
    _std[k] is num &&
        !_EXCLUDED_KEYS.contains(k) &&
        !_EXCLUDED_KEYS.contains(k.toLowerCase()))
        .map((k) => _normalizeKey(k))
        .where((k) => _kKeyToLabel.containsKey(k))
        .cast<String>()
        .toList();

    // 보기 좋은 우선순위
    const preferred = ['enerc', 'prot', 'chocdf', 'fatce'];
    for (final k in preferred) {
      if (keys.contains(k)) map[_labelForKey(k)] = k;
    }
    for (final k in keys) {
      if (map.containsValue(k)) continue;
      map[_labelForKey(k)] = k;
    }

    // 기본 옵션
    if (map.isEmpty) {
      map.addAll({'칼로리': 'enerc', '단백질': 'prot', '탄수화물': 'chocdf', '지방': 'fatce'});
    }

    _labelToKey = map;
    _labels = _labelToKey.keys.toList();

    // ✅ 팝업 기준 라벨 역맵: key -> label (레이더/배지/헤더에 동일 사용)
    _keyLabelFromOptions = {
      for (final e in _labelToKey.entries) e.value: e.key,
    };

    _selectedLabel ??= _labels.first;
    if (!_labelToKey.containsKey(_selectedLabel)) {
      _selectedLabel = _labels.first;
    }
  }

  // 레이더 축은 "표준이 존재하는 키"만 사용 (정규화)
  void _rebuildRadarKeys() {
    final keys = _std.keys
        .where((k) =>
    _std[k] is num &&
        !_EXCLUDED_KEYS.contains(k) &&
        _kKeyToLabel.containsKey(_normalizeKey(k)))
        .map((e) => _normalizeKey(e))
        .where((k) => k.isNotEmpty)
        .toSet()
        .toList();

    if (keys.length < 3) {
      for (final k in ['prot', 'chocdf', 'fatce', 'enerc']) {
        if (!keys.contains(k)) keys.add(k);
        if (keys.length >= 3) break;
      }
    }
    _radarKeys = keys;
  }

  String _labelForKey(String key) {
    if (_kKeyToLabel.containsKey(key)) return _kKeyToLabel[key]!;
    final k = key.toLowerCase();
    if (_EXCLUDED_KEYS.contains(k)) return '';
    if (k == 'nat') return '나트륨'; // 안전 처리
    if (k.startsWith('vitb')) return '비타민B${k.substring(4)}';
    if (k.startsWith('vit')) return '비타민${k.substring(3).toUpperCase()}';
    if (k.contains('fiber')) return '식이섬유';
    return key;
  }

  static double _pickNumber(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  String _fmt(double v, {bool intLike = false}) {
    if (intLike) return v.round().toString();
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  // ─────────────────────── 레이더 차트 데이터(영양기준 대비 백분율 0~100%) ───────────────────────
  List<RadarEntry> _makeRadarEntries() {
    final entries = <RadarEntry>[];
    for (final key in _radarKeys) {
      // 하루치만: 해당 날짜 foods 합(있으면) → 없으면 daily 문서 값
      final actual =
      _foods.isNotEmpty ? _foodsSumForField(key) : _pickNumber(_day[key]);
      final goal = _stdValue(key);

      double pct = (goal > 0.0) ? (actual / goal) * 100.0 : 0.0;
      if (pct.isNaN || pct.isInfinite) pct = 0.0;
      pct = pct.clamp(0.0, 100.0).toDouble(); // 0~100%
      entries.add(RadarEntry(value: pct));
    }
    return entries;
  }

  // nutrition.dart처럼 한 줄: [음식명(좌)] [선택 영양소 함유량(우)]
  List<Map<String, String>> _buildFoodRows() {
    final key = _selectedKey;
    final unit = _kUnit[key] ?? '';

    if (_foods.isNotEmpty) {
      return _foods.map((f) {
        final name = (f['name'] ?? f['foodName'] ?? '식품').toString();
        // DB에서(맵 우선) 해당 영양소 값 읽기
        final v = _pickFoodField(f, key);
        final vText =
        '${_fmt(v, intLike: unit == "kcal" || unit == "mg" || unit.contains("µg"))} $unit'
            .trim();
        return {'name': name, 'value': vText};
      }).toList();
    }

    // 폴백: foods가 전혀 없으면 합계 한 줄
    final sum = _pickNumber(_day[key]);
    final vText =
    '${_fmt(sum, intLike: unit == "kcal" || unit == "mg" || unit.contains("µg"))} $unit'
        .trim();
    return [
      {'name': '합계', 'value': vText},
    ];
  }

  // 합계(선택 영양소) — enerc(칼로리)는 daily 문서를 우선 사용(있다면)
  double _foodsSumForField(String key) {
    if (key == 'enerc') {
      final dbVal = _pickNumber(_day['enerc']);
      if (dbVal > 0) return dbVal;
    }
    if (_foods.isEmpty) return _pickNumber(_day[key]);

    double s = 0.0;
    for (final f in _foods) {
      s += _pickFoodField(f, key);
    }
    return s;
  }

  // ───────── 부족/과다 분류 계산 (라벨은 팝업 기준) ─────────
  List<_NutStatus> _computeStatuses() {
    final list = <_NutStatus>[];

    for (final e in _std.entries) {
      if (e.value is! num) continue;
      final normKey = _normalizeKey(e.key);
      if (normKey.isEmpty) continue;

      final stdVal = _stdValue(normKey);
      if (stdVal <= 0) continue;

      final actual = _foodsSumForField(normKey);
      final pct = (actual / stdVal) * 100.0;
      if (pct.isNaN || pct.isInfinite) continue;

      list.add(_NutStatus(
        key: normKey,
        // ✅ 팝업 라벨 우선 사용 (없으면 기본 라벨)
        label: _keyLabelFromOptions[normKey] ?? _labelForKey(normKey),
        pct: pct,
      ));
    }

    return list;
  }

  List<_NutStatus> _pickDeficient(List<_NutStatus> all) {
    final out = all.where((s) => s.pct < _LOW_RATIO * 100.0).toList();
    out.sort((a, b) => a.pct.compareTo(b.pct)); // 가장 부족한 순
    if (out.length > _MAX_BADGES) return out.sublist(0, _MAX_BADGES);
    return out;
  }

  List<_NutStatus> _pickExcessive(List<_NutStatus> all) {
    final out = all.where((s) => s.pct > _HIGH_RATIO * 100.0).toList();
    out.sort((a, b) => b.pct.compareTo(a.pct)); // 가장 과다한 순
    if (out.length > _MAX_BADGES) return out.sublist(0, _MAX_BADGES);
    return out;
  }

  String _pctText(double pct) => '${_fmt(pct)}%';

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: accentGreen),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _badgeWrap(List<_NutStatus> items) {
    if (items.isEmpty) {
      return const Text('없음', style: TextStyle(color: Colors.black54));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((s) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accentGreen.withOpacity(0.08),
            border: Border.all(color: accentGreen),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${s.label} ${_pctText(s.pct)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Text(_error!, style: TextStyle(color: Colors.red[700])),
          ),
        ),
      );
    }

    final rows = _buildFoodRows();
    final unit = _kUnit[_selectedKey] ?? '';
    final sum = _foodsSumForField(_selectedKey);
    final stdVal = _stdValue(_selectedKey); // ← 정규화 기반 표준값 조회

    double pct = 0.0;
    if (stdVal > 0.0) {
      pct = (sum / stdVal) * 100.0;
      pct = pct.clamp(0.0, 999.0).toDouble();
    }

    final rightHeader =
        '${_keyLabelFromOptions[_selectedKey] ?? _labelForKey(_selectedKey)}'
        '${_kUnit[_selectedKey] != null ? ' (${_kUnit[_selectedKey]})' : ''}';

    // ── 부족/과다 목록 계산(라벨 = 팝업 기준)
    final statuses = _computeStatuses();
    final deficient = _pickDeficient(statuses);
    final excessive = _pickExcessive(statuses);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1) 상단바: 프로필(실시간) + 닫기
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () =>
                          Navigator.push(context, _noAnim(const ProfilePage())),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: (_photoUrl != null)
                                ? NetworkImage(_photoUrl!)
                                : null,
                            child: (_photoUrl == null)
                                ? const Icon(Icons.person,
                                size: 32, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(_userName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.push(
                        context,
                        _noAnim(const StatisticsPage()),
                      ),
                    ),
                  ],
                ),
              ),

              // 2) 제목(날짜)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Center(
                  child: Text(
                    formattedDate,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              // 2.5) 부족/과다 섭취 요약 배지 (날짜 아래, 전체영양변화 위)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('부족한 영양소', Icons.trending_down),
                    const SizedBox(height: 8),
                    _badgeWrap(deficient),
                    const SizedBox(height: 12),
                    _sectionTitle('과다 섭취', Icons.trending_up),
                    const SizedBox(height: 8),
                    _badgeWrap(excessive),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 3) 전체 영양 변화 (표준 대비 %) + 추천음식 버튼
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('전체 영양 변화 (기준 대비 %)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentGreen,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(context, _noAnim(const FoodPage()));
                      },
                      child: const Text(
                        '추천음식',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                height: 250,
                child: RadarChart(
                  RadarChartData(
                    dataSets: [
                      RadarDataSet(
                        fillColor: Colors.grey.withOpacity(0.25),
                        borderColor: accentGreen,
                        entryRadius: 2.0,
                        dataEntries: _makeRadarEntries(), // 0~100%
                      ),
                    ],
                    radarBackgroundColor: Colors.transparent,
                    borderData: FlBorderData(show: false),
                    radarShape: RadarShape.circle,
                    // ✅ 레이더 축 라벨도 팝업 기준 라벨 우선 사용
                    getTitle: (idx, _) => RadarChartTitle(
                      text: _keyLabelFromOptions[_radarKeys[idx]] ??
                          _labelForKey(_radarKeys[idx]),
                    ),
                    titleTextStyle:
                    const TextStyle(color: Colors.black, fontSize: 12),
                    titlePositionPercentageOffset: 0.25,
                    tickCount: 5, // 0,25,50,75,100% 느낌
                    ticksTextStyle:
                    const TextStyle(color: Colors.transparent),
                    tickBorderData: const BorderSide(color: Colors.grey),
                    gridBorderData: const BorderSide(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 4) 영양 정보 표 헤더 + 영양소 선택
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('영양 정보 표',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    _NutrientPickerButton(
                      label: _selectedLabel ?? '',
                      onTap: _showNutrientSheet,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 5) 표: 좌(식품명) | 우(선택 영양소 함유량)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: accentGreen),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      // 헤더
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('식품명'),
                            Text(rightHeader),
                          ],
                        ),
                      ),
                      Divider(color: accentGreen, height: 0.0, thickness: 1.0),

                      // 데이터 행
                      ...rows.map(
                            (r) => Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r['name']!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    r['value']!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                    const TextStyle(color: Colors.black87),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      Divider(color: accentGreen, height: 0.0, thickness: 1.0),

                      // 합계
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text('합계',
                                  style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            SizedBox(
                              width: 140,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${_fmt(sum, intLike: unit == "kcal" || unit == "mg" || unit.contains("µg"))} $unit',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 1일 기준
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: 12, left: 12, right: 12),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text('1일 영양섭취기준 (%)',
                                  style: TextStyle(color: Colors.black54)),
                            ),
                            SizedBox(
                              width: 140,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${_fmt(pct)}%',
                                  style:
                                  const TextStyle(color: Colors.black54),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
              // 인식 버튼
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 70),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      _noAnim(BarcodePage(mealName: '아침식사')),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt,
                            size: 24, color: accentGreen.withOpacity(0.5)),
                        const SizedBox(height: 4),
                        Text('인식',
                            style: TextStyle(
                                fontSize: 12,
                                color: accentGreen.withOpacity(0.5))),
                      ],
                    ),
                  ),
                ),
              ),

              // 홈 버튼
              Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    _noAnim(const NutritionHomePage()),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/home_icon.svg',
                        width: 24,
                        height: 24,
                        color: accentGreen.withOpacity(0.5),
                      ),
                      const SizedBox(height: 4),
                      Text('홈',
                          style: TextStyle(
                              fontSize: 12,
                              color: accentGreen.withOpacity(0.5))),
                    ],
                  ),
                ),
              ),

              // 통계 버튼 (현재 페이지이므로 동작 없음)
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
            ],
          ),
        ),
      ),
    );
  }

  // ───────── 영양소 선택 바텀시트 (현재 선택 중앙에 보이도록) ─────────
  Future<void> _showNutrientSheet() async {
    final sel = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final items = _labels;
        if (items.isEmpty) {
          return const SizedBox(
            height: 120,
            child: Center(child: Text('선택할 항목이 없습니다')),
          );
        }

        const itemHeight = 56.0;
        final visibleCount = math.min(6, items.length);
        final sheetHeight = itemHeight * visibleCount + 16.0;

        final selectedIndex = items.indexOf(_selectedLabel ?? items.first);
        final controller = ScrollController();

        // 현재 선택 항목이 가운데 오도록
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!controller.hasClients) return;
          final target = math.max(
            0.0,
            selectedIndex * itemHeight - (sheetHeight - itemHeight) / 2,
          );
          final maxScroll = controller.position.maxScrollExtent;
          controller.jumpTo(target.clamp(0.0, maxScroll));
        });

        return SizedBox(
          height: sheetHeight,
          child: ListView.builder(
            controller: controller,
            itemExtent: itemHeight,
            itemCount: items.length,
            itemBuilder: (_, i) {
              final label = items[i];
              final selected = label == _selectedLabel;
              return ListTile(
                dense: true,
                title: Text(label),
                trailing: selected
                    ? const Icon(Icons.check,
                    size: 18, color: Color(0xFF24C486))
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
      });
    }
  }
}

// ───────── 상태용 클래스 ─────────
class _NutStatus {
  final String key;
  final String label; // 팝업 라벨
  final double pct;   // 표준 대비 백분율
  _NutStatus({required this.key, required this.label, required this.pct});
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
            Text(label,
                style: const TextStyle(fontSize: 14, color: Colors.black87)),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down,
                size: 18, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}
