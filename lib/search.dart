// lib/search.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 남겨둬도 되지만 여기선 사용 X
import 'package:cloud_firestore/cloud_firestore.dart'; // 남겨둬도 되지만 여기선 사용 X

class SearchPage extends StatefulWidget {
  final String mealName;
  const SearchPage({Key? key, required this.mealName}) : super(key: key);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  // 이미 URL 인코딩된 서비스키를 그대로 넣으세요(재인코딩 금지)
  static const String _serviceKey =
      '%2BSYgkkSj2qW4ve5BGTM3TrgbKQDWf8dc4wmupQn4gyIRxn%2ByAVNQwYwM8%2BxVNQQdy59V5IlmzPuSRYK%2Fj36gbA%3D%3D';

  static const String _base =
      'https://apis.data.go.kr/1471000/FoodNtrCpntDbInfo02/getFoodNtrCpntDbInq02';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (_) => true,
    headers: {'Accept': 'application/json'},
  ));

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  int _pageNo = 1;
  static const int _numRows = 10;
  int? _totalCount;

  List<FoodItem> _foods = [];
  String? _effectiveQuery;

  int get _lastPage {
    final tc = _totalCount ?? 0;
    if (tc <= 0) return 1;
    return ((tc + _numRows - 1) ~/ _numRows);
  }

  bool get _hasNextPage => _pageNo < _lastPage;

  void _safeSet(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------- 유틸 ----------
  double _parseNum(dynamic v) {
    if (v == null) return 0;
    final s = v.toString().replaceAll(',', '');
    return double.tryParse(s) ?? 0;
  }

  double _parseGrams(dynamic v) {
    if (v == null) return 0;
    final s = v.toString();
    final only = s.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(only) ?? 0;
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _extractMsg(dynamic data) {
    try {
      final header = (data is Map)
          ? (data['header'] ?? data['response']?['header'])
          : null;
      if (header is Map && header['resultMsg'] != null) {
        return header['resultMsg'].toString();
      }
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- API → per100g 핵심 영양소 추출(내 기준 키로 매핑) ----------
  Map<String, double> _extractPer100g(Map<String, dynamic> m) {
    // 내가 쓰는 정규 키
    // enerc(kcal), prot(g), fatce(g), chocdf(g), sugar(g), fibtg(g),
    // na(mg), k(mg), ca(mg), fe(mg), chole(mg),
    // vita_rae(µg RAE), vitc(mg), vitd(µg), vite(mg), vitk(µg),
    // vitb1/2/3/6(mg), vitb12(µg), folate(µg), fasat(g)
    final map = <String, double>{
      'enerc': _parseNum(m['AMT_NUM1']),
      'prot': _parseNum(m['AMT_NUM3']),
      'fatce': _parseNum(m['AMT_NUM4']),
      'chocdf': _parseNum(m['AMT_NUM6']),
      'sugar': _parseNum(m['AMT_NUM7']),
      'fibtg': _parseNum(m['AMT_NUM8']),
      'ca': _parseNum(m['AMT_NUM9']),
      'fe': _parseNum(m['AMT_NUM10']),
      'k': _parseNum(m['AMT_NUM12']),
      'na': _parseNum(m['AMT_NUM13']),
      'vita_rae': _parseNum(m['AMT_NUM14']),
      'vitb1': _parseNum(m['AMT_NUM18']),
      'vitb2': _parseNum(m['AMT_NUM19']),
      'vitb3': _parseNum(m['AMT_NUM20']),
      'vitc': _parseNum(m['AMT_NUM21']),
      'vitd': _parseNum(m['AMT_NUM22']),
      'chole': _parseNum(m['AMT_NUM23']),
      'fasat': _parseNum(m['AMT_NUM24']),
      'vitb6': _parseNum(m['AMT_NUM29']),
      'vitb12': _parseNum(m['AMT_NUM30']),
      'folate': _parseNum(m['AMT_NUM31']),
      'vite': _parseNum(m['AMT_NUM36']),
      'vitk': _parseNum(m['AMT_NUM48']),
    };

    // 0만 가득이면 비우지 말고 그대로 두자(사용처에서 필터링)
    return map;
  }

  // ---------- 검색 ----------
  Future<void> _onSearchPressed() async {
    FocusScope.of(context).unfocus();

    _pageNo = 1;
    _totalCount = 0;
    _effectiveQuery = null;
    await _searchWithFallbacks(_searchController.text.trim(), resetPage: true);
  }

  Future<void> _searchWithFallbacks(String keyword, {bool resetPage = false}) async {
    if (keyword.isEmpty) return;
    final cands = <String>{
      keyword,
      keyword.replaceAll(RegExp(r'\s+'), '_'),
      keyword.replaceAll(RegExp(r'\s+'), ''),
      if (keyword.contains(RegExp(r'\s+'))) keyword.split(RegExp(r'\s+')).first,
    }.where((e) => e.isNotEmpty).toList();

    for (final q in cands) {
      final ok = await _searchApi(q, resetPage: resetPage);
      if (ok) {
        _effectiveQuery = q;
        return;
      }
    }
    _showSnack('검색 결과가 없습니다. 다른 키워드를 시도해 보세요.');
  }

  Future<bool> _searchApi(String q, {bool resetPage = false}) async {
    if (q.isEmpty) return false;
    if (resetPage) {
      _pageNo = 1;
      _totalCount = 0;
    }

    _safeSet(() {
      _isLoading = true;
      _foods = [];
    });

    try {
      final url =
          '$_base?serviceKey=$_serviceKey&pageNo=$_pageNo&numOfRows=$_numRows&type=json&FOOD_NM_KR=${Uri.encodeQueryComponent(q)}';

      final resp = await _dio.get(url);
      if (resp.statusCode != 200) {
        _showSnack('(${resp.statusCode}) 서버 응답 오류: ${_extractMsg(resp.data)}');
        return false;
      }

      final data = resp.data;
      final header = (data is Map)
          ? (data['header'] ?? data['response']?['header'])
          : null;
      final body = (data is Map)
          ? (data['body'] ?? data['response']?['body'])
          : null;

      final resultCode = header is Map ? header['resultCode']?.toString() : null;
      if (resultCode != null && resultCode != '00') {
        _showSnack('API 오류: ${_extractMsg(data)}');
        return false;
      }

      _totalCount = _toInt(body is Map ? (body['totalCount'] ?? 0) : 0);

      final dynamic items = (body is Map) ? body['items'] : null;

      final List list;
      if (items is List) {
        list = items;
      } else if (items is Map) {
        list = [items];
      } else {
        list = const [];
      }

      _foods = list.map((raw) {
        final m = raw as Map<String, dynamic>;

        final servingSize = (m['SERVING_SIZE'] as String?) ?? '100g';
        final servingGrams =
            double.tryParse(servingSize.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 100.0;

        final totalGrams = _parseGrams(m['Z10500']);
        final per100g = _extractPer100g(m);

        return FoodItem(
          foodCd: m['FOOD_CD'] as String? ?? '',
          name: m['FOOD_NM_KR'] as String? ?? '이름없음',
          nutrientsPer100g: per100g,
          servingSizeGrams: servingGrams,
          totalServingGrams: totalGrams,
        );
      }).toList();

      return _foods.isNotEmpty;
    } catch (e) {
      _showSnack('네트워크/파싱 오류: $e');
      return false;
    } finally {
      _safeSet(() => _isLoading = false);
    }
  }

  // ---------- 페이지 이동 ----------
  Future<void> _prevPage() async {
    if (_pageNo <= 1) return;
    _pageNo--;
    final q = _effectiveQuery ?? _searchController.text.trim();
    if (q.isEmpty) return;
    final ok = await _searchApi(q);
    if (!ok) _pageNo++;
  }

  Future<void> _nextPage() async {
    if (!_hasNextPage) {
      _showSnack('마지막 페이지입니다.');
      return;
    }
    _pageNo++;
    final q = _effectiveQuery ?? _searchController.text.trim();
    if (q.isEmpty) return;
    await _searchApi(q);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    const themeGreen = Color(0xFF24C486);

    final q = _searchController.text.trim();
    final showNav = !_isLoading && q.isNotEmpty;

    final Color navBg = themeGreen;
    final Color navFg = Colors.white;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '음식 찾기',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 검색창
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _onSearchPressed(),
                      decoration: InputDecoration(
                        hintText: '음식명을 입력하세요',
                        hintStyle: const TextStyle(color: Colors.black38),
                        prefixIcon: const Icon(Icons.search, color: Colors.black38),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.black38),
                          onPressed: () {
                            _searchController.clear();
                            _safeSet(() {
                              _foods = [];
                              _effectiveQuery = null;
                              _pageNo = 1;
                              _totalCount = 0;
                            });
                          },
                        )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: themeGreen),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _onSearchPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('검색'),
                  ),
                ],
              ),
            ),

            // 결과: 1열 리스트(상자)
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildListArea(q),
            ),

            // 페이지 버튼
            if (showNav)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _pageNo > 1 ? _prevPage : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        _pageNo > 1 ? navBg : navBg.withOpacity(0.35),
                        foregroundColor: navFg,
                      ),
                      child: const Text('이전'),
                    ),
                    const SizedBox(width: 16),
                    Text('$_pageNo / $_lastPage 페이지', style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _hasNextPage ? _nextPage : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        _hasNextPage ? navBg : navBg.withOpacity(0.35),
                        foregroundColor: navFg,
                      ),
                      child: const Text('다음'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildListArea(String q) {
    if (q.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_foods.isEmpty) {
      return const Center(
        child: Text('데이터가 없습니다.', style: TextStyle(color: Colors.black54)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _foods.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final f = _foods[i];

        // “약” 제거
        String sub;
        if (f.totalServingGrams > 0) {
          final total = f.totalServingGrams;
          final kcal100 = (f.nutrientsPer100g['enerc'] ?? 0);
          final kcalTotal = (kcal100 * total / 100).round();
          sub = '총 내용량 ${total.toStringAsFixed(0)}g · $kcalTotal kcal';
        } else {
          final kcal100 = (f.nutrientsPer100g['enerc'] ?? 0);
          sub = '총 내용량 정보 없음 · ${kcal100.toStringAsFixed(0)} kcal/100g';
        }

        return InkWell(
          onTap: () => _showFoodDialog(f),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E5E5)),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                )
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFoodDialog(FoodItem food) {
    const themeGreen = Color(0xFF24C486);

    final defaultGram = (food.totalServingGrams > 0
        ? food.totalServingGrams
        : (food.servingSizeGrams > 0 ? food.servingSizeGrams : 100))
        .toStringAsFixed(0);

    final gramCtrl = TextEditingController(text: defaultGram);
    String unit = 'g';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(food.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Text('${(food.nutrientsPer100g['enerc'] ?? 0).toStringAsFixed(0)} kcal / 100g 기준',
                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text('총 내용량', style: TextStyle(fontSize: 13, color: Colors.black54)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: gramCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            isDense: true,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: themeGreen, width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: themeGreen, width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: unit,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'kg', child: Text('kg')),
                          DropdownMenuItem(value: 'g', child: Text('g')),
                          DropdownMenuItem(value: 'mg', child: Text('mg')),
                        ],
                        onChanged: (v) => setDialog(() => unit = v!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소', style: TextStyle(color: Colors.black54))),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () async {
                          final input = double.tryParse(gramCtrl.text) ?? 0;

                          double gramValue;
                          if (unit == 'kg') {
                            gramValue = input * 1000;
                          } else if (unit == 'mg') {
                            gramValue = input / 1000;
                          } else {
                            gramValue = input;
                          }
                          if (gramValue <= 0) return;

                          // per100g → 실제 그램으로 환산
                          final ratio = gramValue / 100.0;
                          final per100 = food.nutrientsPer100g;
                          final amount = <String, double>{};
                          per100.forEach((k, v) => amount[k] = v * ratio);

                          // MealDetailPage에 돌려줄 페이로드(저장 X)
                          final payload = <String, dynamic>{
                            'name': food.name,
                            'gram': gramValue,
                            'count': 1,
                            // 표시용 기본 필드(기존 화면 요약과 호환)
                            'kcal': (amount['enerc'] ?? 0),
                            'carbs': (amount['chocdf'] ?? 0),
                            'protein': (amount['prot'] ?? 0),
                            'fat': (amount['fatce'] ?? 0),
                            // 확장 영양(내 기준 키들)
                            'nutrients': amount, // Map<String,double>
                          };

                          // 다이얼로그 닫고
                          Navigator.of(ctx).pop();
                          // 검색 페이지를 결과와 함께 닫기(중요: 페이지 컨텍스트 사용)
                          if (mounted) {
                            Navigator.of(this.context).pop(payload);
                          }
                        },
                        child: const Text('확인', style: TextStyle(color: Colors.black87)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class FoodItem {
  final String foodCd;
  final String name;
  final Map<String, double> nutrientsPer100g; // enerc/prot/chocdf/fatce 등 per 100g
  final double servingSizeGrams;              // SERVING_SIZE(보통 100g)
  final double totalServingGrams;             // Z10500(총 내용량)

  const FoodItem({
    required this.foodCd,
    required this.name,
    required this.nutrientsPer100g,
    required this.servingSizeGrams,
    required this.totalServingGrams,
  });
}
