// lib/food.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ▶ 정적 DB
import 'nutrients_db.dart';

class FoodPage extends StatefulWidget {
  const FoodPage({Key? key}) : super(key: key);

  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  static const Color accentGreen = Color(0xFF24C486);

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  // nutritionStandard에서 가져온 키(표시용 라벨 매핑 포함)
  List<String> _nutriKeys = [];
  Map<String, String> _labelFor = {}; // key -> 한글 라벨 (팝업/표 기준)
  String? _selectedKey;

  // ▶ 제외 키 모음: 칼로리(enerc), 물 관련 키, 트랜스지방(fatrn) 제외
  static const Set<String> _EXCLUDED_KEYS = {
    'enerc', // 칼로리 제외
    'watergoalml', 'water_goal_ml', 'waterGoalMl',
    'watergoalmi', 'water_goal_mi',
    'water', 'waterml', 'water_ml', 'waterintake',
    'fatrn', // ❌ 트랜스지방 제거
  };

  // ▶ 정렬 그룹: 탄단지 → 나머지 → 비타민 → 무기질
  static const List<String> _GROUP_MACROS = ['chocdf', 'prot', 'fatce'];
  static const List<String> _GROUP_OTHERS = ['fibtg', 'sugar', 'fasat', 'chole'];
  static const List<String> _GROUP_VITS = [
    'vita_rae','vitb1','vitb2','vitb3','vitb6','vitb12','vitc','vitd','vite','vitk','folate','biotin','pantothenic'
  ];
  static const List<String> _GROUP_MINERALS = ['na','k','p','mg','ca','fe','zn'];

  @override
  void initState() {
    super.initState();
    _loadUserStandardKeys();
  }

  Future<void> _loadUserStandardKeys() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw '로그인이 필요합니다.';
      final snap = await _db.collection('users').doc(uid).get();
      final std = (snap.data()?['nutritionStandard'] as Map<String, dynamic>?) ?? {};

      // 숫자값이 있는 키만 채택 + 정규화 + 제외 처리
      final keys = <String>[];
      std.forEach((k, v) {
        if (v is num) {
          final nk = _normalizeKey(k);
          if (nk.isNotEmpty && !_EXCLUDED_KEYS.contains(nk)) {
            keys.add(nk);
          }
        }
      });

      // 표준이 비어있거나 전부 제외되면 기본 후보(칼로리/물 제외, fatrn 제외)
      final defaults = [
        ..._GROUP_MACROS, ..._GROUP_OTHERS, ..._GROUP_VITS, ..._GROUP_MINERALS
      ];
      final dedup = <String>{...keys};
      if (dedup.isEmpty) {
        dedup.addAll(defaults);
      }

      // 라벨 맵 만들기 — DB 라벨 우선, 없으면 규칙 라벨
      final labelMap = <String, String>{};
      for (final k in dedup) {
        labelMap[k] = _keyToKoreanLabel(k);
      }

      // ▶ 요청한 순서대로 정렬
      List<String> sorted = dedup.toList()..sort((a, b) {
        int ga = _groupIndex(a), gb = _groupIndex(b);
        if (ga != gb) return ga.compareTo(gb);
        int oa = _orderInGroup(a), ob = _orderInGroup(b);
        if (oa != ob) return oa.compareTo(ob);
        // 같은 그룹에 없으면 라벨로 보조 정렬
        return (_labelForKey(a)).compareTo(_labelForKey(b));
      });

