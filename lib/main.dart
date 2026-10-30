import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CharMetrics.loadSaved();
  runApp(const MemoratusApp());
}

// ── Constante ────────────────────────────────────────────────────────────────

const kBg      = Color(0xFF0F1117);
const kBg2     = Color(0xFF161B27);
const kBorder  = Color(0xFF1E2330);
const kText    = Color(0xFFE2E8F0);
const kTextDim = Color(0xFF64748B);
const kAccent  = Color(0xFF3B82F6);
const kAccent2 = Color(0xFF1D4ED8);
const kRuler   = Color(0xFF00C8FF);
const kRed     = Color(0xFFEF4444);
const kHandleW = 32.0;
const kTextPad = 48.0;
const kFontSz  = 15.0;
const kPadTop  = 12.0;

// ── CharMetrics — masurare o singura data per device ─────────────────────────
//
// RobotoMono este font MONOSPACED — toate caracterele au aceeasi latime.
// Masuram o singura data 'M' cu textScaler real al device-ului.
// chars_per_row = availableWidth / charWidth
// Aceasta valoare e corecta pe orice telefon, indiferent de:
// - densitate ecran
// - font size din setarile Android
// - dimensiune ecran

// ── CharMetrics ───────────────────────────────────────────────────────────────
//
// Calibrare O SINGURA DATA per device, salvata in SharedPreferences.
//
// Metoda de detectie:
// - Construim string-ul "M M M M M M..." (cuvinte de 1 char separate prin spatiu)
// - Facem layout cu TextPainter cu maxWidth = textWidth real
// - Flutter face wrap natural pe spatii (nu desparte niciodata un 'M')
// - Folosim getBoxesForSelection() ca sa gasim primul caracter de pe randul 2
// - Offset-ul acelui caracter in string = pozitia exacta a wrap-ului
// - Din pozitie deducem exact cate "M"-uri au intrat pe primul rand
//
// De ce e robust:
// - Nu facem nicio impartire sau estimare matematica
// - Flutter insusi ne spune unde a facut wrap
// - textScaler real din context => respecta setarile de font ale device-ului
// - Salvat in SharedPreferences => nu se recalculeaza la fiecare lansare

class CharMetrics {
  static const _kPrefChars = 'calib_chars_per_row';
  static const _kPrefLineH = 'calib_line_h';

  static int    _charsPerRow = 0;
  static double _lineH       = 0;
  static bool   _ready       = false;

  static bool   get isReady     => _ready;
  static int    get charsPerRow => _charsPerRow > 0 ? _charsPerRow : 35;
  static double get lineH       => _lineH > 0 ? _lineH : 22.0;

  // Incearca sa incarce valorile salvate anterior
  static Future<bool> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final chars = prefs.getInt(_kPrefChars) ?? 0;
    final lh    = prefs.getDouble(_kPrefLineH) ?? 0.0;
    if (chars > 0 && lh > 0) {
      _charsPerRow = chars;
      _lineH       = lh;
      _ready       = true;
      debugPrint('=== CharMetrics: valori incarcate din prefs ===');
      debugPrint('charsPerRow: $_charsPerRow  lineH: ${_lineH.toStringAsFixed(1)}px');
      return true;
    }
    return false;
  }

  // Salveaza dupa calibrare
  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefChars, _charsPerRow);
    await prefs.setDouble(_kPrefLineH, _lineH);
  }

  // Apelat dupa ce metoda de detectie a gasit valorile
  static Future<void> setCalibration({
    required int charsPerRow,
    required double lineH,
  }) async {
    if (_ready) return;
    _charsPerRow = charsPerRow;
    _lineH       = lineH;
    _ready       = true;
    await _save();
  }

  // Reseteaza (util la debug sau daca utilizatorul schimba font size in Android)
  static Future<void> reset() async {
    _charsPerRow = 0;
    _lineH       = 0;
    _ready       = false;
    final prefs  = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefChars);
    await prefs.remove(_kPrefLineH);
  }
}

// ── CalibrationOverlay ────────────────────────────────────────────────────────
//
// Afisat INVIZIBIL (Opacity 0) cu textWidth exact disponibil.
// Dupa primul frame:
//   1. Construim "M M M M M..." cu 200 de 'M'
//   2. TextPainter.layout(maxWidth: textWidth) — Flutter face wrap real
//   3. getBoxesForSelection pe fiecare 'M' pana gasim unul cu top > 0
//      => acela e primul caracter de pe randul 2
//   4. Numaram cate 'M' au fost pe randul 1 => charsPerRow
//   5. lineH = top-ul primului caracter de pe randul 2

class CalibrationOverlay extends StatefulWidget {
  final double textWidth;
  final VoidCallback onCalibrated;
  const CalibrationOverlay({
    super.key,
    required this.textWidth,
    required this.onCalibrated,
  });
  @override
  State<CalibrationOverlay> createState() => _CalibrationOverlayState();
}

