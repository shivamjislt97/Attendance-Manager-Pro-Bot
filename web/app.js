/* Attendance App preview — talks to FastAPI backend */
const S = {
  base: localStorage.getItem('api_base') || location.origin,
  token: localStorage.getItem('api_token') || '',
  profile: JSON.parse(localStorage.getItem('api_profile') || 'null'),
  calY: null, calM: null,
};
document.getElementById('in-base').value = S.base;

async function api(path, opts = {}) {
  opts.headers = Object.assign({}, opts.headers || {});
  if (S.token) opts.headers['X-Token'] = S.token;
  const r = await fetch(S.base + path, opts);
  if (r.status === 401) { logout(); throw new Error('Session khatam — dobara login karo'); }
  const ct = r.headers.get('content-type') || '';
  const data = ct.includes('json') ? await r.json() : await r.text();
  if (!r.ok) throw new Error((data && data.detail) || ('Error ' + r.status));
  return data;
}
function show(id) {
  document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
  document.getElementById(id).classList.add('active');
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
document.getElementById('btn-login').onclick = async () => {
  const e = document.getElementById('login-err'); e.textContent = '';
  try {
    const d = await api('/login', { method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ unique_id: document.getElementById('in-uid').value,
                             roll_no: document.getElementById('in-roll').value }) });
    S.token = d.token; S.profile = d;
    localStorage.setItem('api_token', d.token);
    localStorage.setItem('api_profile', JSON.stringify(d));
    document.getElementById('nav').classList.remove('hidden');
    document.getElementById('nav-admin').style.display = d.is_admin ? '' : 'none';
    show('scr-home');
  } catch (err) { e.textContent = '❌ ' + err.message; }
};
function logout() {
  S.token = ''; S.profile = null;
  localStorage.removeItem('api_token'); localStorage.removeItem('api_profile');
  document.getElementById('nav').classList.add('hidden');
  show('scr-login');
}
document.getElementById('btn-logout').onclick = logout;
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
async function loadHome() {
  document.getElementById('home-hi').textContent = '😎 Namaste, ' + (S.profile ? S.profile.naam : 'Dost') + '!';
  document.getElementById('home-date').textContent = '📅 Aaj: ' + todayStr();
  try {
    const r = await api('/record?date=' + encodeURIComponent(todayStr()));
    document.getElementById('home-status').textContent =
      r.status ? ('✅ Aaj ka status: ' + r.status) :
      (r.holiday ? '🏖️ Aaj college band hai — MOZ KARO 🎉' : '⏰ Aaj ki attendance abhi nahi lagi');
  } catch (e) { document.getElementById('home-status').textContent = '❌ ' + e.message; }
}
async function markIt(status) {
  const m = document.getElementById('home-msg'); m.textContent = '';
  try {
    const r = await api('/attendance', { method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status }) });
    m.textContent = '✅ Verify: ' + r.date + ' ka ' + r.status + ' save ho gaya!';
    loadHome();
  } catch (e) { m.textContent = '❌ ' + e.message; }
}
document.getElementById('btn-present').onclick = () => markIt('PRESENT');
document.getElementById('btn-chhutti').onclick = () => markIt('CHHUTTI');

/* ---------- calendar ---------- */
const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
async function loadCal() {
  const now = new Date();
  if (!S.calY) { S.calY = now.getFullYear(); S.calM = now.getMonth() + 1; }
  document.getElementById('cal-title').textContent = MON[S.calM - 1] + ' ' + S.calY;
  const grid = document.getElementById('cal-grid'); grid.innerHTML = '';
  document.getElementById('day-detail').classList.add('hidden');
  ['S','M','T','W','T','F','S'].forEach(d => {
    const e = document.createElement('div'); e.className = 'dow'; e.textContent = d; grid.appendChild(e);
  });
  let days = {};
  try { days = (await api('/calendar?year=' + S.calY + '&month=' + S.calM)).days; }
  catch (e) { grid.innerHTML = '<p class="err">❌ ' + e.message + '</p>'; return; }
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
        const pr = await fetch(S.base + '/holiday-proof?date=' + encodeURIComponent(ds),
                               { headers: { 'X-Token': S.token } });
        if ((pr.headers.get('content-type') || '').includes('image')) {
          const url = URL.createObjectURL(await pr.blob());
          box.innerHTML += '<br><img src="' + url + '">';
        } else {
          const j = await pr.json();
          box.textContent += '\n📝 Proof: ' + j.proof;
        }
      };
      box.appendChild(document.createElement('br')); box.appendChild(b);
    }
  } catch (e) { box.textContent = '❌ ' + e.message; }
}

/* ---------- stats ---------- */
async function loadStats() {
  const box = document.getElementById('stats-cards'); box.innerHTML = '...';
  try {
    const s = await api('/stats');
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
  } catch (e) { box.innerHTML = '<p class="err">❌ ' + e.message + '</p>'; }
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
document.getElementById('btn-holiday').onclick = async () => {
  const m = document.getElementById('admin-msg'); m.textContent = '';
  try {
    const fd = new FormData();
    fd.append('date', document.getElementById('in-hday').value.trim());
    fd.append('proof_text', document.getElementById('in-htext').value.trim());
    const f = document.getElementById('in-hphoto').files[0];
    if (f) fd.append('proof', f);
    const r = await fetch(S.base + '/admin/holiday',
      { method: 'POST', headers: { 'X-Token': S.token }, body: fd });
    const j = await r.json();
    if (!r.ok) throw new Error(j.detail || 'Error');
    m.textContent = '🏖️ Holiday declare! ' + j.date + ' | ' + j.updated +
                    ' entries | broadcast ' + j.broadcast_ok + '/' + j.broadcast_fail;
  } catch (e) { m.textContent = '❌ ' + e.message; }
};