      setState(() {
        _nutriKeys = sorted;
        _labelFor = labelMap;
        _selectedKey = _nutriKeys.isNotEmpty ? _nutriKeys.first : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

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

  // ───────── 키 정규화 (result.dart와 일관) + 약어 매핑(thia/ribf/nia/retol/cartb 등) ─────────
  String _normalizeKey(String raw) {
    var k = raw.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (k.isEmpty) return '';

    // 물 관련 키이면 제외 반환
    const waterKeys = {
      'watergoalml','water_goal_ml','watergoalmL','waterGoalMl',
      'watergoalmi','water_goal_mi',
      'water','waterml','water_ml','waterintake',
    };
    if (waterKeys.contains(k)) return '';

    // kcal → enerc (이후 EXCLUDED로 제거)
    const kcal = {'kcal','calorie','calories','energy','energykcal','enerc_kcal','enerc'};
    if (kcal.contains(k)) return 'enerc';

    // 탄/단/지
    const carb = {'carb','carbs','carbohydrate','carbohydrates','cho','chocdf'};
    if (carb.contains(k)) return 'chocdf';
    const prot = {'protein','proteins','prot'};
    if (prot.contains(k)) return 'prot';
    const fat = {'fat','fats','totalfat','fatce','lipid'};
    if (fat.contains(k)) return 'fatce';
    const sfa = {'saturatedfat','satfat','fasat','fat_sat'};
    if (sfa.contains(k)) return 'fasat';
    const sugar = {'sugar','sugars','added_sugar','addedsugar'};
    if (sugar.contains(k)) return 'sugar';
    const fiber = {'fiber','dietaryfiber','fibtg'};
    if (fiber.contains(k)) return 'fibtg'; // 내부 키를 fibtg로 통일

    // 나트륨 동의어
    const sodium = {'nat','sodium','sod','na'};
    if (sodium.contains(k)) return 'na';

    // 비타민 약어/변형 → 표준키
    const b1 = {'thia','thiamin','thiamine','vitaminb1','vitamin_b1','vitb1'};
    if (b1.contains(k)) return 'vitb1';
    const b2 = {'ribf','riboflavin','vitaminb2','vitamin_b2','vitb2'};
    if (b2.contains(k)) return 'vitb2';
    const b3 = {'nia','niacin','niac','vitaminb3','vitamin_b3','vitb3'};
    if (b3.contains(k)) return 'vitb3';

    // 비타민A(RAE) 변형
    const a = {'retol','retinol','vita_rae','vitarae','vitaminarae','vitamin_a_rae','arae','cartb'};
    if (a.contains(k)) return 'vita_rae';

    // 직접 허용 키
    const direct = {
      'na','k','p','mg','ca','fe','zn','chole','fasat',
      'vita_rae','vitc','vitd','vite','vitk',
      'vitb1','vitb2','vitb3','vitb6','vitb12','folate','biotin','pantothenic',
      'fibtg','sugar','chocdf','prot','fatce'
      // 'fatrn'은 의도적으로 제외
    };
    if (direct.contains(k)) return k;

    if (k.startsWith('vitb')) return 'vitb${k.substring(4)}';
    if (k.startsWith('vit')) return 'vit${k.substring(3)}';
    return k;
  }

  // DB 라벨 우선, 없으면 규칙 라벨
  String _keyToKoreanLabel(String key) {
    final db = NUTRIENT_LABELS[key];
    if (db != null) return db;
    return _labelForKey(key);
  }

  String _labelForKey(String key) {
    if (NUTRIENT_LABELS.containsKey(key)) return NUTRIENT_LABELS[key]!;
    final k = key.toLowerCase();
    if (k == 'nat') return '나트륨';
    if (k.startsWith('vitb')) return '비타민B${k.substring(4)}';
    if (k.startsWith('vit')) return '비타민${k.substring(3).toUpperCase()}';
    if (k.contains('fiber') || k == 'fibtg') return '식이섬유';
    switch (k) {
      case 'prot': return '단백질';
      case 'chocdf': return '탄수화물';
      case 'fatce': return '지방';
      case 'fasat': return '포화지방';
      case 'sugar': return '당류';
      case 'na': return '나트륨';
      case 'k': return '칼륨';
      case 'p': return '인';
      case 'mg': return '마그네슘';
      case 'ca': return '칼슘';
      case 'fe': return '철';
      case 'zn': return '아연';
      case 'chole': return '콜레스테롤';
      case 'vita_rae': return '비타민A';
      default: return key;
    }
  }

  // 대표 음식 데이터(정적 DB에서 읽어서 _FoodItem 변환, 최대 10개)
  List<_FoodItem> _foodsFor(String key) {
    final raw = NUTRIENT_FOODS[key] ?? const <Map<String, dynamic>>[];
    return raw.take(10).map((m) {
      return _FoodItem(
        m['name']?.toString() ?? '식품',
        m['portion']?.toString() ?? '',
        m['note']?.toString() ?? '',
        (m['tags'] is List)
            ? List<String>.from(m['tags'].map((e) => e.toString()))
            : <String>[],
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: const BackButton(color: Colors.black87),
          title: const Text('추천음식', style: TextStyle(color: Colors.black87)),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))),
        ),
      );
    }

    final key = _selectedKey;
    final foods = (key == null) ? <_FoodItem>[] : _foodsFor(key);
    final label = key == null ? '' : _keyToKoreanLabel(key);
    final deficiency = key == null ? null : NUTRIENT_DEFICIENCY[key];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black87),
        centerTitle: true,
        title: const Text('추천음식',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 상단 칩: 사용자가 설정한 영양소 목록 (요청 순서 반영)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: _nutriKeys.map((k) {
                  final selected = k == _selectedKey;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(
                        _labelFor[k] ?? _labelForKey(k),
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      selected: selected,
                      selectedColor: accentGreen,
                      backgroundColor: const Color(0xFFF1F5F4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: selected ? accentGreen : const Color(0xFFE0E0E0),
                        ),
                      ),
                      onSelected: (_) => setState(() => _selectedKey = k),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),

            // 선택된 영양소 헤더 + 결핍 정보 안내(추천음식 위)
            if (key != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x1F24C486),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '대표 음식',
                            style: TextStyle(fontSize: 12, color: Color(0xFF24C486)),
                          ),
                        ),
                      ],
                    ),
                    if (deficiency != null && deficiency.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FBF9),
                          border: Border.all(color: const Color(0xFFDDEFE7)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, size: 18, color: Color(0xFF2E7D6B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '결핍 시: $deficiency',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF2E7D6B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // 리스트
            Expanded(
              child: (key == null || foods.isEmpty)
                  ? const Center(
                child: Text('이 영양소에 대한 추천 음식 데이터를 준비 중입니다.'),
              )
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                itemCount: foods.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final f = foods[i];
                  return _FoodCard(item: f, accent: accentGreen);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodItem {
  final String name;
  final String portion;
  final String note;
  final List<String> tags;
  _FoodItem(this.name, this.portion, this.note, this.tags);
}

class _FoodCard extends StatelessWidget {
  final _FoodItem item;
  final Color accent;
  const _FoodCard({Key? key, required this.item, required this.accent})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        border: Border.all(color: const Color(0xFFE3EEE9)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 동그란 아이콘 대체 (이니셜)
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                item.name.characters.first,
                style: TextStyle(
                  color: accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 텍스트
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${item.portion} · ${item.note}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (item.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: -6,
                    children: item.tags
                        .map(
                          (t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFDDE8E3)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          t,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54),
                        ),
                      ),
                    )
                        .toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
