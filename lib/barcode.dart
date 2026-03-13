// lib/barcode.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BarcodePage extends StatefulWidget {
  final String mealName;

  const BarcodePage({
    Key? key,
    required this.mealName,
  }) : super(key: key);

  @override
  State<BarcodePage> createState() => _BarcodePageState();
}

class _BarcodePageState extends State<BarcodePage> {
  static const String barcodeApiKey = 'c42bf78382fe442590a6';

  // URL-인코딩된 서비스키(재인코딩 금지)
  static const String nutritionApiKey =
      '%2BSYgkkSj2qW4ve5BGTM3TrgbKQDWf8dc4wmupQn4gyIRxn%2ByAVNQwYwM8%2BxVNQQdy59V5IlmzPuSRYK%2Fj36gbA%3D%3D';

  static const String nutrBase =
      'https://apis.data.go.kr/1471000/FoodNtrCpntDbInfo02/getFoodNtrCpntDbInq02';

  String _foodName = '—';
  String _reportNo = '—';
  String _foodSize = '0g';
  double _foodSizeInGrams = 100;
  int _count = 1;

  /// per-100g 값 저장(내 기준 키로)
  final Map<String, double> _per100gValues = {};

  /// 화면 표시용 (기준 키만)
  List<Map<String, String>> _nutrientData = [];

  /// 사용자 표준 키
  Set<String> _stdKeys = {};

  // 라벨(단위 포함) — 키는 내부 기준 키에 맞춤
  static const Map<String, String> _labelMap = {
    // 매크로
    'enerc': '에너지 (kcal)',
    'chocdf': '탄수화물 (g)',
    'prot': '단백질 (g)',
    'fatce': '지방 (g)',
    'fibtg': '식이섬유 (g)',
    'sugar': '당류 (g)',
    // 미량
    'na': '나트륨 (mg)',
    'ca': '칼슘 (mg)',
    'fe': '철 (mg)',
    'k': '칼륨 (mg)',
    'chole': '콜레스테롤 (mg)',
    'fasat': '포화지방 (g)',
    // 비타민
    'vita_rae': '비타민 A (µg RAE)',
    'vitd': '비타민 D (µg)',
    'vite': '비타민 E (mg)',
    'vitk': '비타민 K (µg)',
    'vitb1': '비타민 B1 (mg)',
    'vitb2': '비타민 B2 (mg)',
    'vitb3': '비타민 B3/니아신 (mg)',
    'vitb6': '비타민 B6 (mg)',
    'vitb12': '비타민 B12 (µg)',
    'folate': '엽산(DFE) (µg)',
    'vitc': '비타민 C (mg)',
    'pantothenic': '판토텐산 (mg)',
    'biotin': '비오틴 (µg)',
  };

