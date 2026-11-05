// Utilidad compartida para las funciones serverless (Vercel).
// Variables requeridas en Vercel:
//   SUPABASE_URL = https://<ref>.supabase.co
//   SUPABASE_SERVICE_ROLE = <service_role JWT>
// La service_role NUNCA se expone al navegador: solo vive en estas funciones.

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE;

function json(res, status, body) {
  res.status(status).setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(status >= 400 ? { error: body.error || 'error' } : body));
}

function fail(res, message, code = 500) {
  json(res, code, { error: message });
}

function requireEnv(res) {
  if (!SUPABASE_URL || !SERVICE_ROLE) {
    fail(res, 'Servidor sin configurar: faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE', 503);
    return false;
  }
  return true;
}

async function supabase(path, options = {}) {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    ...options,
    headers: {
      apikey: SERVICE_ROLE,
      Authorization: `Bearer ${SERVICE_ROLE}`,
      'Content-Type': 'application/json',
      ...(options.headers || {})
    }
  });
  let data = null;
  const text = await res.text();
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  return { ok: res.ok, status: res.status, data };
}

// Las cuentas se identifican por nombre de usuario. Supabase Auth trabaja con
// correos, asi que cada usuario recibe un correo interno que nunca se muestra:
// "xpe" -> "xpe@players.boomershooter.app". Asi no hace falta pedir correo.
const EMAIL_DOMAIN = 'players.boomershooter.app';
const USERNAME_RE = /^[a-zA-Z0-9_.-]{3,16}$/;

function normalizeUsername(value) {
  return String(value || '').trim();
}

function validUsername(value) {
  return USERNAME_RE.test(normalizeUsername(value));
}

function usernameToEmail(value) {
  return `${normalizeUsername(value).toLowerCase()}@${EMAIL_DOMAIN}`;
}

module.exports = {
  SUPABASE_URL, SERVICE_ROLE, EMAIL_DOMAIN, json, fail, requireEnv, supabase,
  normalizeUsername, validUsername, usernameToEmail
};

