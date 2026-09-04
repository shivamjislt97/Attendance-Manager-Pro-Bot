import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'theme.dart';

// ---------------- HOME SHELL (fixed bottom nav) ----------------
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int idx = 0;
  bool get isAdmin => Api.profile?['is_admin'] == true;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const HomeTab(),
      const CalTab(),
      const StatsTab(),
      const ChatTab(),
      if (isAdmin) const AdminTab(),
    ];
    final items = [
      const BottomNavigationBarItem(icon: Text('🏠', style: TextStyle(fontSize: 22)), label: 'Home'),
      const BottomNavigationBarItem(icon: Text('🗓️', style: TextStyle(fontSize: 22)), label: 'Calendar'),
      const BottomNavigationBarItem(icon: Text('📊', style: TextStyle(fontSize: 22)), label: 'Stats'),
      const BottomNavigationBarItem(icon: Text('💬', style: TextStyle(fontSize: 22)), label: 'Chat'),
      if (isAdmin)
        const BottomNavigationBarItem(icon: Text('🛠️', style: TextStyle(fontSize: 22)), label: 'Admin'),
      const BottomNavigationBarItem(icon: Text('🚪', style: TextStyle(fontSize: 22)), label: 'Exit'),
    ];
    final exitIdx = items.length - 1;
    return Scaffold(
      body: SafeArea(child: tabs[idx.clamp(0, tabs.length - 1)]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx.clamp(0, exitIdx - 1),
        onTap: (i) {
          if (i == exitIdx) {
            _confirmExit(context);
            return;
          }
          setState(() => idx = i);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0A1830),
        selectedItemColor: green,
        unselectedItemColor: mut,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        items: items,
      ),
    );
  }

  void _confirmExit(BuildContext context) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: card,
              title: const Text('⚠️ Account logout ho jayega!'),
              content: const Text('Kya logout karna hai?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('❌ NHI')),
                TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await Api.clearSession();
                      if (context.mounted) {
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()));
                      }
                    },
                    child: const Text('✅ HAA')),
              ],
            ));
  }
}

// ---------------- HOME ----------------
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String status = '⏳...';
  bool holiday = false;
  bool marked = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _today() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _load() async {
    try {
      final r = await Api.record(_today());
      if (!mounted) return;
      final st = (r['status'] ?? '').toString();
      setState(() {
        marked = st.isNotEmpty;
        holiday = (r['holiday'] ?? false) == true;
        status = marked
            ? '✅ Aaj ka status: $st'
            : (holiday
                ? '🏖️ AAJ TOH CHHUTTI HAI MOZ KARO 🎉'
                : '⏰ Aaj ki attendance abhi nahi lagi');
      });
    } catch (e) {
      if (mounted) setState(() => status = '❌ $e');
    }
  }

  Future<void> _mark(String s) async {
    setState(() => message = '⏳ Saving...');
    try {
      final r = await Api.mark(s);
      setState(() => message =
          '✅ Verify: ${r['date']} ka ${r['status']} save ho gaya!');
      _load();
    } catch (e) {
      setState(() => message = '❌ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final maze = !marked && holiday;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('😎 Namaste, ${Api.profile?['naam'] ?? 'Dost'}!',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text('📅 Aaj: ${_today()}', style: const TextStyle(color: mut)),
        const SizedBox(height: 10),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(12)),
            child: Text(status)),
        const SizedBox(height: 10),
        if (!maze)
          Row(children: [
            Expanded(
                child: ElevatedButton(
                    onPressed: () => _mark('PRESENT'),
                    child: const Text('😎 PRESENT HU'))),
            const SizedBox(width: 8),
            Expanded(
                child: ElevatedButton(
                    onPressed: () => _mark('CHHUTTI'),
                    style: ElevatedButton.styleFrom(backgroundColor: orange),
                    child: const Text('😁 CHHUTTI'))),
          ])
        else
          ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(backgroundColor: orange),
              child: const Text('🏖️ MAZE KARO AJJ')),
        if (message.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message,
                  style: const TextStyle(color: green))),
      ]),
    );
  }
}

// ---------------- CALENDAR ----------------
class CalTab extends StatefulWidget {
  const CalTab({super.key});
  @override
  State<CalTab> createState() => _CalTabState();
}

