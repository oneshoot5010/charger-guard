import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const GuardPage(), const HistoryPage(), const SettingsPage()];
    return Scaffold(
      appBar: AppBar(title: const Text('حارس الشاحن', style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true),
      body: SafeArea(child: pages[i]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'الحارس'),
          NavigationDestination(icon: Icon(Icons.history), label: 'السجل'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ---------------- الحارس ----------------
class GuardPage extends StatefulWidget {
  const GuardPage({super.key});
  @override
  State<GuardPage> createState() => _GuardPageState();
}

class _GuardPageState extends State<GuardPage> {
  Timer? _t;
  Map<String, dynamic> s = {'state': 'off', 'dist': 0.0, 'limit': 10.0, 'away': false, 'charging': false};

  @override
  void initState() {
    super.initState();
    _poll();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final m = await Api.status();
      if (mounted) setState(() => s = m);
    } catch (_) {}
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggle() async {
    if (s['state'] == 'off') {
      final ok = await Api.perm();
      if (!ok) {
        _snack('لازم تسمح بإذن الموقع عشان الحارس يشتغل');
        return;
      }
      await Api.start();
    } else {
      await Api.stop();
    }
    await _poll();
  }

  @override
  Widget build(BuildContext context) {
    final st = s['state'] as String;
    final dist = (s['dist'] as num).toDouble();
    final limit = (s['limit'] as num).toDouble();
    final c = switch (st) {
      'alarm' => Colors.red,
      'tracking' => Colors.amber.shade700,
      'idle' => Colors.green,
      _ => Colors.grey,
    };
    final title = switch (st) {
      'alarm' => '⚠️ نسيت الشاحن!',
      'tracking' => 'فصلت الشاحن — بتابع مكانك',
      'idle' => 'الحارس شغّال',
      _ => 'الحارس متوقف',
    };
    final sub = switch (st) {
      'alarm' => 'اضغط «خدت الشاحن» لإيقاف الإنذار',
      'tracking' => 'المسافة: ${dist.toStringAsFixed(0)} م  (الحد: ${limit.toStringAsFixed(0)} م)',
      'idle' => 'بستنى فصل الشاحن',
      _ => 'اضغط الزرار الكبير للتفعيل',
    };
    final icon = st == 'alarm'
        ? Icons.notifications_active
        : st == 'off'
            ? Icons.power_settings_new
            : Icons.shield;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: _toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.withAlpha(240), c.withAlpha(140)],
                ),
                boxShadow: [BoxShadow(color: c.withAlpha(100), blurRadius: 32, spreadRadius: 4)],
              ),
              child: Icon(icon, size: 84, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(sub, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            Chip(
              avatar: Icon(s['charging'] == true ? Icons.bolt : Icons.power_off, size: 18),
              label: Text(s['charging'] == true ? 'الشاحن موصّل' : 'الشاحن مفصول'),
            ),
            if (s['away'] == true && st != 'off')
              const Chip(avatar: Icon(Icons.place, size: 18), label: Text('وضع «برا البيت» — أقوى')),
          ],
        ),
        const SizedBox(height: 20),
        if (st == 'tracking' || st == 'alarm')
          SizedBox(
            height: 60,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600),
              onPressed: () async {
                await Api.took();
                await Future.delayed(const Duration(milliseconds: 300));
                _poll();
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('خدت الشاحن', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
        if (st != 'alarm') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Api.test();
              _poll();
            },
            icon: const Icon(Icons.volume_up),
            label: const Text('جرّب الإنذار'),
          ),
        ],
        if (st == 'off')
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'إزاي بيشتغل؟\n١) فعّل الحارس.\n٢) لما تفصل الموبايل من الشاحن بيبدأ يتابع مكانك.\n٣) لو بعدت عن مكان الفصل أكتر من المسافة المحددة، الإنذار يرن لحد ما تدوس «خدت الشاحن» أو توصّل الشاحن تاني.\n\nمهم: شغّل الموقع (GPS) وخلّي التطبيق من غير توفير بطارية.',
                  style: TextStyle(height: 1.6),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------- السجل ----------------
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>>? items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await Api.history();
      if (mounted) setState(() => items = h);
    } catch (_) {
      if (mounted) setState(() => items = []);
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) {
      return const Center(child: Text('مفيش مرات نسيت فيها الشاحن 👏', style: TextStyle(fontSize: 18)));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text('نسيت الشاحن ${list.length} مرة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('مسح السجل؟'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لأ')),
                        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('امسح')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await Api.clearHistory();
                    _load();
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('مسح'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, k) {
              final e = list[k];
              final d = DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt());
              final away = e['away'] == true;
              return Card(
                child: ListTile(
                  leading: Icon(away ? Icons.place : Icons.home, color: Colors.amber.shade700),
                  title: Text(away ? 'اتنسى في مكان تاني' : 'اتنسى في البيت'),
                  subtitle: Text('${d.year}-${_p(d.month)}-${_p(d.day)}   ${_p(d.hour)}:${_p(d.minute)}'),
                  trailing: Text('${e['d']} م'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------- الإعدادات ----------------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic>? s;

  @override
  void initState() {
    super.initState();
    Api.settings().then((v) {
      if (mounted) setState(() => s = v);
    });
  }

  String _fmt(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _pick(String key) async {
    final cur = s![key] as int;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
    if (t != null) {
      final v = t.hour * 60 + t.minute;
      await Api.set(key, v);
      setState(() => s![key] = v);
    }
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final m = s;
    if (m == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('المظهر'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ValueListenableBuilder<String>(
                valueListenable: themeMode,
                builder: (_, cur, __) => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('تلقائي'), icon: Icon(Icons.brightness_auto)),
                    ButtonSegment(value: 'light', label: Text('نهاري'), icon: Icon(Icons.light_mode)),
                    ButtonSegment(value: 'dark', label: Text('ليلي'), icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {cur},
                  onSelectionChanged: (v) {
                    themeMode.value = v.first;
                    Api.set('theme', v.first);
                  },
                ),
              ),
            ),
          ),
        ),
        _section('الحراسة'),
        Card(
          child: Column(
            children: [
              ListTile(title: const Text('المسافة اللي يرن عندها'), trailing: Text('${m['threshold']} م')),
              Slider(
                value: (m['threshold'] as int).toDouble(),
                min: 3,
                max: 100,
                divisions: 97,
                label: '${m['threshold']} م',
                onChanged: (v) => setState(() => m['threshold'] = v.round()),
                onChangeEnd: (v) => Api.set('threshold', v.round()),
              ),
              ListTile(title: const Text('مدة المراقبة بعد فصل الشاحن'), trailing: Text('${m['monitor']} دقيقة')),
              Slider(
                value: (m['monitor'] as int).toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                label: '${m['monitor']} د',
                onChanged: (v) => setState(() => m['monitor'] = v.round()),
                onChangeEnd: (v) => Api.set('monitor', v.round()),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('ملحوظة: GPS جوه المباني ممكن يغلط ٥–١٥ متر، فخلّي المسافة ١٠ متر أو أكتر للدقة.', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        _section('وضع «برا البيت»'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.home),
            title: const Text('حدّد مكاني الحالي كالبيت'),
            subtitle: Text(m['home_set'] == true
                ? 'البيت متحدد ✓ — برا البيت الإنذار أقوى والمسافة أقصر'
                : 'لو فصلت الشاحن بعيد عن البيت الإنذار يبقى أقوى'),
            onTap: () async {
              final ok = await Api.setHome();
              if (!mounted) return;
              if (ok) setState(() => m['home_set'] = true);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'تم حفظ مكان البيت' : 'مش قادر أحدد موقعك — شغّل الـGPS وافتح خرائط جوجل مرة وجرّب تاني')));
            },
          ),
        ),
        _section('الوضع الصامت'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('اهتزاز بس في أوقات معينة'),
                subtitle: const Text('من غير صوت، مثلاً بالليل'),
                value: m['silent_on'] == true,
                onChanged: (v) {
                  Api.set('silent_on', v);
                  setState(() => m['silent_on'] = v);
                },
              ),
              if (m['silent_on'] == true) ...[
                ListTile(title: const Text('من'), trailing: Text(_fmt(m['silent_start'] as int)), onTap: () => _pick('silent_start')),
                ListTile(title: const Text('إلى'), trailing: Text(_fmt(m['silent_end'] as int)), onTap: () => _pick('silent_end')),
              ],
            ],
          ),
        ),
        _section('عن التطبيق'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: const Text('عن المطوّر'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeveloperPage())),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ---------------- عن المطوّر ----------------
