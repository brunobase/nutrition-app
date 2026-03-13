// lib/me_standard.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// ─────────────────────────────────────────
/// 메타 타입 (파일 최상단에 선언)
/// ─────────────────────────────────────────
enum _NumType { intLike, doubleLike }

class _FieldMeta {
  final String title;      // 화면 라벨
  final String key;        // nutritionStandard 저장 키
  final String unit;       // 표시 단위
  final _NumType type;     // 정수형/실수형
  final int decimals;      // 실수 표시 소수자리
  const _FieldMeta({
    required this.title,
    required this.key,
    required this.unit,
    required this.type,
    this.decimals = 1,
  });
}

class MeStandardPage extends StatefulWidget {
  const MeStandardPage({Key? key}) : super(key: key);

  @override
  State<MeStandardPage> createState() => _MeStandardPageState();
}

class _MeStandardPageState extends State<MeStandardPage> {
  static const Color _accentGreen = Color(0xFF24C486);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// 편집 중 값(저장 전 임시, 문자열 그대로 보관)
  final Map<String, String> _edited = {};
  final Set<String> _dirty = {};
  bool _saving = false;

  // ─────────────────────────────────────────
  // OnboardingFlow에서 저장한 전체 기준 항목 정의
  // ─────────────────────────────────────────
  final List<_FieldMeta> _fields = const [
    // 에너지/매크로
    _FieldMeta(title: '칼로리',           key: 'enerc', unit: 'kcal', type: _NumType.intLike),
    _FieldMeta(title: '탄수화물',         key: 'chocdf', unit: 'g', type: _NumType.doubleLike),
    _FieldMeta(title: '단백질',           key: 'prot', unit: 'g', type: _NumType.doubleLike),
    _FieldMeta(title: '지방',             key: 'fatce', unit: 'g', type: _NumType.doubleLike),
    _FieldMeta(title: '식이섬유',         key: 'fibtg', unit: 'g', type: _NumType.doubleLike),
    _FieldMeta(title: '당류(상한)',        key: 'sugar', unit: 'g', type: _NumType.doubleLike),

    // 미량영양소/지방상한
    _FieldMeta(title: '나트륨(상한)',     key: 'nat', unit: 'mg', type: _NumType.intLike),
    _FieldMeta(title: '칼슘',             key: 'ca', unit: 'mg', type: _NumType.intLike),
    _FieldMeta(title: '철',               key: 'fe', unit: 'mg', type: _NumType.intLike),
    _FieldMeta(title: '칼륨',             key: 'k', unit: 'mg', type: _NumType.intLike),
    _FieldMeta(title: '인',               key: 'p', unit: 'mg', type: _NumType.intLike),
    _FieldMeta(title: '콜레스테롤(상한)', key: 'chole', unit: 'mg', type: _NumType.intLike),
    _FieldMeta(title: '포화지방(상한)',    key: 'fasat', unit: 'g', type: _NumType.doubleLike),
    _FieldMeta(title: '트랜스지방(상한)',  key: 'fatrn', unit: 'g', type: _NumType.doubleLike),

    // 비타민
    _FieldMeta(title: '비타민 A',         key: 'vita', unit: 'µg RAE', type: _NumType.intLike),
    _FieldMeta(title: '비타민 D',         key: 'vitd', unit: 'µg', type: _NumType.intLike),
    _FieldMeta(title: '비타민 E',         key: 'vite', unit: 'mg α-TE', type: _NumType.doubleLike),
    _FieldMeta(title: '비타민 K',         key: 'vitk', unit: 'µg', type: _NumType.intLike),
    _FieldMeta(title: '비타민 B1(티아민)', key: 'vitb1', unit: 'mg', type: _NumType.doubleLike),
    _FieldMeta(title: '비타민 B2(리보플라빈)', key: 'vitb2', unit: 'mg', type: _NumType.doubleLike),
    _FieldMeta(title: '비타민 B6',        key: 'vitb6', unit: 'mg', type: _NumType.doubleLike),
    _FieldMeta(title: '비타민 B12',       key: 'vitb12', unit: 'µg', type: _NumType.doubleLike),
    _FieldMeta(title: '엽산(DFE)',        key: 'fol', unit: 'µg', type: _NumType.intLike),
    _FieldMeta(title: '나이아신(NE)',     key: 'nia', unit: 'mg', type: _NumType.doubleLike),
    _FieldMeta(title: '판토텐산',          key: 'pant', unit: 'mg', type: _NumType.doubleLike),
    _FieldMeta(title: '비오틴',           key: 'bio', unit: 'µg', type: _NumType.intLike),
    _FieldMeta(title: '비타민 C',         key: 'vitc', unit: 'mg', type: _NumType.intLike),
  ];

