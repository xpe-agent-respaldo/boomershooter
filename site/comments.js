// Login + comentarios de Boomer Shooter.
// El backend vive en /api/* (Vercel serverless); la clave de servicio de
// Supabase nunca llega al navegador, solo el access_token devuelto al entrar.

const SESSION_KEY = 'bs_session';

const COMMENTS_TEXT = {
  es: {
    welcome: 'Sesion iniciada. Bienvenido, ',
    badCreds: 'Usuario o contrasena incorrectos.',
    userExists: 'Ese nombre de usuario ya esta cogido.',
    confirm: 'Cuenta creada. Ya puedes entrar.',
    signupFail: 'No se pudo crear la cuenta.',
    needLogin: 'Inicia sesion para comentar.',
    shortPass: 'La contrasena necesita al menos 6 caracteres.',
    badUser: 'El usuario necesita entre 3 y 16 caracteres: letras, numeros, punto, guion o guion bajo.',
    genHint: 'Contrasena generada. Copiala y guardala: sin ella no hay forma de recuperar la cuenta.',
    empty: 'Escribe algo antes de publicar.',
    fail: 'No se pudo conectar con el servidor.',
    bye: 'Sesion cerrada.',
    anon: 'Anonimo',
    now: 'Ahora mismo'
  },
  en: {
    welcome: 'Signed in. Welcome, ',
    badCreds: 'Wrong username or password.',
    userExists: 'That username is taken.',
    confirm: 'Account created. You can log in now.',
    signupFail: 'Could not create the account.',
    needLogin: 'Log in to comment.',
    shortPass: 'Password needs at least 6 characters.',
    badUser: 'Username needs 3 to 16 characters: letters, numbers, dot, dash or underscore.',
    genHint: 'Password generated. Copy it and keep it safe: without it the account cannot be recovered.',
    empty: 'Write something before posting.',
    fail: 'Could not reach the server.',
    bye: 'Signed out.',
    anon: 'Anonymous',
    now: 'Just now'
  }
};

function ctext(key) {
  const lang = langSuffix();
  return (COMMENTS_TEXT[lang] && COMMENTS_TEXT[lang][key]) || COMMENTS_TEXT.es[key] || '';
}

function langSuffix() {
  return (document.documentElement.lang || 'es').startsWith('en') ? 'en' : 'es';
}

function getSession() {
  try { return JSON.parse(localStorage.getItem(SESSION_KEY) || 'null'); } catch { return null; }
}

function saveSession(session) {
  if (session) localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  else localStorage.removeItem(SESSION_KEY);
}

async function api(path, options = {}) {
  const session = getSession();
  const headers = { 'Content-Type': 'application/json' };
  if (session && session.access_token) headers.Authorization = 'Bearer ' + session.access_token;
  const res = await fetch(path, {
    method: options.method || 'GET',
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined
  });
  let data = null;
  try { data = await res.json(); } catch { data = null; }
  return { ok: res.ok, status: res.status, data };
}

async function refreshSession() {
  const session = getSession();
  if (!session || !session.refresh_token) return null;
  const { ok, data } = await api('/api/auth-refresh', { method: 'POST', body: { refresh_token: session.refresh_token } });
  if (ok && data && data.session) {
    const next = Object.assign({}, session, data.session, { user: data.user || session.user });
    saveSession(next);
    return next;
  }
  saveSession(null);
  return null;
}

function escapeHtml(text) {
  const el = document.createElement('div');
  el.textContent = String(text);
  return el.innerHTML;
}

function timeAgo(iso) {
  const diff = (Date.now() - new Date(iso).getTime()) / 1000;
  const en = langSuffix() === 'en';
  if (diff < 90) return ctext('now');
  const mins = Math.floor(diff / 60);
  if (mins < 60) return en ? mins + ' min ago' : 'hace ' + mins + ' min';
  const hours = Math.floor(mins / 60);
  if (hours < 24) return en ? hours + ' h ago' : 'hace ' + hours + ' h';
  const days = Math.floor(hours / 24);
  return en ? days + ' d ago' : 'hace ' + days + ' d';
}

function renderComments(comments) {
  const list = document.getElementById('comments-list');
  if (!list) return;
  if (!comments.length) {
    list.innerHTML = '<p class="comments-empty" data-es="Aun no hay comentarios." data-en="No comments yet.">Aun no hay comentarios.</p>';
    return;
  }
  list.innerHTML = comments.map((c) => {
    const name = escapeHtml(c.display_name || ctext('anon'));
    const avatar = c.avatar_url
      ? '<img class="comment-avatar" src="' + escapeHtml(c.avatar_url) + '" alt="" loading="lazy">'
      : '<span class="comment-avatar avatar-fallback">' + name.charAt(0).toUpperCase() + '</span>';
    return (
      '<article class="comment">' +
        '<header>' + avatar + '<strong>' + name + '</strong>' +
        '<time>' + timeAgo(c.created_at) + '</time></header>' +
        '<p>' + escapeHtml(c.content) + '</p>' +
      '</article>'
    );
  }).join('');
}