class _CalibrationOverlayState extends State<CalibrationOverlay> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _detect());
  }

  void _detect() {
    if (CharMetrics.isReady) { widget.onCalibrated(); return; }

    // Construim un string CONTINUU de 200 'M' fara spatii
    // TextPainter cu maxWidth va face wrap dupa exact cate caractere incap
    // getBoxesForSelection ne spune pozitia primului caracter de pe randul 2
    const total   = 200;
    final testStr = 'M' * total; // "MMMMMM..." 200 de M fara spatii

    final scaler = MediaQuery.textScalerOf(context);
    final style  = GoogleFonts.robotoMono(fontSize: kFontSz);

    final tp = TextPainter(
      text:          TextSpan(text: testStr, style: style),
      textDirection: TextDirection.ltr,
      textScaler:    scaler,
    )..layout(maxWidth: widget.textWidth);

    // Folosim coordonata 'bottom' care e mai stabila decat 'top'
    // pe device-uri cu density diferita
    final boxes0  = tp.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 1));
    final bottom0 = boxes0.isNotEmpty ? boxes0.first.bottom : 15.0;
    final charH   = boxes0.isNotEmpty
        ? boxes0.first.bottom - boxes0.first.top : 15.0;

    // Un caracter e pe randul 2 daca bottom-ul sau e semnificativ
    // mai mare decat bottom-ul primului caracter (> 1.5x charH)
    final threshold = bottom0 + charH * 0.5;

    int    charsOnRow1 = 0;
    double lineH       = 0;

    // Metoda corecta: getLineBoundary(TextPosition(0)) returneaza
    // exact pozitia de start si sfarsit a primului rand vizual
    // Aceasta e metoda interna a Flutter pentru detectia randurilor
    final firstLineBoundary = tp.getLineBoundary(const TextPosition(offset: 0));
    final firstLineEnd = firstLineBoundary.end;

    // charsPerRow = numarul de caractere pe primul rand
    // firstLineEnd include si caracterul de newline/wrap daca exista
    // dar noi nu avem newline deci e exact cate caractere incap
    charsOnRow1 = firstLineEnd.clamp(1, total);

    // lineH: masurata din pozitia celui de-al doilea rand
    if (firstLineEnd < total) {
      final boxes1 = tp.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: 1));
      final boxes2 = tp.getBoxesForSelection(
          TextSelection(baseOffset: firstLineEnd, extentOffset: firstLineEnd + 1));
      if (boxes1.isNotEmpty && boxes2.isNotEmpty) {
        lineH = (boxes2.first.top - boxes1.first.top).abs();
      }
    }
    if (lineH <= 0) lineH = charH;

    if (charsOnRow1 <= 0 || lineH <= 0) {
      charsOnRow1 = total;
      lineH       = tp.height;
    }

    final finalLineH = lineH * 1.4;

    debugPrint('=== CALIBRARE MEMORATUS ===');
    debugPrint('textWidth: ${widget.textWidth.toStringAsFixed(1)}px');
    debugPrint('charH: ${charH.toStringAsFixed(2)}px');
    debugPrint('getLineBoundary.end: $firstLineEnd');
    debugPrint('charsPerRow DETECTAT: $charsOnRow1');
    debugPrint('lineH real: ${lineH.toStringAsFixed(2)}px  x1.4 = ${finalLineH.toStringAsFixed(2)}px');
    debugPrint('===========================');

    CharMetrics.setCalibration(
      charsPerRow: charsOnRow1,
      lineH:       finalLineH,
    ).then((_) => widget.onCalibrated());
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ── Rich Text Parser ──────────────────────────────────────────────────────────

class RToken {
  final String text;
  final bool bold;
  final bool italic;
  final bool red;
  const RToken(this.text,
      {this.bold = false, this.italic = false, this.red = false});
}

List<RToken> parseRich(String raw) {
  final result = <RToken>[];
  bool bold = false, italic = false, red = false;
  final tagRe = RegExp(r'\[(/?)([bir])\]');
  int pos = 0;
  for (final m in tagRe.allMatches(raw)) {
    if (m.start > pos) {
      final chunk = raw.substring(pos, m.start);
      if (chunk.isNotEmpty)
        result.add(RToken(chunk, bold: bold, italic: italic, red: red));
    }
    final closing = m.group(1) == '/';
    final tag     = m.group(2);
    if (tag == 'b') bold   = !closing;
    if (tag == 'i') italic = !closing;
    if (tag == 'r') red    = !closing;
    pos = m.end;
  }
  if (pos < raw.length) {
    final chunk = raw.substring(pos);
    if (chunk.isNotEmpty)
      result.add(RToken(chunk, bold: bold, italic: italic, red: red));
  }
  return result;
}

String stripTags(String raw) =>
    raw.replaceAll(RegExp(r'\[/?[bir]\]'), '');

// ── Word wrap bazat pe caractere ──────────────────────────────────────────────
//
// Functioneaza cu orice font monospaced.
// Nu depinde de TextPainter pentru fiecare cuvant — doar de chars_per_row.

class _Word {
  final String text;
  final bool bold;
  final bool italic;
  final bool red;
  const _Word(this.text,
      {required this.bold, required this.italic, required this.red});
}

List<List<_Word>> wrapLineByChars(List<RToken> tokens, int maxChars) {
  // Extragem cuvintele
  final words = <_Word>[];
  for (final tok in tokens) {
    for (final part in tok.text.split(' ')) {
      if (part.isNotEmpty)
        words.add(_Word(part,
            bold: tok.bold, italic: tok.italic, red: tok.red));
    }
  }
  if (words.isEmpty) return [[]];

  final rows = <List<_Word>>[];
  var   row  = <_Word>[];
  var   rowChars = 0;

  for (final w in words) {
    final wc = w.text.length;
    if (row.isNotEmpty && rowChars + 1 + wc > maxChars) {
      rows.add(row);
      row       = [w];
      rowChars  = wc;
    } else {
      if (row.isNotEmpty) rowChars += 1; // spatiu
      row.add(w);
      rowChars += wc;
    }
  }
  if (row.isNotEmpty) rows.add(row);
  return rows;
}

// ── Font style ────────────────────────────────────────────────────────────────

TextStyle monoStyle({Color color = kText, bool bold = false,
    bool italic = false}) =>
    GoogleFonts.robotoMono(
      color: color,
      fontSize: kFontSz,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );

// ── Span builders ─────────────────────────────────────────────────────────────

bool _isSuffix(String ch) => '.,!?;:'.contains(ch);

String _firstOf(String word) {
  if (word.isEmpty) return word;
  int end = word.length - 1;
  while (end >= 1 && _isSuffix(word[end])) end--;
  return word[0] + word.substring(end + 1);
}

String _middleOf(String word) {
  if (word.length <= 1) return '';
  int end = word.length - 1;
  while (end >= 1 && _isSuffix(word[end])) end--;
  if (end < 1) return '';
  return word.substring(1, end + 1);
}

TextSpan rowSpan(List<_Word> words,
    {required bool revealed, required bool condensed}) {
  final spans = <InlineSpan>[];
  for (int wi = 0; wi < words.length; wi++) {
    final w     = words[wi];
    final space = wi < words.length - 1 ? ' ' : '';
    final base  = w.red ? kRed : kText;
    final dim   = w.red ? kRed.withOpacity(0.7) : const Color(0xFF94A3B8);

    if (revealed || condensed) {
      final disp = condensed ? _firstOf(w.text) : w.text;
      spans.add(TextSpan(text: '$disp$space',
          style: monoStyle(color: base, bold: w.bold, italic: w.italic)));
    } else {
      final fc     = w.text[0];
      final middle = _middleOf(w.text);
      final punct  = _firstOf(w.text).substring(1);
      spans.add(TextSpan(text: fc,
          style: monoStyle(color: dim, bold: w.bold, italic: w.italic)));
      if (middle.isNotEmpty)
        spans.add(TextSpan(text: middle,
            style: monoStyle(color: Colors.transparent,
                bold: w.bold, italic: w.italic)));
      if (punct.isNotEmpty)
        spans.add(TextSpan(text: punct,
            style: monoStyle(color: dim, bold: w.bold, italic: w.italic)));
      spans.add(TextSpan(text: space,
          style: monoStyle(color: Colors.transparent)));
    }
  }
  return TextSpan(children: spans);
}

