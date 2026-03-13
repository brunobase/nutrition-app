// lib/nutrition.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'search.dart';
import 'barcode.dart';

class NutritionApp extends StatelessWidget {
  const NutritionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MealDetailPage(mealName: '아침식사'),
    );
  }
}

class MealDetailPage extends StatefulWidget {
  final String mealName;
  const MealDetailPage({Key? key, required this.mealName}) : super(key: key);

  @override
  State<MealDetailPage> createState() => _MealDetailPageState();
}

class _MealDetailPageState extends State<MealDetailPage> {
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _mealKey {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}_${widget.mealName}';
  }

  // ─────────────────────────────────────────────────
  // 즉시전환 라우트
  // ─────────────────────────────────────────────────
  Route<T> _noAnim<T>(Widget page) => PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );

  // ─────────────────────────────────────────────────
  // "저장" 버튼을 누를 때만 DB에 반영하기 위한 로컬 변경 버퍼
  // ─────────────────────────────────────────────────
  final Map<String, Map<String, dynamic>> _pendingUpdates = {};
  final Set<String> _pendingDeletes = {};
  final List<Map<String, dynamic>> _pendingAdds = [];

  bool get _hasPending =>
      _pendingUpdates.isNotEmpty ||
          _pendingDeletes.isNotEmpty ||
          _pendingAdds.isNotEmpty;

  Map<String, dynamic> _overlayWithPending(
      String id,
      Map<String, dynamic> original,
      ) {
    if (_pendingDeletes.contains(id)) return {};
    if (_pendingUpdates.containsKey(id)) {
      return {...original, ..._pendingUpdates[id]!};
    }
    return original;
  }

  // ─────────────────────────────────────────────────
  // 키 정규화 / 읽기 헬퍼
  // ─────────────────────────────────────────────────
  String _normalizeKey(String raw) {
    var k =
    raw.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    const kcalKeys = {
      'kcal',
      'calorie',
      'calories',
      'energy',
      'energykcal',
      'enerc_kcal',
      'enerc'
    };
    if (kcalKeys.contains(k)) return 'enerc';
    const carbKeys = {
      'carb',
      'carbs',
      'carbohydrate',
      'carbohydrates',
      'cho',
      'chocdf'
    };
    if (carbKeys.contains(k)) return 'chocdf';
    const protKeys = {'protein', 'proteins', 'prot'};
    if (protKeys.contains(k)) return 'prot';
    const fatKeys = {'fat', 'fats', 'totalfat', 'fatce', 'lipid'};
    if (fatKeys.contains(k)) return 'fatce';
    const sfaKeys = {'saturatedfat', 'satfat', 'fasat', 'fat_sat'};
    if (sfaKeys.contains(k)) return 'fasat';
    const sugarKeys = {'sugar', 'sugars', 'addedsugar', 'added_sugar'};
    if (sugarKeys.contains(k)) return 'sugar';
    const fiberKeys = {'fiber', 'dietaryfiber', 'fibtg'};
    if (fiberKeys.contains(k)) return 'fibtg';

    const direct = {
      'na',
      'k',
      'mg',
      'ca',
      'fe',
      'zn',
      'chole',
      'vita_rae',
      'vitc',
      'vitd',
      'vite',
      'vitk',
      'vitb1',
      'vitb2',
      'vitb3',
      'vitb6',
      'vitb12',
      'folate',
      'biotin',
      'pantothenic',
      'gram', // 👈 g(총내용량)도 nutrients 안에 저장
    };
    if (direct.contains(k)) return k;

    if (k.startsWith('vitb')) return 'vitb${k.substring(4)}';
    if (k.startsWith('vit')) return 'vit${k.substring(3)}';
    return k;
  }

  Map<String, double> _normalizeNutrientMap(Object? n) {
    final out = <String, double>{};
    if (n is Map) {
      n.forEach((key, val) {
        if (val is num) {
          final nk = _normalizeKey(key.toString());
          if (nk.isNotEmpty) out[nk] = val.toDouble();
        }
      });
    }
    return out;
  }

  /// nutrients 우선 사용. 없으면 상단(kcal/carbs/protein/fat/gram)에서 보강.
  Map<String, double> _nutrientsFrom(Map<String, dynamic> m) {
    final n = _normalizeNutrientMap(m['nutrients']);

    double? topKcal =
    (m['kcal'] is num) ? (m['kcal'] as num).toDouble() : null;
    double? topCarb =
    (m['carbs'] is num) ? (m['carbs'] as num).toDouble() : null;
    double? topProt =
    (m['protein'] is num) ? (m['protein'] as num).toDouble() : null;
    double? topFat =
    (m['fat'] is num) ? (m['fat'] as num).toDouble() : null;
    double? topGram =
    (m['gram'] is num) ? (m['gram'] as num).toDouble() : null;

    if (topKcal != null && !n.containsKey('enerc')) n['enerc'] = topKcal;
    if (topCarb != null && !n.containsKey('chocdf')) n['chocdf'] = topCarb;
    if (topProt != null && !n.containsKey('prot')) n['prot'] = topProt;
    if (topFat != null && !n.containsKey('fatce')) n['fatce'] = topFat;
    if (topGram != null && !n.containsKey('gram')) n['gram'] = topGram;

    return n;
  }

  double _macroOf(Map<String, dynamic> m, String key) {
    final n = _nutrientsFrom(m);
    return n[key] ?? 0.0;
  }

  double _gramOf(Map<String, dynamic> m) {
    final n = _nutrientsFrom(m);
    return n['gram'] ?? ((m['gram'] as num?)?.toDouble() ?? 0.0);
  }

  Map<String, double> _scaleNutrients(Map<String, double> base, double ratio) {
    if (ratio == 1) return Map.of(base);
    final out = <String, double>{};
    base.forEach((k, v) {
      out[k] = v * ratio;
    });
    return out;
  }

  /// 저장 직전: 상단(kcal/carbs/protein/fat/gram)은 제거하고 모두 nutrients로만 합쳐 저장
  Map<String, dynamic> _canonicalizeForSave(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    final n = _nutrientsFrom(out);

    // top -> nutrients로 이동(이미 있으면 덮지 않음)
    if (out['gram'] is num) n['gram'] = (out['gram'] as num).toDouble();

    // 상단 영양 필드 제거(중복 방지)
    out.remove('kcal');
    out.remove('carbs');
    out.remove('protein');
    out.remove('fat');
    out.remove('gram');

    out['nutrients'] = n;
    return out;
  }

  // ─────────────────────────────────────────────────
  // 저장 실행
  // ─────────────────────────────────────────────────
  Future<void> _commitChanges(
      QuerySnapshot<Map<String, dynamic>> currentSnap,
      ) async {
    if (!_hasPending) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final foodsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('meals')
        .doc(_mealKey)
        .collection('foods');

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 추가: nutrients만 사용
      for (final data in _pendingAdds) {
        final ref = foodsRef.doc();
        final toSave = _canonicalizeForSave(data);
        toSave['createdAt'] = FieldValue.serverTimestamp();
        batch.set(ref, toSave);
      }

      // 업데이트: nutrients로 덮고, top 필드 완전 삭제
      for (final entry in _pendingUpdates.entries) {
        final id = entry.key;
        final ref =
            currentSnap.docs.firstWhere((d) => d.id == id).reference;

        final payload = _canonicalizeForSave(entry.value);
        final updateMap = <String, dynamic>{}
          ..addAll(payload)
          ..addAll({
            'kcal': FieldValue.delete(),
            'carbs': FieldValue.delete(),
            'protein': FieldValue.delete(),
            'fat': FieldValue.delete(),
            'gram': FieldValue.delete(),
          });

        batch.update(ref, updateMap);
      }

      // 삭제
      for (final id in _pendingDeletes) {
        final ref =
            currentSnap.docs.firstWhere((d) => d.id == id).reference;
        batch.delete(ref);
      }

      await batch.commit();

      // 미러 재구성
      await _fullSyncDaily();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
      return;
    }

    _pendingUpdates.clear();
    _pendingDeletes.clear();
    _pendingAdds.clear();
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────────────────────────────
  // ✅ 하루 미러 전체 재구성 + 상단필드 마이그레이션(삭제)
  // ─────────────────────────────────────────────────
  Future<void> _fullSyncDaily() async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final dayId =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    final userRef = FirebaseFirestore.instance.collection('users').doc(_uid);
    final dailyRef = userRef.collection('daily').doc(dayId);

    // 허용 키: 표준 + 기본 매크로
    final userSnap = await userRef.get();
    final std =
        (userSnap.data()?['nutritionStandard'] as Map?)?.cast<String, dynamic>() ??
            {};
    final allowed = <String>{
      'enerc', 'prot', 'chocdf', 'fatce',
      ...std.keys.map((e) => e.toString()),
    };

    const mealNames = ['아침식사', '점심식사', '저녁식사', '간식'];

    final dailyTotals = <String, double>{};
    final flatFoods = <_FlatFood>[];

    for (final mealName in mealNames) {
      final mealKey = '${day.year}-${day.month}-${day.day}_$mealName';
      final foodsRef =
      userRef.collection('meals').doc(mealKey).collection('foods');
      final foodsSnap = await foodsRef.get();

      final mealTotals = <String, double>{};

      final fixBatch = FirebaseFirestore.instance.batch();
      var needFixCommit = false;

      for (final d in foodsSnap.docs) {
        final m = d.data();

        final nNorm = _nutrientsFrom(m);

        // 합계
        nNorm.forEach((k, v) {
          if (allowed.contains(k) && v != 0) _acc(mealTotals, k, v);
        });

        // daily/foods 표시용
        flatFoods.add(_FlatFood(
          id: '${mealName}__${d.id}',
          meal: mealName,
          name: (m['name'] ?? m['foodName'] ?? '식품').toString(),
          gram: nNorm['gram'] ?? 0.0,
          kcal: nNorm['enerc'] ?? 0.0,
          carbs: nNorm['chocdf'] ?? 0.0,
          protein: nNorm['prot'] ?? 0.0,
          fat: nNorm['fatce'] ?? 0.0,
          nutrients: nNorm,
          createdAt: m['createdAt'] is Timestamp
              ? (m['createdAt'] as Timestamp)
              : null,
        ));

        // 상단 영양 필드가 남아있으면 삭제(중복 방지)
        final hasTop = m.containsKey('kcal') ||
            m.containsKey('carbs') ||
            m.containsKey('protein') ||
            m.containsKey('fat') ||
            m.containsKey('gram');
        if (hasTop) {
          fixBatch.update(d.reference, {
            'nutrients': nNorm,
            'kcal': FieldValue.delete(),
            'carbs': FieldValue.delete(),
            'protein': FieldValue.delete(),
            'fat': FieldValue.delete(),
            'gram': FieldValue.delete(),
          });
          needFixCommit = true;
        }
      }

      if (needFixCommit) {
        await fixBatch.commit();
      }

      // 끼니 문서 작성
      final mealDocRef = dailyRef.collection('meals').doc(mealName);
      final mealWrite = <String, dynamic>{
        'name': mealName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      for (final k in allowed) {
        mealWrite[k] = mealTotals[k] ?? 0.0;
      }
      await mealDocRef.set(mealWrite, SetOptions(merge: true));

      // 일일 합계
      for (final k in allowed) {
        _acc(dailyTotals, k, mealTotals[k] ?? 0.0);
      }
    }

    // 일일 합계 저장
    final dailyWrite = <String, dynamic>{
      'date': Timestamp.fromDate(day),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    for (final k in allowed) {
      dailyWrite[k] = dailyTotals[k] ?? 0.0;
    }
    await dailyRef.set(dailyWrite, SetOptions(merge: true));

    // daily/foods 재작성
    final dailyFoodsRef = dailyRef.collection('foods');
    final existing = await dailyFoodsRef.get();

    if (existing.docs.isNotEmpty) {
      var idx = 0;
      while (idx < existing.docs.length) {
        final end = (idx + 400 < existing.docs.length)
            ? idx + 400
            : existing.docs.length;
        final batch = FirebaseFirestore.instance.batch();
        for (var i = idx; i < end; i++) {
          batch.delete(existing.docs[i].reference);
        }
        await batch.commit();
        idx = end;
      }
    }

    if (flatFoods.isNotEmpty) {
      var idx = 0;
      while (idx < flatFoods.length) {
        final end =
        (idx + 300 < flatFoods.length) ? idx + 300 : flatFoods.length;
        final batch = FirebaseFirestore.instance.batch();

        for (var i = idx; i < end; i++) {
          final f = flatFoods[i];
          final data = <String, dynamic>{
            'meal': f.meal,
            'name': f.name,
            'gram': f.gram, // 총 g만 별도 편의 필드로 유지
            'createdAt': f.createdAt ?? FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

// ✅ 허용 키(enerc, chocdf, prot, fatce, …)만 저장
//    → enerc가 칼로리의 유일 키가 됨
          f.nutrients.forEach((k, v) {
            if (allowed.contains(k)) data[k] = v;
          });

          batch.set(dailyFoodsRef.doc(f.id), data, SetOptions(merge: false));
        }

        await batch.commit();
        idx = end;
      }
    }
  }

  void _acc(Map<String, double> acc, String key, double v) {
    if (v == 0) return;
    acc[key] = (acc[key] ?? 0) + v;
  }

  // ─────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final foodsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('meals')
        .doc(_mealKey)
        .collection('foods');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.mealName,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Colors.black87),
            onPressed: () async {
              await Navigator.push(
                context,
                _noAnim(BarcodePage(mealName: widget.mealName)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black87),
            onPressed: () async {
              final payload = await Navigator.push(
                context,
                _noAnim(SearchPage(mealName: widget.mealName)),
              );
              if (payload is Map<String, dynamic>) {
                final normalized = _canonicalizeForSave(payload);
                setState(() {
                  _pendingAdds.add(normalized);
                });
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: foodsRef.orderBy('createdAt').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs =
          snap.data!.docs.where((d) => !_pendingDeletes.contains(d.id)).toList();

          double kc = 0, cb = 0, pt = 0, ft = 0;

          for (final d in docs) {
            final over = _overlayWithPending(d.id, d.data());
            kc += _macroOf(over, 'enerc');
            cb += _macroOf(over, 'chocdf');
            pt += _macroOf(over, 'prot');
            ft += _macroOf(over, 'fatce');
          }
          for (final m in _pendingAdds) {
            kc += _macroOf(m, 'enerc');
            cb += _macroOf(m, 'chocdf');
            pt += _macroOf(m, 'prot');
            ft += _macroOf(m, 'fatce');
          }

          final summary = Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(child: _SummaryItem(valueText: kc.toStringAsFixed(0), unitText: '칼로리')),
                Expanded(child: _SummaryItem(valueText: '${cb.toStringAsFixed(0)}g', unitText: '탄수화물')),
                Expanded(child: _SummaryItem(valueText: '${pt.toStringAsFixed(0)}g', unitText: '단백질')),
                Expanded(child: _SummaryItem(valueText: '${ft.toStringAsFixed(0)}g', unitText: '지방')),
              ],
            ),
          );

          final hasExisting = docs.isNotEmpty;
          final hasAdds = _pendingAdds.isNotEmpty;

          Widget list;
          if (!hasExisting && !hasAdds) {
            list = const Expanded(child: Center(child: Text('아직 음식이 없습니다.')));
          } else {
            list = Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: docs.length + _pendingAdds.length,
                itemBuilder: (ctx, index) {
                  if (index < docs.length) {
                    // 기존 문서
                    final doc = docs[index];
                    final m = _overlayWithPending(doc.id, doc.data());

                    final name = (m['name'] as String?) ?? '';
                    final gramVal = _gramOf(m);
                    final kcalVal = _macroOf(m, 'enerc');

                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: index == 0 ? 8 : 2),
                      child: ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -1),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        title: Text(
                          name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                        ),
                        subtitle: Text(
                          '${gramVal.toStringAsFixed(0)}g • ${kcalVal.toStringAsFixed(0)} kcal',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                        trailing: PopupMenuButton<String>(
                          color: Colors.white,
                          onSelected: (v) {
                            if (v == 'delete') {
                              setState(() {
                                _pendingDeletes.add(doc.id);
                                _pendingUpdates.remove(doc.id);
                              });
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'delete', child: Text('삭제하기'))
                          ],
                          icon: const Icon(Icons.more_vert, color: Colors.black38),
                        ),
                        onTap: () => _showEditDialogExisting(context, doc),
                      ),
                    );
                  }

                  // 추가예정 항목
                  final addIndex = index - docs.length;
                  final m = _pendingAdds[addIndex];
                  final name = (m['name'] as String?) ?? '';
                  final gramVal = _gramOf(m);
                  final kcalVal = _macroOf(m, 'enerc');

                  return Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: (!hasExisting && addIndex == 0) ? 8 : 2),
                    child: ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -1),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Row(
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x1F24C486),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('새 항목',
                                style: TextStyle(fontSize: 11, color: Color(0xFF24C486))),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${gramVal.toStringAsFixed(0)}g • ${kcalVal.toStringAsFixed(0)} kcal',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                      trailing: PopupMenuButton<String>(
                        color: Colors.white,
                        onSelected: (v) {
                          if (v == 'delete') {
                            setState(() {
                              _pendingAdds.removeAt(addIndex);
                            });
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'delete', child: Text('삭제하기'))
                        ],
                        icon: const Icon(Icons.more_vert, color: Colors.black38),
                      ),
                      onTap: () => _showEditDialogPendingAdd(context, addIndex, m),
                    ),
                  );
                },
              ),
            );
          }

          return Column(
            children: [
              summary,
              const SizedBox(height: 16),
              list,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF24C486),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _commitChanges(snap.data!),
                    child: Text(
                      _hasPending ? '저장 (변경사항 적용)' : '저장',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────
  // 편집 다이얼로그
  // ─────────────────────────────────────────────────
  void _showEditDialogExisting(
      BuildContext ctx,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    const themeGreen = Color(0xFF24C486);
    final data = _overlayWithPending(doc.id, doc.data());

    final oldTotalGram = _gramOf(data);
    final oldCount = (data['count'] as num?)?.toInt() ?? 1;
    final perItemOldGram = (oldCount > 0) ? (oldTotalGram / oldCount) : oldTotalGram;

    final gramCtl = TextEditingController(text: perItemOldGram.toStringAsFixed(0)); // 1개당 g
    final countCtl = TextEditingController(text: oldCount.toString()); // 개수
    String unit = 'g'; // g 먼저

    showGeneralDialog(
      context: ctx,
      barrierLabel: '총 내용량',
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogCtx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (dCtx, setDialog) {
                return Dialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('총 내용량', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        const Center(
                          child: Text('총 내용량을 입력하세요', style: TextStyle(fontSize: 13, color: Colors.black54)),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: gramCtl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.left,
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
                            const Text('개', style: TextStyle(color: Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              child: const Text('취소', style: TextStyle(color: Colors.black54)),
                            ),
                            const SizedBox(width: 16),
                            TextButton(
                              onPressed: () {
                                final perItemInput = double.tryParse(gramCtl.text) ?? 0;
                                final newCount = int.tryParse(countCtl.text) ?? 0;
                                if (perItemInput <= 0 || newCount <= 0 || oldTotalGram <= 0) {
                                  Navigator.of(dialogCtx).pop();
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

                                final newTotalGram = perItemGram * newCount;
                                final ratio = newTotalGram / (oldTotalGram == 0 ? 1 : oldTotalGram);

                                final baseN = _nutrientsFrom(Map<String, dynamic>.from(data));
                                final scaledN = _scaleNutrients(baseN, ratio);
                                scaledN['gram'] = newTotalGram; // 총 g는 직접 대입

                                setState(() {
                                  _pendingUpdates[doc.id] = {
                                    'count': newCount,
                                    'nutrients': scaledN,
                                  };
                                });

                                Navigator.of(dialogCtx).pop();
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
          ),
        );
      },
      transitionBuilder: (_, __, ___, child) => child,
    );
  }

  void _showEditDialogPendingAdd(
      BuildContext ctx,
      int addIndex,
      Map<String, dynamic> data,
      ) {
    const themeGreen = Color(0xFF24C486);

    final oldTotalGram = _gramOf(data);
    final oldCount = (data['count'] as num?)?.toInt() ?? 1;
    final perItemOldGram = (oldCount > 0) ? (oldTotalGram / oldCount) : oldTotalGram;

    final gramCtl = TextEditingController(text: perItemOldGram.toStringAsFixed(0));
    final countCtl = TextEditingController(text: oldCount.toString());
    String unit = 'g';

    showGeneralDialog(
      context: ctx,
      barrierLabel: '총 내용량',
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogCtx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (dCtx, setDialog) {
                return Dialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('총 내용량', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        const Center(
                          child: Text('총 내용량을 입력하세요', style: TextStyle(fontSize: 13, color: Colors.black54)),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: gramCtl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.left,
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
                            const Text('개', style: TextStyle(color: Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              child: const Text('취소', style: TextStyle(color: Colors.black54)),
                            ),
                            const SizedBox(width: 16),
                            TextButton(
                              onPressed: () {
                                final perItemInput = double.tryParse(gramCtl.text) ?? 0;
                                final newCount = int.tryParse(countCtl.text) ?? 0;
                                if (perItemInput <= 0 || newCount <= 0 || oldTotalGram <= 0) {
                                  Navigator.of(dialogCtx).pop();
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

                                final newTotalGram = perItemGram * newCount;
                                final ratio = newTotalGram / (oldTotalGram == 0 ? 1 : oldTotalGram);

                                final baseN = _nutrientsFrom(Map<String, dynamic>.from(data));
                                final scaledN = _scaleNutrients(baseN, ratio);
                                scaledN['gram'] = newTotalGram; // 총 g는 직접 대입

                                final newMap = Map<String, dynamic>.from(data);
                                newMap['count'] = newCount;
                                newMap['nutrients'] = scaledN;

                                // 상단 필드 제거(중복 방지)
                                newMap.remove('kcal');
                                newMap.remove('carbs');
                                newMap.remove('protein');
                                newMap.remove('fat');
                                newMap.remove('gram');

                                setState(() {
                                  _pendingAdds[addIndex] = newMap;
                                });

                                Navigator.of(dialogCtx).pop();
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
          ),
        );
      },
      transitionBuilder: (_, __, ___, child) => child,
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String valueText;
  final String unitText;

  const _SummaryItem({
    Key? key,
    required this.valueText,
    required this.unitText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          valueText,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          unitText,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}

class _FlatFood {
  final String id; // mealName__docId
  final String meal;
  final String name;
  final double gram;
  final double kcal;
  final double carbs;
  final double protein;
  final double fat;
  final Map<String, double> nutrients; // 정규화된 키
  final Timestamp? createdAt;

  _FlatFood({
    required this.id,
    required this.meal,
    required this.name,
    required this.gram,
    required this.kcal,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.nutrients,
    required this.createdAt,
  });
}