async function loadComments() {
  const { ok, status, data } = await api('/api/comments');
  if (ok && data && data.comments) { renderComments(data.comments); return; }
  const list = document.getElementById('comments-list');
  if (!list) return;
  // 503 = el backend esta desplegado pero sin base de datos configurada.
  const setup = status === 503;
  list.innerHTML = '<p class="comments-empty">' + (setup
    ? (langSuffix() === 'en'
        ? 'Comments turn on as soon as the database is connected. Your photo is already saved on this device.'
        : 'Los comentarios se activan en cuanto se conecte la base de datos. Tu foto ya queda guardada en este dispositivo.')
    : ctext('fail')) + '</p>';
}

function renderAuthState() {
  const authBox = document.getElementById('auth-box');
  const userBox = document.getElementById('user-box');
  const nameEl = document.getElementById('user-name');
  if (!authBox || !userBox) return;
  const session = getSession();
  if (session && session.user) {
    authBox.hidden = true;
    userBox.hidden = false;
    if (typeof paintAvatar === 'function') paintAvatar();
    if (nameEl) nameEl.textContent = session.user.username || session.user.email || '';
  } else {
    authBox.hidden = false;
    userBox.hidden = true;
    if (nameEl) nameEl.textContent = '';
  }
}

let signupMode = false;

function setAuthMessage(text) {
  const el = document.getElementById('auth-msg');
  if (el) el.textContent = text || '';
}

document.addEventListener('DOMContentLoaded', () => {
  const form = document.getElementById('auth-form');
  if (!form) return;

  renderAuthState();
  loadComments();

  function setMode(signup) {
    signupMode = signup;
    document.getElementById('tab-login').classList.toggle('active', !signup);
    document.getElementById('tab-signup').classList.toggle('active', signup);
    document.getElementById('auth-submit').innerHTML = signup
      ? (langSuffix() === 'en' ? 'CREATE <span>&rarr;</span>' : 'CREAR <span>&rarr;</span>')
      : (langSuffix() === 'en' ? 'LOG IN <span>&rarr;</span>' : 'ENTRAR <span>&rarr;</span>');
    setAuthMessage('');
  }

  document.getElementById('tab-login').addEventListener('click', () => setMode(false));
  document.getElementById('tab-signup').addEventListener('click', () => setMode(true));

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    setAuthMessage('');
    const username = (document.getElementById('auth-username').value || '').trim();
    const password = document.getElementById('auth-password').value;
    if (!/^[a-zA-Z0-9_.-]{3,16}$/.test(username)) return setAuthMessage(ctext('badUser'));
    if (password.length < 6) return setAuthMessage(ctext('shortPass'));
    const endpoint = signupMode ? '/api/auth-signup' : '/api/auth-login';
    const { ok, status, data } = await api(endpoint, { method: 'POST', body: { username, password } });
    if (!ok) {
      const serverMsg = data && data.error ? data.error : '';
      if (status === 409 || /cogido|taken|registered/i.test(serverMsg)) return setAuthMessage(ctext('userExists'));
      if (!signupMode) return setAuthMessage(ctext('badCreds'));
      return setAuthMessage(serverMsg || ctext('signupFail'));
    }
    if (signupMode && data.needs_confirmation) {
      setAuthMessage(ctext('confirm'));
      return;
    }
    if (data.session && data.user) {
      saveSession({ access_token: data.session.access_token, refresh_token: data.session.refresh_token, user: data.user });
      renderAuthState();
      setAuthMessage(ctext('welcome') + (data.user.username || data.user.email || ''));
    }
  });

  document.getElementById('logout').addEventListener('click', () => {
    saveSession(null);
    renderAuthState();
    setAuthMessage(ctext('bye'));
  });

  document.getElementById('comment-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const input = document.getElementById('comment-input');
    const content = (input.value || '').trim();
    if (!content) return setAuthMessage(ctext('empty'));
    let result = await api('/api/comments', { method: 'POST', body: { content } });
    if (result.status === 401) {
      const renewed = await refreshSession();
      if (renewed) result = await api('/api/comments', { method: 'POST', body: { content } });
    }
    if (result.ok) {
      input.value = '';
      setAuthMessage('');
      loadComments();
    } else if (result.status === 401) {
      saveSession(null);
      renderAuthState();
      setAuthMessage(ctext('needLogin'));
    } else {
      setAuthMessage((result.data && result.data.error) || ctext('fail'));
    }
  });
});


// ---------------------------------------------------------------------------
// Foto de perfil: se reduce en el navegador, se guarda al instante en local
// (asi nunca se pierde aunque el servidor falle) y se sube a Supabase Storage.
// ---------------------------------------------------------------------------
const AVATAR_CACHE = 'bs_avatars';