// ── Model ────────────────────────────────────────────────────────────────────

class MNode {
  String id;
  String title;
  String? content;
  List<MNode> children;
  bool expanded;

  MNode({required this.id, required this.title, this.content,
      List<MNode>? children, this.expanded = false})
      : children = children ?? [];

  bool get isFolder => content == null;
  bool get isText   => content != null;

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'content': content,
    'children': children.map((c) => c.toJson()).toList(),
    'expanded': expanded,
  };

  factory MNode.fromJson(Map<String, dynamic> j) => MNode(
    id: j['id'] as String, title: j['title'] as String,
    content: j['content'] as String?,
    children: (j['children'] as List<dynamic>? ?? [])
        .map((c) => MNode.fromJson(c as Map<String, dynamic>)).toList(),
    expanded: j['expanded'] as bool? ?? false,
  );
}

// ── Storage ───────────────────────────────────────────────────────────────────

class Store {
  static const _kNodes  = 'nodes_v1';
  static const _kLastId = 'last_id';

  static Future<List<MNode>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kNodes);
    if (raw == null) return _demo();
    try {
      return (jsonDecode(raw) as List)
          .map((e) => MNode.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) { return _demo(); }
  }

  static Future<void> save(List<MNode> nodes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNodes,
        jsonEncode(nodes.map((n) => n.toJson()).toList()));
  }

  static Future<String> nextId() async {
    final prefs = await SharedPreferences.getInstance();
    final n = (prefs.getInt(_kLastId) ?? 0) + 1;
    await prefs.setInt(_kLastId, n);
    return 'n$n';
  }

  static List<MNode> _demo() => [
    MNode(id: 'd1', title: 'Morning Prayers', children: [
      MNode(id: 'd2', title: '01 Opening Prayers',
        content:
          '[b]In the name of the Father[/b] and of the Son and of the Holy Spirit. Amen.\n'
          '[r]Glory to You, our God,[/r] Glory to You!\n'
          '[i]Heavenly King, Comforter,[/i]\n'
          'Spirit of truth, present everywhere and filling all things,\n'
          'Treasury of blessings and Giver of life,\n'
          'come and dwell within us, cleanse us of all impurity,\n'
          'and save our souls, O Good One.'),
      MNode(id: 'd3', title: '02 Trisagion',
        content:
          '[b]Holy God,[/b] Holy Mighty,\n'
          'Holy Immortal, [r]have mercy on us.[/r]\n'
          '[b]Holy God,[/b] Holy Mighty,\n'
          'Holy Immortal, [r]have mercy on us.[/r]'),
    ]),
    MNode(id: 'd4', title: 'Example text',
      content:
        'This is an [b]example[/b] text at the root level,\n'
        'without any [i]parent folder.[/i]\n'
        'It can be [r]memorized[/r] just like any other text.'),
  ];
}

// ── App ───────────────────────────────────────────────────────────────────────

class MemoratusApp extends StatelessWidget {
  const MemoratusApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Memoratus',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kBg,
      colorScheme: const ColorScheme.dark(
          primary: kAccent, secondary: kAccent2, surface: kBg2),
      appBarTheme: const AppBarTheme(
        backgroundColor: kBg, elevation: 0,
        titleTextStyle: TextStyle(
            color: kText, fontSize: 18, fontWeight: FontWeight.w600),
        iconTheme: IconThemeData(color: kText),
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: kBg),
    ),
    home: const RootScreen(),
  );
}

