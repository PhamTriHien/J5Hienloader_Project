import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import '../bridge/j2me_ffi.dart';

// Các cờ ràng buộc kiểu nhập liệu của MIDP TextField
const int _kConstraintMask = 0xFFFF;
const int _kEmail = 1;
const int _kNumeric = 2;
const int _kPhone = 3;
const int _kUrl = 4;
const int _kDecimal = 5;
const int _kPassword = 0x10000;
const int _kUneditable = 0x20000;

// Các mã loại lệnh MIDP Command
const int _kBack = 2;
const int _kCancel = 3;
const int _kStop = 6;
const int _kExit = 7;

// Các chế độ lựa chọn ChoiceGroup / List
const int _kExclusive = 1;
const int _kMultiple = 2;
const int _kImplicit = 3;

// Mã tác vụ gửi về hàm screen_submit phía C++
const int _kActionStore = -1;
const int _kActionDismiss = -2;
const int _kActionSelect = -3;

class LcduiCommand {
  final String label;
  final int type;
  final int priority;
  LcduiCommand.fromJson(Map<String, dynamic> j)
      : label = j['label'] as String,
        type = j['type'] as int,
        priority = (j['priority'] ?? 0) as int;

  bool get isNegative => type == _kBack || type == _kCancel || type == _kExit || type == _kStop;
}

List<LcduiCommand> _commands(dynamic list) =>
    ((list ?? []) as List).map((e) => LcduiCommand.fromJson(e as Map<String, dynamic>)).toList();

class LcduiItem {
  final String kind; // text, string, choice, gauge, date, spacer, image
  final String label;
  final String text;
  final int maxSize;
  final int constraints;
  final int appearance;
  final int choiceType;
  final List<String> options;
  final List<bool> selected;
  final bool interactive;
  final int max;
  final int value;
  final int dateMode;
  final int? date;
  final List<LcduiCommand> commands;

  LcduiItem.fromJson(Map<String, dynamic> j)
      : kind = j['kind'] as String,
        label = (j['label'] ?? '') as String,
        text = (j['text'] ?? '') as String,
        maxSize = (j['maxSize'] ?? 0) as int,
        constraints = (j['constraints'] ?? 0) as int,
        appearance = (j['appearance'] ?? 0) as int,
        choiceType = (j['choiceType'] ?? _kExclusive) as int,
        options = ((j['options'] ?? []) as List).cast<String>(),
        selected = ((j['selected'] ?? []) as List).cast<bool>(),
        interactive = (j['interactive'] ?? false) as bool,
        max = (j['max'] ?? 100) as int,
        value = (j['value'] ?? 0) as int,
        dateMode = (j['dateMode'] ?? 3) as int,
        date = j['date'] as int?,
        commands = _commands(j['commands']);
}

/// Dữ liệu màn hình giao diện cấp cao (Form/TextBox/List/Alert) đang được MIDlet hiển thị.
class LcduiScreen {
  final String type; // form, textbox, list, alert
  final String title;
  final String text;
  final int timeout;
  final List<LcduiItem> items;
  final List<LcduiCommand> commands;

  LcduiScreen._(Map<String, dynamic> j)
      : type = j['type'] as String,
        title = (j['title'] ?? '') as String,
        text = (j['text'] ?? '') as String,
        timeout = (j['timeout'] ?? -2) as int,
        items = ((j['items'] ?? []) as List).map((e) => LcduiItem.fromJson(e as Map<String, dynamic>)).toList(),
        commands = _commands(j['commands']);

  static LcduiScreen? fetch(ffi.Pointer<ffi.Void> inst) {
    const maxLen = 256 * 1024;
    final buf = calloc<ffi.Uint8>(maxLen).cast<Utf8>();
    try {
      if (!J2meBindings.instance.coreScreenGet(inst, buf, maxLen)) return null;
      return LcduiScreen._(jsonDecode(buf.toDartString()) as Map<String, dynamic>);
    } finally {
      calloc.free(buf);
    }
  }
}

