// Parche de contenido para iPhone/iPad (content.pck). iOS no puede reemplazar la app, asi que el
// juego descarga este archivo y lo monta al arrancar. Mismo criterio que Windows y Linux.
const RELEASE_FALLBACK =
  'https://gitlab.com/api/v4/projects/88475071/packages/generic/boomershooter/1.3.0/content-ios.pck';

module.exports = function handler(_request, response) {
  const url = process.env.IOS_PATCH_URL || RELEASE_FALLBACK;
  response.setHeader('Cache-Control', 'public, max-age=300');
  response.setHeader('Content-Disposition', 'attachment; filename="content.pck"');
  return response.redirect(302, url);
}