// ── Root Screen ───────────────────────────────────────────────────────────────

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  List<MNode> _nodes   = [];
  MNode?      _selected;
  bool        _loading = true;
  final _scaffoldKey   = GlobalKey<ScaffoldState>();

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final nodes = await Store.load();
    setState(() { _nodes = nodes; _loading = false; });
  }

  Future<void> _save() => Store.save(_nodes);

  // Returneaza toate fisierele text din acelasi folder cu nodul dat
  List<MNode> _siblingsOf(MNode target) {
    // Cauta recursiv in arbore
    List<MNode>? _findSiblings(List<MNode> list) {
      // Verifica la nivel curent
      final texts = list.where((n) => n.isText).toList();
      if (texts.any((n) => n.id == target.id)) return texts;
      // Cauta in foldere
      for (final n in list) {
        if (n.isFolder) {
          final found = _findSiblings(n.children);
          if (found != null) return found;
        }
      }
      return null;
    }
    return _findSiblings(_nodes) ?? [];
  }

  // ── Export ──────────────────────────────────────────────────────────────────

  Future<void> _exportData() async {
    try {
      final json     = jsonEncode(_nodes.map((n) => n.toJson()).toList());
      final bytes    = utf8.encode(json);
      final now      = DateTime.now();
      final filename = 'memoratus_backup_'
          '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}'
          '_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}'
          '.memoratus';

      // Scriem in directorul temporar si dam share
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);

      // Share sheet nativ Android
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Memoratus Backup',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export error: $e'),
                backgroundColor: Colors.red[800]));
      }
    }
  }

  // ── Import ──────────────────────────────────────────────────────────────────

  Future<void> _importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.single.path == null) return;

      final path    = result.files.single.path!;
      final content = await File(path).readAsString();
      final list    = jsonDecode(content) as List<dynamic>;
      final imported = list
          .map((e) => MNode.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      // Intrebam utilizatorul: merge sau inlocuieste
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: kBg2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Import backup',
              style: TextStyle(color: kText)),
          content: Text(
            'Found ${imported.length} item(s).\n\nMerge with existing data or replace all?',
            style: const TextStyle(color: kTextDim, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel',
                  style: TextStyle(color: kTextDim)),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'merge'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: kAccent,
                  side: const BorderSide(color: kAccent)),
              child: const Text('Merge'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'replace'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent),
              child: const Text('Replace'),
            ),
          ],
        ),
      );

      if (choice == null || choice == 'cancel') return;

      // Generăm ID-uri noi pentru a evita conflicte la merge
      Future<void> reassignIds(MNode node) async {
        node.id = await Store.nextId();
        for (final child in node.children) {
          await reassignIds(child);
        }
      }

      if (choice == 'replace') {
        setState(() { _nodes
          ..clear()
          ..addAll(imported); });
      } else {
        // Merge: adaugam doar itemele cu titluri noi
        for (final imp in imported) {
          await reassignIds(imp);
        }
        setState(() => _nodes.addAll(imported));
      }

      await _save();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import successful — ${imported.length} item(s) ${choice == 'replace' ? 'replaced' : 'merged'}'),
              backgroundColor: Colors.green[800],
            ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import error: $e'),
                backgroundColor: Colors.red[800]));
      }
    }
  }

  void _selectNode(MNode node) {
    if (node.isText) {
      setState(() => _selected = node);
      Navigator.pop(context);
    } else {
      setState(() => node.expanded = !node.expanded);
      _save();
    }
  }

  Future<void> _addFolder({MNode? parent}) async {
    final title = await _askTitle('New folder');
    if (title == null || title.isEmpty) return;
    final node = MNode(id: await Store.nextId(), title: title);
    setState(() {
      if (parent == null) _nodes.add(node);
      else { parent.children.add(node); parent.expanded = true; }
    });
    await _save();
  }

  Future<void> _deleteNode(MNode node, MNode? parent) async {
    if (!await _confirm('Delete "${node.title}"?')) return;
    setState(() {
      if (parent == null) _nodes.removeWhere((n) => n.id == node.id);
      else parent.children.removeWhere((n) => n.id == node.id);
      if (_selected?.id == node.id) _selected = null;
    });
    await _save();
  }

  Future<void> _renameNode(MNode node) async {
    final title = await _askTitle('Rename', initial: node.title);
    if (title == null || title.isEmpty) return;
    setState(() => node.title = title);
    await _save();
  }

  Future<String?> _askTitle(String label, {String? initial}) {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kBg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(label, style: const TextStyle(color: kText)),
        content: TextField(controller: ctrl, autofocus: true,
            style: const TextStyle(color: kText),
            decoration: _inputDecor('Enter name...'),
            onSubmitted: (v) => Navigator.pop(context, v.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: kTextDim))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: kAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool> _confirm(String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kBg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(msg, style: const TextStyle(color: kText, fontSize: 15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: kTextDim))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
              child: const Text('Delete')),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer()),
        title: Text(_selected?.title ?? 'Memoratus',
            overflow: TextOverflow.ellipsis),
        actions: _selected != null ? [
          IconButton(icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final ok = await Navigator.push<bool>(context,
                  MaterialPageRoute(
                      builder: (_) => EditScreen(node: _selected!)));
              if (ok == true) { setState(() {}); await _save(); }
            }),
        ] : [],
      ),
      drawer: _buildDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : _selected != null
              ? ViewerScreen(
                  key: ValueKey(_selected!.id),
                  node: _selected!,
                  siblings: _siblingsOf(_selected!),
                  onNavigate: (node) => setState(() => _selected = node),
                )
              : _buildWelcome(),
    );
  }

  Widget _buildWelcome() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 80, height: 80,
              decoration: BoxDecoration(color: kBg2,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: kBorder)),
              child: const Icon(Icons.menu_book_outlined, color: kAccent, size: 38)),
          const SizedBox(height: 20),
          const Text('Memoratus', style: TextStyle(color: kText, fontSize: 28,
              fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          const Text('Memorize any text by heart\nwith the smart reveal ruler',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextDim, fontSize: 14, height: 1.6)),
          const SizedBox(height: 36),
          _featureCard(Icons.visibility_outlined,
              'Original', 'Read the complete text'),
          const SizedBox(height: 10),
          _featureCard(Icons.view_stream_outlined,
              'Mask', 'Drag the ruler to reveal line by line'),
          const SizedBox(height: 10),
          _featureCard(Icons.format_list_bulleted,
              'Condensed', 'First letter of each word only'),
          const SizedBox(height: 36),
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E40AF)),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.menu, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text('Get started', style: TextStyle(color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.w600)),
                  ]),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _featureCard(IconData icon, String title, String subtitle) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: kBg2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder)),
        child: Row(children: [
          Container(width: 38, height: 38,
              decoration: BoxDecoration(color: const Color(0xFF1E3A5F),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: kAccent, size: 20)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: kText, fontSize: 14,
                    fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(
                    color: kTextDim, fontSize: 12)),
              ])),
          const Icon(Icons.arrow_forward_ios, color: kBorder, size: 14),
        ]),
      );

  Widget _buildDrawer() => Drawer(
    child: SafeArea(child: Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kBorder))),
        child: Row(children: [
          const Icon(Icons.menu_book_outlined, color: kAccent, size: 24),
          const SizedBox(width: 10),
          const Text('Memoratus', style: TextStyle(color: kText, fontSize: 18,
              fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.create_new_folder_outlined,
              color: kTextDim, size: 20), onPressed: () => _addFolder()),
          IconButton(icon: const Icon(Icons.add, color: kAccent, size: 22),
              onPressed: () => _showAddTextSheet(parent: null)),
        ]),
      ),
      Expanded(child: _nodes.isEmpty
          ? const Center(child: Text('No texts added',
              style: TextStyle(color: kTextDim)))
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _nodes.length,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                child: child,
              ),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final node = _nodes.removeAt(oldIndex);
                  _nodes.insert(newIndex, node);
                });
                _save();
              },
              itemBuilder: (_, i) => _buildNodeTile(
                  _nodes[i], null, 0, key: ValueKey(_nodes[i].id)))),
      // ── Export / Import ────────────────────────────────────────────────────
      Container(
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: kBorder))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.upload_outlined, color: kAccent, size: 20),
            title: const Text('Export backup',
                style: TextStyle(color: kText, fontSize: 13)),
            onTap: () { Navigator.pop(context); _exportData(); },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined, color: kAccent, size: 20),
            title: const Text('Import backup',
                style: TextStyle(color: kText, fontSize: 13)),
            onTap: () { Navigator.pop(context); _importData(); },
          ),
        ]),
      ),
      // ── Buton debug calibrare ──────────────────────────────────────────────
      Container(
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: kBorder))),
        child: ListTile(
          leading: const Icon(Icons.tune, color: kTextDim, size: 20),
          title: const Text('Calibration debug',
              style: TextStyle(color: kTextDim, fontSize: 13)),
          trailing: Text('${CharMetrics.charsPerRow} chars/row',
              style: const TextStyle(color: kAccent, fontSize: 12)),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const CalibrationDebugScreen()));
          },
        ),
      ),
    ])),
  );

  Widget _buildNodeTile(MNode node, MNode? parent, int depth, {Key? key}) {
    final isSelected = _selected?.id == node.id;
    final indent     = depth * 16.0;

    if (node.isText) {
      return GestureDetector(
        key: key ?? ValueKey(node.id),
        onLongPress: () => _showNodeMenu(node, parent),
        child: ListTile(
          contentPadding: EdgeInsets.only(left: 16 + indent, right: 4),
          leading: Icon(Icons.article_outlined,
              color: isSelected ? kAccent : kTextDim, size: 20),
          title: Text(node.title, style: TextStyle(
              color: isSelected ? kAccent : kText, fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            // Handle drag vizibil
            ReorderableDragStartListener(
              index: parent == null
                  ? _nodes.indexOf(node)
                  : parent.children.indexOf(node),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle, color: kBorder, size: 20),
              ),
            ),
          ]),
          selected: isSelected,
          selectedTileColor: const Color(0x1A3B82F6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: () => _selectNode(node),
        ),
      );
    }

    return Column(key: key ?? ValueKey(node.id),
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onLongPress: () => _showNodeMenu(node, parent),
        child: ListTile(
          contentPadding: EdgeInsets.only(left: 16 + indent, right: 4),
          leading: Icon(node.expanded
              ? Icons.folder_open_outlined : Icons.folder_outlined,
              color: kAccent, size: 20),
          title: Text(node.title, style: const TextStyle(
              color: kText, fontSize: 14, fontWeight: FontWeight.w600)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (depth < 2) ...[
              IconButton(icon: const Icon(Icons.create_new_folder_outlined,
                  color: kTextDim, size: 18),
                  onPressed: () => _addFolder(parent: node),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              const SizedBox(width: 4),
            ],
            IconButton(icon: const Icon(Icons.add, color: kAccent, size: 20),
                onPressed: () => _showAddTextSheet(parent: node),
                padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            const SizedBox(width: 4),
            Icon(node.expanded ? Icons.expand_less : Icons.expand_more,
                color: kTextDim, size: 18),
            // Handle drag vizibil
            ReorderableDragStartListener(
              index: parent == null
                  ? _nodes.indexOf(node)
                  : parent.children.indexOf(node),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle, color: kBorder, size: 20),
              ),
            ),
          ]),
          onTap: () => _selectNode(node),
        ),
      ),
      if (node.expanded && node.children.isNotEmpty)
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent, child: child),
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final child = node.children.removeAt(oldIndex);
              node.children.insert(newIndex, child);
            });
            _save();
          },
          itemCount: node.children.length,
          itemBuilder: (_, i) => _buildNodeTile(
              node.children[i], node, depth + 1,
              key: ValueKey(node.children[i].id)),
        ),
    ]);
  }

  void _showNodeMenu(MNode node, MNode? parent) {
    showModalBottomSheet(context: context, backgroundColor: kBg2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
              leading: const Icon(Icons.drive_file_rename_outline, color: kAccent),
              title: const Text('Rename', style: TextStyle(color: kText)),
              onTap: () { Navigator.pop(context); _renameNode(node); }),
          ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () { Navigator.pop(context); _deleteNode(node, parent); }),
        ],
      )),
    );
  }

  void _showAddTextSheet({MNode? parent}) {
    Navigator.pop(context);
    showModalBottomSheet(context: context, backgroundColor: kBg2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddTextSheet(onAdd: (title, content) async {
        final node = MNode(id: await Store.nextId(), title: title, content: content);
        setState(() {
          if (parent == null) _nodes.add(node);
          else { parent.children.add(node); parent.expanded = true; }
          _selected = node;
        });
        await _save();
      }),
    );
  }
}

