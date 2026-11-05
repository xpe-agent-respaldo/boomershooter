const { json, fail, requireEnv, supabase, validUsername, normalizeUsername, usernameToEmail } = require('./_supabase');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return fail(res, 'Metodo no permitido', 405);
  if (!requireEnv(res)) return;
  const { username, email, password } = req.body || {};
  if (!password) return fail(res, 'Falta la contrasena', 400);
  if (String(password).length < 6) return fail(res, 'La contrasena necesita al menos 6 caracteres', 400);

  let loginEmail;
  let displayName = '';
  if (email) {
    loginEmail = String(email).trim().toLowerCase();
  } else {
    if (!validUsername(username)) {
      return fail(res, 'El usuario necesita entre 3 y 16 caracteres: letras, numeros, punto, guion o guion bajo', 400);
    }
    displayName = normalizeUsername(username);
    loginEmail = usernameToEmail(displayName);
  }

  // Las cuentas por nombre de usuario usan un correo interno que no existe. El registro
  // publico (/auth/v1/signup) lo rechaza y ademas exigiria confirmarlo, algo imposible.
  // Se crean por la via admin con el correo ya confirmado y se inicia sesion a continuacion.
  const internal = !email;
  const created = await supabase(internal ? '/auth/v1/admin/users' : '/auth/v1/signup', {
    method: 'POST',
    body: JSON.stringify(internal ? {
      email: loginEmail,
      password,
      email_confirm: true,
      user_metadata: { username: displayName, display_name: displayName }
    } : { email: loginEmail, password })
  });
  if (!created.ok) {
    const raw = String((created.data && (created.data.msg || created.data.message || created.data.error_description)) || '');
    if (/already (been )?registered|already exists|duplicate|email_exists/i.test(raw + ' ' + (created.data && created.data.error_code || ''))) {
      return fail(res, 'Ese nombre de usuario ya esta cogido', 409);
    }
    return fail(res, raw || 'No se pudo crear la cuenta', created.status === 400 || created.status === 422 ? 400 : 502);
  }
  const user = created.data.user || created.data;

  // Sesion inmediata (con el flujo publico ya viene en la respuesta; con admin hay que pedirla).
  let session = created.data.session || null;
  if (!session) {
    const signed = await supabase('/auth/v1/token?grant_type=password', {
      method: 'POST',
      body: JSON.stringify({ email: loginEmail, password })
    });
    if (signed.ok) session = signed.data;
  }
  json(res, 200, {
    needs_confirmation: !session,
    session: session
      ? { access_token: session.access_token, refresh_token: session.refresh_token, expires_at: session.expires_at }
      : null,
    user: user && user.id
      ? { id: user.id, email: user.email, username: displayName || String(user.email || '').split('@')[0] }
      : null
  });
};