function avatarCache() {
  try { return JSON.parse(localStorage.getItem(AVATAR_CACHE) || '{}'); } catch { return {}; }
}

function getCachedAvatar(userId) {
  return avatarCache()[userId] || '';
}

function setCachedAvatar(userId, url) {
  const all = avatarCache();
  if (url) all[userId] = url; else delete all[userId];
  localStorage.setItem(AVATAR_CACHE, JSON.stringify(all));
}

function resizeToDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('read'));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error('decode'));
      img.onload = () => {
        const size = 256;
        const canvas = document.createElement('canvas');
        canvas.width = size;
        canvas.height = size;
        const ctx = canvas.getContext('2d');
        const side = Math.min(img.width, img.height);
        ctx.drawImage(img, (img.width - side) / 2, (img.height - side) / 2, side, side, 0, 0, size, size);
        resolve(canvas.toDataURL('image/jpeg', 0.86));
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

function paintAvatar() {
  const session = getSession();
  const img = document.getElementById('user-avatar');
  if (!img) return;
  if (!session || !session.user) { img.hidden = true; return; }
  const url = getCachedAvatar(session.user.id);
  if (url) {
    img.src = url;
    img.classList.remove('avatar-fallback');
    img.hidden = false;
  } else {
    const initial = (session.user.username || session.user.email || '?').charAt(0).toUpperCase();
    img.removeAttribute('src');
    img.classList.add('avatar-fallback');
    img.alt = initial;
    img.hidden = false;
  }
}

async function handleAvatarFile(event) {
  const file = event.target.files && event.target.files[0];
  const msg = document.getElementById('avatar-msg');
  const session = getSession();
  if (!file || !session || !session.user) return;
  if (file.size > 8 * 1024 * 1024) {
    if (msg) msg.textContent = langSuffix() === 'en' ? 'Image too large (max 8 MB).' : 'Imagen demasiado grande (max 8 MB).';
    return;
  }
  if (msg) msg.textContent = langSuffix() === 'en' ? 'Uploading...' : 'Subiendo...';
  try {
    const dataUrl = await resizeToDataUrl(file);
    setCachedAvatar(session.user.id, dataUrl);
    paintAvatar();
    const { ok, data } = await api('/api/avatar', { method: 'POST', body: JSON.stringify({ image: dataUrl }) });
    if (ok && data && data.avatar_url) {
      setCachedAvatar(session.user.id, data.avatar_url);
      paintAvatar();
      if (msg) msg.textContent = langSuffix() === 'en' ? 'Photo saved.' : 'Foto guardada.';
      loadComments();
    } else if (msg) {
      msg.textContent = (data && data.error) || (langSuffix() === 'en' ? 'Saved on this device only.' : 'Guardada solo en este dispositivo.');
    }
  } catch {
    if (msg) msg.textContent = langSuffix() === 'en' ? 'Could not read that image.' : 'No se pudo leer la imagen.';
  }
}

window.addEventListener('DOMContentLoaded', function () {
  const input = document.getElementById('avatar-input');
  if (input) input.addEventListener('change', handleAvatarFile);
  paintAvatar();
});

// ---------------------------------------------------------------------------
// Generador de contrasenas del formulario de cuenta.
// Usa crypto.getRandomValues (no Math.random) y garantiza al menos una
// minuscula, una mayuscula, un digito y un simbolo.
// ---------------------------------------------------------------------------
function generateStrongPassword(length) {
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const digits = '23456789';
  const symbols = '!@#$%&*?-_';
  const all = lower + upper + digits + symbols;
  const size = Math.max(12, length || 14);

  function pick(set) {
    const buf = new Uint32Array(1);
    window.crypto.getRandomValues(buf);
    return set[buf[0] % set.length];
  }

  const chars = [pick(lower), pick(upper), pick(digits), pick(symbols)];
  while (chars.length < size) chars.push(pick(all));
  for (let i = chars.length - 1; i > 0; i -= 1) {
    const buf = new Uint32Array(1);
    window.crypto.getRandomValues(buf);
    const j = buf[0] % (i + 1);
    const tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }
  return chars.join('');
}

window.addEventListener('DOMContentLoaded', function () {
  const button = document.getElementById('gen-pass');
  const field = document.getElementById('auth-password');
  const hint = document.getElementById('pass-hint');
  if (!button || !field) return;

  button.addEventListener('click', function () {
    const password = generateStrongPassword(14);
    field.type = 'text';           // que se pueda leer y copiar
    field.value = password;
    field.dispatchEvent(new Event('input', { bubbles: true }));

    if (hint) {
      hint.hidden = false;
      hint.innerHTML = '';
      const text = document.createElement('span');
      text.textContent = ctext('genHint') + ' ';
      const code = document.createElement('strong');
      code.textContent = password;
      hint.appendChild(text);
      hint.appendChild(code);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(password).catch(function () {});
    }
  });
});