/// Lấy danh sách các lệnh Command gắn vào Canvas hiện tại.
List<LcduiCommand>? fetchCanvasCommands(ffi.Pointer<ffi.Void> inst) {
  const maxLen = 16 * 1024;
  final buf = calloc<ffi.Uint8>(maxLen).cast<Utf8>();
  try {
    if (!J2meBindings.instance.coreCanvasCommands(inst, buf, maxLen)) return null;
    return _commands(jsonDecode(buf.toDartString()));
  } finally {
    calloc.free(buf);
  }
}

/// Hiển thị [screen] dưới dạng hộp thoại và phản hồi thao tác người dùng về CommandListener của MIDlet.
Future<void> showLcduiScreenDialog(BuildContext context, ffi.Pointer<ffi.Void> inst, LcduiScreen screen) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LcduiScreenDialog(inst: inst, screen: screen),
  );
}

class _LcduiScreenDialog extends StatefulWidget {
  final ffi.Pointer<ffi.Void> inst;
  final LcduiScreen screen;
  const _LcduiScreenDialog({required this.inst, required this.screen});

  @override
  State<_LcduiScreenDialog> createState() => _LcduiScreenDialogState();
}

class _LcduiScreenDialogState extends State<_LcduiScreenDialog> {
  late final List<TextEditingController> _text;
  late final List<List<bool>> _selected;
  late final List<double> _gauge;
  late final List<int?> _date;
  late final List<bool> _obscure;
  Timer? _alertTimer;
  bool _closed = false;

  LcduiScreen get _screen => widget.screen;

  @override
  void initState() {
    super.initState();
    final items = _screen.items;
    _text = items.map((i) => TextEditingController(text: i.text)).toList();
    _selected = items.map((i) => List<bool>.of(i.selected)).toList();
    _gauge = items.map((i) => i.value.toDouble()).toList();
    _date = items.map((i) => i.date).toList();
    _obscure = items.map((i) => i.constraints & _kPassword != 0).toList();
    if (_screen.type == 'alert' && _screen.timeout > 0) {
      _alertTimer = Timer(Duration(milliseconds: _screen.timeout), () => _submit(_kActionDismiss));
    }
  }

  @override
  void dispose() {
    _alertTimer?.cancel();
    for (final c in _text) {
      c.dispose();
    }
    super.dispose();
  }

  String _values() {
    final out = <String>[];
    for (int i = 0; i < _screen.items.length; ++i) {
      final item = _screen.items[i];
      switch (item.kind) {
        case 'text':
          out.add(_text[i].text);
        case 'choice':
          out.add(_selected[i].map((b) => b ? '1' : '0').join());
        case 'gauge':
          out.add(_gauge[i].round().toString());
        case 'date':
          out.add(_date[i]?.toString() ?? '');
        default:
          out.add('');
      }
    }
    return out.join('\u001f');
  }