class _CalTabState extends State<CalTab> {
  late int y, m;
  Map<String, dynamic> days = {};
  bool loading = true;
  String sel = '';
  String detail = '';
  bool hasProof = false;
  Uint8List? proofImg;
  final cache = <String, Map<String, dynamic>>{};
  static const mon = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    y = n.year;
    m = n.month;
    _load();
  }

  Future<void> _load() async {
    final key = '$y-$m';
    if (cache.containsKey(key)) {
      setState(() {
        days = cache[key]!;
        loading = false;
      });
      return;
    }
    setState(() => loading = true);
    try {
      final r = await Api.calendar(y, m);
      cache[key] = r;
      if (!mounted) return;
      setState(() {
        days = r;
        loading = false;
      });
      // prefetch neighbours
      for (final dm in [-1, 1]) {
        var mm = m + dm, yy = y;
        if (mm < 1) { mm = 12; yy--; }
        if (mm > 12) { mm = 1; yy++; }
        final k = '$yy-$mm';
        if (!cache.containsKey(k)) {
          Api.calendar(yy, mm)
              .then((v) => cache[k] = v)
              .catchError((_) => {});
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          detail = '❌ $e';
        });
      }
    }
  }

  Color _cellColor(String marker) {
    switch (marker) {
      case 'present':
        return const Color(0xFF166534);
      case 'absent':
        return const Color(0xFF991B1B);
      case 'holiday':
        return const Color(0xFF854D0E);
      case 'chutti':
        return const Color(0xFF9A3412);
      default:
        return const Color(0xFF0F2038);
    }
  }

  Future<void> _showDay(String ds) async {
    setState(() {
      sel = ds;
      detail = '⏳...';
      hasProof = false;
      proofImg = null;
    });
    try {
      final r = await Api.record(ds);
      if (!mounted) return;
      final st = (r['status'] ?? '').toString();
      setState(() {
        detail = '🗓️ $ds\n' +
            (st.isNotEmpty
                ? 'Status: $st'
                : ((r['holiday'] ?? false) == true
                    ? '🏖️ COLLEGE BAND tha!'
                    : '❓ Koi record nahi'));
        hasProof = (r['has_proof'] ?? false) == true;
      });
    } catch (e) {
      if (mounted) setState(() => detail = '❌ $e');
    }
  }

  Future<void> _loadProof() async {
    try {
      final p = await Api.proof(sel, thumb: true);
      if (!mounted) return;
      if (p.isImage) {
        setState(() => proofImg = p.bytes);
      } else {
        setState(() => detail +=
            '\n😈😈 Hmm mujh per vishvash nhi hai 😤😤\n😎Abh toh bohot kush hoga 🦉');
      }
    } catch (e) {
      if (mounted) setState(() => detail += '\n❌ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(y, m, 1).weekday % 7;
    final n = DateTime(y, m + 1, 0).day;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(
              onPressed: () {
                setState(() {
                  m--;
                  if (m < 1) { m = 12; y--; }
                });
                _load();
              },
              icon: const Text('‹', style: TextStyle(fontSize: 28))),
          Text('${mon[m - 1]} $y',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          IconButton(
              onPressed: () {
                setState(() {
                  m++;
                  if (m > 12) { m = 1; y++; }
                });
                _load();
              },
              icon: const Text('›', style: TextStyle(fontSize: 28))),
        ]),
        const Text('🟢 Present  🔴 Absent  🟡 Holiday  🟠 Chhutti',
            style: TextStyle(color: mut, fontSize: 12)),
        const SizedBox(height: 8),
        if (loading)
          const Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(color: green))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.85),
          itemCount: first + n,
          itemBuilder: (_, i) {
            if (i < first) return const SizedBox();
            final d = i - first + 1;
            final ds =
                '${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y';
            final marker =
                (days[ds] as Map?)?['marker']?.toString() ?? 'none';
            return GestureDetector(
              onTap: () => _showDay(ds),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _cellColor(marker),
                  borderRadius: BorderRadius.circular(10),
                  border: sel == ds
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                ),
                child: Text('$d',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            );
          },
          ),
        if (detail.isNotEmpty)
          Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12)),
              child: Text(detail)),
        if (hasProof)
          ElevatedButton(
              onPressed: _loadProof,
              child: const Text('😈😈 PROOF CHAHIYE KYA 👹👹')),
        if (proofImg != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Image.memory(proofImg!, height: 220, fit: BoxFit.cover)),
      ]),
    );
  }
}

