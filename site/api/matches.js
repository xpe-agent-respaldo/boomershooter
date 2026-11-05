const { json, fail, requireEnv, supabase } = require('./_supabase');
const { toUuid } = require('./_uuid');
const { ensureUser } = require('./_users');

// Historial de partidas. Guarda cada oleada alcanzada como una fila de
// wave_matches, para tener historial real aunque la partida siga en curso.
module.exports = async (req, res) => {
  if (!requireEnv(res)) return;

  if (req.method === 'GET') {
    const limit = Math.min(Number((req.query && req.query.limit) || 20), 50);

    const { ok, data } = await supabase(
      `/rest/v1/wave_matches?select=*&order=created_at.desc&limit=${limit}`
    );
    if (!ok) return fail(res, 'No se pudieron leer las partidas', 500);
    return json(res, 200, { matches: data || [] });
  }

  if (req.method === 'POST') {
    let body = req.body;
    if (typeof body === 'string') {
      try { body = JSON.parse(body); } catch (e) { return fail(res, 'JSON invalido', 400); }
    }
    body = body || {};

    const fila = {
      // Son columnas unicas: vacio tiene que ser null o la segunda partida choca.
      nakama_match_id: String(body.nakama_match_id || body.match_id || '').slice(0, 64) || null,
      host_user_id: toUuid(body.host_user_id || body.user_id),
      visibility: body.visibility === 'public' ? 'public' : 'private',
      room_code: String(body.room_code || '').slice(0, 12) || null,
      map_id: String(body.map_id || 'desconocido').slice(0, 40),
      wave_reached: Math.max(0, Math.min(999, Number(body.wave_reached) || 0)),
      player_count: Math.max(0, Math.min(4, Number(body.player_count) || 1)),
      status: ['lobby', 'active', 'finished', 'closed'].includes(body.status) ? body.status : 'active',
      finished_at: body.status === 'finished' || body.status === 'closed' ? new Date().toISOString() : null,
    };

    if (fila.host_user_id) await ensureUser(fila.host_user_id, body.host_user_id);

    const { ok, data } = await supabase(
      '/rest/v1/wave_matches?select=*',
      { method: 'POST', body: JSON.stringify(fila), headers: { Prefer: 'return=representation' } }
    );
    if (!ok) return fail(res, 'No se pudo guardar la partida', 500);
    return json(res, 200, { match: (data && data[0]) || null });
  }

  return fail(res, 'Metodo no permitido', 405);
};
