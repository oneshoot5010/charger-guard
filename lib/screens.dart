import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'update.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _checkUpdate);
  }

  Future<void> _checkUpdate() async {
    try {
      final v = await Api.appVersion();
      final u = await Updater.latest();
      if (!mounted || u == null || u.build <= (v['code'] as num).toInt()) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 12),
        content: Text('فيه تحديث جديد — الإصدار ${u.version}'),
        action: SnackBarAction(label: 'حدّث', onPressed: () => showUpdateDialog(context)),
      ));
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final pages = [const GuardPage(), const HistoryPage(), const SettingsPage()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('حارس الشاحن', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(tooltip: 'الشرح', icon: const Icon(Icons.help_outline), onPressed: () => showHelpDialog(context)),
          IconButton(tooltip: 'استثناء البطارية', icon: const Icon(Icons.battery_saver), onPressed: () => showBatteryDialog(context)),
        ],
      ),
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
  Map<String, dynamic> s = {'state': 'off', 'steps': 0, 'dist': 0.0, 'limit': 10.0, 'away': false, 'charging': false};

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
      'tracking' => 'المسافة: ${dist.toStringAsFixed(1)} م  (الحد: ${limit.toStringAsFixed(0)} م)\nخطوات: ${s['steps'] ?? 0}',
      'idle' => s['charging'] == true
          ? 'الشاحن موصّل — هبدأ أراقب أول ما تفصله'
          : 'الشاحن مفصول — وصّله الأول عشان الحارس يبدأ المراقبة',
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
                  kHelp,
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

  Future<void> _copyReport() async {
    try {
      final r = await Api.report();
      await Clipboard.setData(ClipboardData(text: r));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اتنسخ تقرير الأخطاء — ابعته للمطوّر')));
      }
    } catch (_) {}
  }

  Future<void> _clearLog() async {
    await Api.clearLog();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اتمسح سجل الأخطاء')));
    }
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
                min: 1,
                max: 100,
                divisions: 99,
                label: '${m['threshold']} م',
                onChanged: (v) => setState(() => m['threshold'] = v.round()),
                onChangeEnd: (v) => Api.set('threshold', v.round()),
              ),
              ListTile(title: const Text('مدة المراقبة بعد فصل الشاحن'), trailing: Text('${m['monitor']} دقيقة')),
              Slider(
                value: (m['monitor'] as int).toDouble(),
                min: 1,
                max: 120,
                divisions: 119,
                label: '${m['monitor']} د',
                onChanged: (v) => setState(() => m['monitor'] = v.round()),
                onChangeEnd: (v) => Api.set('monitor', v.round()),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('المسافة بتتحسب من GPS وعدّاد الخطوات مع بعض. جوه المباني الـGPS بيغلط، فالمسافات الصغيرة (١–٥ متر) بتعتمد أكتر على الخطوات.', style: TextStyle(fontSize: 12)),
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
        _section('الصيانة'),
        Row(
          children: [
            Expanded(child: ActionTile(icon: Icons.system_update, label: 'تحديث التطبيق', onTap: () => showUpdateDialog(context))),
            const SizedBox(width: 12),
            Expanded(child: ActionTile(icon: Icons.bug_report, label: 'نسخ تقرير الأخطاء', onTap: _copyReport, onLongPress: _clearLog)),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('اضغط مطوّلاً على «نسخ تقرير الأخطاء» لمسح السجل.', style: TextStyle(fontSize: 12)),
        ),
        _section('البطارية'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.battery_saver),
            title: const Text('استثناء من توفير البطارية'),
            subtitle: const Text('ضروري عشان الحارس ميتقفلش في الخلفية'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => showBatteryDialog(context),
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

// ---------------- الشرح والبطارية ----------------
const kHelp = 'إزاي بيشتغل؟\n'
    '١) فعّل الحارس واسمح بالموقع والإشعارات والنشاط البدني.\n'
    '٢) لما تفصل الشاحن بيبدأ يحسب المسافة اللي بتتحركها (GPS + عدّاد خطوات).\n'
    '٣) لو بعدت أكتر من المسافة المحددة الإنذار يرن لحد ما تدوس «خدت الشاحن» أو توصّل الشاحن تاني.\n'
    '٤) 🔋 دوس أيقونة البطارية فوق واستثني التطبيق من توفير البطارية عشان الحارس ميتقفلش.\n'
    '٥) شغّل الموقع (GPS).\n'
    '٦) تقدر تضيف «حارس الشاحن» في لوحة الإعدادات السريعة (اسحب من فوق ← القلم ← أضف).';

void showHelpDialog(BuildContext context) => showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.shield, size: 36),
        content: const SingleChildScrollView(child: Text(kHelp, style: TextStyle(height: 1.7))),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('تمام'))],
      ),
    );

void showBatteryDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _BatteryDialog());

class _BatteryDialog extends StatefulWidget {
  const _BatteryDialog();
  @override
  State<_BatteryDialog> createState() => _BatteryDialogState();
}

