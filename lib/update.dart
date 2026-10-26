import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'api.dart';

class UpdateInfo {
  final int build;
  final String version;
  final String notes;
  final String url;
  final int size;
  UpdateInfo(this.build, this.version, this.notes, this.url, this.size);
}

class Updater {
  static const _api = 'https://api.github.com/repos/oneshoot5010/charger-guard/releases/latest';

  static Future<UpdateInfo?> latest() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final rq = await c.getUrl(Uri.parse(_api));
      rq.headers.set('User-Agent', 'charger-guard');
      rq.headers.set('Accept', 'application/vnd.github+json');
      final rs = await rq.close();
      if (rs.statusCode != 200) {
        await rs.drain();
        return null;
      }
      final j = jsonDecode(await rs.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      final build = int.tryParse(tag.contains('+') ? tag.split('+').last : '') ?? 0;
      final ver = tag.replaceFirst('v', '').split('+').first;
      final assets = ((j['assets'] as List?) ?? []).cast<Map>();
      Map? apk;
      for (final a in assets) {
        if ((a['name'] as String).endsWith('.apk')) {
          apk = a;
          break;
        }
      }
      if (apk == null || build == 0) return null;
      return UpdateInfo(build, ver, (j['body'] ?? '') as String, apk['browser_download_url'] as String, (apk['size'] ?? 0) as int);
    } finally {
      c.close();
    }
  }

  static Future<String> download(UpdateInfo i, void Function(double) onProgress) async {
    final dir = await Api.updDir();
    final f = File('$dir/charger-guard.apk');
    if (await f.exists()) await f.delete();
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final rq = await c.getUrl(Uri.parse(i.url));
      rq.headers.set('User-Agent', 'charger-guard');
      final rs = await rq.close();
      if (rs.statusCode != 200) throw 'HTTP ${rs.statusCode}';
      final total = rs.contentLength > 0 ? rs.contentLength : i.size;
      var got = 0;
      final sink = f.openWrite();
      await for (final chunk in rs) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress((got / total).clamp(0.0, 1.0));
      }
      await sink.close();
      return f.path;
    } finally {
      c.close();
    }
  }
}

// ---------- شريط بطارية بتشحن ----------
class ChargingBar extends StatefulWidget {
  final double value;
  const ChargingBar({super.key, required this.value});
  @override
  State<ChargingBar> createState() => _ChargingBarState();
}

class _ChargingBarState extends State<ChargingBar> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = widget.value.clamp(0.0, 1.0);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 210,
            height: 60,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: cs.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v < 0.03 ? 0.03 : v,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF43A047), Color(0xFFB2D235), Color(0xFFFFC107)]),
                      ),
                    ),
                  ),
                  Center(
                    child: AnimatedBuilder(
                      animation: _a,
                      builder: (_, __) => Opacity(
                        opacity: 0.6 + 0.4 * _a.value,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt, color: Colors.white, size: 26, shadows: [Shadow(blurRadius: 6, color: Colors.black87)]),
                            Text('${(v * 100).round()}%',
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, shadows: [Shadow(blurRadius: 6, color: Colors.black87)])),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 7,
            height: 22,
            decoration: BoxDecoration(color: cs.primary, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))),
          ),
        ],
      ),
    );
  }
}

// ---------- نافذة التحديث ----------
void showUpdateDialog(BuildContext context) =>
    showDialog(context: context, barrierDismissible: false, builder: (_) => const _UpdateDialog());

enum _Ph { checking, none, avail, down, ready, err }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Ph ph = _Ph.checking;
  UpdateInfo? info;
  double p = 0;
  String err = '';
  String? path;
  String curName = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final v = await Api.appVersion();
      curName = '${v['name']}';
      final cur = (v['code'] as num).toInt();
      final u = await Updater.latest();
      if (!mounted) return;
      if (u != null && u.build > cur) {
        info = u;
        setState(() => ph = _Ph.avail);
      } else {
        setState(() => ph = _Ph.none);
      }
    } catch (e) {
      _fail('تعذّر الاتصال: $e');
    }
  }

  void _fail(String m) {
    Api.log('update: $m');
    if (mounted) {
      setState(() {
        err = m;
        ph = _Ph.err;
      });
    }
  }

  Future<void> _download() async {
    setState(() {
      ph = _Ph.down;
      p = 0;
    });
    try {
      path = await Updater.download(info!, (v) {
        if (mounted) setState(() => p = v);
      });
      if (!mounted) return;
      setState(() => ph = _Ph.ready);
      await _install();
    } catch (e) {
      _fail('فشل التحميل: $e');
    }
  }

  Future<void> _install() async {
    final ok = await Api.install(path!);
    if (!ok) _fail('فشل بدء التثبيت');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    IconData icon = Icons.system_update;
    String title = 'تحديث التطبيق';
    Widget body;
    List<Widget> actions = [];
    void close() => Navigator.pop(context);
    switch (ph) {
      case _Ph.checking:
        body = const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('بدوّر على تحديث...'),
        ]);
        actions = [TextButton(onPressed: close, child: const Text('إغلاق'))];
        break;
      case _Ph.none:
        icon = Icons.verified;
        body = Text('أنت على آخر إصدار ✓\n(الإصدار $curName)', textAlign: TextAlign.center, style: const TextStyle(height: 1.6));
        actions = [TextButton(onPressed: close, child: const Text('تمام'))];
        break;
      case _Ph.avail:
        icon = Icons.new_releases;
        title = 'فيه تحديث جديد';
        body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الإصدار ${info!.version}  (الحالي $curName)', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (info!.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Flexible(child: SingleChildScrollView(child: Text(info!.notes.trim(), style: const TextStyle(height: 1.6)))),
          ],
        ]);
        actions = [
          TextButton(onPressed: close, child: const Text('لاحقاً')),
          FilledButton.icon(onPressed: _download, icon: const Icon(Icons.bolt), label: const Text('حدّث دلوقتي')),
        ];
        break;
      case _Ph.down:
        title = 'بنشحن التحديث...';
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          ChargingBar(value: p),
          const SizedBox(height: 14),
          const Text('متقفلش التطبيق لحد ما التحميل يخلص'),
        ]);
        break;
      case _Ph.ready:
        icon = Icons.download_done;
        title = 'التحديث جاهز';
        body = const Text('اتحمّل ✓ وافق على التثبيت لما الشاشة تظهر.\nلو مظهرتش اضغط «تثبيت».', textAlign: TextAlign.center, style: TextStyle(height: 1.6));
        actions = [
          TextButton(onPressed: close, child: const Text('إغلاق')),
          FilledButton(onPressed: _install, child: const Text('تثبيت')),
        ];
        break;
      case _Ph.err:
        icon = Icons.error_outline;
        title = 'حصلت مشكلة';
        body = Text(err, style: const TextStyle(height: 1.6));
        actions = [
          TextButton(onPressed: close, child: const Text('إغلاق')),
          FilledButton(
              onPressed: () {
                setState(() => ph = _Ph.checking);
                _check();
              },
              child: const Text('حاول تاني')),
        ];
        break;
    }
    return PopScope(
      canPop: ph != _Ph.down,
      child: AlertDialog(
        icon: Icon(icon, size: 38, color: cs.primary),
        title: Text(title, textAlign: TextAlign.center),
        content: body,
        actions: actions,
      ),
    );
  }
}

// ---------- زرار أيقونة في الإعدادات ----------
class ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const ActionTile({super.key, required this.icon, required this.label, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                ),
                child: Icon(icon, color: cs.onPrimary, size: 28),
              ),
              const SizedBox(height: 10),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
