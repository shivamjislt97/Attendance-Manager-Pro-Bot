/* Attendance App preview — talks to FastAPI backend */
const S = {
  base: localStorage.getItem('api_base') || location.origin,
  token: localStorage.getItem('api_token') || '',
  profile: JSON.parse(localStorage.getItem('api_profile') || 'null'),
  calY: null, calM: null,
};
document.getElementById('in-base').value = S.base;

const DEBUG = new URLSearchParams(location.search).has('debug');
const C = {};  // session cache: month/stats/home (actions par clear hota hai)
function cacheClear() { for (const k in C) delete C[k]; }
let lastMs = 0;
function debugBadge(path, ms) {
  lastMs = ms;
  if (!DEBUG) return;
  let b = document.getElementById('debug-badge');
  if (!b) {
    b = document.createElement('div'); b.id = 'debug-badge';
    b.style.cssText = 'position:fixed;top:6px;right:8px;background:#000;color:#4ade80;font-size:11px;padding:4px 8px;border-radius:8px;z-index:200;opacity:.85';
    document.body.appendChild(b);
  }
  b.textContent = path.split('?')[0] + ' ' + Math.round(ms) + 'ms';
}
async function api(path, opts = {}) {
  const noLogout = !!opts._noLogout; delete opts._noLogout;
  opts.headers = Object.assign({}, opts.headers || {});
  if (S.token) opts.headers['X-Token'] = S.token;
  const t0 = performance.now();
  const r = await fetch(S.base + path, opts);
  debugBadge(path, performance.now() - t0);
  const ct = r.headers.get('content-type') || '';
  const data = ct.includes('json') ? await r.json() : await r.text();
  if (!r.ok) {
    const det = data && data.detail;
    const err = new Error((det && (det.message || det)) || ('Error ' + r.status));
    err.code = det && det.code;
    err.status = r.status;
    if (r.status === 401 && !noLogout && !err.code) logout();
    throw err;
  }
  return data;
}
function show(id) {
  document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
  document.getElementById(id).classList.add('active');
  document.querySelectorAll('#nav button[data-scr]').forEach(b =>
    b.classList.toggle('active', b.dataset.scr === id));
  if (id === 'scr-cal') loadCal();
  if (id === 'scr-stats') loadStats();
  if (id === 'scr-home') loadHome();
}
document.querySelectorAll('#nav button[data-scr]').forEach(b =>
  b.addEventListener('click', () => show(b.dataset.scr)));