// ---------------- STATS ----------------
class StatsTab extends StatefulWidget {
  const StatsTab({super.key});
  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  Map<String, dynamic>? s;
  String err = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.stats();
      if (mounted) setState(() => s = r);
    } catch (e) {
      if (mounted) setState(() => err = '❌ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (err.isNotEmpty) return Padding(padding: const EdgeInsets.all(18), child: Text(err));
    if (s == null) {
      return const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator(color: green)));
    }
    final pct = (s!['percent'] as num).toDouble();
    final cards = [
      ['🎒 Khule din', s!['college_open']],
      ['🔒 Band din', s!['college_closed']],
      ['✅ Present', s!['present']],
      ['😁 Chhutti', s!['chutti']],
      ['🚫 Absent', s!['absent']],
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        const Text('📊 Meri Attendance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          width: 132,
          height: 132,
          child: CustomPaint(
            painter: _RingPainter(pct / 100),
            child: Center(
                child: Text('$pct%',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white))),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8),
          itemCount: cards.length,
          itemBuilder: (_, i) => Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(12)),
            child: Text('${cards[i][0]}\n${cards[i][1]}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double p;
  _RingPainter(this.p);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final bg = Paint()
      ..color = const Color(0xFF243B5C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    canvas.drawCircle(c, r - 7, bg);
    final fg = Paint()
      ..color = green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r - 7), -3.14159 / 2,
        2 * 3.14159 * p.clamp(0.0, 1.0), false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.p != p;
}

// ---------------- CHAT ----------------
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final msgs = <String>[];
  final inp = TextEditingController();
  final qs = ['0', '1', '2', '3', '4', '5', '6', '7'];

  Future<void> send(String t) async {
    setState(() => msgs.add('👤: $t'));
    try {
      final r = await Api.chat(t);
      var txt = "🤖: ${r['reply']}";
      if (r['options'] != null) {
        txt += '\n' + (r['options'] as List).join(' | ');
      }
      setState(() => msgs.add(txt));
    } catch (e) {
      setState(() => msgs.add('🤖: ❌ $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        const Text('💬 Bot Chat',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: qs
              .map((q) => ElevatedButton(
                  onPressed: () => send(q),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: surface,
                      minimumSize: const Size(64, 36),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8)),
                  child: Text(q, style: const TextStyle(fontSize: 12))))
              .toList(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(
                reverse: true,
                child: Text(msgs.join('\n\n'))),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: inp,
                  decoration: fld('0-7 ya DD/MM/YYYY...'))),
          const SizedBox(width: 8),
          ElevatedButton(
              onPressed: () {
                final t = inp.text.trim();
                if (t.isNotEmpty) {
                  inp.clear();
                  send(t);
                }
              },
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  padding: EdgeInsets.zero),
              child: const Text('➤')),
        ]),
      ]),
    );
  }
}

// ---------------- ADMIN ----------------
class AdminTab extends StatefulWidget {
  const AdminTab({super.key});
  @override
  State<AdminTab> createState() => _AdminTabState();
}

