#!/usr/bin/env python3
"""Publica una version del juego: manifiesto de actualizacion y rutas de descarga.

No hay nada escrito a mano por version. Se le pasan los binarios ya compilados y el
script calcula tamano y SHA-256 reales, escribe `site/update.json` (con historial de
las ultimas 100 versiones) y apunta `site/api/download/*.js` a la version nueva.

Uso tipico (desde la raiz del repositorio):

    python3 tools/publish_update.py \
        --version 1.2.8 \
        --notes "Arreglos de red;nuevo mapa" \
        --windows Build/Windows/BoomerShooter.exe \
        --linux Build/Linux/boomershooter.x86_64

Sin --version se lee `config/version` de project.godot.
Con --dry-run solo ensena lo que haria (no escribe nada).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFIESTO = os.path.join(RAIZ, "site", "update.json")
DESCARGAS = os.path.join(RAIZ, "site", "api", "download")
PROYECTO = os.path.join(RAIZ, "project.godot")
MAX_HISTORIAL = 100
BASE_DESCARGAS = "https://boomershooter.vercel.app/api/download"


def version_del_proyecto() -> str:
    with open(PROYECTO, encoding="utf-8") as f:
        for linea in f:
            if linea.startswith("config/version="):
                return linea.split("=", 1)[1].strip().strip('"')
    return "0.0.0"


def sha256_y_tamano(ruta: str) -> tuple[str, int]:
    h = hashlib.sha256()
    total = 0
    with open(ruta, "rb") as f:
        for bloque in iter(lambda: f.read(1024 * 1024), b""):
            h.update(bloque)
            total += len(bloque)
    return h.hexdigest(), total


def notas_en_lineas(texto: str) -> str:
    """El cliente acepta texto con ; o saltos, o una lista. Aqui se guarda texto."""
    return texto.replace("|", ";").strip()


def cargar_manifiesto() -> dict:
    if not os.path.exists(MANIFIESTO):
        return {}
    with open(MANIFIESTO, encoding="utf-8") as f:
        datos = json.load(f)
    return datos if isinstance(datos, dict) else {}


def escribir_manifiesto(datos: dict) -> None:
    with open(MANIFIESTO, "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=2)
        f.write("\n")


def apuntar_descarga(nombre: str, version: str) -> bool:
    """Cambia la version del paquete en site/api/download/<nombre>.js."""
    ruta = os.path.join(DESCARGAS, nombre + ".js")
    if not os.path.exists(ruta):
        return False
    with open(ruta, encoding="utf-8") as f:
        texto = f.read()
    nuevo, cambios = re.subn(
        r"(packages/generic/boomershooter/)([0-9][^/]*)(/)",
        lambda m: m.group(1) + version + m.group(3),
        texto,
    )
    if not cambios:
        return False
    if nuevo != texto:
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(nuevo)
    return True


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--version", default="")
    p.add_argument("--notes", default="")
    p.add_argument("--minimum", default="", help="version minima aceptada (por defecto se conserva)")
    p.add_argument("--windows", default="")
    p.add_argument("--linux", default="")
    p.add_argument("--windows-url", default="")
    p.add_argument("--linux-url", default="")
    p.add_argument("--patch-ios", default="", help="parche de contenido de iOS (content.pck) ya generado")
    p.add_argument("--patch-ios-url", default="", help="URL publica de ese parche")
    p.add_argument("--base-ios", default="1.3.0", help="version de la IPA instalada sobre la que se aplica el parche")
    p.add_argument("--engine-revision", default="1")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    if not args.notes:
        # En CI las notas son el mensaje del tag: git tag -a v1.2.8 -m "notas;separadas"
        args.notes = os.environ.get("CI_COMMIT_TAG_MESSAGE", "") or os.environ.get("NOTAS", "")
    version = (args.version or version_del_proyecto()).strip().lstrip("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        print(f"ERROR: version no valida: {version!r}")
        return 2

    previo = cargar_manifiesto()
    datos: dict = {}
    datos["version"] = version
    datos["minimum_version"] = (args.minimum or str(previo.get("minimum_version", version))).strip()
    datos["notes"] = notas_en_lineas(args.notes) or str(previo.get("notes", ""))
    datos["windows_url"] = args.windows_url or f"{BASE_DESCARGAS}/windows"
    datos["linux_url"] = args.linux_url or f"{BASE_DESCARGAS}/linux"

    if not args.windows and not args.linux:
        # Sin binarios: se reutilizan los del manifiesto anterior (solo cambia el texto).
        for clave in ("windows_size", "windows_sha256", "linux_size", "linux_sha256"):
            if clave in previo:
                datos[clave] = previo[clave]
    for plataforma, ruta in (("windows", args.windows), ("linux", args.linux)):
        if not ruta:
            continue
        if not os.path.exists(ruta):
            print(f"ERROR: no existe el binario {plataforma}: {ruta}")
            return 2
        huella, tamano = sha256_y_tamano(ruta)
        datos[f"{plataforma}_size"] = tamano
        datos[f"{plataforma}_sha256"] = huella
        print(f"  {plataforma}: {tamano} bytes  sha256={huella}")

    # Parche de contenido para iPhone/iPad: iOS no puede reemplazar la app, asi que recibe un
    # content.pck que se monta al arrancar. Va en su propia clave (patch_ios): el pack de iOS
    # es distinto al de PC y jamas debe ofrecerse a Windows/Linux.
    if args.patch_ios:
        if not os.path.exists(args.patch_ios):
            print(f"ERROR: no existe el parche de iOS: {args.patch_ios}")
            return 2
        huella, tamano = sha256_y_tamano(args.patch_ios)
        datos["patch_ios"] = {
            "url": args.patch_ios_url or f"{BASE_DESCARGAS}/ios-patch",
            "size": tamano,
            "sha256": huella,
            "min_base": args.base_ios,
            "engine_revision": args.engine_revision,
            "version": version,
        }
        print(f"  parche iOS: {tamano} bytes  sha256={huella}  base>={args.base_ios}")
    elif isinstance(previo.get("patch_ios"), dict) and previo["patch_ios"].get("version") == version:
        datos["patch_ios"] = previo["patch_ios"]
    # Sin parche nuevo no se arrastra el de una version anterior: ofreceria contenido viejo.

    # Historial: las ultimas 100 versiones publicadas, para poder volver atras o
    # consultar que se entrego cada dia sin depender del repositorio.
    historial = [h for h in previo.get("history", []) if isinstance(h, dict)]
    historial = [h for h in historial if str(h.get("version")) != version]
    historial.append({
        "version": version,
        "released_at": dt.date.today().isoformat(),
        "windows_size": datos.get("windows_size"),
        "windows_sha256": datos.get("windows_sha256"),
        "linux_size": datos.get("linux_size"),
        "linux_sha256": datos.get("linux_sha256"),
    })
    historial = historial[-MAX_HISTORIAL:]
    datos["history"] = historial
    datos["released_at"] = dt.date.today().isoformat()
    datos["updates_soportadas"] = MAX_HISTORIAL

    print(f"manifiesto {version}: {datos.get('windows_size')} bytes (Windows), "
          f"{datos.get('linux_size')} bytes (Linux), historial={len(historial)}")
    print(f"minimo aceptado: {datos['minimum_version']}")

    if args.dry_run:
        print(json.dumps(datos, ensure_ascii=False, indent=2)[:1200])
        print("(--dry-run: no se ha escrito nada)")
        return 0

    escribir_manifiesto(datos)
    for nombre in ("windows", "linux", "ios-patch"):
        if apuntar_descarga(nombre, version):
            print(f"  site/api/download/{nombre}.js -> {version}")
        else:
            print(f"  AVISO: no se pudo actualizar site/api/download/{nombre}.js")
    return 0


if __name__ == "__main__":
    sys.exit(main())