/* ---------- login / logout ---------- */
document.getElementById('btn-base').onclick = () => {
  S.base = document.getElementById('in-base').value.replace(/\/$/, '');
  localStorage.setItem('api_base', S.base);
  alert('Server saved: ' + S.base);
};
const LP = { uid: '', roll: '' };  // login pehchan (steps me reuse)
function hideLoginBlocks() {
  ['login-pw-block', 'login-set-block', 'login-forgot-block',
   'login-reg-block'].forEach(id =>
    document.getElementById(id).classList.add('hidden'));
}
function enterApp(d) {
  S.token = d.token; S.profile = d;
  localStorage.setItem('api_token', d.token);
  localStorage.setItem('api_profile', JSON.stringify(d));
  document.getElementById('nav').classList.remove('hidden');
  document.getElementById('nav-admin').style.display = d.is_admin ? '' : 'none';
  show('scr-home');
}
document.getElementById('btn-login').onclick = async () => {
  const e = document.getElementById('login-err'); e.textContent = '';
  hideLoginBlocks();
  LP.uid = document.getElementById('in-uid').value.trim();
  LP.roll = document.getElementById('in-roll').value.trim();
  try {
    enterApp(await api('/login', { method: 'POST', _noLogout: true,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ unique_id: LP.uid, roll_no: LP.roll }) }));
  } catch (err) {
    if (err.code === 'password_not_set') {
      document.getElementById('login-set-block').classList.remove('hidden');
      e.textContent = '🔑 ' + err.message;
    } else if (err.code === 'password_required') {
      document.getElementById('login-pw-block').classList.remove('hidden');
      e.textContent = '🔒 Admin hai — password do 👇';
    } else { e.textContent = '❌ ' + err.message; }
  }
};
document.getElementById('btn-pw-login').onclick = async () => {
  const e = document.getElementById('pw-err'); e.textContent = '';
  try {
    enterApp(await api('/login', { method: 'POST', _noLogout: true,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ unique_id: LP.uid, roll_no: LP.roll,
                             password: document.getElementById('in-pw').value }) }));
  } catch (err) { e.textContent = '❌ ' + err.message; }
};
document.getElementById('link-forgot').onclick = () => {
  hideLoginBlocks();
  document.getElementById('login-forgot-block').classList.remove('hidden');
};
document.getElementById('link-register').onclick = () => {
  hideLoginBlocks();
  document.getElementById('login-reg-block').classList.remove('hidden');
};
document.getElementById('btn-register').onclick = async () => {
  const e = document.getElementById('reg-err');
  const m = document.getElementById('reg-ok');
  e.textContent = ''; m.textContent = '';
  try {
    const r = await api('/register', { method: 'POST', _noLogout: true,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ naam: document.getElementById('in-rnaam').value,
        branch: document.getElementById('in-rbranch').value,
        year: document.getElementById('in-ryear').value,
        roll_no: document.getElementById('in-rroll').value }) });
    m.textContent = '🎉 Registration COMPLETE!\n🆔 UNIQUE ID: ' + r.unique_id +
      '\n(Isse likh lo — login me kaam aayegi)';
    document.getElementById('in-uid').value = r.unique_id;
    document.getElementById('in-roll').value = r.roll_no;
  } catch (err) { e.textContent = '❌ ' + err.message; }
};
document.getElementById('btn-setpw').onclick = async () => {
  const e = document.getElementById('set-err'); e.textContent = '';
  const p1 = document.getElementById('in-newpw1').value;
  const p2 = document.getElementById('in-newpw2').value;
  if (p1 !== p2) { e.textContent = '❌ Dono password same likho'; return; }
  try {
    await api('/admin/set-password', { method: 'POST', _noLogout: true,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ unique_id: LP.uid, roll_no: LP.roll, password: p1 }) });
    document.getElementById('in-pw').value = p1;
    hideLoginBlocks();
    document.getElementById('login-pw-block').classList.remove('hidden');
    e.textContent = '';
    document.getElementById('login-err').textContent = '✅ Password set! Ab Admin Login dabao 👇';
  } catch (err) { e.textContent = '❌ ' + err.message; }
};
document.getElementById('btn-getcode').onclick = async () => {
  const m = document.getElementById('forgot-msg');
  const e = document.getElementById('forgot-err');
  m.textContent = ''; e.textContent = '';
  try {
    await api('/admin/forgot-password', { method: 'POST', _noLogout: true,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ unique_id: LP.uid, roll_no: LP.roll }) });
    m.textContent = '✅ Code Telegram par bhej diya! 📩';
  } catch (err) { e.textContent = '❌ ' + err.message; }
};
document.getElementById('btn-resetpw').onclick = async () => {
  const m = document.getElementById('forgot-msg');
  const e = document.getElementById('forgot-err');
  m.textContent = ''; e.textContent = '';
  try {
    await api('/admin/reset-password', { method: 'POST', _noLogout: true,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ unique_id: LP.uid, roll_no: LP.roll,
        code: document.getElementById('in-code').value.trim(),
        new_password: document.getElementById('in-resetpw').value }) });
    m.textContent = '✅ Password reset! Ab password se login karo 👇';
    hideLoginBlocks();
    document.getElementById('login-pw-block').classList.remove('hidden');
  } catch (err) { e.textContent = '❌ ' + err.message; }
};
function logout() {
  S.token = ''; S.profile = null; cacheClear();
  localStorage.removeItem('api_token'); localStorage.removeItem('api_profile');
  document.getElementById('nav').classList.add('hidden');
  show('scr-login');
}
document.getElementById('btn-logout').onclick = () => {
  document.getElementById('logout-confirm').classList.remove('hidden');
};
document.getElementById('btn-lo-haa').onclick = () => {
  document.getElementById('logout-confirm').classList.add('hidden');
  logout();
};
document.getElementById('btn-lo-nhi').onclick = () => {
  document.getElementById('logout-confirm').classList.add('hidden');
};
if (S.token && S.profile) {
  document.getElementById('nav').classList.remove('hidden');
  document.getElementById('nav-admin').style.display = S.profile.is_admin ? '' : 'none';
  show('scr-home');
}

