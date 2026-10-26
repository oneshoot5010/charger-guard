import 'dart:convert';
import 'package:flutter/material.dart';

final ValueNotifier<String> themeMode = ValueNotifier<String>('system');

class Api {
  static const _c = MethodChannel('cg');

  static Future<Map<String, dynamic>> settings() async =>
      Map<String, dynamic>.from((await _c.invokeMethod('settings')) as Map);
  static Future<void> set(String k, Object v) async {
    await _c.invokeMethod('set', {'k': k, 'v': v});
  }

  static Future<bool> perm() async => (await _c.invokeMethod('perm')) == true;
  static Future<bool> start() async => (await _c.invokeMethod('start')) == true;
  static Future<void> stop() async {
    await _c.invokeMethod('stop');
  }

  static Future<void> took() async {
    await _c.invokeMethod('took');
  }

  static Future<void> test() async {
    await _c.invokeMethod('test');
  }

  static Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from((await _c.invokeMethod('status')) as Map);

  static Future<List<Map<String, dynamic>>> history() async {
    final s = (await _c.invokeMethod('history')) as String;
    return (jsonDecode(s) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> clearHistory() async {
    await _c.invokeMethod('clearHistory');
  }

  static Future<bool> setHome() async => (await _c.invokeMethod('home')) == true;
  static Future<void> open(String url) async {
    await _c.invokeMethod('open', {'url': url});
  }
}