  // ─────────────────────────────────────────
  // 포맷/파싱 유틸
  // ─────────────────────────────────────────
  String _fmtDisplay(dynamic v, _FieldMeta f) {
    if (v == null) return '—';
    if (f.type == _NumType.intLike) {
      if (v is int) return v.toString();
      if (v is double) return v.round().toString();
      final d = double.tryParse('$v');
      return d == null ? '—' : d.round().toString();
    } else {
      final d = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
      final s = d.toStringAsFixed(f.decimals);
      return f.decimals == 0 || !s.contains('.')
          ? s
          : (s.endsWith('.0') ? s.substring(0, s.length - 2) : s);
    }
  }

  /// 리스트에서 초기 채우기 값(편집 중이면 편집값 우선)
  String _prefillValue(Map<String, dynamic> std, _FieldMeta f) {
    final dirty = _edited[f.title];
    if (dirty != null) return dirty;
    return _fmtDisplay(std[f.key], f);
  }

  /// 저장용 파싱(숫자 타입으로만 변환; 화면 표시는 편집시엔 변환하지 않음)
  dynamic _parseForSave(String raw, _FieldMeta f) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final d = double.tryParse(t.replaceAll(',', ''));
    if (d == null) return null;
    if (f.type == _NumType.intLike) return d.round();
    return double.parse(d.toStringAsFixed(f.decimals));
  }

  void _onEdit(String title, String newText) {
    setState(() {
      _edited[title] = newText; // ← 사용자가 쓴 그대로
      _dirty.add(title);
    });
  }

  Future<void> _saveEdited() async {
    final uid = _uid;
    if (uid == null || _dirty.isEmpty || _saving) return;
    setState(() => _saving = true);

    try {
      final Map<String, dynamic> update = {};
      for (final f in _fields) {
        if (!_dirty.contains(f.title)) continue;
        final raw = _edited[f.title] ?? '';
        final parsed = _parseForSave(raw, f);
        if (parsed == null) continue;
        update['nutritionStandard.${f.key}'] = parsed;
      }
      update['nutritionStandard.updatedAt'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(update, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _saving = false;
        _edited.clear();
        _dirty.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기준이 저장되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    }
  }

  /// 수정 입력 시트: 열리자마자 키보드 자동 표시(autofocus + requestFocus)
  void _showInputSheet({
    required _FieldMeta field,
    required String initialText,
  }) {
    final controller =
    TextEditingController(text: initialText == '—' ? '' : initialText);
    final isDecimalKeyboard = field.type == _NumType.doubleLike;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => AnimatedPadding(
        // ✅ 키보드가 올라오면 그 즉시(애니메이션 없이) 시트가 키보드 위로 이동
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        duration: const Duration(milliseconds: 0),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  field.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // ✅ 자동 포커스/강제 포커스 제거: 사용자가 텍스트필드를 탭해야 키보드가 뜸
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: controller,
                    autofocus: false,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: isDecimalKeyboard,
                      signed: false,
                    ),
                    decoration: InputDecoration(
                      suffixText: field.unit,
                      suffixStyle: const TextStyle(color: Colors.black54),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.transparent),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.transparent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity, height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        _onEdit(field.title, controller.text); // 변환 없이 임시 저장
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF24C486),
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


  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text('로그인이 필요합니다.')),
      );
    }

    final userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        final std = (snap.data?.data()?['nutritionStandard'] as Map<String, dynamic>?) ?? {};

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text(
              '1일 영양소 섭취기준',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            leading: const BackButton(color: Colors.black87),
          ),
          body: ListView.separated(
            itemCount: _fields.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.transparent),
            itemBuilder: (ctx, idx) {
              final f = _fields[idx];

              // ✅ 리스트 표시: 편집 중이면 "입력한 그대로" 표시(단위만 붙임),
              //    아니면 실시간 DB 값을 포맷해서 표시
              final editedText = _edited[f.title];
              final baseText = (editedText != null && _dirty.contains(f.title))
                  ? (editedText.isEmpty ? '—' : editedText)                 // 변환 X
                  : _fmtDisplay(std[f.key], f);                             // DB 포맷

              final withUnit =
              baseText == '—' ? baseText : '$baseText ${f.unit}';

              final prefill = _prefillValue(std, f);

              return InkWell(
                onTap: () => _showInputSheet(field: f, initialText: prefill),
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(f.title,
                            style: const TextStyle(fontSize: 16, color: Colors.black87)),
                      ),
                      Text(
                        withUnit,
                        style: const TextStyle(fontSize: 16, color: _accentGreen),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving || _dirty.isEmpty ? null : _saveEdited,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : Text(
                    _dirty.isEmpty ? '수정할 항목을 선택하세요' : '저장',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
