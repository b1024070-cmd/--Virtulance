// =============================================================
// my_page_screen.dart
// グラフ画面(徳・収支の推移を折れ線グラフで表示)。
// 担当: 西園寺こうぼう
//
// 週/月/年での表示切り替え、縦の拡大率スライダー、横スクロールで
// 日付幅を動的計算する仕組みが実装されている(fl_chartパッケージを使用)。
// =============================================================

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'main.dart';

class MyPageScreen extends StatefulWidget {
  final List<RecordItem> records;
  const MyPageScreen({super.key, required this.records});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  @override
  Widget build(BuildContext context) {
    int totalPoints = widget.records.where((r) => r.type == '徳').fold(0, (sum, r) => sum + r.value);
    int totalBalance = widget.records.where((r) => r.type == '収支').fold(0, (sum, r) => sum + r.value);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('グラフ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ScrollableGraph(records: widget.records),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _buildTotalCard('総ポイント', '$totalPoints P', Colors.blue, totalPoints)),
                const SizedBox(width: 12),
                Expanded(child: _buildTotalCard('総収支', '$totalBalance 円', Colors.green, totalBalance)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('直近の記録', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildSummaryTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard(String title, String value, Color color, int numericValue) {
    // 数値が0未満の場合は赤色、0以上の場合は元の色を使用
    final displayColor = numericValue < 0 ? Colors.red : color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              if (title == '総ポイント') ...[
                Icon(Icons.auto_awesome, color: Colors.amber[700], size: 18),
              ] else if (title == '総収支') ...[
                const Icon(Icons.wallet, color: Colors.brown, size: 18),
              ],
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: displayColor))),
        ],
      ),
    );
  }

  Widget _buildSummaryTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          border: TableBorder.all(color: Colors.grey[200]!, width: 1),
          children: widget.records.reversed.take(5).map((record) {
            return TableRow(
              children: [
                TableCell(child: Padding(padding: const EdgeInsets.all(12), child: Text(record.type, textAlign: TextAlign.center))),
                TableCell(child: Padding(padding: const EdgeInsets.all(12), child: Text('${record.value > 0 ? "+" : ""}${record.value}${record.type == "徳" ? "P" : "円"}', textAlign: TextAlign.center, style: TextStyle(color: record.value >= 0 ? Colors.black : Colors.red)))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class ScrollableGraph extends StatefulWidget {
  final List<RecordItem> records;
  const ScrollableGraph({super.key, required this.records});
  @override
  State<ScrollableGraph> createState() => _ScrollableGraphState();
}

class _ScrollableGraphState extends State<ScrollableGraph> {
  final ScrollController _scrollController = ScrollController();
  String _selectedRange = '週';
  double verticalZoom = 1.0;

  static final DateTime now = DateTime.now();
  final DateTime startDate = DateTime(now.year - 2, now.month, now.day);
  final DateTime endDate = DateTime(now.year + 2, now.month, now.day);

  late final int totalDays;
  late int _currentMonth;
  late int _currentYear;

  @override
  void initState() {
    super.initState();
    totalDays = endDate.difference(startDate).inDays;
    _currentMonth = now.month;
    _currentYear = now.year;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentDay());
  }

  double _calculateDayWidth(double screenWidth) {
    double chartAreaWidth = screenWidth - (55 * 2) - 32;
    if (_selectedRange == '週') return chartAreaWidth / 7;
    if (_selectedRange == '月') return chartAreaWidth / 30;
    if (_selectedRange == '年') return chartAreaWidth / 365;
    return 60.0;
  }

  void _scrollToCurrentDay() {
    if (!_scrollController.hasClients) return;
    final diff = DateTime.now().difference(startDate).inDays;
    double dayWidth = _calculateDayWidth(MediaQuery.of(context).size.width);

    double scrollPos = diff * dayWidth;
    // maxScrollExtentが0の場合は、少し待ってから再試行
    if (_scrollController.position.maxScrollExtent == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          double newScrollPos = diff * _calculateDayWidth(MediaQuery.of(context).size.width);
          _scrollController.jumpTo(
            newScrollPos.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      });
      return;
    }
    _scrollController.jumpTo(
      scrollPos.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  void _updateHeaderInfo() {
    if (!_scrollController.hasClients) return;
    double dayWidth = _calculateDayWidth(MediaQuery.of(context).size.width);
    double centerOffset = _scrollController.offset + (MediaQuery.of(context).size.width / 2);
    int dayIndex = (centerOffset / dayWidth).floor();

    if (dayIndex >= 0 && dayIndex < totalDays) {
      DateTime centerDate = startDate.add(Duration(days: dayIndex));
      if (_currentMonth != centerDate.month || _currentYear != centerDate.year) {
        setState(() {
          _currentMonth = centerDate.month;
          _currentYear = centerDate.year;
        });
      }
    }
  }

  List<FlSpot> _getSpots(String type) {
    Map<int, double> dailySums = {};
    for (var r in widget.records.where((r) => r.type == type)) {
      int day = r.date.difference(startDate).inDays;
      if (day >= 0 && day < totalDays) {
        dailySums[day] = (dailySums[day] ?? 0) + r.value.toDouble();
      }
    }
    return dailySums.entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList()..sort((a, b) => a.x.compareTo(b.x));
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double dayWidth = _calculateDayWidth(screenWidth);

    double ptMax = 150 / verticalZoom;
    double ptMin = -100 / verticalZoom;
    double moneyMax = 150000 / verticalZoom;
    double moneyMin = -100000 / verticalZoom;

    return Container(
      height: 480,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        children: [
          _buildGraphControls(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedRange == '年' ? '$_currentYear年' : '$_currentYear年 $_currentMonth月',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    _buildLegendItem('ポイント', Colors.blue),
                    const SizedBox(width: 12),
                    _buildLegendItem('収支', Colors.green),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                _buildYAxis(ptMax, ptMin, Colors.blue, "P"),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) { _updateHeaderInfo(); return true; },
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: dayWidth * totalDays,
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 50, top: 20),
                              child: LineChart(
                                LineChartData(
                                  minX: 0, maxX: totalDays.toDouble() - 1,
                                  minY: ptMin, maxY: ptMax,
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: _getSpots('徳'),
                                      color: Colors.blue,
                                      dotData: FlDotData(show: _selectedRange != '年'),
                                      barWidth: _selectedRange == '週' ? 4 : 2,
                                    ),
                                    LineChartBarData(
                                      spots: _getSpots('収支').map((s) => FlSpot(s.x, s.y * (ptMax / moneyMax))).toList(),
                                      color: Colors.green,
                                      dotData: FlDotData(show: _selectedRange != '年'),
                                      barWidth: _selectedRange == '週' ? 4 : 2,
                                    ),
                                  ],
                                  titlesData: const FlTitlesData(show: false),
                                  gridData: FlGridData(
                                    show: true,
                                    horizontalInterval: (ptMax - ptMin) / 5,
                                    verticalInterval: 1,
                                    checkToShowVerticalLine: (double value) {
                                      int i = value.toInt();
                                      if (i < 0 || i >= totalDays) return false;
                                      DateTime date = startDate.add(Duration(days: i));
                                      if (_selectedRange == '週') return true;
                                      if (_selectedRange == '月') return i % 3 == 0;
                                      if (_selectedRange == '年') return date.day == 1;
                                      return false;
                                    },
                                    getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey[100]!, strokeWidth: 1),
                                    getDrawingVerticalLine: (v) => FlLine(color: Colors.grey[300]!, strokeWidth: 2.5),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  lineTouchData: LineTouchData(
                                    touchTooltipData: LineTouchTooltipData(
                                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                                        return touchedSpots.asMap().entries.map((entry) {
                                          final index = entry.key;
                                          final touchedSpot = entry.value;

                                          // どのラインか判定（0: 徳、1: 収支）
                                          final isVirtue = index == 0;

                                          String valueText;
                                          if (isVirtue) {
                                            // ポイントの場合
                                            final actualValue = touchedSpot.y;
                                            valueText = '${actualValue.toStringAsFixed(0)}P';
                                          } else {
                                            // 収支の場合（スケールを元に戻す）
                                            final scaledValue = touchedSpot.y;
                                            final actualValue = scaledValue * (moneyMax / ptMax);
                                            if (actualValue.abs() >= 10000) {
                                              valueText = '${(actualValue / 10000).toStringAsFixed(1)}万円';
                                            } else if (actualValue.abs() >= 1000) {
                                              valueText = '${(actualValue / 1000).toStringAsFixed(0)}k円';
                                            } else {
                                              valueText = '${actualValue.toStringAsFixed(0)}円';
                                            }
                                          }

                                          return LineTooltipItem(
                                            valueText,
                                            TextStyle(
                                              color: isVirtue ? Colors.blue : Colors.green,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          );
                                        }).toList();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 15,
                              left: 0,
                              right: 0,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(totalDays, (i) {
                                  final date = startDate.add(Duration(days: i));
                                  bool showLabel = false;
                                  String labelText = "";
                                  Color textColor = Colors.black;

                                  if (_selectedRange == '週') {
                                    showLabel = true;
                                    labelText = "${date.day}";
                                  } else if (_selectedRange == '月') {
                                    if (i % 3 == 0) { showLabel = true; labelText = "${date.day}"; }
                                  } else if (_selectedRange == '年') {
                                    if (date.day == 1) {
                                      showLabel = true;
                                      labelText = "${date.month}月";
                                      textColor = Colors.blueGrey;
                                    }
                                  }

                                  if (_selectedRange != '年') {
                                    if (date.weekday == DateTime.sunday) textColor = Colors.red;
                                    if (date.weekday == DateTime.saturday) textColor = Colors.blue;
                                  }

                                  return SizedBox(
                                    width: dayWidth,
                                    child: showLabel ? Center(
                                      child: Text(labelText, style: TextStyle(fontSize: _selectedRange == '年' ? 9 : 10, fontWeight: FontWeight.bold, color: textColor)),
                                    ) : const SizedBox.shrink(),
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _buildYAxis(moneyMax, moneyMin, Colors.green, "円"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYAxis(double max, double min, Color color, String unit) {
    double range = max - min;
    List<double> steps = List.generate(6, (i) => max - (range / 5 * i));
    const double topPadding = 16;   // ← 上の安全余白
    const double bottomPadding = 16; // ← 下の安全余白

    return SizedBox(
      width: 55,
      child: Column(
        children: [
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(
                children: steps.asMap().entries.map((entry) {
                  int idx = entry.key;
                  double val = entry.value;
                  double topOffset = (constraints.maxHeight / 5) * idx;
                  String displayVal;
                  if (unit == "P") {
                    displayVal = verticalZoom > 3.0 ? "${val.toStringAsFixed(1)}P" : "${val.toStringAsFixed(0)}P";
                  } else {
                    if (val.abs() >= 10000) {
                      displayVal = "${(val / 10000).toStringAsFixed(1)}万";
                    } else if (val.abs() >= 1000) {
                      displayVal = "${(val / 1000).toStringAsFixed(0)}k";
                    } else {
                      displayVal = val.toStringAsFixed(0);
                    }
                  }
                  // ポイント（P）の場合は負の値だけ赤色、収支（円）の場合は緑色の時のみ負の値を赤色
                  Color textColor;
                  if (unit == "P") {
                    textColor = val < 0 ? Colors.red : color;
                  } else {
                    textColor = val < 0 && color == Colors.green ? Colors.red : color;
                  }

                  return Positioned(
                    top: topOffset,
                    left: 0,
                    right: 0,
                    child: Text(
                      displayVal,
                      style: TextStyle(fontSize: 8, color: textColor),
                      textAlign: TextAlign.center,
                    ),
                  );
                }).toList(),
              );
            }),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildGraphControls() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ['週', '月', '年'].map((r) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(r),
                selected: _selectedRange == r,
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedRange = r;
                    });
                    // 範囲変更後、レイアウトが完了してからスクロール位置を更新
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (mounted && _scrollController.hasClients) {
                          _scrollToCurrentDay();
                        }
                      });
                    });
                  }
                },
              ),
            )).toList(),
          ),
          // Wrap を使用して、微細なサイズ計算誤差を吸収します
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.height, size: 16, color: Colors.grey),
              const Text(' 縦の拡大率', style: TextStyle(fontSize: 10)),
              SizedBox(
                // 画面幅からアイコンとテキストの概算幅を引いた分をスライダーに割り当て
                width: MediaQuery.of(context).size.width * 0.7,
                child: Slider(
                  value: verticalZoom,
                  min: 0.2,
                  max: 10.0,
                  onChanged: (v) => setState(() => verticalZoom = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
