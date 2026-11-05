const { json, fail, requireEnv, supabase } = require('./_supabase');
const { toUuid } = require('./_uuid');
const { ensureUser } = require('./_users');

// Perfil de jugador: se crea o actualiza uno por usuario de Supabase Auth.
module.exports = async (req, res) => {
  if (!requireEnv(res)) return;

  if (req.method === 'GET') {
    const user_id = toUuid(req.query && req.query.user_id);
    if (!user_id) return fail(res, 'Falta user_id', 400);

    const { ok, data } = await supabase(
      `/rest/v1/player_profiles?id=eq.${encodeURIComponent(user_id)}&select=*`
    );
    if (!ok) return fail(res, 'No se pudo leer el perfil', 500);
    return json(res, 200, { profile: (data && data[0]) || null });
  }

  if (req.method === 'POST') {
    let body = req.body;
    if (typeof body === 'string') {
      try { body = JSON.parse(body); } catch (e) { return fail(res, 'JSON invalido', 400); }
    }
    body = body || {};
    const id = toUuid(body.user_id || body.id || body.display_name);
    if (!id) return fail(res, 'Falta user_id', 400);

    const plataformas = ['windows', 'linux', 'web', 'unknown'];
    const pedida = String(body.platform || '').toLowerCase();
    const platform = plataformas.includes(pedida) ? pedida : (pedida.includes('win') ? 'windows' : (pedida.includes('linux') ? 'linux' : 'unknown'));
    const fila = {
      id,
      display_name: String(body.display_name || 'jugador').slice(0, 24),
      platform,
      controller_connected: !!body.controller_connected,
      updated_at: new Date().toISOString(),
    };
    // Contadores: se suman solo si llegan como delta, nunca se restan.
    for (const campo of ['total_kills', 'total_waves', 'games_played']) {
      const delta = Number(body[campo]);
      if (Number.isFinite(delta) && delta > 0) fila[campo] = delta;
    }

    await ensureUser(id, body.display_name);

    const { ok, data } = await supabase(
      '/rest/v1/player_profiles?on_conflict=id&select=*',
      { method: 'POST', body: JSON.stringify(fila), headers: { Prefer: 'resolution=merge-duplicates,return=representation' } }
    );
    if (!ok) return fail(res, 'No se pudo guardar el perfil', 500);
    return json(res, 200, { profile: (data && data[0]) || null });
  }

  return fail(res, 'Metodo no permitido', 405);
};