  void _submit(int action) {
    if (_closed) return;
    _closed = true;
    _alertTimer?.cancel();
    final values = _values();
    Navigator.of(context).pop();
    final ptr = values.toNativeUtf8();
    try {
      J2meBindings.instance.coreScreenSubmit(widget.inst, action, ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  // Values changed without closing (e.g. Form ItemStateListener)
  void _store() {
    final ptr = _values().toNativeUtf8();
    try {
      J2meBindings.instance.coreScreenSubmit(widget.inst, _kActionStore, ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  int _firstCommand({required bool negative}) {
    final cmds = _screen.commands;
    for (int i = 0; i < cmds.length; ++i) {
      if (cmds[i].isNegative == negative) return i;
    }
    return -1;
  }

  void _onEnter() {
    final c = _firstCommand(negative: false);
    if (c >= 0) {
      _submit(c);
    } else if (_screen.type == 'alert') {
      _submit(_kActionDismiss);
    }
  }

  void _onClose() {
    final c = _firstCommand(negative: true);
    if (c >= 0) {
      _submit(c);
    } else if (_screen.type == 'alert') {
      _submit(_kActionDismiss);
    } else if (_screen.commands.isEmpty) {
      // Nothing the MIDlet can react to: keep showing the screen
    }
  }

  TextInputType _keyboard(int constraints) {
    switch (constraints & _kConstraintMask) {
      case _kNumeric:
        return TextInputType.number;
      case _kDecimal:
        return const TextInputType.numberWithOptions(decimal: true);
      case _kEmail:
        return TextInputType.emailAddress;
      case _kPhone:
        return TextInputType.phone;
      case _kUrl:
        return TextInputType.url;
      default:
        return TextInputType.text;
    }
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(s, style: const TextStyle(fontSize: 12, color: Color(0xFF64B5F6), fontWeight: FontWeight.w600)),
      );

  Widget _textField(int i, LcduiItem f) {
    final kind = f.constraints & _kConstraintMask;
    final password = f.constraints & _kPassword != 0;
    final firstEditable = _screen.items.indexWhere((e) => e.kind == 'text');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: _text[i],
        autofocus: i == firstEditable,
        readOnly: f.constraints & _kUneditable != 0,
        obscureText: _obscure[i],
        keyboardType: _keyboard(f.constraints),
        maxLength: f.maxSize > 0 ? f.maxSize : null,
        maxLines: _screen.type == 'textbox' && !password && kind == 0 ? null : 1,
        inputFormatters: [
          if (kind == _kNumeric) FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
        ],
        onSubmitted: (_) => _onEnter(),
        decoration: InputDecoration(
          labelText: f.label.isEmpty ? null : f.label,
          border: const OutlineInputBorder(),
          isDense: true,
          counterText: '',
          suffixIcon: password
              ? IconButton(
                  icon: Icon(_obscure[i] ? Icons.visibility : Icons.visibility_off, size: 18),
                  onPressed: () => setState(() => _obscure[i] = !_obscure[i]),
                )
              : null,
        ),
      ),
    );
  }

  Widget _choice(int i, LcduiItem c, {required bool isList}) {
    final sel = _selected[i];
    if (c.choiceType == _kImplicit && isList) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int k = 0; k < c.options.length; ++k)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              selected: sel[k],
              title: Text(c.options[k]),
              onTap: () {
                for (int m = 0; m < sel.length; ++m) {
                  sel[m] = m == k;
                }
                _submit(_kActionSelect);
              },
            ),
        ],
      );
    }
    if (c.choiceType == _kMultiple) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.label.isNotEmpty) _label(c.label),
          for (int k = 0; k < c.options.length; ++k)
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: sel[k],
              title: Text(c.options[k]),
              onChanged: (v) {
                setState(() => sel[k] = v ?? false);
                if (!isList) _store();
              },
            ),
        ],
      );
    }
    final current = sel.indexWhere((b) => b);
    void choose(int? k) {
      if (k == null) return;
      setState(() {
        for (int m = 0; m < sel.length; ++m) {
          sel[m] = m == k;
        }
      });
      if (!isList) _store();
    }

    if (c.choiceType != _kExclusive && !isList) {
      // POPUP
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.label.isNotEmpty) _label(c.label),
          DropdownButton<int>(
            isExpanded: true,
            value: current < 0 ? null : current,
            items: [for (int k = 0; k < c.options.length; ++k) DropdownMenuItem(value: k, child: Text(c.options[k]))],
            onChanged: choose,
          ),
        ],
      );
    }
    return RadioGroup<int>(
      groupValue: current < 0 ? null : current,
      onChanged: choose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.label.isNotEmpty) _label(c.label),
          for (int k = 0; k < c.options.length; ++k)
            RadioListTile<int>(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              value: k,
              title: Text(c.options[k]),
            ),
        ],
      ),
    );
  }

  Widget _gaugeItem(int i, LcduiItem g) {
    final indefinite = g.max < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (g.label.isNotEmpty) _label(g.label),
        if (g.interactive && !indefinite)
          Slider(
            value: _gauge[i].clamp(0, g.max.toDouble()),
            max: g.max <= 0 ? 1 : g.max.toDouble(),
            divisions: g.max > 0 ? g.max : null,
            label: _gauge[i].round().toString(),
            onChanged: (v) => setState(() => _gauge[i] = v),
            onChangeEnd: (_) => _store(),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(value: indefinite || g.max <= 0 ? null : (g.value / g.max).clamp(0.0, 1.0)),
          ),
      ],
    );
  }

  Widget _dateItem(int i, LcduiItem d) {
    final ms = _date[i];
    final dt = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    String fmt(DateTime t) {
      final date = '${two(t.day)}/${two(t.month)}/${t.year}';
      final time = '${two(t.hour)}:${two(t.minute)}';
      return d.dateMode == 1 ? date : (d.dateMode == 2 ? time : '$date $time');
    }

    Future<void> pick() async {
      var base = dt ?? DateTime.now();
      if (d.dateMode != 2) {
        final day = await showDatePicker(context: context, initialDate: base, firstDate: DateTime(1900), lastDate: DateTime(2100));
        if (day == null) return;
        base = DateTime(day.year, day.month, day.day, base.hour, base.minute);
      }
      if (d.dateMode != 1 && mounted) {
        final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
        if (t == null) return;
        // TIME mode: MIDP expects the time on January 1, 1970
        base = d.dateMode == 2
            ? DateTime(1970, 1, 1, t.hour, t.minute)
            : DateTime(base.year, base.month, base.day, t.hour, t.minute);
      }
      setState(() => _date[i] = base.millisecondsSinceEpoch);
      _store();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (d.label.isNotEmpty) _label(d.label),
        OutlinedButton.icon(
          icon: Icon(d.dateMode == 2 ? Icons.access_time : Icons.calendar_today, size: 16),
          label: Text(dt == null ? '--' : fmt(dt)),
          onPressed: pick,
        ),
      ],
    );
  }

  Widget _stringItem(int i, LcduiItem s) {
    final body = s.label.isEmpty ? s.text : (s.text.isEmpty ? s.label : '${s.label} ${s.text}');
    if (s.commands.isNotEmpty && (s.appearance == 1 || s.appearance == 2)) {
      final button = s.appearance == 2;
      final text = Text(s.text.isEmpty ? (s.label.isEmpty ? s.commands.first.label : s.label) : s.text);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: button
            ? OutlinedButton(onPressed: () => _submit(1000 + i * 100), child: text)
            : TextButton(onPressed: () => _submit(1000 + i * 100), child: text),
      );
    }
    if (body.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SelectableText(body, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _itemCommands(int i, LcduiItem item) {
    if (item.commands.isEmpty || (item.kind == 'string' && (item.appearance == 1 || item.appearance == 2))) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 6,
      children: [
        for (int k = 0; k < item.commands.length; ++k)
          TextButton(onPressed: () => _submit(1000 + i * 100 + k), child: Text(item.commands[k].label)),
      ],
    );
  }

  Widget _item(int i) {
    final item = _screen.items[i];
    final isList = _screen.type == 'list';
    final Widget w;
    switch (item.kind) {
      case 'text':
        w = _textField(i, item);
      case 'choice':
        w = _choice(i, item, isList: isList);
      case 'gauge':
        w = _gaugeItem(i, item);
      case 'date':
        w = _dateItem(i, item);
      case 'spacer':
        return const SizedBox(height: 6);
      default:
        w = _stringItem(i, item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [w, _itemCommands(i, item)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = _screen;
    final isAlert = screen.type == 'alert';
    final commands = screen.commands;
    final actions = <Widget>[
      for (int i = 0; i < commands.length; ++i)
        commands[i].isNegative
            ? TextButton(onPressed: () => _submit(i), child: Text(commands[i].label))
            : FilledButton(onPressed: () => _submit(i), child: Text(commands[i].label)),
      if (isAlert && commands.isEmpty) FilledButton(onPressed: () => _submit(_kActionDismiss), child: const Text('OK')),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onClose();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _onClose},
        child: AlertDialog(
          title: screen.title.isEmpty ? null : Text(screen.title),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isAlert && screen.text.isNotEmpty) Text(screen.text, style: const TextStyle(fontSize: 13)),
                  for (int i = 0; i < screen.items.length; ++i) _item(i),
                ],
              ),
            ),
          ),
          actions: actions.isEmpty ? null : actions,
        ),
      ),
    );
  }
}