class _BatteryDialogState extends State<_BatteryDialog> with WidgetsBindingObserver {
  bool? ok;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    try {
      final v = await Api.batteryOk();
      if (mounted) setState(() => ok = v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final good = ok == true;
    return AlertDialog(
      icon: Icon(good ? Icons.verified : Icons.battery_alert, size: 40, color: good ? Colors.green : Colors.amber.shade700),
      title: const Text('استثناء من توفير البطارية'),
      content: Text(
        good
            ? 'تمام ✓ التطبيق مستثنى من توفير البطارية، والحارس هيفضل شغال في الخلفية.'
            : 'الموبايل ممكن يقفل الحارس في الخلفية عشان يوفّر بطارية، وساعتها مش هيرن لو نسيت الشاحن.\n\nدوس «استثناء التطبيق» ووافق.\n\nعلى موبايلات أوبو وشاومي وسامسونج فعّل كمان «التشغيل التلقائي» أو «الخلفية بلا قيود» من إعدادات التطبيق.',
        style: const TextStyle(height: 1.6),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        if (!good) FilledButton(onPressed: () => Api.batteryAsk(), child: const Text('استثناء التطبيق')),
      ],
    );
  }
}

// ---------------- عن المطوّر ----------------
class DeveloperPage extends StatelessWidget {
  const DeveloperPage({super.key});

  static const phone = '+201044947639';
  static const gold1 = Color(0xFFFFD27A);
  static const gold2 = Color(0xFFE08A00);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final top = MediaQuery.of(context).padding.top + kToolbarHeight;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: dark ? Colors.white : const Color(0xFF2A1E08),
        title: const Text('عن المطوّر'),
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, top + 8, 20, 36),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: dark
                    ? const [Color(0xFF3A2A0C), Color(0xFF14110B)]
                    : const [Color(0xFFFFD27A), Color(0xFFE08A00)],
              ),
            ),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(top: -10, left: -50, child: _orb(150, 40)),
                Positioned(top: 120, right: -60, child: _orb(130, 28)),
                Column(
                  children: [
                    Container(
                      width: 128,
                      height: 128,
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(colors: [gold1, gold2, Color(0xFFFFF1CC), gold2, gold1]),
                        boxShadow: [BoxShadow(color: Color(0x66E08A00), blurRadius: 30, spreadRadius: 2)],
                      ),
                      child: Container(
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A1409)),
                        alignment: Alignment.center,
                        child: ShaderMask(
                          shaderCallback: (r) => const LinearGradient(colors: [gold1, gold2]).createShader(r),
                          child: const Text('MH', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text('Mohamed Hassan Taha',
                          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: dark ? Colors.white : const Color(0xFF2A1E08))),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(dark ? 90 : 45),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: gold1.withAlpha(140)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 18, color: gold1),
                          SizedBox(width: 6),
                          Text('مطوّر تطبيقات أندرويد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 30 * (1 - v)), child: child)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(context, 'نبذة', Icons.person_outline),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'بصمّم وأبني تطبيقات أندرويد بسيطة وسريعة وبتحل مشاكل حقيقية في الحياة اليومية، من الفكرة لحد ما التطبيق يوصل لإيد المستخدم.',
                        style: TextStyle(height: 1.7),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _title(context, 'المهارات', Icons.bolt),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Skill(Icons.android, 'Android'),
                      _Skill(Icons.flutter_dash, 'Flutter'),
                      _Skill(Icons.code, 'Kotlin'),
                      _Skill(Icons.terminal, 'Termux'),
                      _Skill(Icons.cloud_sync, 'GitHub Actions'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _title(context, 'تواصل معايا', Icons.forum_outlined),
                  _Cta(
                    colors: const [Color(0xFF25D366), Color(0xFF128C7E)],
                    icon: Icons.chat,
                    title: 'كلمني على واتساب',
                    sub: phone,
                    onTap: () => Api.open('https://wa.me/201044947639'),
                    onCopy: () {
                      Clipboard.setData(const ClipboardData(text: phone));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اتنسخ الرقم')));
                    },
                  ),
                  const SizedBox(height: 12),
                  _Cta(
                    colors: dark ? const [Color(0xFF3A3A3A), Color(0xFF111111)] : const [Color(0xFF3B3B3B), Color(0xFF111111)],
                    icon: Icons.code,
                    title: 'افتح GitHub',
                    sub: 'github.com/oneshoot5010',
                    onTap: () => Api.open('https://github.com/oneshoot5010'),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Text('حارس الشاحن • الإصدار 1.2.0',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150))),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _orb(double size, int alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(alpha)),
      );

  static Widget _title(BuildContext context, String t, IconData i) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Row(
          children: [
            Icon(i, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _Skill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Skill(this.icon, this.label);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: cs.primary.withAlpha(110)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Cta extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final VoidCallback? onCopy;
  const _Cta({required this.colors, required this.icon, required this.title, required this.sub, required this.onTap, this.onCopy});
  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: colors),
          boxShadow: [BoxShadow(color: colors.first.withAlpha(70), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(45)),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Directionality(textDirection: TextDirection.ltr, child: Text(sub, style: TextStyle(color: Colors.white.withAlpha(210)))),
                    ],
                  ),
                ),
                if (onCopy != null) IconButton(onPressed: onCopy, icon: const Icon(Icons.copy, color: Colors.white)),
                if (onCopy == null) const Icon(Icons.open_in_new, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
