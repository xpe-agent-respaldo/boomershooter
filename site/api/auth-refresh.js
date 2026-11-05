const { json, fail, requireEnv, supabase } = require('./_supabase');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return fail(res, 'Metodo no permitido', 405);
  if (!requireEnv(res)) return;
  const { refresh_token } = req.body || {};
  if (!refresh_token) return fail(res, 'Falta refresh_token', 400);
  const { ok, status, data } = await supabase('/auth/v1/token?grant_type=refresh_token', {
    method: 'POST',
    body: JSON.stringify({ refresh_token })
  });
  if (!ok) return fail(res, 'Sesion expirada', 401);
  json(res, 200, {
    session: {
      access_token: data.access_token,
      refresh_token: data.refresh_token,
      expires_at: data.expires_at
    },
    user: data.user
      ? {
          id: data.user.id,
          email: data.user.email,
          username: (data.user.user_metadata && (data.user.user_metadata.username || data.user.user_metadata.display_name))
            || (data.user.email || '').split('@')[0]
        }
      : null
  });
};