/* ---------- home ---------- */
function todayStr() {
  const d = new Date();
  return String(d.getDate()).padStart(2, '0') + '/' +
         String(d.getMonth() + 1).padStart(2, '0') + '/' + d.getFullYear();
}
async function loadHome(force) {
  document.getElementById('home-hi').textContent = '😎 Namaste, ' + (S.profile ? S.profile.naam : 'Dost') + '!';
  document.getElementById('home-date').textContent = '📅 Aaj: ' + todayStr();
  const box = document.getElementById('home-status');
  const key = 'home:' + todayStr();
  const paint = (r) => { box.textContent =
      r.status ? ('✅ Aaj ka status: ' + r.status) :
      (r.holiday ? '🏖️ AAJ TOH CHHUTTI HAI MOZ KARO 🎉' : '⏰ Aaj ki attendance abhi nahi lagi');
    // bot jaisa: holiday (koi bhi status) par mark buttons nahi
    const hideMark = r.holiday || r.status === 'HOLIDAY';
    document.getElementById('btn-present').style.display = hideMark ? 'none' : '';
    document.getElementById('btn-chhutti').style.display = hideMark ? 'none' : '';
    if (!r.status && r.holiday) {
      const mb = document.createElement('button');
      mb.className = 'warn'; mb.textContent = '🏖️ MAZE KARO AJJ';
      mb.onclick = async () => {
        box.textContent = '🏖️ AAJ TOH CHHUTTI HAI MOZ KARO 🎉';
        try {
          const pr = await fetch(S.base + '/holiday-proof?date=' + encodeURIComponent(todayStr()) + '&thumb=1',
                                 { headers: { 'X-Token': S.token } });
          if ((pr.headers.get('content-type') || '').includes('image')) {
            const url = URL.createObjectURL(await pr.blob());
            box.innerHTML += '<br><img src="' + url + '" style="max-width:100%;border-radius:8px">';
          } else {
            const j = await pr.json();
            box.textContent += '\n📝 Proof: ' + j.proof;
          }
        } catch (e) { box.textContent += '\n❌ Proof nahi khula'; }
      };
      box.appendChild(document.createElement('br')); box.appendChild(mb);
    } };
  if (!force && C[key]) { paint(C[key]); loadNotices(false); return; }
  box.innerHTML = '<div class="skel" style="height:44px"></div>';
  try {
    const r = await api('/record?date=' + encodeURIComponent(todayStr()));
    C[key] = r; paint(r); loadNotices(false);
  } catch (e) { box.textContent = '❌ ' + e.message; }
}
async function loadNotices(force) {
  const nl = document.getElementById('notices-list');
  const al = document.getElementById('activity-list');
  if (!force && C.notices) { paintNotices(C.notices); return; }
  try {
    const r = await api('/notices');
    C.notices = r; paintNotices(r);
  } catch (e) {
    nl.textContent = '❌ ' + e.message; al.textContent = '';
  }
}
function paintNotices(r) {
  const nl = document.getElementById('notices-list');
  const al = document.getElementById('activity-list');
  nl.innerHTML = '';
  (r.notices || []).forEach(n => {
    const d = document.createElement('div');
    d.textContent = '🏖️ ' + n.date + ' — ' + n.tag;
    d.style.cssText = 'padding:6px 0;border-bottom:1px solid var(--line);cursor:pointer';
    d.onclick = async () => {
      try {
        const pr = await fetch(S.base + '/holiday-proof?date=' + encodeURIComponent(n.date) + '&thumb=1',
                               { headers: { 'X-Token': S.token } });
        if ((pr.headers.get('content-type') || '').includes('image')) {
          const url = URL.createObjectURL(await pr.blob());
          nl.innerHTML += '<br><img src="' + url + '" style="max-width:100%;border-radius:8px">';
        } else {
          const j = await pr.json();
          d.textContent += '\n📝 Proof: ' + j.proof;
        }
      } catch (e) { d.textContent += ' (❌ proof nahi khula)'; }
    };
    nl.appendChild(d);
  });
  if (!(r.notices || []).length) nl.textContent = '(koi notice nahi)';
  al.innerHTML = '';
  (r.activity || []).forEach(a => {
    const d = document.createElement('div');
    d.textContent = (a.emoji || '•') + ' ' + a.date + ' — ' + a.status;
    d.style.cssText = 'padding:6px 0;border-bottom:1px solid var(--line)';
    al.appendChild(d);
  });
  if (!(r.activity || []).length) al.textContent = '(koi record nahi)';
}
async function markIt(status) {
  const m = document.getElementById('home-msg');
  m.textContent = '⏳ Saving...';
  document.getElementById('btn-present').disabled = true;
  document.getElementById('btn-chhutti').disabled = true;
  try {
    const r = await api('/attendance', { method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status }) });
    m.textContent = '✅ Verify: ' + r.date + ' ka ' + r.status + ' save ho gaya!';
    cacheClear(); loadHome(true);
  } catch (e) { m.textContent = '❌ ' + e.message; }
  document.getElementById('btn-present').disabled = false;
  document.getElementById('btn-chhutti').disabled = false;
}
document.getElementById('btn-present').onclick = () => markIt('PRESENT');
document.getElementById('btn-chhutti').onclick = () => markIt('CHHUTTI');

