const { json, fail, requireEnv, supabase, validUsername, normalizeUsername, usernameToEmail } = require('./_supabase');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return fail(res, 'Metodo no permitido', 405);
  if (!requireEnv(res)) return;
  const { username, email, password } = req.body || {};
  if (!password) return fail(res, 'Falta la contrasena', 400);

  let loginEmail;
  if (email) {
    loginEmail = String(email).trim().toLowerCase();
  } else {
    if (!validUsername(username)) return fail(res, 'Usuario o contrasena incorrectos', 401);
    loginEmail = usernameToEmail(normalizeUsername(username));
  }
  const { ok, status, data } = await supabase('/auth/v1/token?grant_type=password', {
    method: 'POST',
    body: JSON.stringify({ email: loginEmail, password })
  });
  if (!ok) return fail(res, 'Usuario o contrasena incorrectos', status === 400 ? 401 : 502);
  const user = data.user || {};
  json(res, 200, {
    session: {
      access_token: data.access_token,
      refresh_token: data.refresh_token,
      expires_at: data.expires_at
    },
    user: {
      id: user.id,
      email: user.email,
      username: (user.user_metadata && (user.user_metadata.username || user.user_metadata.display_name))
        || (user.email || '').split('@')[0]
    }
  });
};