// ── Add Text Sheet ────────────────────────────────────────────────────────────

class _AddTextSheet extends StatefulWidget {
  final Future<void> Function(String, String) onAdd;
  const _AddTextSheet({required this.onAdd});
  @override
  State<_AddTextSheet> createState() => _AddTextSheetState();
}

class _AddTextSheetState extends State<_AddTextSheet> {
  final _titleCtrl   = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _titleCtrl.dispose(); _contentCtrl.dispose(); super.dispose(); }

  Future<void> _pickFile() async {
    setState(() => _loading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['txt']);
      if (result?.files.single.path != null) {
        final content = await File(result!.files.single.path!).readAsString();
        final name = result.files.single.name
            .replaceAll('.txt', '').replaceAll('_', ' ');
        setState(() {
          _contentCtrl.text = content;
          if (_titleCtrl.text.isEmpty) _titleCtrl.text = name;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    setState(() => _loading = false);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) setState(() => _contentCtrl.text = data!.text!);
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a title')));
      return;
    }
    Navigator.pop(context);
    await widget.onAdd(title, _contentCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: kBorder,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Add new text', style: TextStyle(
                color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(controller: _titleCtrl,
                style: const TextStyle(color: kText),
                decoration: _inputDecor('Title')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                  onPressed: _loading ? null : _paste,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Paste'),
                  style: OutlinedButton.styleFrom(foregroundColor: kAccent,
                      side: const BorderSide(color: kBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                  onPressed: _loading ? null : _pickFile,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kAccent))
                      : const Icon(Icons.upload_file, size: 18),
                  label: const Text('Import .txt'),
                  style: OutlinedButton.styleFrom(foregroundColor: kAccent,
                      side: const BorderSide(color: kBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _contentCtrl, maxLines: 6,
                style: GoogleFonts.robotoMono(color: kText, fontSize: 13),
                decoration: _inputDecor('Type or paste text here...')),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
                child: ElevatedButton(onPressed: _submit,
                    style: ElevatedButton.styleFrom(backgroundColor: kAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    child: const Text('Save', style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)))),
          ]),
    );
  }
}