/* ---------- calendar ---------- */
const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
async function loadCal(force) {
  const now = new Date();
  if (!S.calY) { S.calY = now.getFullYear(); S.calM = now.getMonth() + 1; }
  document.getElementById('cal-title').textContent = MON[S.calM - 1] + ' ' + S.calY;
  const grid = document.getElementById('cal-grid');
  document.getElementById('day-detail').classList.add('hidden');
  const key = 'cal:' + S.calY + '-' + S.calM;
  let days = (!force && C[key]) || null;
  const paint = () => {
    grid.innerHTML = '';
    ['S','M','T','W','T','F','S'].forEach(d => {
      const e = document.createElement('div'); e.className = 'dow'; e.textContent = d; grid.appendChild(e);
    });
    const first = new Date(S.calY, S.calM - 1, 1).getDay();
    for (let i = 0; i < first; i++) grid.appendChild(document.createElement('div'));
    const n = new Date(S.calY, S.calM, 0).getDate();
    for (let d = 1; d <= n; d++) {
      const ds = String(d).padStart(2, '0') + '/' + String(S.calM).padStart(2, '0') + '/' + S.calY;
      const b = document.createElement('button');
      b.className = 'day m-' + ((days[ds] && days[ds].marker) || 'none');
      b.textContent = d;
      b.onclick = () => showDay(ds, b);
      grid.appendChild(b);
    }
  };
  const skel = () => {
    grid.innerHTML = '';
    for (let i = 0; i < 35; i++) {
      const s = document.createElement('div'); s.className = 'skel'; grid.appendChild(s);
    }
  };
  if (days) { paint(); }
  else {
    skel();
    try { days = (await api('/calendar?year=' + S.calY + '&month=' + S.calM)).days; C[key] = days; paint(); }
    catch (e) { grid.innerHTML = '<p class="err">❌ ' + e.message + '</p>'; return; }
  }
  // aas-paas ke months silent prefetch
  [[S.calM - 1, S.calY], [S.calM + 1, S.calY]].forEach(([m, y]) => {
    let mm = m, yy = y;
    if (mm < 1) { mm = 12; yy--; } if (mm > 12) { mm = 1; yy++; }
    const k = 'cal:' + yy + '-' + mm;
    if (!C[k]) api('/calendar?year=' + yy + '&month=' + mm).then(r => { C[k] = r.days; }).catch(() => {});
  });
}
document.getElementById('cal-prev').onclick = () => {
  S.calM--; if (S.calM < 1) { S.calM = 12; S.calY--; } loadCal();
};
document.getElementById('cal-next').onclick = () => {
  S.calM++; if (S.calM > 12) { S.calM = 1; S.calY++; } loadCal();
};
async function showDay(ds, btn) {
  document.querySelectorAll('.cal-grid .day').forEach(x => x.classList.remove('sel'));
  btn.classList.add('sel');
  const box = document.getElementById('day-detail');
  box.classList.remove('hidden'); box.textContent = '...';
  try {
    const r = await api('/record?date=' + encodeURIComponent(ds));
    let t = '🗓️ ' + ds + '\n' +
      (r.status ? ('Status: ' + r.status + ' (by ' + r.marked_by + ')') :
       (r.holiday ? '🏖️ COLLEGE BAND tha!' : '❓ Koi record nahi'));
    box.textContent = t;
    if (r.has_proof) {
      const b = document.createElement('button');
      b.className = 'primary'; b.textContent = '😈😈 PROOF CHAHIYE KYA 👹👹';
      b.onclick = async () => {
        b.disabled = true; b.textContent = '⏳ Loading...';
        const pr = await fetch(S.base + '/holiday-proof?date=' + encodeURIComponent(ds) + '&thumb=1',
                               { headers: { 'X-Token': S.token } });
        if ((pr.headers.get('content-type') || '').includes('image')) {
          const url = URL.createObjectURL(await pr.blob());
          box.innerHTML += '<br><img src="' + url + '">';
        } else {
          const j = await pr.json();
          box.textContent += '\n📝 Proof: ' + j.proof;
        }
        box.textContent += '\n\n😈😈 Hmm mujh per vishvash nhi hai 😤😤 proof maang raha hai 🤬🤬';
        box.textContent += '\n😎Abh toh bohot kush hoga 🦉';
        const ok = document.createElement('button');
        ok.textContent = '✅ Theek hai'; ok.onclick = () => showDay(ds, btn);
        box.appendChild(document.createElement('br')); box.appendChild(ok);
      };
      box.appendChild(document.createElement('br')); box.appendChild(b);
    }
  } catch (e) { box.textContent = '❌ ' + e.message; }
}

