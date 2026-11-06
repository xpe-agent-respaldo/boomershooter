// Descarga directa del ejecutable de Windows.
//
// El .exe se publica como asset de un Release en el repositorio publico de
// descargas (el repositorio del juego es privado, asi que su artefacto de CI no
// se puede enlazar sin autenticacion). Si existe la variable de entorno
// WINDOWS_DOWNLOAD_URL en Vercel, manda esa; si no, se usa la release publicada.

const RELEASE_FALLBACK =
  'https://gitlab.com/api/v4/projects/88475071/packages/generic/boomershooter/1.2.9/BoomerShooter.exe';

module.exports = function handler(_request, response) {
  const url = process.env.WINDOWS_DOWNLOAD_URL || RELEASE_FALLBACK;
  if (!url) return response.status(503).json({ error: 'La descarga de Windows se publicara pronto.' });
  // Que el navegador lo guarde como archivo en vez de abrirlo o sacarte de la web.
  response.setHeader('Cache-Control', 'public, max-age=300');
  response.setHeader('Content-Disposition', 'attachment; filename="BoomerShooter.exe"');
  return response.redirect(302, url);
}
