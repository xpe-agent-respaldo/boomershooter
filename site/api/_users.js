const { SUPABASE_URL, SERVICE_ROLE } = require('./_supabase');

// Las tablas de perfiles y partidas apuntan a auth.users. Un jugador del juego
// puede no tener cuenta web, asi que se le crea una cuenta sombra con el mismo
// uuid derivado de su nombre. Es idempotente: si ya existe, no hace nada.
async function ensureUser(uuid, username) {
  if (!uuid) return { ok: false, status: 400 };
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${uuid}`, {
    headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${SERVICE_ROLE}` },
  });
  if (res.ok) return { ok: true, created: false };

  const alta = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_ROLE,
      Authorization: `Bearer ${SERVICE_ROLE}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      id: uuid,
      email: `${uuid}@players.boomershooter.app`,
      email_confirm: true,
      user_metadata: { username: String(username || 'jugador').slice(0, 24), sombra: true },
    }),
  });
  return { ok: alta.ok, created: alta.ok };
}

module.exports = { ensureUser };