/* ---------- stats ---------- */
async function loadStats(force) {
  const box = document.getElementById('stats-cards');
  if (!force && C.stats) { paintStats(C.stats); return; }
  box.innerHTML = '<div class="skel" style="height:120px"></div><div class="skel" style="height:60px"></div><div class="skel" style="height:60px"></div>';
  try {
    const s = await api('/stats');
    C.stats = s; paintStats(s);
  } catch (e) { box.innerHTML = '<p class="err">❌ ' + e.message + '</p>'; }
}
function paintStats(s) {
  const box = document.getElementById('stats-cards');
  const ring = document.getElementById('ring');
  document.getElementById('ring-txt').textContent = s.percent + '%';
  ring.style.setProperty('--p', s.percent + '%');
  box.innerHTML = '';
  [['🎒 Khule din', s.college_open], ['🔒 Band din', s.college_closed],
   ['✅ Present', s.present], ['😁 Chhutti', s.chutti],
   ['🚫 Absent', s.absent]].forEach(([k, v]) => {
    const d = document.createElement('div'); d.className = 'card';
    d.textContent = k + '\n' + v; box.appendChild(d);
  });
}

/* ---------- chat ---------- */
const CHAT_Q = ['% kitni hai?', 'kitne din gaya', 'chhutti', 'khula tha',
                'band tha', 'mahine ka record', 'absent dates', 'present dates'];
const chipsBox = document.getElementById('chips');
CHAT_Q.forEach((q, i) => {
  const b = document.createElement('button'); b.textContent = i + '. ' + q;
  b.onclick = () => sendChat(String(i)); chipsBox.appendChild(b);
});
function chatAdd(who, text) {
  const box = document.getElementById('chat-box');
  const d = document.createElement('div'); d.className = who; d.textContent = text;
  box.appendChild(d); box.scrollTop = box.scrollHeight;
}
async function sendChat(text) {
  chatAdd('me', text || document.getElementById('in-chat').value);
  const t = text || document.getElementById('in-chat').value;
  document.getElementById('in-chat').value = '';
  try {
    const r = await api('/chat', { method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: t }) });
    chatAdd('bot', r.reply);
    if (r.options) chatAdd('bot', 'Options: ' + r.options.join(' | '));
  } catch (e) { chatAdd('bot', '❌ ' + e.message); }
}
document.getElementById('btn-chat').onclick = () => {
  const v = document.getElementById('in-chat').value.trim();
  if (v) sendChat(v);
};

