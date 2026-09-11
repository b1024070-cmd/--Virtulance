// =============================================================
// record_page.dart
// 記録画面(「記録」タブと「見る」タブ)。
// 担当: Hayato
//
// ポイント:
//   - 「徳」は-10〜10の範囲に入力バリデーションをかけている
//   - 保存前に「自分のみ記録」か「世界に投稿」かを選ばせる確認ダイアログを挟み、
//     これがRecordItem.isPublicとしてローカル/Firestoreの保存先の分岐点になる
//   - 記録詳細では、その記録時点までの累計値を計算して表示する
//     (_calculateTotalAtPoint。実装で最も苦労した処理)
// =============================================================

import 'package:flutter/material.dart';
import 'main.dart'; // RecordItemを参照するために追加

class RecordPage extends StatefulWidget {
  final List<RecordItem> records;
  final Function(RecordItem) onSave;
  final Function(RecordItem) onUpdate;
  final Function(RecordItem) onDelete;

  const RecordPage({
    super.key,
    required this.records,
    required this.onSave,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  int _selectedTab = 0;
  // リストは親からもらったものを使用する
  List<RecordItem> get _records => widget.records;

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  int? _selectedDay;

  final TextEditingController _virtueCommentController = TextEditingController();
  final TextEditingController _virtuePtController = TextEditingController();
  final TextEditingController _balanceCommentController = TextEditingController();
  final TextEditingController _balanceAmountController = TextEditingController();

  // その記録が作られた「時点」での累計値を計算する。
  // 同じ種類(徳/収支)の記録のうち、対象の記録の日時以前のものだけを合計する、
  // という時系列を意識した集計。「今この記録を見た時点で、それまでの累計がいくつだったか」を
  // 正しく出すために、日付でのフィルタと合計を組み合わせる必要があり、この画面の実装の中で
  // 最も考え方の整理に時間がかかった部分。
  int _calculateTotalAtPoint(RecordItem targetItem) {
    return _records
        .where((r) => r.type == targetItem.type)
        .where((r) => r.date.isBefore(targetItem.date) || r.date.isAtSameMomentAs(targetItem.date))
        .fold(0, (sum, item) => sum + item.value);
  }

  // 入力内容のバリデーションと保存を行う。
  // 「徳」は-10〜10の範囲に収まっているかをチェックし、範囲外ならSnackBarで通知して保存を中断する。
  void _saveRecord(String type) {
    String comment = type == '徳' ? _virtueCommentController.text : _balanceCommentController.text;
    String valStr = type == '徳' ? _virtuePtController.text : _balanceAmountController.text;
    int? value = int.tryParse(valStr);

    if (comment.isEmpty || value == null) return;

    // 徳のバリデーション
    if (type == '徳' && (value > 10 || value < -10)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('徳は -10 ~ 10 で入力してください'), backgroundColor: Colors.redAccent)
      );
      return;
    }

    // 保存前に必ず公開範囲を選ばせる確認ダイアログを表示する。
    // ここでの選択(isGlobal)が、main.dartの_addNewRecordでの
    // 「ローカルのみ保存」か「Firestoreにも保存」かの分岐に直結する。
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('保存の確認'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('種類: $type'),
            Text('内容: $comment'),
            Text('数値: $value'),
            const SizedBox(height: 16),
            const Text('この内容をどうしますか？', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // パターン1: 記録のみ（自分だけ）
          TextButton(
            onPressed: () {
              _executeSave(type, comment, value, isGlobal: false);
              Navigator.pop(context);
            },
            child: const Text('自分のみ記録', style: TextStyle(color: Colors.grey)),
          ),
          // パターン2: 記録 ＋ 投稿（みんなに見える）
          ElevatedButton(
            onPressed: () {
              _executeSave(type, comment, value, isGlobal: true);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('世界に投稿', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 保存処理の共通化
  void _executeSave(String type, String comment, int value, {required bool isGlobal}) {
    widget.onSave(RecordItem(
      type: type,
      comment: comment,
      value: value,
      date: DateTime.now(),
      isPublic: isGlobal, // グローバルなら true、自分のみなら false になる
    ));

    setState(() {
      if (type == '徳') {
        _virtueCommentController.clear();
        _virtuePtController.clear();
      } else {
        _balanceCommentController.clear();
        _balanceAmountController.clear();
      }
    });

    final message = isGlobal ? '世界に投稿しました！' : '自分のみ記録しました';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _editRecord(RecordItem item) {
    final cCtrl = TextEditingController(text: item.comment);
    final vCtrl = TextEditingController(text: item.value.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('記録を修正'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: cCtrl, decoration: const InputDecoration(labelText: '内容')),
            TextField(controller: vCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '数値')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              // 元のアイテムを削除
              widget.onDelete(item);
              // 新しいRecordItemを作成して追加（isPublicも保持）
              final updatedItem = RecordItem(
                type: item.type,
                comment: cCtrl.text,
                value: int.tryParse(vCtrl.text) ?? item.value,
                date: item.date,
                isPublic: item.isPublic, // isPublicも保持
              );
              widget.onSave(updatedItem);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('記録', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildTabSwitcher(),
          Expanded(child: _selectedTab == 0 ? _buildRecordView() : _buildViewPage()),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        height: 45,
        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(25)),
        child: Row(
          children: [
            _buildTabButton('記録', 0),
            _buildTabButton('見る', 1),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          decoration: BoxDecoration(color: isSelected ? Colors.blue : Colors.transparent, borderRadius: BorderRadius.circular(25)),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildRecordView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _buildInputCard('徳を積む', Icons.auto_awesome, Colors.amber[700]!, _virtueCommentController, _virtuePtController, 'Pt', () => _saveRecord('徳'), hintValue: '(-10~10)', hintComment: '例：ゴミを拾った'),
        const SizedBox(height: 16),
        _buildInputCard('収支を記録', Icons.currency_yen, Colors.blueGrey, _balanceCommentController, _balanceAmountController, '円', () => _saveRecord('収支'), hintValue: '金額', hintComment: '例：パチンコで勝った'),
      ],
    );
  }

  Widget _buildInputCard(String title, IconData icon, Color color, TextEditingController cCtrl, TextEditingController vCtrl, String unit, VoidCallback onSave, {required String hintValue, String? hintComment}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: color), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          TextField(controller: cCtrl, decoration: InputDecoration(hintText: hintComment ?? '内容を入力', filled: true, fillColor: const Color(0xFFF5F5F5), border: InputBorder.none)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(controller: vCtrl, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: InputDecoration(hintText: hintValue, suffixText: unit, filled: true, fillColor: const Color(0xFFF5F5F5), border: InputBorder.none))),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: onSave, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white), child: const Text('決定')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewPage() {
    final filteredRecords = _records.where((r) {
      bool match = r.date.year == _selectedYear && r.date.month == _selectedMonth;
      if (_selectedDay != null) match = match && r.date.day == _selectedDay;
      return match;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('年:', style: TextStyle(color: Colors.grey)),
              DropdownButton<int>(
                value: _selectedYear,
                items: List.generate(26, (index) => 2025 + index).map((y) => DropdownMenuItem(value: y, child: Text('$y年'))).toList(),
                onChanged: (val) => setState(() { _selectedYear = val!; _selectedDay = null; }),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(12, (i) => i + 1).map((m) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text('$m月'),
                        selected: _selectedMonth == m,
                        onSelected: (val) => setState(() { _selectedMonth = m; _selectedDay = null; }),
                      ),
                    )).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.calendar_month, color: _selectedDay != null ? Colors.blue : Colors.grey),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime(_selectedYear, _selectedMonth, _selectedDay ?? 1),
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2050),
                  );
                  if (date != null) {
                    setState(() {
                      _selectedYear = date.year;
                      _selectedMonth = date.month;
                      _selectedDay = date.day;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        if (_selectedDay != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                InputChip(
                  label: Text('$_selectedYear/$_selectedMonth/$_selectedDay'),
                  onDeleted: () => setState(() => _selectedDay = null),
                  deleteIcon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
        const Divider(),
        Expanded(
          child: filteredRecords.isEmpty
              ? const Center(child: Text('記録がありません'))
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredRecords.length,
            itemBuilder: (context, index) {
              final item = filteredRecords[index];
              return Dismissible(
                key: ObjectKey(item),
                direction: DismissDirection.endToStart,
                background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: Colors.red, child: const Icon(Icons.delete, color: Colors.white)),
                onDismissed: (dir) {
                  widget.onDelete(item);
                },
                child: Card(
                  child: ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => _DetailView(
                      item: item,
                      totalAtPoint: _calculateTotalAtPoint(item),
                      onUpdate: () => setState(() {}),
                      onDelete: () {
                        Navigator.pop(context);
                        widget.onDelete(item);
                      },
                      onEdit: () => _editRecord(item),
                    ))),
                    leading: Icon(item.type == '徳' ? Icons.auto_awesome : Icons.currency_yen, color: item.type == '徳' ? Colors.amber[700] : Colors.blueGrey),
                    title: Text(item.comment, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${item.date.month}/${item.date.day} ${item.date.hour}:${item.date.minute.toString().padLeft(2, '0')}'),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DetailView extends StatelessWidget {
  final RecordItem item;
  final int totalAtPoint;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  const _DetailView({required this.item, required this.totalAtPoint, required this.onUpdate, required this.onDelete, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('詳細'),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row('種類', item.type),
              _row('日時', '${item.date.year}/${item.date.month}/${item.date.day} ${item.date.hour}:${item.date.minute}'),
              const Divider(height: 30),
              _row('内容', item.comment),
              _row('変動', '${item.value > 0 ? "+" : ""}${item.value}', isBold: true),
              const Divider(height: 30),
              _row('この時点の累計', '$totalAtPoint ${item.type == '徳' ? "Pt" : "円"}', color: Colors.blue[700], isBold: true),
            ],
          ),
        ),
      ),
    );
  }
  Widget _row(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color, fontSize: 16)),
        ],
      ),
    );
  }
}