// ── Viewer Screen ─────────────────────────────────────────────────────────────

class ViewerScreen extends StatefulWidget {
  final MNode node;
  final List<MNode> siblings;
  final void Function(MNode) onNavigate;
  const ViewerScreen({
    super.key,
    required this.node,
    required this.siblings,
    required this.onNavigate,
  });
  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  String _mode = 'original';
  final _scrollCtrl = ScrollController();

  List<List<_Word>> _rows        = [];
  int               _lastMaxChars = -1;
  String            _lastContent  = '';

  double _rulerPx     = kPadTop;
  int    _revealed    = 0;
  bool   _dragging    = false;
  bool   _dragOnRuler = false;

  @override
  void dispose() { _scrollCtrl.dispose(); super.dispose(); }

  void _computeLayout(double textWidth) {
    final content  = widget.node.content ?? '';
    final maxChars = CharMetrics.charsPerRow;

    if (maxChars == _lastMaxChars &&
        content == _lastContent &&
        _rows.isNotEmpty) return;

    _lastMaxChars = maxChars;
    _lastContent  = content;

    final newRows = <List<_Word>>[];
    for (final line in content.split('\n')) {
      if (stripTags(line).trim().isEmpty) { newRows.add([]); continue; }
      newRows.addAll(wrapLineByChars(parseRich(line), maxChars));
    }
    _rows = newRows;
  }

  void _setMode(String mode) {
    final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    setState(() => _mode = mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients)
        _scrollCtrl.jumpTo(
            offset.clamp(0.0, _scrollCtrl.position.maxScrollExtent));
    });
  }

  int    get _rowCount  => _rows.length;
  double get _scrollOff => _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
  double get _lineH     => CharMetrics.lineH;

  double _rulerScreenY() => kPadTop + _revealed * _lineH - _scrollOff;

  int _revealedAt(double screenY) =>
      ((screenY + _scrollOff - kPadTop) / _lineH)
          .floor().clamp(0, _rowCount - 1);

  bool _isOnHandle(double x, double w) =>
      x <= kHandleW || x >= w - kHandleW;

  void _onDragStart(DragStartDetails d, double w, double safeH) {
    final sy = _rulerScreenY();
    final onH = _isOnHandle(d.localPosition.dx, w);
    final onR = d.localPosition.dy >= sy && d.localPosition.dy <= sy + _lineH;
    _dragOnRuler = onH || onR;
    if (_dragOnRuler) setState(() { _rulerPx = sy; _dragging = true; });
  }

  void _onDragUpdate(DragUpdateDetails d, double w, double safeH) {
    if (_dragOnRuler) {
      final newPx = (_rulerPx + d.delta.dy).clamp(kPadTop, safeH - _lineH);
      setState(() { _rulerPx = newPx; _revealed = _revealedAt(newPx); });
    } else {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo((_scrollCtrl.offset - d.delta.dy)
            .clamp(0.0, _scrollCtrl.position.maxScrollExtent));
        setState(() => _revealed = _revealedAt(_rulerPx));
      }
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragOnRuler)
      setState(() { _rulerPx = _rulerScreenY(); _dragging = false; });
    _dragOnRuler = false;
  }

  void _onTapDown(TapDownDetails d, double w) {
    final sy = _rulerScreenY();
    if (_isOnHandle(d.localPosition.dx, w) ||
        (d.localPosition.dy >= sy && d.localPosition.dy <= sy + _lineH)) {
      final line = _revealedAt(d.localPosition.dy);
      setState(() { _revealed = line; _rulerPx = _rulerScreenY(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.node.content ?? '';
    // Calculam indexul curent si daca exista prev/next
    final siblings  = widget.siblings;
    final currIdx   = siblings.indexWhere((n) => n.id == widget.node.id);
    final hasPrev   = currIdx > 0;
    final hasNext   = currIdx >= 0 && currIdx < siblings.length - 1;

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: const BoxDecoration(color: kBg,
            border: Border(bottom: BorderSide(color: kBorder))),
        child: Row(children: [
          // Sageata stanga
          _NavArrow(
            icon: Icons.chevron_left,
            enabled: hasPrev,
            onTap: () => widget.onNavigate(siblings[currIdx - 1]),
          ),
          const SizedBox(width: 4),
          // Butoanele de mod
          Expanded(child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ModeBtn(label: 'Original', active: _mode == 'original',
                  onTap: () => _setMode('original')),
              const SizedBox(width: 6),
              _ModeBtn(label: 'Mask', active: _mode == 'mask',
                  onTap: () => _setMode('mask')),
              const SizedBox(width: 6),
              _ModeBtn(label: 'Condensed', active: _mode == 'condensed',
                  onTap: () => _setMode('condensed')),
            ],
          )),
          const SizedBox(width: 4),
          // Sageata dreapta
          _NavArrow(
            icon: Icons.chevron_right,
            enabled: hasNext,
            onTap: () => widget.onNavigate(siblings[currIdx + 1]),
          ),
        ]),
      ),
      Expanded(child: content.isEmpty
          ? const Center(child: Text('Empty text.\nTap pencil to edit.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextDim)))
          : LayoutBuilder(builder: (ctx, cons) {
              final textW  = cons.maxWidth - kTextPad * 2;

              // Daca nu e calibrat, facem calibrarea automat in background
              // fara spinner — utilizatorul nu vede nimic
              if (!CharMetrics.isReady) {
                return CalibrationOverlay(
                  textWidth: textW,
                  onCalibrated: () => setState(() {}),
                );
              }

              _computeLayout(textW);

              final isMask      = _mode == 'mask';
              final isCondensed = _mode == 'condensed';
              final w           = cons.maxWidth;
              final bottomPad   = MediaQuery.of(ctx).padding.bottom;
              final safeH       = cons.maxHeight - bottomPad;
              final lh          = CharMetrics.lineH;

              final col = Padding(
                padding: const EdgeInsets.only(top: kPadTop, bottom: kPadTop),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _rows.asMap().entries.map((e) {
                    final idx      = e.key;
                    final row      = e.value;
                    final revealed = isMask && idx == _revealed;

                    if (row.isEmpty) {
                      return Container(height: lh, width: double.infinity,
                          decoration: revealed ? BoxDecoration(
                              color: const Color(0x1800C8FF),
                              borderRadius: BorderRadius.circular(4)) : null);
                    }

                    final span = rowSpan(row,
                        revealed: revealed || !isMask,
                        condensed: isCondensed && !isMask);

                    return Container(
                      height: lh,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: kTextPad),
                      alignment: Alignment.centerLeft,
                      decoration: revealed
                          ? BoxDecoration(color: const Color(0x1800C8FF),
                              borderRadius: BorderRadius.circular(4))
                          : null,
                      child: RichText(
                        overflow: TextOverflow.clip,
                        maxLines: 1,
                        textScaler: MediaQuery.textScalerOf(ctx),
                        text: TextSpan(children: [span]),
                      ),
                    );
                  }).toList(),
                ),
              );

              if (!isMask) {
                return SingleChildScrollView(
                    controller: _scrollCtrl,
                    physics: const ClampingScrollPhysics(),
                    child: col);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart:  (d) => _onDragStart(d, w, safeH),
                onVerticalDragUpdate: (d) => _onDragUpdate(d, w, safeH),
                onVerticalDragEnd:    _onDragEnd,
                onTapDown:            (d) => _onTapDown(d, w),
                child: Stack(children: [
                  Positioned.fill(child: SingleChildScrollView(
                      controller: _scrollCtrl,
                      physics: const NeverScrollableScrollPhysics(),
                      child: col)),
                  AnimatedPositioned(
                    duration: _dragging ? Duration.zero
                        : const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    top: _rulerPx, left: 0, right: 0, height: lh,
                    child: IgnorePointer(
                        child: CustomPaint(painter: _RulerPainter())),
                  ),
                  if (bottomPad > 0)
                    Positioned(bottom: 0, left: 0, right: 0,
                        height: bottomPad + lh,
                        child: IgnorePointer(child: Container(
                          decoration: BoxDecoration(gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [kBg.withOpacity(0.0), kBg.withOpacity(0.95)],
                          )),
                        ))),
                ]),
              );
            })),
    ]);
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _NavArrow({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color: enabled ? kBg2 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: enabled ? kBorder : Colors.transparent),
      ),
      child: Icon(icon,
          color: enabled ? kText : kBorder.withOpacity(0.4), size: 22),
    ),
  );
}

