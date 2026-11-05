let language = 'es';

function applyLanguage() {
  document.documentElement.lang = language;
  document.querySelectorAll('[data-es][data-en]').forEach((node) => {
    const value = node.dataset[language];
    if (value.includes('<')) node.innerHTML = value;
    else node.textContent = value;
  });
  document.getElementById('lang-toggle').textContent = language === 'es' ? 'EN' : 'ES';
}

document.getElementById('lang-toggle').addEventListener('click', () => {
  language = language === 'es' ? 'en' : 'es';
  applyLanguage();
});

document.getElementById('year').textContent = new Date().getFullYear();

document.getElementById('compatibility-check')?.addEventListener('click', () => {
  const result = document.getElementById('compatibility-result');
  const ram = navigator.deviceMemory;
  const canvas = document.createElement('canvas');
  const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
  const renderer = gl ? gl.getParameter(gl.RENDERER) : null;
  const ramText = ram ? `${ram} GB RAM detectados` : 'RAM no disponible para este navegador';
  const graphicsText = renderer ? `grafica detectada: ${renderer}` : 'no se pudo detectar la grafica';
  const verdict = ram && ram < 4 ? 'Puede requerir el perfil Bajo.' : 'Prueba el perfil Equilibrado; baja a Bajo si ves caidas de FPS.';
  result.textContent = `${ramText}; ${graphicsText}. ${verdict} Esta comprobacion es orientativa y no envia datos.`;
});
applyLanguage();

/* Carrusel automatico de mundos: pasa solo cada 6.5 s y se puede fijar a mano. */
(function () {
  var carousel = document.getElementById("world-carousel");
  if (!carousel) return;
  var slides = Array.prototype.slice.call(carousel.querySelectorAll(".world-slide"));
  var dots = Array.prototype.slice.call(carousel.querySelectorAll(".world-dot"));
  var index = 0;
  var timer = null;
  function show(next) {
    index = (next + slides.length) % slides.length;
    slides.forEach(function (slide, i) { slide.classList.toggle("is-active", i === index); });
    dots.forEach(function (dot, i) { dot.classList.toggle("is-active", i === index); });
  }
  function start() {
    stop();
    timer = setInterval(function () { show(index + 1); }, 6500);
  }
  function stop() { if (timer) { clearInterval(timer); timer = null; } }
  dots.forEach(function (dot) {
    dot.addEventListener("click", function () {
      show(parseInt(dot.getAttribute("data-slide"), 10) || 0);
      start();
    });
  });
  carousel.addEventListener("mouseenter", stop);
  carousel.addEventListener("mouseleave", start);
  show(0);
  start();
})();

/* Visor del Neko: cada chip tine el modelo con el color de la skin de la tienda */
(function () {
  const viewer = document.getElementById('neko-viewer');
  const list = document.getElementById('skin-list');
  if (!viewer || !list) return;
  const nameEl = document.getElementById('skin-name');
  const priceEl = document.getElementById('skin-price');
  function hex(c) { const n = parseInt(c.slice(1), 16); return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255, 1]; }
  // La skin base conserva los colores originales; las demas mezclan el color en el cuerpo (materiales claros)
  function pintar(color, esBase) {
    if (!viewer.model) return;
    const target = hex(color);
    for (const m of viewer.model.materials) {
      if (!m.pbrMetallicRoughness) continue;
      if (!m._orig) m._orig = m.pbrMetallicRoughness.baseColorFactor.slice();
      if (esBase) { m.pbrMetallicRoughness.setBaseColorFactor(m._orig); continue; }
      const o = m._orig, luz = (o[0] + o[1] + o[2]) / 3;
      // los materiales muy oscuros (ojos, boca) no se tocan: se mantiene la cara del personaje
      if (luz < 0.12) { m.pbrMetallicRoughness.setBaseColorFactor(o); continue; }
      const t = 0.78;
      m.pbrMetallicRoughness.setBaseColorFactor([o[0] * (1 - t) + target[0] * t, o[1] * (1 - t) + target[1] * t, o[2] * (1 - t) + target[2] * t, 1]);
    }
  }
  let actual = { color: '#f2ebdc', base: true };
  viewer.addEventListener('load', () => pintar(actual.color, actual.base));
  list.addEventListener('click', (e) => {
    const b = e.target.closest('.skin-chip');
    if (!b) return;
    list.querySelectorAll('.skin-chip').forEach((x) => x.classList.remove('is-active'));
    b.classList.add('is-active');
    actual = { color: b.dataset.color, base: b.dataset.name === 'NEKO CLASICA' };
    nameEl.textContent = b.dataset.name;
    const p = Number(b.dataset.price);
    priceEl.textContent = p === 0 ? priceEl.dataset.free : p + ' ' + priceEl.dataset.coins;
    pintar(actual.color, actual.base);
  });
})();
