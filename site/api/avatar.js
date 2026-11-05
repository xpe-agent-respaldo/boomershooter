const { SUPABASE_URL, SERVICE_ROLE, json, fail, requireEnv, supabase } = require('./_supabase');

// Limites del avatar: se redimensiona en el navegador antes de subirlo, asi que
// aqui solo se valida que no llegue nada raro.
const MAX_BYTES = 2 * 1024 * 1024;
const ALLOWED = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };

async function userFromToken(access_token) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${access_token}` }
  });
  if (!res.ok) return null;
  return res.json();
}

async function uploadObject(path, bytes, contentType) {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/avatars/${path}`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_ROLE,
      Authorization: `Bearer ${SERVICE_ROLE}`,
      'Content-Type': contentType,
      'x-upsert': 'true',
      'cache-control': '31536000'
    },
    body: bytes
  });
  if (!res.ok) {
    const detail = await res.text();
    return { ok: false, detail };
  }
  return { ok: true };
}

module.exports = async (req, res) => {
  if (!requireEnv(res)) return;
  if (req.method !== 'POST') return fail(res, 'Metodo no permitido', 405);

  const auth = req.headers.authorization || '';
  const access_token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!access_token) return fail(res, 'Inicia sesion para cambiar tu foto', 401);

  const user = await userFromToken(access_token);
  if (!user) return fail(res, 'Sesion invalida o expirada', 401);

  const image = (req.body || {}).image;
  if (typeof image !== 'string' || !image.startsWith('data:')) {
    return fail(res, 'Falta la imagen', 400);
  }

  const match = /^data:([a-z/+.-]+);base64,(.+)$/i.exec(image);
  if (!match) return fail(res, 'Formato de imagen no valido', 400);

  const contentType = match[1].toLowerCase();
  const ext = ALLOWED[contentType];
  if (!ext) return fail(res, 'Solo se aceptan PNG, JPG o WebP', 400);

  let bytes;
  try {
    bytes = Buffer.from(match[2], 'base64');
  } catch {
    return fail(res, 'La imagen esta corrupta', 400);
  }
  if (bytes.length > MAX_BYTES) return fail(res, 'La imagen supera 2 MB', 413);

  const path = `${user.id}.${ext}`;
  const upload = await uploadObject(path, bytes, contentType);
  if (!upload.ok) {
    const missingBucket = String(upload.detail || '').includes('Bucket not found');
    return fail(
      res,
      missingBucket
        ? 'Falta el bucket "avatars": ejecuta supabase/migrations/003_avatars.sql'
        : 'No se pudo guardar la imagen',
      missingBucket ? 503 : 500
    );
  }

  const avatar_url = `${SUPABASE_URL}/storage/v1/object/public/avatars/${path}`;
  const stamp = new Date().toISOString();
  const meta = user.user_metadata || {};
  const display_name = String(
    meta.display_name || meta.name || (user.email ? user.email.split('@')[0] : 'player')
  ).slice(0, 32);

  await supabase('/rest/v1/site_profiles', {
    method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify([
      { user_id: user.id, display_name, avatar_url, updated_at: stamp }
    ])
  });

  // Los comentarios ya publicados heredan la foto nueva.
  await supabase(`/rest/v1/game_comments?user_id=eq.${user.id}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ avatar_url })
  });

  return json(res, 200, { avatar_url, display_name });
};