  // 즉시 전환 라우트
  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  void safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadNutritionStandardKeys();
      await _startBarcodeScan();
    });
  }

  Future<void> _loadNutritionStandardKeys() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final std =
          (snap.data()?['nutritionStandard'] as Map<String, dynamic>?) ?? {};
      final keys = <String>{};
      for (final e in std.entries) {
        final v = e.value;
        if (v == null) continue;
        if (v is num || double.tryParse('$v') != null) {
          keys.add(e.key);
        }
      }
      safeSetState(() => _stdKeys = keys);
    } catch (_) {}
  }

  // 숫자 파서
  double _num(dynamic v) {
    if (v == null) return 0;
    final s = v.toString().replaceAll(',', '');
    return double.tryParse(s) ?? 0;
  }

  // 텍스트/숫자에서 g 단위로 변환 (kg/mg/ml 일부 처리)
  double _toGram(dynamic raw, {double fallback = 100}) {
    if (raw == null) return fallback;
    if (raw is num) return raw.toDouble();
    final s = raw.toString().trim().toLowerCase();
    final n = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (n == null) return fallback;
    if (s.contains('kg')) return n * 1000;
    if (s.contains('mg')) return n / 1000;
    // ml은 밀도 1 가정(물/음료 등) — 불확실하면 g로 동일 처리
    // 필요 시 품목 유형별 보정 가능
    return n; // 기본 g
  }

  Future<void> _startBarcodeScan() async {
    try {
      final code = await Navigator.of(context).push<String>(
        _noAnim(const ScannerScreen()),
      );
      if (!mounted || code == null || code.isEmpty) {
        safeSetState(() => _foodName = '스캔 취소됨');
        return;
      }
      safeSetState(() {
        _foodName = '로딩 중…';
        _reportNo = '—';
        _per100gValues.clear();
        _nutrientData.clear();
        _foodSizeInGrams = 100;
        _count = 1;
        _foodSize = '100g × 1개';
      });
      await _fetchFoodNameFromBarcode(code);
    } catch (_) {
      safeSetState(() => _foodName = '스캔 오류');
    }
  }

  Future<void> _fetchFoodNameFromBarcode(String barcode) async {
    try {
      final dio = Dio();
      final resp = await dio.get(
        'http://openapi.foodsafetykorea.go.kr/api/$barcodeApiKey/C005/json/1/1/BAR_CD=$barcode',
      );
      final rows = resp.data['C005']?['row'] as List<dynamic>?;
      if (rows == null || rows.isEmpty) {
        safeSetState(() => _foodName = '제품 정보 없음');
        return;
      }
      final item = rows.first as Map<String, dynamic>;
      final name = item['PRDLST_NM'] as String? ?? '이름 없음';
      final reportNo = item['PRDLST_REPORT_NO'] as String? ?? '—';
      safeSetState(() {
        _foodName = name;
        _reportNo = reportNo;
      });
      if (reportNo != '—') {
        await _fetchNutritionInfoByReportNo(reportNo);
      }
    } catch (_) {
      safeSetState(() => _foodName = 'API 오류');
    }
  }

  /// 응답에서 item 리스트를 꺼내는 유틸(배열/단일객체/깊은 경로 모두 처리)
  List<Map<String, dynamic>> _extractItemList(dynamic rawData) {
    try {
      final data = rawData as Map?;
      if (data == null) return const [];

      // data['response']['body'] 또는 data['body']
      final body = (data['body'] ??
          (data['response'] is Map ? data['response']['body'] : null)) as Map?;

      if (body == null) return const [];

      // 보통은 body['items']['item'] 구조
      final itemsNode = body['items'] ?? body['item'];
      if (itemsNode == null) return const [];

      // itemsNode가 { item: [...] } 형태
      if (itemsNode is Map && itemsNode['item'] != null) {
        final itemNode = itemsNode['item'];
        if (itemNode is List) {
          return itemNode
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        } else if (itemNode is Map) {
          return [itemNode.cast<String, dynamic>()];
        }
      }

      // itemsNode가 곧바로 리스트이거나 맵인 경우
      if (itemsNode is List) {
        return itemsNode
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else if (itemsNode is Map) {
        return [itemsNode.cast<String, dynamic>()];
      }

      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// ✅ 식약처_식품영양성분DB정보(getFoodNtrCpntDbInq02) 호출
  ///    - 파라미터: serviceKey + type=json + ITEM_REPORT_NO
  Future<void> _fetchNutritionInfoByReportNo(String reportNo) async {
    try {
      final url =
          '$nutrBase?serviceKey=$nutritionApiKey&type=json&ITEM_REPORT_NO=$reportNo';

      final dio = Dio();
      final resp = await dio.get(url);

      if (resp.statusCode != 200 || resp.data == null) {
        safeSetState(() => _nutrientData = []);
        return;
      }

      // 헤더 에러 코드 체크(있을 때)
      final header = (resp.data['header'] ??
          (resp.data['response'] is Map
              ? resp.data['response']['header']
              : null)) as Map?;
      final resultCode = header?['resultCode']?.toString();
      if (resultCode != null && resultCode != '00') {
        safeSetState(() {
          _nutrientData = [];
          _foodName = 'API 응답 오류($resultCode)';
        });
        return;
      }

      final list = _extractItemList(resp.data);
      if (list.isEmpty) {
        safeSetState(() {
          _nutrientData = [];
          _foodName = '영양 데이터 없음';
        });
        return;
      }

      // 동일 보고번호의 첫 번째 항목 사용
      final m = list.first;

      // 1) 제품명 보정(가능하면 DB의 FOOD_NM_KR 사용)
      final dbName =
      (m['FOOD_NM_KR'] ?? m['FOOD_NAME'] ?? m['DESC_KOR']) as String?;
      if (dbName != null && dbName.trim().isNotEmpty) {
        safeSetState(() => _foodName = dbName.trim());
      }

      // 2) 총 내용량: Z10500 우선 사용, 없으면 기존 키들 폴백
      //    (표시용 문자열과 계산용 g 모두 갱신)
      final zTotalRaw = m['Z10500'];
      double grams = _toGram(zTotalRaw, fallback: -1);
      if (grams <= 0) {
        // 폴백: 1회 제공량/식품중량 등
        final servingRaw = m['SERVING_SIZE'] ??
            m['SERVING_WT'] ??
            m['FOOD_SIZE'] ??
            m['FOOD_WEIGHT'] ??
            m['FOOD_SIZE_QTY'] ??
            '100g';
        grams = _toGram(servingRaw, fallback: 100);
      }
      _foodSizeInGrams = grams;

      // 3) per-100g 추출
      _per100gValues.clear();
      void put(String k, double v) {
        if (v.isNaN || v.isInfinite) return;
        if (v <= 0) return;
        _per100gValues[k] = v;
      }

      // AMT_NUM 매핑 (데이터셋 스키마 기준)
      put('enerc', _num(m['AMT_NUM1']));
      put('chocdf', _num(m['AMT_NUM6']));
      put('prot', _num(m['AMT_NUM3']));
      put('fatce', _num(m['AMT_NUM4']));
      put('sugar', _num(m['AMT_NUM7']));
      put('fibtg', _num(m['AMT_NUM8']));

      put('ca', _num(m['AMT_NUM9']));
      put('fe', _num(m['AMT_NUM10']));
      put('k', _num(m['AMT_NUM12']));
      put('na', _num(m['AMT_NUM13']));
      put('chole', _num(m['AMT_NUM23']));
      put('fasat', _num(m['AMT_NUM24']));

      put('vita_rae', _num(m['AMT_NUM14']));
      put('vitb1', _num(m['AMT_NUM18']));
      put('vitb2', _num(m['AMT_NUM19']));
      put('vitb3', _num(m['AMT_NUM20']));
      put('vitc', _num(m['AMT_NUM21']));
      put('vitd', _num(m['AMT_NUM22']));
      put('vitb6', _num(m['AMT_NUM29']));
      put('vitb12', _num(m['AMT_NUM30']));
      put('folate', _num(m['AMT_NUM31']));
      put('pantothenic', _num(m['AMT_NUM33']));
      put('vite', _num(m['AMT_NUM36']));
      put('vitk', _num(m['AMT_NUM48']));
      put('biotin', _num(m['AMT_NUM28']));

      _recalcNutrientData(); // _count 반영
      safeSetState(() {
        _foodSize = '${_foodSizeInGrams.toStringAsFixed(0)}g × ${_count}개';
      });
    } catch (_) {
      safeSetState(() {
        _nutrientData = [];
        _foodName = '네트워크/파싱 오류';
      });
    }
  }

  /// 현재 1개 g(_foodSizeInGrams)와 개수(_count)를 반영해 표용 데이터 계산
  void _recalcNutrientData() {
    final data = <Map<String, String>>[];
    final showKeys = _labelMap.keys.where((k) => _stdKeys.contains(k));
    for (final key in showKeys) {
      final per100 = _per100gValues[key];
      if (per100 == null) continue;
      final total = per100 / 100 * _foodSizeInGrams * _count;
      if (total <= 0) continue;
      data.add({'성분': _labelMap[key]!, '함량': total.toStringAsFixed(2)});
    }
    safeSetState(() => _nutrientData = data);
  }

  Future<void> _editFoodSize() async {
    const themeGreen = Color(0xFF24C486);

    final perItemCtl =
    TextEditingController(text: _foodSizeInGrams.toStringAsFixed(0));
    final countCtl = TextEditingController(text: _count.toString());
    String unit = 'g';

    await showGeneralDialog<void>(
      context: context,
      barrierLabel: '총 내용량 수정',
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (dCtx, setDialog) {
                return Dialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('총 내용량',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        const Center(
                          child: Text('총 내용량을 입력하세요',
                              style:
                              TextStyle(fontSize: 13, color: Colors.black54)),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: perItemCtl,
                                keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                                textAlign: TextAlign.left,
                                decoration: InputDecoration(
                                  isDense: true,
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: themeGreen, width: 1.5),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: themeGreen, width: 2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: unit,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: 'g', child: Text('g')),
                                DropdownMenuItem(value: 'kg', child: Text('kg')),
                                DropdownMenuItem(value: 'mg', child: Text('mg')),
                              ],
                              onChanged: (v) => setDialog(() => unit = v!),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: countCtl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.left,
                                decoration: InputDecoration(
                                  isDense: true,
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: themeGreen, width: 1.5),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: themeGreen, width: 2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('개',
                                style: TextStyle(color: Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('취소',
                                  style: TextStyle(color: Colors.black54)),
                            ),
                            const SizedBox(width: 16),
                            TextButton(
                              onPressed: () {
                                final perItemInput =
                                    double.tryParse(perItemCtl.text) ?? 0;
                                int newCount = int.tryParse(countCtl.text) ?? 0;
                                if (perItemInput <= 0 || newCount <= 0) {
                                  Navigator.of(ctx).pop();
                                  return;
                                }
                                double perItemGram;
                                if (unit == 'kg') {
                                  perItemGram = perItemInput * 1000;
                                } else if (unit == 'mg') {
                                  perItemGram = perItemInput / 1000;
                                } else {
                                  perItemGram = perItemInput;
                                }
                                _foodSizeInGrams = perItemGram;
                                _count = newCount;
                                _foodSize =
                                '${_foodSizeInGrams.toStringAsFixed(0)}g × ${_count}개';
                                _recalcNutrientData();
                                Navigator.of(ctx).pop();
                              },
                              child: const Text('확인',
                                  style: TextStyle(color: Colors.black87)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      transitionBuilder: (ctx, a1, a2, child) => child,
    );
  }

  Future<String?> _pickMeal() async {
    const themeGreen = Color(0xFF24C486);
    final options = ['아침식사', '점심식사', '저녁식사', '간식'];
    String? selected;

    return showGeneralDialog<String>(
      context: context,
      barrierLabel: '식사 선택',
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (dCtx, setDialog) {
                return Dialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('식사 선택',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        const Center(
                          child: Text('추가할 식사를 선택하세요',
                              style:
                              TextStyle(fontSize: 13, color: Colors.black54)),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: options.map((lbl) {
                            final sel = selected == lbl;
                            return SizedBox(
                              width: 110,
                              height: 42,
                              child: OutlinedButton(
                                onPressed: () =>
                                    setDialog(() => selected = lbl),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor:
                                  sel ? themeGreen : Colors.grey[200],
                                  side: BorderSide(
                                    color: sel ? themeGreen : Colors.grey,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(
                                  lbl,
                                  style: TextStyle(
                                    color:
                                    sel ? Colors.white : Colors.black87,
                                    fontWeight:
                                    sel ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(null),
                              child: const Text('취소',
                                  style: TextStyle(color: Colors.black54)),
                            ),
                            const SizedBox(width: 16),
                            TextButton(
                              onPressed: selected == null
                                  ? null
                                  : () => Navigator.of(ctx).pop(selected),
                              child: Text('확인',
                                  style: TextStyle(
                                      color: selected == null
                                          ? Colors.black26
                                          : Colors.black87)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      transitionBuilder: (_, __, ___, child) => child,
    );
  }

  Future<void> _saveToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    String? mealName = widget.mealName;
    if (mealName == 'none') {
      final picked = await _pickMeal();
      if (picked == null) return;
      mealName = picked;
    }

    final now = DateTime.now();
    final mealKey = '${now.year}-${now.month}-${now.day}_$mealName';

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('meals')
        .doc(mealKey)
        .collection('foods');

    final totalGram = (_foodSizeInGrams * _count);

    double totalOf(String key) =>
        ((_per100gValues[key] ?? 0) / 100) * totalGram;

    final Map<String, dynamic> payload = {
      'name': _foodName,
      'gram': totalGram.toInt(),
      'count': _count,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (_stdKeys.contains('enerc')) payload['kcal'] = totalOf('enerc');
    if (_stdKeys.contains('chocdf')) payload['carbs'] = totalOf('chocdf');
    if (_stdKeys.contains('prot')) payload['protein'] = totalOf('prot');
    if (_stdKeys.contains('fatce')) payload['fat'] = totalOf('fatce');

    final extra = <String, num>{};
    for (final key in _labelMap.keys) {
      if (!_stdKeys.contains(key)) continue;
      if (key == 'enerc' || key == 'chocdf' || key == 'prot' || key == 'fatce') {
        continue;
      }
      final v = totalOf(key);
      if (v > 0) {
        final num rounded = (v * 100).roundToDouble() / 100.0;
        extra[key] = rounded;
      }
    }
    if (extra.isNotEmpty) payload['extraNutrients'] = extra;

    await ref.add(payload);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const borderGreen = Color(0xFF24C486);
    const bw = 2.5;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.mealName == 'none' ? '바코드 인식' : '${widget.mealName} 바코드 인식',
          style: const TextStyle(color: Colors.black87),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Color(0xFF24C486)),
            onPressed: _startBarcodeScan,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: borderGreen, width: bw),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _editFoodSize,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: borderGreen, width: bw),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_foodName,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('품목보고번호: $_reportNo',
                                  style:
                                  const TextStyle(color: Colors.black54)),
                              const SizedBox(height: 8),
                              Text('총 내용량: $_foodSize',
                                  style:
                                  const TextStyle(color: Colors.black54)),
                              const SizedBox(height: 4),
                              const Text('(터치하여 수정)',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: _buildTable(borderGreen, bw)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: borderGreen,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _saveToFirestore,
                  child: const Text('추가',
                      style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable(Color borderColor, double borderWidth) {
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
        border: const TableBorder(
          horizontalInside: BorderSide.none,
          verticalInside: BorderSide.none,
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderColor, width: borderWidth),
              ),
            ),
            children: const [
              Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text('영양소'))),
              Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text('내용량'))),
            ],
          ),
          for (var row in _nutrientData)
            TableRow(children: [
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: Text(row['성분']!))),
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: Text(row['함량']!))),
            ]),
        ],
      ),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({Key? key}) : super(key: key);

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final controller =
  MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _scanned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('바코드 스캔')),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          if (_scanned || capture.barcodes.isEmpty) return;
          final code = capture.barcodes.first.rawValue;
          if (code != null) {
            _scanned = true;
            controller.stop();
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}