class DeveloperPage extends StatelessWidget {
  const DeveloperPage({super.key});

  static const phone = '+201044947639';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('عن المطوّر'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [cs.primaryContainer, cs.tertiaryContainer],
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [BoxShadow(color: cs.primary.withAlpha(110), blurRadius: 24)],
                  ),
                  alignment: Alignment.center,
                  child: Text('MH', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: cs.onPrimary)),
                ),
                const SizedBox(height: 16),
                const Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('Mohamed Hassan Taha', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                const Text('مطوّر تطبيقات أندرويد', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 8,
                  children: [Chip(label: Text('Android')), Chip(label: Text('Flutter')), Chip(label: Text('Kotlin'))],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF25D366), child: Icon(Icons.chat, color: Colors.white)),
              title: const Text('كلمني على واتساب'),
              subtitle: const Directionality(textDirection: TextDirection.ltr, child: Text(phone)),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: phone));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اتنسخ الرقم')));
                },
              ),
              onTap: () => Api.open('https://wa.me/201044947639'),
            ),
          ),
          Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: cs.inverseSurface, child: Icon(Icons.code, color: cs.onInverseSurface)),
              title: const Text('افتح GitHub'),
              subtitle: const Directionality(textDirection: TextDirection.ltr, child: Text('github.com/oneshoot5010')),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => Api.open('https://github.com/oneshoot5010'),
            ),
          ),
          const SizedBox(height: 24),
          const Center(child: Text('حارس الشاحن • الإصدار 1.0.0', style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
