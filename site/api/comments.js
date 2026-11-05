const { SUPABASE_URL, SERVICE_ROLE, json, fail, requireEnv, supabase } = require('./_supabase');

const MAX_CONTENT = 500;

module.exports = async (req, res) => {
  if (!requireEnv(res)) return;

  if (req.method === 'GET') {
    const { ok, status, data } = await supabase(
      '/rest/v1/game_comments?select=id,display_name,content,created_at,avatar_url&order=created_at.desc&limit=50'
    );
    if (!ok) return fail(res, 'No se pudieron leer los comentarios', 500);
    return json(res, 200, { comments: data || [] });
  }

  if (req.method === 'POST') {
    const auth = req.headers.authorization || '';
    const access_token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
    if (!access_token) return fail(res, 'Inicia sesion para comentar', 401);

    const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${access_token}` }
    });
    if (!userRes.ok) return fail(res, 'Sesion invalida o expirada', 401);
    const user = await userRes.json();

    const { content } = req.body || {};
    const text = typeof content === 'string' ? content.trim() : '';
    if (!text) return fail(res, 'El comentario esta vacio', 400);
    if (text.length > MAX_CONTENT) return fail(res, `Maximo ${MAX_CONTENT} caracteres`, 400);

    const meta = user.user_metadata || {};
    const name = String(meta.display_name || meta.name || (user.email ? user.email.split('@')[0] : 'player')).slice(0, 32);

    // La foto de perfil vive en site_profiles: se copia en el comentario para
    // que la lista publica no necesite join ni exponer la tabla de perfiles.
    let avatar_url = null;
    const profile = await supabase(
      `/rest/v1/site_profiles?user_id=eq.${user.id}&select=avatar_url&limit=1`
    );
    if (profile.ok && Array.isArray(profile.data) && profile.data[0]) {
      avatar_url = profile.data[0].avatar_url || null;
    }

    const ins = await supabase('/rest/v1/game_comments', {
      method: 'POST',
      body: JSON.stringify({ user_id: user.id, display_name: name, content: text, avatar_url }),
      headers: { Prefer: 'return=representation' }
    });
    if (!ins.ok) {
      const code = ins.status === 401 || ins.status === 403 ? 401 : 500;
      return fail(res, 'No se pudo publicar el comentario', code);
    }
    return json(res, 201, { comment: ins.data && ins.data[0] ? ins.data[0] : null });
  }

  fail(res, 'Metodo no permitido', 405);
};

