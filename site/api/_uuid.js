
const crypto = require('crypto');

// Las columnas de usuario son uuid. Un jugador offline no tiene cuenta, asi que
// se deriva un uuid estable de su nombre: mismo nombre, mismo perfil siempre.
function toUuid(value) {
  const raw = String(value || '').trim();
  if (!raw) return null;
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(raw)) return raw.toLowerCase();
  const h = crypto.createHash('sha1').update('boomershooter:' + raw.toLowerCase()).digest();
  h[6] = (h[6] & 0x0f) | 0x50;
  h[8] = (h[8] & 0x3f) | 0x80;
  const hex = h.toString('hex').slice(0, 32);
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20,32)}`;
}

module.exports = { toUuid };
