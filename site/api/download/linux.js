// Descarga directa del ejecutable de Linux. Mismo criterio que Windows: asset
// publico del Release oficial, con override por variable de entorno.
const RELEASE_FALLBACK =
  'https://gitlab.com/api/v4/projects/88475071/packages/generic/boomershooter/1.3.0/boomershooter.x86_64';

module.exports = function handler(_request, response) {
  const url = process.env.LINUX_DOWNLOAD_URL || RELEASE_FALLBACK;
  if (!url) return response.status(503).json({ error: 'La descarga de Linux se publicara pronto.' });
  response.setHeader('Cache-Control', 'public, max-age=300');
  response.setHeader('Content-Disposition', 'attachment; filename="boomershooter.x86_64"');
  return response.redirect(302, url);
}