/* ---------- admin ---------- */
document.getElementById('btn-count').onclick = async () => {
  const box = document.getElementById('count-out');
  box.classList.remove('hidden'); box.textContent = '...';
  try {
    const c = await api('/admin/count');
    let t = '👥 Total: ' + c.total + '\n🏷️ ' + JSON.stringify(c.by_branch) +
            '\n🎓 ' + JSON.stringify(c.by_year) + '\n🧮 Matrix:\n';
    for (const b in c.matrix) t += b + ': ' + JSON.stringify(c.matrix[b]) + '\n';
    box.textContent = t;
  } catch (e) { box.textContent = '❌ ' + e.message; }
};
document.getElementById('btn-lookup').onclick = async () => {
  const box = document.getElementById('lookup-out');
  box.classList.remove('hidden'); box.textContent = '...';
  try {
    const r = await api('/admin/lookup?key=' +
      encodeURIComponent(document.getElementById('in-lookup').value));
    box.textContent = '👤 ' + r.student.naam + ' | ' + r.student.branch + ' | ' +
      r.student.roll_no + '\n📊 ' + r.stats.percent + '% (' +
      r.stats.present + '/' + r.stats.college_open + ')';
  } catch (e) { box.textContent = '❌ ' + e.message; }
};
document.getElementById('btn-recall').onclick = async () => {
  const box = document.getElementById('recall-out');
  const day = document.getElementById('in-recall').value.trim();
  box.classList.remove('hidden');
  if (box.dataset.armed !== day) {
    box.dataset.armed = day;
    box.textContent = '⚠️ Pakka? ' + (day || '?') + ' ka broadcast users ke paas se delete hoga (48h window). Confirm ke liye dobara dabao.';
    return;
  }
  box.dataset.armed = '';
  box.textContent = '...';
  try {
    const r = await api('/admin/recall', { method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ date: day }) });
    box.textContent = '🗑️ Recall complete (' + r.date + ')!\n✅ Deleted: ' + r.deleted + ' | ❌ Failed: ' + r.failed;
  } catch (e) { box.textContent = '❌ ' + e.message; }
};
async function holidaySubmit(dry) {
  const m = document.getElementById('admin-msg');
  const box = document.getElementById('preview-out');
  const bPrev = document.getElementById('btn-preview');
  const bDec = document.getElementById('btn-holiday');
  m.textContent = '';
  bPrev.disabled = true; bDec.disabled = true;
  try {
    const fd = new FormData();
    fd.append('date', document.getElementById('in-hday').value.trim());
    fd.append('proof_text', document.getElementById('in-htext').value.trim());
    const f = document.getElementById('in-hphoto').files[0];
    if (f) fd.append('proof', f);
    const r = await fetch(S.base + '/admin/holiday?dry_run=' + (dry ? 'true' : 'false'),
      { method: 'POST', headers: { 'X-Token': S.token }, body: fd });
    const j = await r.json();
    if (!r.ok) throw new Error((j.detail && (j.detail.message || j.detail)) || 'Error');
    if (dry) {
      box.classList.remove('hidden');
      box.textContent = '👁️ Preview (users ko YEHI dikhega):\n\n' + j.preview;
      return;
    }
    box.classList.add('hidden');
    m.textContent = j.scheduled_for
      ? ('📅 Schedule ho gaya! ✅\n📅 Date: ' + j.date +
         '\n📢 Notice 1-din-pehle (' + j.scheduled_for + ') subah 8:15 AM jayega — abhi kisi ko kuch nahi gaya.\n👥 ' +
         j.updated + ' entries HOLIDAY me update (DB me ' + j.date + ' hi mark)')
      : ('🏖️ Holiday declare! 📅 ' + j.date + '\n' +
        '📎 Proof file: 1 (' + j.type + ')\n' +
        '👥 ' + j.updated + ' entries HOLIDAY me update\n' +
        '📢 ' + j.broadcast_ok + ' users ko bheja, ' + j.broadcast_fail + ' fail');
    cacheClear();
  } catch (e) { m.textContent = '❌ ' + e.message; }
  finally { bPrev.disabled = false; bDec.disabled = false; }
}
document.getElementById('btn-preview').onclick = () => holidaySubmit(true);
document.getElementById('btn-holiday').onclick = () => holidaySubmit(false);
