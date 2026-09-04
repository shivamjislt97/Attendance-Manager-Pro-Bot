import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// FastAPI backend client. Base URL user-changeable (tunnel-proof).
class Api {
  static String base = '';
  static String token = '';
  static Map<String, dynamic>? profile;

  static const _defaultBase =
      'https://hidden-bush-188f.shivamjislt95288.workers.dev';

  static Future<void> loadSaved() async {
    final p = await SharedPreferences.getInstance();
    base = p.getString('base') ?? _defaultBase;
    token = p.getString('token') ?? '';
    final pr = p.getString('profile');
    profile = pr == null ? null : jsonDecode(pr) as Map<String, dynamic>;
  }

  static Future<void> saveSession(String t, Map<String, dynamic> pr) async {
    token = t;
    profile = pr;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', t);
    await p.setString('profile', jsonEncode(pr));
  }

  static Future<void> clearSession() async {
    token = '';
    profile = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('profile');
  }

  static Map<String, String> get _h => {
        if (token.isNotEmpty) 'X-Token': token,
      };

  static dynamic _decode(http.Response r) {
    dynamic d;
    try {
      d = jsonDecode(r.body);
    } catch (_) {
      d = r.body;
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      var msg = 'Error ${r.statusCode}';
      String? code;
      if (d is Map) {
        final det = d['detail'];
        if (det is Map) {
          code = det['code']?.toString();
          msg = (det['message'] ?? det['code'] ?? msg).toString();
        } else if (det != null) {
          msg = det.toString();
        }
      }
      throw ApiErr(msg, code: code, status: r.statusCode);
    }
    return d;
  }

  static Future<Map<String, dynamic>> login(
      String uid, String roll, [String? pw]) async {
    final body = {'unique_id': uid, 'roll_no': roll};
    if (pw != null) body['password'] = pw;
    final r = await http
        .post(Uri.parse('$base/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> register(
      String naam, String branch, String year, String roll) async {
    final r = await http
        .post(Uri.parse('$base/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'naam': naam,
              'branch': branch,
              'year': year,
              'roll_no': roll
            }))
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> setPassword(
      String uid, String roll, String pw) async {
    final r = await http
        .post(Uri.parse('$base/admin/set-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'unique_id': uid, 'roll_no': roll, 'password': pw}))
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> forgot(String uid, String roll) async {
    final r = await http
        .post(Uri.parse('$base/admin/forgot-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'unique_id': uid, 'roll_no': roll}))
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> resetPw(
      String uid, String roll, String code, String npw) async {
    final r = await http
        .post(Uri.parse('$base/admin/reset-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'unique_id': uid,
              'roll_no': roll,
              'code': code,
              'new_password': npw
            }))
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> calendar(int y, int m) async {
    final r = await http
        .get(Uri.parse('$base/calendar?year=$y&month=$m'), headers: _h)
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> stats() async {
    final r =
        await http.get(Uri.parse('$base/stats'), headers: _h).timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> mark(String status) async {
    final r = await http
        .post(Uri.parse('$base/attendance'),
            headers: {'Content-Type': 'application/json', ..._h},
            body: jsonEncode({'status': status}))
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> record(String date) async {
    final r = await http
        .get(Uri.parse('$base/record?date=${Uri.encodeComponent(date)}'),
            headers: _h)
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<ProofData> proof(String date, {bool thumb = true}) async {
    final uri = Uri.parse(
        '$base/holiday-proof?date=${Uri.encodeComponent(date)}${thumb ? '&thumb=1' : ''}');
    final req = http.Request('GET', uri);
    if (token.isNotEmpty) req.headers['X-Token'] = token;
    final resp = await req.send().timeout(const Duration(seconds: 30));
    final bytes =
        await resp.stream.toBytes().timeout(const Duration(seconds: 30));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Error ${resp.statusCode}');
    }
    return ProofData(
        (resp.headers['content-type'] ?? '').contains('image'), bytes);
  }

  static Future<Map<String, dynamic>> chat(String text) async {
    final r = await http
        .post(Uri.parse('$base/chat'),
            headers: {'Content-Type': 'application/json', ..._h},
            body: jsonEncode({'text': text}))
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> adminCount() async {
    final r = await http
        .get(Uri.parse('$base/admin/count'), headers: _h)
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> adminLookup(String key) async {
    final r = await http
        .get(Uri.parse('$base/admin/lookup?key=${Uri.encodeComponent(key)}'),
            headers: _h)
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<Map<String, dynamic>> holidayPreview(
      String date, String text) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('$base/admin/holiday?dry_run=true'));
    if (token.isNotEmpty) req.headers['X-Token'] = token;
    req.fields['date'] = date;
    req.fields['proof_text'] = text;
    final resp = await req.send().timeout(const Duration(seconds: 30));
    final body = await resp.stream.bytesToString();
    return Map<String, dynamic>.from(_decode(
        http.Response(body, resp.statusCode,
            headers: {'content-type': 'application/json'})) as Map);
  }

  static Future<Map<String, dynamic>> holidayDeclare(String date, String text,
      {String? photoPath, bool dry = false}) async {
    final req = http.MultipartRequest('POST',
        Uri.parse('$base/admin/holiday?dry_run=${dry ? 'true' : 'false'}'));
    if (token.isNotEmpty) req.headers['X-Token'] = token;
    req.fields['date'] = date;
    req.fields['proof_text'] = text;
    if (photoPath != null) {
      req.files.add(await http.MultipartFile.fromPath('proof', photoPath));
    }
    final resp = await req.send().timeout(const Duration(seconds: 60));
    final body = await resp.stream.bytesToString();
    return Map<String, dynamic>.from(_decode(
        http.Response(body, resp.statusCode,
            headers: {'content-type': 'application/json'})) as Map);
  }

  static Future<Map<String, dynamic>> adminRecall(String date) async {
    final r = await http
        .post(Uri.parse('$base/admin/recall'),
            headers: {'Content-Type': 'application/json', ..._h},
            body: jsonEncode({'date': date}))
        .timeout(const Duration(seconds: 30));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }
}

class ProofData {
  final bool isImage;
  final Uint8List bytes;
  ProofData(this.isImage, this.bytes);
}

class ApiErr implements Exception {
  final String message;
  final String? code;
  final int? status;
  ApiErr(this.message, {this.code, this.status});
  @override
  String toString() => message;
}