// ── Mode Button ───────────────────────────────────────────────────────────────

class _ModeBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeBtn({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: active ? const LinearGradient(
            colors: [Color(0xFF2563EB), kAccent2],
            begin: Alignment.topCenter, end: Alignment.bottomCenter) : null,
        color: active ? null : kBg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? const Color(0xFF1E40AF) : kBorder),
      ),
      child: Text(label, style: TextStyle(
        color: active ? Colors.white : kTextDim, fontSize: 13,
        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
      )),
    ),
  );
}

// ── Ruler Painter ─────────────────────────────────────────────────────────────

class _RulerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final lp = Paint()..color = kRuler.withOpacity(0.65)..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, 0), Offset(w, 0), lp);
    canvas.drawLine(Offset(0, h), Offset(w, h), lp);
    _handle(canvas, 0, h, left: true);
    _handle(canvas, w, h, left: false);
  }

  void _handle(Canvas canvas, double x, double h, {required bool left}) {
    final lx = left ? x : x - kHandleW;
    final rr = RRect.fromRectAndCorners(Rect.fromLTWH(lx, 0, kHandleW, h),
        topLeft: Radius.circular(left ? 0 : 6),
        bottomLeft: Radius.circular(left ? 0 : 6),
        topRight: Radius.circular(left ? 6 : 0),
        bottomRight: Radius.circular(left ? 6 : 0));
    canvas.drawRRect(rr, Paint()..color = kRuler.withOpacity(0.18));
    canvas.drawRRect(rr, Paint()
      ..color = kRuler.withOpacity(0.5)
      ..strokeWidth = 1.0..style = PaintingStyle.stroke);
    final gp = Paint()..color = kRuler.withOpacity(0.75)..strokeWidth = 1.2;
    final cx = lx + kHandleW / 2;
    for (final dy in [-5.0, 0.0, 5.0])
      canvas.drawLine(Offset(cx-6, h/2+dy), Offset(cx+6, h/2+dy), gp);
  }

  @override
  bool shouldRepaint(_RulerPainter old) => false;
}

// ── Calibration Debug Screen ──────────────────────────────────────────────────
//
// Arata vizual textul de calibrare exact cum il vede Flutter
// si marcheaza cu culori unde s-a facut wrap-ul detectat.

class CalibrationDebugScreen extends StatefulWidget {
  const CalibrationDebugScreen({super.key});
  @override
  State<CalibrationDebugScreen> createState() => _CalibrationDebugScreenState();
}

class _CalibrationDebugScreenState extends State<CalibrationDebugScreen> {
  bool _recalibrating = false;

