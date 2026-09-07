import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
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
      backgroundColor: bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SafeArea(child: tabs[idx.clamp(0, tabs.length - 1)]),
        ),
      ),
      bottomNavigationBar: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xF20A1830),
              border: Border(top: BorderSide(color: line)),
            ),
            child: BottomNavigationBar(
              currentIndex: idx.clamp(0, exitIdx - 1),
              onTap: (i) {
                if (i == exitIdx) {
                  _confirmExit(context);
                  return;
                }
                setState(() => idx = i);
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: green,
              unselectedItemColor: mut,
              selectedFontSize: 10,
              unselectedFontSize: 10,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
              items: items.map((e) {
                final isSel = items.indexOf(e) == idx.clamp(0, exitIdx - 1);
                return BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.only(top: 3),
                    decoration: isSel ? const BoxDecoration(border: Border(top: BorderSide(color: green, width: 3))) : null,
                    child: e.icon,
                  ),
                  label: e.label,
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmExit(BuildContext context) {
    showDialog(
        context: context,
        barrierColor: const Color(0xA6000000),
        builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [card, Color(0xFF0F2038)]),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: line),
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 18))],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('⚠️ Account logout ho jayega!\nKya logout karna hai?',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.7)),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: ElevatedButton(onPressed: () async { Navigator.pop(context); await Api.clearSession(); if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }, child: const Text('✅ HAA'))),
                      const SizedBox(width: 10),
                      Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: orange), child: const Text('❌ NHI'))),
                    ]),
                  ]),
                ),
              ),
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
  List notices = [];
  List activity = [];
  String noticesErr = '';

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
    _loadNotices();
  }

  Future<void> _loadNotices() async {
    try {
      final r = await Api.notices();
      if (!mounted) return;
      setState(() {
        notices = (r['notices'] as List?) ?? [];
        activity = (r['activity'] as List?) ?? [];
        noticesErr = '';
      });
    } catch (e) {
      if (mounted) setState(() => noticesErr = '❌ $e');
    }
  }

  Future<void> _viewProof(String ds) async {
    try {
      final p = await Api.proof(ds, thumb: true);
      if (!mounted) return;
      if (p.isImage) {
        showDialog(context: context, builder: (_) => AlertDialog(content: Image.memory(p.bytes)));
      } else {
        msg(context, utf8.decode(p.bytes));
      }
    } catch (e) {
      if (mounted) msg(context, '❌ $e');
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('😎 Namaste, ${Api.profile?['naam'] ?? 'Dost'}!',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        Text('📅 Aaj: ${_today()}', style: const TextStyle(color: mut, fontSize: 14)),
        const SizedBox(height: 10),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [card, Color(0xFF0F2038)]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: line),
                boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8))]),
            child: Text(status, style: const TextStyle(fontSize: 14, height: 1.6))),
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
                    onPressed: () => _mark('ABSENT'),
                    style: ElevatedButton.styleFrom(backgroundColor: orange),
                    child: const Text('🚫 ABSENT HU'))),
          ])
        else
          ElevatedButton(
              onPressed: () async {
                try {
                  final p = await Api.proof(_today(), thumb: true);
                  if (!mounted) return;
                  if (p.isImage) {
                    showDialog(context: context, builder: (_) => AlertDialog(content: Image.memory(p.bytes)));
                  } else {
                    msg(context, utf8.decode(p.bytes));
                  }
                } catch (e) {
                  if (mounted) msg(context, '❌ $e');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: orange),
              child: const Text('🏖️ MAZE KARO AJJ')),
        if (message.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message,
                  style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 14))),
        const SizedBox(height: 14),
        InkWell(
          onTap: () async {
            const url = 'https://t.me/attendance_manager_pro_bot';
            try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {}
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
                color: const Color(0xFF229ED9),
                borderRadius: BorderRadius.circular(999)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.send, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('@attendance_manager_pro_bot on Telegram',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        // Bot Messages window - telegram ke niche wala card (web jaisa)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [card, Color(0xFF0F2038)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
            boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📢 Bot Messages',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: mut)),
            const SizedBox(height: 6),
            if (noticesErr.isNotEmpty) Text(noticesErr, style: const TextStyle(color: red, fontSize: 12)),
            if (notices.isEmpty && noticesErr.isEmpty)
              const Text('(koi notice nahi)', style: TextStyle(color: mut, fontSize: 13))
            else
              ...notices.map((n) => InkWell(
                onTap: () => _viewProof(n['date'].toString()),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
                  child: Text('🏖️ ${n['date']} — ${n['tag']}', style: const TextStyle(fontSize: 13)),
                ),
              )),
            const SizedBox(height: 10),
            const Text('🧾 Meri activity',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: mut)),
            const SizedBox(height: 6),
            if (activity.isEmpty)
              const Text('(koi record nahi)', style: TextStyle(color: mut, fontSize: 13))
            else
              ...activity.map((a) => Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
                child: Text('${a['emoji'] ?? '•'} ${a['date']} — ${a['status']}', style: const TextStyle(fontSize: 13)),
              )),
          ]),
        ),
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
      // api returns {"days": { "DD/MM/YYYY": {"marker":...}}}
      final extracted = (r['days'] as Map?) ?? r;
      final dmap = Map<String, dynamic>.from(extracted as Map);
      cache[key] = dmap;
      if (!mounted) return;
      setState(() {
        days = dmap;
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
              .then((v) {
                final ex = (v['days'] as Map?) ?? v;
                cache[k] = Map<String, dynamic>.from(ex as Map);
                return null;
              }, onError: (_) => null);
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

  // Web styles.css matching: rgba + border + shadow
  Color _cellColor(String marker) {
    switch (marker) {
      case 'present':
        return const Color(0x6B22C55E); // rgba(34,197,94,.42)
      case 'absent':
        return const Color(0x4DEF4444); // rgba(239,68,68,.30)
      case 'holiday':
        return const Color(0x6BEAB308); // rgba(234,179,8,.42)
      case 'chutti':
        return const Color(0x52F97316); // rgba(249,115,22,.32)
      case 'future':
      case 'none':
      case 'closed':
      default:
        return const Color(0xFF0F2038);
    }
  }

  Color _borderColor(String marker) {
    switch (marker) {
      case 'present':
        return const Color(0xFF4ADE80);
      case 'absent':
        return red;
      case 'holiday':
        return const Color(0xFFFACC15);
      case 'chutti':
        return orange;
      default:
        return Colors.transparent;
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () { setState(() { m--; if (m < 1) { m = 12; y--; }}); _load(); },
              child: const Center(child: Text('‹', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            ),
          ),
          Text('${mon[m - 1]} $y',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () { setState(() { m++; if (m > 12) { m = 1; y++; }}); _load(); },
              child: const Center(child: Text('›', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 6, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 11, height: 11, decoration: const BoxDecoration(shape: BoxShape.circle, color: green, boxShadow: [BoxShadow(color: green, blurRadius: 6)] )), const SizedBox(width: 5), const Text('Present', style: TextStyle(color: mut, fontSize: 12))]),
          Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 11, height: 11, decoration: const BoxDecoration(shape: BoxShape.circle, color: red, boxShadow: [BoxShadow(color: red, blurRadius: 6)] )), const SizedBox(width: 5), const Text('Absent', style: TextStyle(color: mut, fontSize: 12))]),
          Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 11, height: 11, decoration: const BoxDecoration(shape: BoxShape.circle, color: yellow, boxShadow: [BoxShadow(color: yellow, blurRadius: 6)] )), const SizedBox(width: 5), const Text('Holiday', style: TextStyle(color: mut, fontSize: 12))]),
          Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 11, height: 11, decoration: const BoxDecoration(shape: BoxShape.circle, color: red, boxShadow: [BoxShadow(color: red, blurRadius: 6)] )), const SizedBox(width: 5), const Text('Absent', style: TextStyle(color: mut, fontSize: 12))]),
        ]),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(color: green))
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
            child: Column(children: [
              // DOW header
              Row(children: ['S','M','T','W','T','F','S'].map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(color: mut, fontSize: 11, fontWeight: FontWeight.w700))))).toList()),
              const SizedBox(height: 7),
              GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
              childAspectRatio: 0.85),
          itemCount: first + n,
          itemBuilder: (_, i) {
            if (i < first) return const SizedBox();
            final d = i - first + 1;
            final ds =
                '${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y';
            final marker =
                (days[ds] as Map?)?['marker']?.toString() ?? 'none';
            final isFuture = marker == 'future' || marker == 'none' || marker == 'closed';
            return GestureDetector(
              onTap: () => _showDay(ds),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _cellColor(marker),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: sel == ds ? Colors.white : _borderColor(marker),
                    width: sel == ds ? 2 : 1,
                  ),
                  boxShadow: (marker == 'present' || marker == 'holiday')
                      ? [BoxShadow(color: _borderColor(marker).withValues(alpha: .45), blurRadius: 10)]
                      : (marker == 'absent' || marker == 'chutti')
                          ? [BoxShadow(color: _borderColor(marker).withValues(alpha: .35), blurRadius: 8)]
                          : null,
                ),
                child: Opacity(
                  opacity: isFuture ? .55 : 1,
                  child: Text('$d',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: (marker == 'present' || marker == 'holiday') ? FontWeight.w800 : FontWeight.bold,
                          fontSize: 13)),
                ),
              ),
            );
          },
          ),
            ]),
          ),
        if (detail.isNotEmpty)
          Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [card, Color(0xFF0F2038)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: line),
                  boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8))]),
              child: Text(detail, style: const TextStyle(fontSize: 14, height: 1.6))),
        if (hasProof)
          Padding(padding: const EdgeInsets.only(top: 8), child: ElevatedButton(
              onPressed: _loadProof,
              child: const Text('😈😈 PROOF CHAHIYE KYA 👹👹'))),
        if (proofImg != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(proofImg!, height: 220, fit: BoxFit.cover))),
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
      ['🏖️ Chhutti (declared)', s!['chutti']],
      ['🚫 Absent', s!['absent']],
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      child: Column(children: [
        const Text('📊 Meri Attendance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3)),
        const SizedBox(height: 12),
        Container(
          width: 132, height: 132,
          decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x4022C55E), blurRadius: 28, offset: Offset(0, 8))]),
          child: CustomPaint(
            painter: _RingPainter(pct / 100),
            child: Center(
                child: Text('${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}%',
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
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.4),
          itemCount: cards.length,
          itemBuilder: (_, i) => Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [card, Color(0xFF0F2038)]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: line),
                boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8))]),
            child: Text('${cards[i][0]}\n${cards[i][1]}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.6)),
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
  final msgs = <Map<String, String>>[]; // {who, text}
  final inp = TextEditingController();
  final ScrollController _sc = ScrollController();
  // Web jaisa: code + label
  final qs = const [
    {'code': '0', 'label': '0. % kitni hai?'},
    {'code': '1', 'label': '1. kitne din gaya'},
    {'code': '2', 'label': '2. chhutti'},
    {'code': '3', 'label': '3. khula tha'},
    {'code': '4', 'label': '4. band tha'},
    {'code': '5', 'label': '5. mahine ka record'},
    {'code': '6', 'label': '6. absent dates'},
    {'code': '7', 'label': '7. present dates'},
  ];

  Future<void> send(String t) async {
    setState(() => msgs.add({'who': 'me', 'text': t}));
    _jump();
    try {
      final r = await Api.chat(t);
      var txt = (r['reply'] ?? '').toString();
      if (r['options'] != null) {
        txt += '\n\nOptions: ' + (r['options'] as List).join(' | ');
      }
      if (r['has_proof'] == true && r['proof_date'] != null) {
        txt += '\n(has proof — calendar me dekho)';
      }
      setState(() => msgs.add({'who': 'bot', 'text': txt}));
    } catch (e) {
      setState(() => msgs.add({'who': 'bot', 'text': '❌ $e'}));
    }
    _jump();
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      child: Column(children: [
        const Text('💬 Bot Chat',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: qs
              .map((q) => ElevatedButton(
                  onPressed: () => send(q['code']!),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: surface,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      side: const BorderSide(color: line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  child: Text(q['label']!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))))
              .toList(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            height: 320,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFF0F2038),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: line)),
            child: msgs.isEmpty
                ? const Text('👆 upar se 0-7 ya DD/MM/YYYY bhejo',
                    style: TextStyle(color: mut, fontSize: 13))
                : ListView.builder(
                    controller: _sc,
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final m = msgs[i];
                      final isMe = m['who'] == 'me';
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0x1F22C55E)
                                : surface,
                            borderRadius: BorderRadius.circular(10),
                            border: isMe ? null : Border.all(color: line),
                          ),
                          child: Text(
                            m['text']!,
                            textAlign: isMe ? TextAlign.right : TextAlign.left,
                            style: TextStyle(
                                color: isMe ? const Color(0xFF86EFAC) : txt,
                                fontSize: 14, height: 1.4),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: inp,
                  onSubmitted: (v) {
                    final t = v.trim();
                    if (t.isNotEmpty) {
                      inp.clear();
                      send(t);
                    }
                  },
                  decoration: fld('0-7 ya DD/MM/YYYY...'))),
          const SizedBox(width: 10),
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
  final bmsg = TextEditingController();
  final bbranch = TextEditingController();
  final byear = TextEditingController();
  String countOut = '';
  String lookupOut = '';
  String adminMsg = '';
  String previewOut = '';
  String recallOut = '';
  String bcastOut = '';
  String bcastListTxt = '';
  bool recallArmed = false;
  bool countVisible = false;
  bool lookupVisible = false;
  bool previewVisible = false;
  bool recallVisible = false;
  bool bcastVisible = false;
  bool bcastListVisible = false;
  final picker = ImagePicker();
  String? photoPath;
  String? bphotoPath;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final r = await Api.adminBroadcasts();
      final batches = r['batches'] as List? ?? [];
      if (!mounted) return;
      setState(() {
        if (batches.isEmpty) {
          bcastListVisible = false;
        } else {
          bcastListVisible = true;
          bcastListTxt = batches
              .map((b) => '📢 ${b['day']} → ${b['count']} msgs (${b['batch']})')
              .join('\n');
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🛠️ Admin',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3)),
        const SizedBox(height: 8),
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
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
              child: Text(countOut, style: const TextStyle(fontSize: 13))),
        const SizedBox(height: 10),
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
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
              child: Text(lookupOut, style: const TextStyle(fontSize: 13))),
        const SizedBox(height: 14),
        const Text('📢 Broadcast (admin-only)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: .8, color: mut)),
        TextField(controller: bmsg, maxLines: 3, decoration: fld('Message (sabko/filter karke)')),
        Row(children: [
          Expanded(child: TextField(controller: bbranch, decoration: fld('Branch (All/CS/IT/EC/ME)'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: byear, decoration: fld('Year (All/1st Year...)'))),
        ]),
        Row(children: [
          Expanded(
              child: ElevatedButton(
                  onPressed: () async {
                    final x = await picker.pickImage(source: ImageSource.gallery);
                    if (x != null) {
                      setState(() => bphotoPath = x.path);
                      if (mounted) msg(context, '📎 Photo lagi: ${x.name}');
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: surface, side: const BorderSide(color: line)),
                  child: Text(bphotoPath == null ? '📎 Photo' : '📎 Photo ✅',
                      style: const TextStyle(fontSize: 13)))),
        ]),
        Row(children: [
          Expanded(
              child: ElevatedButton(
                  onPressed: () async {
                    try {
                      final r = await Api.broadcastPreview(
                          bmsg.text.trim(), bbranch.text.trim(), byear.text.trim(), bphotoPath);
                      setState(() {
                        bcastVisible = true;
                        bcastOut = '👁️ Preview (${r['recipients']} users ko jayega):\n\n${r['preview']}\n\nTo: ${(r['to'] as List? ?? []).join(', ')}';
                      });
                    } catch (e) {
                      setState(() {
                        bcastVisible = true;
                        bcastOut = '❌ $e';
                      });
                    }
                  },
                  child: const Text('👁️ Preview'))),
          const SizedBox(width: 8),
          Expanded(
              child: ElevatedButton(
                  onPressed: () async {
                    try {
                      final r = await Api.broadcastSend(
                          bmsg.text.trim(), bbranch.text.trim(), byear.text.trim(), bphotoPath);
                      setState(() {
                        bcastVisible = true;
                        bcastOut = '📢 Ho gaya! 👥 ${r['recipients']} target | ✅ ${r['sent']} bheja, ❌ ${r['failed']} fail\nBatch: ${r['batch']}';
                      });
                      _loadBatches();
                    } catch (e) {
                      setState(() {
                        bcastVisible = true;
                        bcastOut = '❌ $e';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: orange),
                  child: const Text('📢 Send'))),
        ]),
        if (bcastVisible)
          Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
              child: Text(bcastOut, style: const TextStyle(fontSize: 13))),
        if (bcastListVisible)
          Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Recent batches', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: mut)),
                  InkWell(onTap: _loadBatches, child: const Text('↻ refresh', style: TextStyle(color: green, fontSize: 12))),
                ]),
                const SizedBox(height: 6),
                Text(bcastListTxt, style: const TextStyle(fontSize: 12)),
              ])),
        const SizedBox(height: 14),
        const Text('🏖️ Holiday declare',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: .8, color: mut)),
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
                  style: ElevatedButton.styleFrom(backgroundColor: surface, side: const BorderSide(color: line)),
                  child: Text(photoPath == null ? '📎 Photo' : '📎 Photo ✅', style: const TextStyle(fontSize: 13)))),
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
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
              child: Text(previewOut, style: const TextStyle(fontSize: 13))),
        if (adminMsg.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(adminMsg, style: const TextStyle(color: green, fontSize: 13))),
        const SizedBox(height: 14),
        const Text('🗑️ Broadcast recall (admin-only)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: .8, color: mut)),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: recallDay, decoration: fld('DD/MM/YYYY ya g... batch'))),
          const SizedBox(width: 8),
          ElevatedButton(
              onPressed: () async {
                final day = recallDay.text.trim();
                // batch vs date
                final isBatch = day.startsWith('g');
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
                  final r = isBatch ? await Api.adminRecallBatch(day) : await Api.adminRecall(day);
                  setState(() => recallOut =
                      '🗑️ Deleted: ${r['deleted']} | Failed: ${r['failed']}');
                  _loadBatches();
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
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
              child: Text(recallOut, style: const TextStyle(fontSize: 13))),
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

  String _humanHostErr(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('failed host lookup') || s.contains('no address associated') || s.contains('errno = 7')) {
      return '❌ Server DNS fail — auto fallback try kiya.\n'
          'Agar ab bhi fail ho to ⚙️ Server setting me direct tunnel paste karo:\n'
          'https://column-emperor-ship-identifier.trycloudflare.com\n'
          'Ya WiFi/mobile data badlo, Private DNS OFF karo.';
    }
    return '❌ $e';
  }

  Future<void> doLogin([String? password]) async {
    setState(() { err = ''; okMsg = ''; });
    try {
      final d = await Api.login(uid.text.trim(), roll.text.trim(), password);
      // if fallback switch hua to user ko batao
      if (Api.base.contains('trycloudflare.com') && Api.base != Api.defaultBaseForUi) {
        setState(() => okMsg = '⚠️ Worker DNS fail tha — direct tunnel par auto-switch ho gaya. ✅');
      }
      enterApp(d);
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
      final msg = _humanHostErr(e);
      setState(() => err = msg);
      if (msg.contains('Server DNS fail')) {
        // fallback already tried inside Api._withFallback; if still fails, offer server dialog
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted && msg.contains('Server DNS fail')) msgToast();
          });
        }
      }
    }
  }

  void msgToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('DNS fail — ⚙️ Server setting kholo aur direct tunnel try karo'),
        action: SnackBarAction(label: 'Open', onPressed: () => _serverDialog(context)),
      ),
    );
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
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFDBE7FF)]),
                  boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, 10))],
                ),
                child: const Center(
                    child: Text('🎒', style: TextStyle(fontSize: 40))),
              ),
              const SizedBox(height: 10),
              const Text('Attendance Manager Pro',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const Text('Student Check-In Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mut, fontSize: 14)),
              const SizedBox(height: 10),
              // Telegram pill - web .tg-link exact
              InkWell(
                onTap: () async {
                  const url = 'https://t.me/attendance_manager_pro_bot';
                  try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {}
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: const Color(0xFF229ED9), borderRadius: BorderRadius.circular(999)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.send, color: Colors.white, size: 14),
                    SizedBox(width: 6),
                    Text('Telegram: @attendance_manager_pro_bot',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FF),
                  borderRadius: BorderRadius.circular(20),
                  border: const Border(
                      top: BorderSide(color: green, width: 5)),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 14))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('UNIQUE ID / ROLL NUMBER',
                        style: TextStyle(
                            color: Color(0xFF0B1C30),
                            fontWeight: FontWeight.w800,
                            fontSize: 12, letterSpacing: 1)),
                    TextField(
                        controller: uid,
                        style: const TextStyle(color: Color(0xFF0B1C30)),
                        decoration: fld('STU-XXXXXXXX').copyWith(
                            fillColor: const Color(0xFFEEF2F9),
                            hintStyle: const TextStyle(color: Color(0xFF8FA0BB)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD4DDED))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: green, width: 2)))),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Expanded(child: Divider(color: Color(0xFFD4DDED), thickness: 1)),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('OR', style: TextStyle(color: Color(0xFF5B7191), fontSize: 12, fontWeight: FontWeight.w700))),
                      const Expanded(child: Divider(color: Color(0xFFD4DDED), thickness: 1)),
                    ]),
                    const SizedBox(height: 4),
                    TextField(
                        controller: roll,
                        style: const TextStyle(color: Color(0xFF0B1C30)),
                        decoration: fld('Roll Number').copyWith(
                            fillColor: const Color(0xFFEEF2F9),
                            hintStyle: const TextStyle(color: Color(0xFF8FA0BB)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD4DDED))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: green, width: 2)))),
                    const Center(
                        child: Padding(padding: EdgeInsets.only(top: 6), child: Text('Koi ek chalega — UNIQUE ID ya Roll', style: TextStyle(color: Color(0xFF5B7191), fontSize: 12)))),
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
                          child: const Text('Forgot password?', style: TextStyle(color: greenD, fontSize: 13, fontWeight: FontWeight.w700))),
                    ],
                    if (mode == 'set') ...[
                      Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.only(top: 12), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFD4DDED), style: BorderStyle.solid, width: 1))), child: const SizedBox.shrink()),
                      const Text('🔑 PEHLI BAAR — PASSWORD SET KARO',
                          style: TextStyle(
                              color: Color(0xFF0B1C30),
                              fontWeight: FontWeight.w800,
                              fontSize: 12, letterSpacing: 1)),
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
                      Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.only(top: 12), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFD4DDED), style: BorderStyle.solid, width: 1))), child: const SizedBox.shrink()),
                      const Text('🔑 RESET CODE (Telegram par aayega)',
                          style: TextStyle(
                              color: Color(0xFF0B1C30),
                              fontWeight: FontWeight.w800,
                              fontSize: 12, letterSpacing: 1)),
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
                        child: const Text('Naya ho? Register karo 📝', style: TextStyle(color: greenD, fontSize: 13, fontWeight: FontWeight.w700))),
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