class _AdminTabState extends State<AdminTab> {
  final lookup = TextEditingController();
  final hday = TextEditingController();
  final htext = TextEditingController();
  final recallDay = TextEditingController();
  String countOut = '';
  String lookupOut = '';
  String adminMsg = '';
  String previewOut = '';
  String recallOut = '';
  bool recallArmed = false;
  bool countVisible = false;
  bool lookupVisible = false;
  bool previewVisible = false;
  bool recallVisible = false;
  final picker = ImagePicker();
  String? photoPath;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🛠️ Admin',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ElevatedButton(
            onPressed: () async {
              try {
                final c = await Api.adminCount();
                setState(() {
                  countVisible = true;
                  countOut =
                      '👥 Total: ${c['total']}\n🏷️ ${c['by_branch']}\n🎓 ${c['by_year']}\n🧮 ${c['matrix']}';
                });
              } catch (e) {
                setState(() {
                  countVisible = true;
                  countOut = '❌ $e';
                });
              }
            },
            child: const Text('👥 Students Count')),
        if (countVisible)
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12)),
              child: Text(countOut)),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: lookup,
                  decoration: fld('Roll / chat id / STU ID'))),
          const SizedBox(width: 8),
          ElevatedButton(
              onPressed: () async {
                try {
                  final r = await Api.adminLookup(lookup.text.trim());
                  final st = r['student'];
                  final s = r['stats'];
                  setState(() {
                    lookupVisible = true;
                    lookupOut =
                        '👤 ${st['naam']} | ${st['branch']} | ${st['roll_no']}\n📊 ${s['percent']}% (${s['present']}/${s['college_open']})';
                  });
                } catch (e) {
                  setState(() {
                    lookupVisible = true;
                    lookupOut = '❌ $e';
                  });
                }
              },
              child: const Text('🔍')),
        ]),
        if (lookupVisible)
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12)),
              child: Text(lookupOut)),
        const Text('🏖️ Holiday declare',
            style: TextStyle(fontWeight: FontWeight.bold)),
        TextField(controller: hday, decoration: fld('DD/MM/YYYY')),
        TextField(controller: htext, decoration: fld('Notice text (optional)')),
        Row(children: [
          Expanded(
              child: ElevatedButton(
                  onPressed: () async {
                    final x = await picker.pickImage(
                        source: ImageSource.gallery);
                    if (x != null) {
                      setState(() => photoPath = x.path);
                      if (mounted) msg(context, '📎 Photo lagi: ${x.name}');
                    }
                  },
                  child: Text(photoPath == null ? '📎 Photo' : '📎 Photo ✅'))),
        ]),
        Row(children: [
          Expanded(
              child: ElevatedButton(
                  onPressed: () => _holiday(true),
                  child: const Text('👁️ Preview'))),
          const SizedBox(width: 8),
          Expanded(
              child: ElevatedButton(
                  onPressed: () => _holiday(false),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: orange),
                  child: const Text('Declare karo'))),
        ]),
        if (previewVisible)
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12)),
              child: Text(previewOut)),
        const Text('🗑️ Broadcast recall (admin-only)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: recallDay, decoration: fld('DD/MM/YYYY'))),
          const SizedBox(width: 8),
          ElevatedButton(
              onPressed: () async {
                final day = recallDay.text.trim();
                if (!recallArmed || _armedDay != day) {
                  setState(() {
                    recallArmed = true;
                    _armedDay = day;
                    recallVisible = true;
                    recallOut =
                        '⚠️ Pakka? $day ka broadcast delete hoga. Confirm: dobara dabao.';
                  });
                  return;
                }
                setState(() {
                  recallArmed = false;
                  recallOut = '...';
                });
                try {
                  final r = await Api.adminRecall(day);
                  setState(() => recallOut =
                      '🗑️ Deleted: ${r['deleted']} | Failed: ${r['failed']}');
                } catch (e) {
                  setState(() => recallOut = '❌ $e');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: orange),
              child: const Text('Recall')),
        ]),
        if (recallVisible)
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12)),
              child: Text(recallOut)),
        if (adminMsg.isNotEmpty) Text(adminMsg),
      ]),
    );
  }

  String _armedDay = '';

  Future<void> _holiday(bool dry) async {
    try {
      final r = await Api.holidayDeclare(
          hday.text.trim(), htext.text.trim(),
          photoPath: photoPath, dry: dry);
      setState(() {
        if (dry) {
          previewVisible = true;
          previewOut = '👁️ Preview:\n' + (r['preview'] ?? '').toString();
        } else {
          adminMsg =
              '🏖️ Holiday declare! ${r['date']} | ${r['updated']} entries | broadcast ${r['broadcast_ok']}/${r['broadcast_fail']}';
        }
      });
    } catch (e) {
      setState(() => adminMsg = '❌ $e');
    }
  }
}
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final uid = TextEditingController();
  final roll = TextEditingController();
  final pw = TextEditingController();
  final npw1 = TextEditingController();
  final npw2 = TextEditingController();
  final code = TextEditingController();
  final rpw = TextEditingController();
  final rNaam = TextEditingController();
  final rBranch = TextEditingController();
  final rYear = TextEditingController();
  final rRoll = TextEditingController();
  String mode = 'login'; // login | pw | set | forgot | reg
  String err = '';
  String okMsg = '';

  void enterApp(Map<String, dynamic> d) async {
    await Api.saveSession(d['token'] as String, d);
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  Future<void> doLogin([String? password]) async {
    setState(() => err = '');
    try {
      enterApp(await Api.login(uid.text.trim(), roll.text.trim(), password));
    } on ApiErr catch (e) {
      if (e.message.contains('pehle admin password') ||
          e.message.contains('password_not_set')) {
        setState(() {
          mode = 'set';
          err = '🔑 $e';
        });
      } else if (e.message.contains('Admin password') ||
          e.message.contains('password_required')) {
        setState(() {
          mode = 'pw';
          err = '🔒 Admin hai — password do 👇';
        });
      } else {
        setState(() => err = '❌ $e');
      }
    } catch (e) {
      setState(() => err = '❌ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(colors: [
                    Colors.white,
                    Color(0xFFDBE7FF)
                  ]),
                ),
                child: const Center(
                    child: Text('🎒', style: TextStyle(fontSize: 40))),
              ),
              const SizedBox(height: 10),
              const Text('Attendance App',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const Text('Student Check-In Portal',
                  style: TextStyle(color: mut)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FF),
                  borderRadius: BorderRadius.circular(20),
                  border: const Border(
                      top: BorderSide(color: green, width: 5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('UNIQUE ID / ROLL NUMBER',
                        style: TextStyle(
                            color: Color(0xFF0B1C30),
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                    TextField(
                        controller: uid,
                        style: const TextStyle(color: Color(0xFF0B1C30)),
                        decoration: fld('STU-XXXXXXXX').copyWith(
                            fillColor: const Color(0xFFEEF2F9))),
                    const Center(
                        child: Text('— OR —',
                            style: TextStyle(color: mut, fontSize: 12))),
                    TextField(
                        controller: roll,
                        style: const TextStyle(color: Color(0xFF0B1C30)),
                        decoration: fld('Roll Number').copyWith(
                            fillColor: const Color(0xFFEEF2F9))),
                    const Center(
                        child: Text('Koi ek chalega — UNIQUE ID ya Roll',
                            style: TextStyle(color: mut, fontSize: 12))),
                    const SizedBox(height: 8),
                    ElevatedButton(
                        onPressed: () => doLogin(), child: const Text('Login ➜')),
                    if (err.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(err,
                              style: const TextStyle(color: red))),
                    if (okMsg.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(okMsg,
                              style: const TextStyle(color: greenD))),
                    if (mode == 'pw') ...[
                      const SizedBox(height: 10),
                      const Text('🔒 ADMIN PASSWORD',
                          style: TextStyle(
                              color: Color(0xFF0B1C30),
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                      TextField(
                          controller: pw,
                          obscureText: true,
                          style: const TextStyle(color: Color(0xFF0B1C30)),
                          decoration: fld('Admin password').copyWith(
                              fillColor: const Color(0xFFEEF2F9))),
                      ElevatedButton(
                          onPressed: () => doLogin(pw.text),
                          child: const Text('Admin Login ➜')),
                      TextButton(
                          onPressed: () =>
                              setState(() => mode = 'forgot'),
                          child: const Text('Forgot password?')),
                    ],
                    if (mode == 'set') ...[
                      const SizedBox(height: 10),
                      const Text('🔑 PEHLI BAAR — PASSWORD SET KARO',
                          style: TextStyle(
                              color: Color(0xFF0B1C30),
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                      TextField(
                          controller: npw1,
                          obscureText: true,
                          style: const TextStyle(color: Color(0xFF0B1C30)),
                          decoration: fld('Naya password (min 4)').copyWith(
                              fillColor: const Color(0xFFEEF2F9))),
                      TextField(
                          controller: npw2,
                          obscureText: true,
                          style: const TextStyle(color: Color(0xFF0B1C30)),
                          decoration: fld('Dobara likho').copyWith(
                              fillColor: const Color(0xFFEEF2F9))),
                      ElevatedButton(
                          onPressed: () async {
                            if (npw1.text != npw2.text) {
                              setState(() => err =
                                  '❌ Dono password same likho');
                              return;
                            }
                            try {
                              await Api.setPassword(uid.text.trim(),
                                  roll.text.trim(), npw1.text);
                              setState(() {
                                mode = 'pw';
                                err = '';
                                okMsg =
                                    '✅ Password set! Ab Admin Login dabao 👇';
                              });
                            } catch (e) {
                              setState(() => err = '❌ $e');
                            }
                          },
                          child: const Text('Set Password ➜')),
                    ],
                    if (mode == 'forgot') ...[
                      const SizedBox(height: 10),
                      const Text('🔑 RESET CODE (Telegram par aayega)',
                          style: TextStyle(
                              color: Color(0xFF0B1C30),
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                      ElevatedButton(
                          onPressed: () async {
                            try {
                              await Api.forgot(
                                  uid.text.trim(), roll.text.trim());
                              setState(() => okMsg =
                                  '✅ Code Telegram par bhej diya! 📩');
                            } catch (e) {
                              setState(() => err = '❌ $e');
                            }
                          },
                          child: const Text('Telegram par code bhejo')),
                      TextField(
                          controller: code,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Color(0xFF0B1C30)),
                          decoration: fld('6-digit code').copyWith(
                              fillColor: const Color(0xFFEEF2F9))),
                      TextField(
                          controller: rpw,
                          obscureText: true,
                          style: const TextStyle(color: Color(0xFF0B1C30)),
                          decoration: fld('Naya password (min 4)').copyWith(
                              fillColor: const Color(0xFFEEF2F9))),
                      ElevatedButton(
                          onPressed: () async {
                            try {
                              await Api.resetPw(
                                  uid.text.trim(),
                                  roll.text.trim(),
                                  code.text.trim(),
                                  rpw.text);
                              setState(() {
                                mode = 'pw';
                                okMsg =
                                    '✅ Reset! Ab password se login karo 👇';
                              });
                            } catch (e) {
                              setState(() => err = '❌ $e');
                            }
                          },
                          child: const Text('Reset karo ➜')),
                    ],
                    TextButton(
                        onPressed: () => setState(() => mode =
                            mode == 'reg' ? 'login' : 'reg'),
                        child: const Text('Naya ho? Register karo 📝')),
                    if (mode == 'reg') ...[
                      TextField(
                          controller: rNaam,
                          style: const TextStyle(color: Color(0xFF0B1C30)),
                          decoration: fld('Apna naam').copyWith(
                              fillColor: const Color(0xFFEEF2F9))),
                      TextField(
                          controller: rBranch,
                          style: const TextStyle(color: Color(0xFF0B1C30)),
                          decoration: fld('Branch (CS/IT/EC/ME)').copyWith(
                              fillColor: const Color(0xFFEEF2F9))),
                      TextField(
                          controller: rYear,
                          style: const TextStyle(color: Color(0xFF0B1C30)),
                          decoration: fld('Year (1st Year...)').copyWith(
                              fillColor: const Color(0xFFEEF2F9))),
                      TextField(
                          controller: rRoll,
                          style: const TextStyle(color: Color(0xFF0B1C30)),
                          decoration: fld('Roll number').copyWith(
                              fillColor: const Color(0xFFEEF2F9))),
                      ElevatedButton(
                          onPressed: () async {
                            try {
                              final r = await Api.register(
                                  rNaam.text.trim(),
                                  rBranch.text.trim(),
                                  rYear.text.trim(),
                                  rRoll.text.trim());
                              uid.text = r['unique_id'].toString();
                              roll.text = r['roll_no'].toString();
                              setState(() => okMsg =
                                  '🎉 COMPLETE! 🆔 ${r['unique_id']}');
                            } catch (e) {
                              setState(() => err = '❌ $e');
                            }
                          },
                          child: const Text('Register ➜')),
                    ],
                  ],
                ),
              ),
              TextButton(
                  onPressed: () => _serverDialog(context),
                  child: const Text('⚙️ Server setting',
                      style: TextStyle(color: mut))),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _serverDialog(BuildContext context) async {
    final c = TextEditingController(text: Api.base);
    final v = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Server URL'),
              content: TextField(controller: c),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(context, c.text.trim()),
                    child: const Text('Save')),
              ],
            ));
    if (v != null && v.isNotEmpty) {
      Api.base = v.replaceAll(RegExp(r'/+$'), '');
      final p = await SharedPreferences.getInstance();
      await p.setString('base', Api.base);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Server: ${Api.base}')));
      }
    }
  }
}