  Future<void> _resetAndRecalibrate() async {
    setState(() => _recalibrating = true);
    await CharMetrics.reset();
    setState(() => _recalibrating = false);
  }

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.robotoMono(fontSize: kFontSz);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Calibration Debug'),
        actions: [
          TextButton.icon(
            onPressed: _recalibrating ? null : _resetAndRecalibrate,
            icon: const Icon(Icons.refresh, color: kAccent),
            label: const Text('Reset', style: TextStyle(color: kAccent)),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, cons) {
        final textWidth = cons.maxWidth - kTextPad * 2;
        final cpr       = CharMetrics.charsPerRow;
        final lh        = CharMetrics.lineH;

        if (_recalibrating || !CharMetrics.isReady) {
          return CalibrationOverlay(
            textWidth: textWidth,
            onCalibrated: () => setState(() {}),
          );
        }

        // Construim string-ul de test vizibil
        // Randul 1: exact cpr litere 'M' continue
        // Randul 2: incepe cu 'X' ca sa fie vizibil diferit
        final row1      = 'M' * cpr;
        final row2start = 'X' * 20;
        final testVisible = '$row1$row2start';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Info box ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: kBg2, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBorder)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('charsPerRow', '$cpr caractere'),
                    _infoRow('lineH', '${lh.toStringAsFixed(1)}px'),
                    _infoRow('textWidth', '${textWidth.toStringAsFixed(1)}px'),
                    _infoRow('fontSize', '${kFontSz}px'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Instructiuni ─────────────────────────────────────────────
              Text(
                'Visual check:\n'
                '• Row 1 must contain exactly $cpr "M" letters\n'
                '• Row 2 must start with "X"\n'
                '• If "X" is on row 1 → charsPerRow is too large\n'
                '• If last "M" is on row 2 → charsPerRow is too small',
                style: const TextStyle(color: kTextDim, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 16),

              // ── Text de test vizibil cu linia de separator ───────────────
              Container(
                decoration: BoxDecoration(
                    color: kBg2, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder)),
                child: Stack(children: [
                  // Highlight randul 1 (inaltimea lh)
                  Positioned(
                    top: 0, left: 0, right: 0,
                    height: lh,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0x223B82F6),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8)),
                      ),
                    ),
                  ),
                  // Textul propriu-zis
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: kTextPad, vertical: 8),
                    child: RichText(
                      softWrap: true,
                      textScaler: MediaQuery.textScalerOf(ctx),
                      text: TextSpan(children: [
                        TextSpan(
                          text: row1,
                          style: style.copyWith(color: kAccent),
                        ),
                        TextSpan(
                          text: row2start,
                          style: style.copyWith(color: kRed),
                        ),
                      ]),
                    ),
                  ),
                  // Linie rosie la granita rand 1 / rand 2
                  Positioned(
                    top: lh + 8, left: 0, right: 0,
                    child: Container(height: 1, color: kRed.withOpacity(0.4)),
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Test cu text real ─────────────────────────────────────────
              const Text('Test cu text real (word-wrap):',
                  style: TextStyle(color: kTextDim, fontSize: 12)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: kTextPad, vertical: 8),
                decoration: BoxDecoration(
                    color: kBg2, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    'Acesta este un text de test pentru verificarea word-wrap-ului.',
                    'Spirit of truth present everywhere and filling all things.',
                    'Treasury of blessings and Giver of life come and dwell within us.',
                  ].map((line) {
                    // Simulam word-wrap manual cu charsPerRow
                    final words  = line.split(' ');
                    final rows   = <String>[];
                    var   row    = '';
                    for (final w in words) {
                      if (row.isEmpty) {
                        row = w;
                      } else if (row.length + 1 + w.length <= cpr) {
                        row += ' $w';
                      } else {
                        rows.add(row);
                        row = w;
                      }
                    }
                    if (row.isNotEmpty) rows.add(row);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: rows.map((r) => Container(
                        height: lh,
                        alignment: Alignment.centerLeft,
                        child: Text(r,
                            style: style.copyWith(color: kText),
                            maxLines: 1),
                      )).toList(),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Text('$label: ', style: const TextStyle(color: kTextDim, fontSize: 13)),
      Text(value, style: const TextStyle(
          color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}


// ── Edit Screen ───────────────────────────────────────────────────────────────

class EditScreen extends StatefulWidget {
  final MNode node;
  const EditScreen({super.key, required this.node});
  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl   = TextEditingController(text: widget.node.title);
    _contentCtrl = TextEditingController(text: widget.node.content ?? '');
  }

  @override
  void dispose() { _titleCtrl.dispose(); _contentCtrl.dispose(); super.dispose(); }

  void _applyTag(String tag) {
    final ctrl = _contentCtrl;
    final s = ctrl.selection.start, e = ctrl.selection.end;
    if (s < 0 || e < 0 || s == e) return;
    final sel = ctrl.text.substring(s, e);
    final o = '[$tag]', c = '[/$tag]';
    final ns = (sel.startsWith(o) && sel.endsWith(c))
        ? sel.substring(o.length, sel.length - c.length)
        : '$o${sel.replaceAll(o,'').replaceAll(c,'')}$c';
    ctrl.value = TextEditingValue(
      text: ctrl.text.substring(0, s) + ns + ctrl.text.substring(e),
      selection: TextSelection(baseOffset: s, extentOffset: s + ns.length),
    );
  }

  void _save() {
    widget.node.title   = _titleCtrl.text.trim();
    widget.node.content = _contentCtrl.text;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Edit'),
      actions: [TextButton(onPressed: _save,
          child: const Text('Save', style: TextStyle(
              color: kAccent, fontWeight: FontWeight.w600)))],
    ),
    body: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(color: kBg2,
            border: Border(bottom: BorderSide(color: kBorder))),
        child: Row(children: [
          const Text('Format:', style: TextStyle(color: kTextDim, fontSize: 12)),
          const SizedBox(width: 10),
          _FmtBtn(onTap: () => _applyTag('b'),
              child: const Text('B', style: TextStyle(color: kText,
                  fontWeight: FontWeight.bold, fontSize: 14))),
          const SizedBox(width: 6),
          _FmtBtn(onTap: () => _applyTag('i'),
              child: const Text('I', style: TextStyle(color: kText,
                  fontStyle: FontStyle.italic, fontSize: 14))),
          const SizedBox(width: 6),
          _FmtBtn(onTap: () => _applyTag('r'),
              child: const Text('R', style: TextStyle(color: kRed,
                  fontWeight: FontWeight.bold, fontSize: 14))),
          const SizedBox(width: 12),
          const Expanded(child: Text('Select text then tap B / I / R',
              style: TextStyle(color: kTextDim, fontSize: 11),
              overflow: TextOverflow.ellipsis)),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(controller: _titleCtrl,
              style: const TextStyle(color: kText, fontSize: 15,
                  fontWeight: FontWeight.w600),
              decoration: _inputDecor('Title...'))),
      Expanded(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: TextField(controller: _contentCtrl,
              maxLines: null, expands: true,
              style: GoogleFonts.robotoMono(
                  color: kText, fontSize: 14, height: 1.7),
              decoration: _inputDecor(
                  'Text to memorize...\n\n'
                  'Tags: [b]bold[/b]  [i]italic[/i]  [r]red[/r]')))),
    ]),
  );
}

class _FmtBtn extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _FmtBtn({required this.onTap, required this.child});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 34, height: 30,
        decoration: BoxDecoration(color: kBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kBorder)),
        alignment: Alignment.center, child: child));
}

InputDecoration _inputDecor(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: kTextDim, fontSize: 13),
  filled: true, fillColor: kBg2,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kBorder)),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kBorder)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kAccent)),
);
