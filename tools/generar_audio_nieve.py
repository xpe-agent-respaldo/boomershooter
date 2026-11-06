#!/usr/bin/env python3
"""Sintetiza el audio del mapa de nieve con codigo propio (sin muestras de terceros: no hay
licencias que cumplir). Mismo formato que el resto de pistas: mono, 22050 Hz, 16 bit.

  Assets/Sounds/Music/Maps/campos_nieve.wav     pad frio + campanitas de hielo (bucle)
  Assets/Sounds/SFX/Ambience/viento_nieve.wav   viento filtrado (bucle)
Los dos cierran en bucle SIN salto: el final enlaza con el principio.
"""
import os
import wave
import numpy as np

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
rng = np.random.default_rng(2026)


def guardar(ruta, x, rms=0.17, pico_max=0.72):
    """Iguala el volumen al de las demas pistas (RMS ~0.17); si eso pasara del pico, se baja."""
    x = x / (np.sqrt(np.mean(x ** 2)) + 1e-9) * rms
    x = x * min(1.0, pico_max / (np.max(np.abs(x)) + 1e-9))
    pcm = (x * 32767).astype("<i2")
    with wave.open(ruta, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(os.path.basename(ruta), round(len(x) / SR, 1), "s")


def cerrar_bucle(x, fade=0.35):
    """Mezcla el final con el principio para que el bucle no haga 'clic'."""
    n = int(fade * SR)
    if len(x) <= 2 * n:
        return x
    rampa = np.linspace(0, 1, n)
    x = x.copy()
    x[:n] = x[:n] * rampa + x[-n:] * (1 - rampa)
    return x[:-n]


def musica():
    dur = 16.0
    t = np.arange(int((dur + 0.35) * SR)) / SR
    # acordes lentos (La menor -> Fa mayor 7 -> Do -> Sol): 4 s cada uno
    acordes = [(220.0, 261.63, 329.63), (174.61, 220.0, 261.63, 329.63),
               (196.0, 261.63, 329.63), (196.0, 246.94, 293.66)]
    pad = np.zeros_like(t)
    for i, notas in enumerate(acordes):
        ini, fin = i * 4.0, (i + 1) * 4.0 + 0.8
        env = np.clip(np.minimum((t - ini) / 1.4, (fin - t) / 1.4), 0, 1)
        for f in notas:
            for det in (-0.6, 0.0, 0.7):          # voces ligeramente desafinadas = calidez
                pad += env * np.sin(2 * np.pi * (f + det) * t) * 0.07
    # campanitas de hielo: notas agudas con caida rapida, en posiciones fijas
    campana = np.zeros_like(t)
    escala = [880.0, 987.77, 1174.66, 1318.51, 1567.98]
    for k, ini in enumerate([1.2, 3.6, 5.5, 8.4, 10.1, 12.6, 14.3]):
        f = escala[(k * 2) % len(escala)]
        m = t >= ini
        d = np.where(m, t - ini, 0)
        campana += m * np.exp(-d * 2.6) * (np.sin(2 * np.pi * f * d) + 0.35 * np.sin(2 * np.pi * f * 2.01 * d)) * 0.10
    # soplo de aire muy suave
    ruido = rng.standard_normal(len(t))
    k = np.ones(220) / 220
    aire = np.convolve(ruido, k, mode="same") * 0.5
    return cerrar_bucle(pad + campana + aire * 0.4)


def viento():
    dur = 12.0
    n = int((dur + 0.5) * SR)
    ruido = rng.standard_normal(n)
    # pasa-bajos suave + dos ritmos lentos que mueven la intensidad (rachas)
    suave = np.convolve(ruido, np.ones(140) / 140, mode="same")
    t = np.arange(n) / SR
    rachas = 0.55 + 0.30 * np.sin(2 * np.pi * t / 6.0) + 0.15 * np.sin(2 * np.pi * t / 2.3 + 1.0)
    silbido = np.sin(2 * np.pi * (420 + 60 * np.sin(2 * np.pi * t / 5.0)) * t) * 0.025 * rachas
    return cerrar_bucle(suave * rachas + silbido, fade=0.5)


if __name__ == "__main__":
    guardar(os.path.join(ROOT, "Assets/Sounds/Music/Maps/campos_nieve.wav"), musica(), rms=0.17)
    guardar(os.path.join(ROOT, "Assets/Sounds/SFX/Ambience/viento_nieve.wav"), viento(), rms=0.10)
