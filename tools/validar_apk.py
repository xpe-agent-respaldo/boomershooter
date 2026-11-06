#!/usr/bin/env python3
"""Valida el APK de Android antes de entregarlo. No necesita Android SDK ni aapt.

Comprueba lo que hace que el juego funcione (o no) en un movil:
  1. Es un zip con AndroidManifest.xml, classes.dex y resources.arsc/assets.
  2. El manifiesto (binario AXML, se lee aqui) declara el paquete y los permisos que usa el juego:
     INTERNET (online), RECORD_AUDIO (chat de voz: sin ella Android bloquea el micro), VIBRATE.
     Y NO pide permisos de mas (camara, ubicacion, almacenamiento).
  3. Lleva la libreria nativa de Godot para arm64-v8a (los moviles actuales).
  4. El paquete de datos incluye online_defaults.cfg (sin el, el online esta muerto) y NO la clave vieja.
  5. Esta firmado (META-INF con firma): un APK sin firmar no se instala.
Sale con codigo 1 si algo esta mal.
"""
import struct
import sys
import zipfile

PERMISOS_NECESARIOS = {"android.permission.INTERNET", "android.permission.RECORD_AUDIO",
                       "android.permission.VIBRATE"}
PERMISOS_PROHIBIDOS = {"android.permission.CAMERA", "android.permission.ACCESS_FINE_LOCATION",
                       "android.permission.ACCESS_COARSE_LOCATION",
                       "android.permission.READ_EXTERNAL_STORAGE",
                       "android.permission.WRITE_EXTERNAL_STORAGE",
                       "android.permission.READ_CONTACTS", "android.permission.READ_SMS"}
CLAVE_VIEJA = b"BoomerShooterSecretKey2026"


def leer_axml(datos: bytes) -> dict:
    """Lector minimo del XML binario de Android: devuelve paquete, permisos y orientacion."""
    if len(datos) < 8 or struct.unpack_from("<H", datos, 0)[0] != 0x0003:
        raise ValueError("AndroidManifest.xml no es un AXML valido")
    pos = 8
    cadenas = []
    resultado = {"package": None, "permisos": set(), "orientacion": None, "version": None}
    while pos + 8 <= len(datos):
        tipo, cab, tam = struct.unpack_from("<HHI", datos, pos)
        if tam == 0:
            break
        if tipo == 0x0001:  # pool de cadenas
            n, _estilos, flags, ini_cad, _ini_est = struct.unpack_from("<IIIII", datos, pos + 8)
            utf8 = bool(flags & 0x100)
            offs = struct.unpack_from("<%dI" % n, datos, pos + 28)
            base = pos + ini_cad
            for o in offs:
                p = base + o
                if utf8:
                    l = datos[p]; p += 1 if not (l & 0x80) else 2
                    l2 = datos[p]; p += 1
                    if l2 & 0x80:
                        l2 = ((l2 & 0x7F) << 8) | datos[p]; p += 1
                    cadenas.append(datos[p:p + l2].decode("utf-8", "replace"))
                else:
                    l = struct.unpack_from("<H", datos, p)[0]; p += 2
                    if l & 0x8000:
                        l = ((l & 0x7FFF) << 16) | struct.unpack_from("<H", datos, p)[0]; p += 2
                    cadenas.append(datos[p:p + l * 2].decode("utf-16-le", "replace"))
        elif tipo == 0x0102:  # inicio de elemento
            _ns, nombre, ini_attr, tam_attr, n_attr = struct.unpack_from("<iiHHH", datos, pos + 16)
            ele = cadenas[nombre] if 0 <= nombre < len(cadenas) else ""
            for i in range(n_attr):
                o = pos + 16 + ini_attr + i * tam_attr
                _a_ns, a_nom, a_raw = struct.unpack_from("<iii", datos, o)
                nom = cadenas[a_nom] if 0 <= a_nom < len(cadenas) else ""
                val = cadenas[a_raw] if 0 <= a_raw < len(cadenas) else None
                if ele == "manifest" and nom == "package":
                    resultado["package"] = val
                elif ele == "manifest" and nom == "versionName":
                    resultado["version"] = val
                elif ele == "uses-permission" and nom == "name" and isinstance(val, str):
                    resultado["permisos"].add(val)
                elif ele == "activity" and nom == "screenOrientation":
                    resultado["orientacion"] = val
        pos += tam
    return resultado


def main(ruta: str) -> int:
    fallos, avisos = [], []
    mal, aviso = fallos.append, avisos.append
    try:
        z = zipfile.ZipFile(ruta)
    except Exception as e:
        print(f"FALLA no es un zip valido: {e}")
        return 1
    nombres = z.namelist()

    for obligatorio in ("AndroidManifest.xml", "classes.dex"):
        if obligatorio not in nombres:
            mal(f"falta {obligatorio} en el APK")
    if not any(n.startswith("assets/") for n in nombres):
        mal("no hay carpeta assets/ (sin ella no estan los datos del juego)")

    if "AndroidManifest.xml" in nombres:
        try:
            m = leer_axml(z.read("AndroidManifest.xml"))
            print(f"  paquete: {m['package']}  version: {m['version']}")
            if m["package"] != "com.boomershooter.game":
                mal(f"paquete inesperado: {m['package']}")
            faltan = PERMISOS_NECESARIOS - m["permisos"]
            if faltan:
                mal("faltan permisos en el manifiesto: " + ", ".join(sorted(faltan)))
            sobran = PERMISOS_PROHIBIDOS & m["permisos"]
            if sobran:
                mal("pide permisos que el juego no usa: " + ", ".join(sorted(sobran)))
            print("  permisos: " + ", ".join(sorted(p.split(".")[-1] for p in m["permisos"])))
        except Exception as e:
            mal(f"no se pudo leer el manifiesto: {e}")

    libs = [n for n in nombres if n.startswith("lib/") and n.endswith(".so")]
    if not any(n.startswith("lib/arm64-v8a/") for n in libs):
        mal("falta la libreria nativa para arm64-v8a (movil moderno)")
    print(f"  librerias nativas: {len(libs)} ({', '.join(sorted({n.split('/')[1] for n in libs}))})")

    # Godot mete los recursos sueltos en assets/ (o en un .pck): se busca el archivo por nombre.
    cfg = [n for n in nombres if n.endswith("online_defaults.cfg")]
    if cfg:
        d = z.read(cfg[0])
        if b"host" not in d.lower():
            mal("online_defaults.cfg esta vacio: el online estaria muerto")
    else:
        pck = [n for n in nombres if n.endswith(".pck")]
        if not pck or b"online_defaults.cfg" not in z.read(pck[0]):
            mal("FALTA online_defaults.cfg: el online estaria muerto")
    for n in nombres:
        if n.startswith("assets/") and not n.endswith((".mp3str", ".ctex", ".sample", ".oggvorbisstr", ".png", ".ogg", ".wav", ".mp3")) \
                and CLAVE_VIEJA in z.read(n):
            mal(f"la clave vieja del servidor sigue dentro de {n}")

    if not any(n.startswith("META-INF/") and n.endswith((".RSA", ".DSA", ".EC", ".SF")) for n in nombres) \
            and not any(n == "META-INF/CERT.SF" for n in nombres):
        mal("el APK no esta firmado (sin META-INF/*.SF): Android no lo instala")

    for a in avisos:
        print("  AVISO " + a)
    if fallos:
        for f in fallos:
            print("  FALLA " + f)
        print(f"\nAPK: {len(fallos)} FALLOS")
        return 1
    print("\nAPK: TODO BIEN")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]) if len(sys.argv) > 1 else 2)
