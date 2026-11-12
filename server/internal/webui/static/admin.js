// PassOne admin web UI.
//
// Security note: every value that comes from the server (usernames, invite
// tokens, fingerprints) is rendered through textContent / createElement and
// never through innerHTML, so a value can never be interpreted as markup.
// The server additionally restricts usernames to a safe character set and
// sends a strict Content-Security-Policy for this page.
'use strict';

const state = { token: '' };
const $ = (id) => document.getElementById(id);

// The only status values the server can produce; used to build a CSS class.
const STATUS_CLASSES = ['pending', 'active', 'disabled'];

// el() builds an element: text is assigned via textContent (never parsed as
// HTML), so any string is safe to display.
function el(tag, opts = {}) {
  const node = document.createElement(tag);
  if (opts.text !== undefined && opts.text !== null) node.textContent = String(opts.text);
  if (opts.className) node.className = opts.className;
  if (opts.onClick) node.addEventListener('click', opts.onClick);
  if (opts.attrs) {
    for (const [k, v] of Object.entries(opts.attrs)) node.setAttribute(k, String(v));
  }
  if (opts.style) Object.assign(node.style, opts.style);
  return node;
}

function statusClass(status) {
  return STATUS_CLASSES.includes(status) ? status : '';
}

function setToken(t) {
  state.token = t;
  $('tokenInput').value = '';
  $('loginCard').classList.add('hidden');
  $('createCard').classList.remove('hidden');
  $('listCard').classList.remove('hidden');
  $('pairingCard').classList.remove('hidden');
  $('logoutBtn').style.display = '';
  refresh();
}

$('loginBtn').onclick = () => {
  const t = $('tokenInput').value.trim();
  if (!t) return;
  setToken(t);
};

$('logoutBtn').onclick = () => {
  state.token = '';
  $('logoutBtn').style.display = 'none';
  $('createCard').classList.add('hidden');
  $('listCard').classList.add('hidden');
  $('pairingCard').classList.add('hidden');
  $('loginCard').classList.remove('hidden');
};

async function api(path, opts = {}) {
  const res = await fetch('/api/v1' + path, {
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + state.token },
    ...opts,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(data.error || res.status);
    err.code = data.code;
    throw err;
  }
  return data;
}

async function refresh() {
  const q = $('searchInput').value.toLowerCase();
  const body = $('usersBody');
  try {
    const data = await api('/admin/users');
    const users = Array.isArray(data.users) ? data.users : [];
    const rows = users.filter((u) => !q || String(u.username).toLowerCase().includes(q));

    body.textContent = '';
    if (rows.length === 0) {
      const tr = el('tr');
      tr.appendChild(el('td', {
        text: 'Nessun utente.',
        className: 'muted',
        attrs: { colspan: '5' },
      }));
      body.appendChild(tr);
      return;
    }

    for (const u of rows) {
      const tr = el('tr');
      tr.appendChild(el('td', { text: u.id }));
      tr.appendChild(el('td', { text: u.username }));

      const statusTd = el('td');
      statusTd.appendChild(el('span', {
        text: u.status,
        className: 'status ' + statusClass(u.status),
      }));
      tr.appendChild(statusTd);

      tr.appendChild(el('td', { text: u.vault_revision }));

      const actions = el('td');
      if (u.status === 'pending') {
        actions.appendChild(el('button', {
          text: 'Nuovo invite',
          className: 'secondary',
          onClick: () => resetInvite(u.id),
        }));
      }
      actions.appendChild(el('button', {
        text: 'Elimina',
        className: 'danger',
        onClick: () => delUser(u.id),
      }));
      tr.appendChild(actions);

      body.appendChild(tr);
    }
  } catch (e) {
    toast('Errore: ' + e.message, true);
  }
}

$('searchInput').oninput = refresh;

$('createBtn').onclick = async () => {
  const username = $('usernameInput').value.trim();
  if (!username) return;
  const out = $('createResult');
  try {
    const data = await api('/admin/users', {
      method: 'POST',
      body: JSON.stringify({ username }),
    });
    out.textContent = '';
    out.appendChild(el('p', {
      text: 'Utente "' + data.user.username + '" creato.',
      className: 'ok',
    }));
    out.appendChild(el('div', { text: data.invite_token, className: 'invite' }));
    out.appendChild(el('p', {
      text: "Invite token monouso — consegnalo all'utente.",
      className: 'muted',
    }));
    $('usernameInput').value = '';
    refresh();
  } catch (e) {
    out.textContent = '';
    out.appendChild(el('p', { text: e.message, className: 'error' }));
  }
};

async function resetInvite(id) {
  const out = $('createResult');
  try {
    const data = await api('/admin/users/' + id + '/reset-invite', { method: 'POST' });
    out.textContent = '';
    out.appendChild(el('div', { text: data.invite_token, className: 'invite' }));
    out.appendChild(el('p', { text: 'Nuovo invite token.', className: 'muted' }));
  } catch (e) {
    toast(e.message, true);
  }
}

async function delUser(id) {
  if (!confirm('Eliminare definitivamente questo utente?')) return;
  try {
    await api('/admin/users/' + id, { method: 'DELETE' });
    refresh();
  } catch (e) {
    toast(e.message, true);
  }
}

$('pairingBtn').onclick = async () => {
  try {
    const data = await api('/admin/pairing');
    $('pairingResult').classList.remove('hidden');
    $('pairingQr').textContent = '';
    if (data.tls_mode === 'selfsigned' && data.fingerprint) {
      $('pairingFp').textContent = data.fingerprint;
      $('pairingMode').textContent = data.pair_url || '';
      $('pairingCopyBtn').style.display = '';
      // Only the server-generated PNG data URL is accepted as an image source.
      if (typeof data.qr === 'string' && data.qr.startsWith('data:image/png;base64,')) {
        $('pairingQr').appendChild(el('img', {
          attrs: { src: data.qr, alt: 'QR pairing' },
          style: {
            width: '200px', height: '200px', background: '#fff',
            padding: '8px', borderRadius: '8px',
          },
        }));
      }
    } else {
      $('pairingFp').textContent = 'TLS non in modalità self-signed: il pairing non è necessario.';
      $('pairingMode').textContent = 'tls_mode: ' + data.tls_mode;
      $('pairingCopyBtn').style.display = 'none';
    }
  } catch (e) {
    toast(e.message, true);
  }
};

$('pairingCopyBtn').onclick = async () => {
  try {
    await navigator.clipboard.writeText($('pairingFp').textContent);
    toast('Fingerprint copiata');
  } catch (_) {
    toast('Copia non disponibile: selezionala manualmente', true);
  }
};

let toastTimer;
function toast(msg, isErr) {
  const t = $('toast');
  t.textContent = msg;
  t.style.borderColor = isErr ? 'var(--danger)' : 'var(--border)';
  t.style.display = 'block';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.style.display = 'none'; }, 4000);
}
