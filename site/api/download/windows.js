// Descarga directa del ejecutable de Windows.
//
// El .exe se publica como asset de un Release en el repositorio publico de
// descargas (el repositorio del juego es privado, asi que su artefacto de CI no
// se puede enlazar sin autenticacion). Si existe la variable de entorno
// WINDOWS_DOWNLOAD_URL en Vercel, manda esa; si no, se usa la release publicada.

const RELEASE_FALLBACK =
  'https://gitlab.com/api/v4/projects/88475071/packages/generic/boomershooter/1.3.0/BoomerShooter.exe';

module.exports = function handler(request, response) {
  // Un iPhone/iPad no puede ejecutar el .exe. La 1.3.0 instalada en iOS (que aun no conoce los
  // parches de iPhone) abre esta ruta al pulsar ACTUALIZAR: se le lleva a la pagina de la IPA.
  const agente = String((request.headers && request.headers['user-agent']) || '');
  if (/iPhone|iPad|iPod/i.test(agente)) {
    response.setHeader('Cache-Control', 'no-store');
    return response.redirect(302, '/#ios');
  }
  const url = process.env.WINDOWS_DOWNLOAD_URL || RELEASE_FALLBACK;
  if (!url) return response.status(503).json({ error: 'La descarga de Windows se publicara pronto.' });
  // Que el navegador lo guarde como archivo en vez de abrirlo o sacarte de la web.
  response.setHeader('Cache-Control', 'public, max-age=300');
  response.setHeader('Content-Disposition', 'attachment; filename="BoomerShooter.exe"');
  return response.redirect(302, url);
}
