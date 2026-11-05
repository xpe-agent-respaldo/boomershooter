// Estadisticas del proyecto para el panel /admin. Solo responde con la clave de admin.
// Variables en Vercel: ADMIN_PANEL_KEY (la clave que escribes en el panel), SUPABASE_URL, SUPABASE_SERVICE_ROLE.
// Opcionales: RENDER_API_KEY + RENDER_SERVICE_ID (estado del servidor), GITLAB_TOKEN (descargas).
const crypto = require('crypto');
const { fail, json } = require('./_supabase');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE;

function claveValida(recibida) {
  const esperada = process.env.ADMIN_PANEL_KEY || '';
  if (!esperada || !recibida) return false;
  const a = Buffer.from(String(recibida));
  const b = Buffer.from(esperada);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

async function contar(tabla, filtro = '') {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${tabla}?select=id${filtro}`, {
    method: 'HEAD',
    headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${SERVICE_ROLE}`, Prefer: 'count=exact', Range: '0-0' },
  });
  const rango = r.headers.get('content-range') || '';
  const n = parseInt(rango.split('/')[1], 10);
  return Number.isFinite(n) ? n : null;
}

async function filas(ruta) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${ruta}`, {
    headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${SERVICE_ROLE}` },
  });
  return r.ok ? r.json() : [];
}

async function seguro(fn, defecto) {
  try { return await fn(); } catch { return defecto; }
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') return fail(res, 'Metodo no permitido', 405);
  if (!SUPABASE_URL || !SERVICE_ROLE) return fail(res, 'Servidor sin configurar', 503);
  const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
  if (!claveValida(body.key)) return fail(res, 'Clave incorrecta', 401);

  const hoy = new Date(); hoy.setUTCHours(0, 0, 0, 0);
  const hace7 = new Date(Date.now() - 7 * 86400000).toISOString();
  const [perfiles, partidas, partidasHoy, partidas7, comentarios, ultimas, perfilesRecientes] = await Promise.all([
    seguro(() => contar('player_profiles'), null),
    seguro(() => contar('wave_matches'), null),
    seguro(() => contar('wave_matches', `&created_at=gte.${hoy.toISOString()}`), null),
    seguro(() => contar('wave_matches', `&created_at=gte.${hace7}`), null),
    seguro(() => contar('game_comments'), null),
    seguro(() => filas('wave_matches?select=map_id,wave_reached,player_count,status,created_at&order=created_at.desc&limit=200'), []),
    seguro(() => filas('player_profiles?select=display_name,created_at&order=created_at.desc&limit=8'), []),
  ]);

  // partidas por mapa y por dia (ultimas 200)
  const porMapa = {}; const porDia = {};
  for (const p of ultimas) {
    // ids antiguos con basura (p. ej. "N") se agrupan aparte, sin tocar los datos
    const mapa = ['RecyclingPlant', 'StormVillage', 'SpaceArena', 'recycling_plant', 'storm_village', 'space_arena'].includes(p.map_id) ? p.map_id : 'sin mapa (version antigua)';
    porMapa[mapa] = (porMapa[mapa] || 0) + 1;
    const d = (p.created_at || '').slice(0, 10);
    if (d) porDia[d] = (porDia[d] || 0) + 1;
  }

  // estado del servidor online (Render) y ultima version publicada
  const render = await seguro(async () => {
    const t0 = Date.now();
    const r = await fetch('https://boomershooter.onrender.com/healthcheck', { signal: AbortSignal.timeout(8000) });
    return { ok: r.ok, ms: Date.now() - t0 };
  }, { ok: false, ms: null });
  const version = await seguro(async () => {
    const r = await fetch('https://boomershooter.vercel.app/update.json');
    const j = await r.json();
    return { actual: j.version, minima: j.minimum_version };
  }, null);

  json(res, 200, {
    generado: new Date().toISOString(),
    jugadores: perfiles, comentarios,
    partidas: { total: partidas, hoy: partidasHoy, ultimos7dias: partidas7 },
    porMapa, porDia,
    perfilesRecientes: perfilesRecientes.map((p) => ({ nombre: p.display_name, alta: p.created_at })),
    servidor: render, version,
  });
};
