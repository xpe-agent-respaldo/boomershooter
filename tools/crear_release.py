#!/usr/bin/env python3
"""Crea la release de una version en GitLab con los enlaces de descarga.

Se usa desde CI (con CI_JOB_TOKEN) pero tambien se puede lanzar a mano:

    GITLAB_TOKEN=... python3 tools/crear_release.py --version 1.3.0 --notes "Arreglos;mapa nuevo"

Si la release ya existe no falla: informa y sigue.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

API = os.environ.get("CI_API_V4_URL", "https://gitlab.com/api/v4")
PROYECTO = os.environ.get("CI_PROJECT_ID", "85907027")
DESCARGAS = os.environ.get("DESCARGAS_PROYECTO", "88475071")
COPYRIGHT = "© 2026 xpe.nettt · Stealth Proyects"


def token() -> tuple[str, str]:
    """(nombre de cabecera, valor). En CI manda el token del trabajo."""
    job = os.environ.get("CI_JOB_TOKEN", "")
    if job:
        return "JOB-TOKEN", job
    priv = os.environ.get("GITLAB_TOKEN", "")
    if priv:
        return "PRIVATE-TOKEN", priv
    return "", ""


def base_descargas(version: str) -> str:
    return f"{API}/projects/{DESCARGAS}/packages/generic/boomershooter/{version}"


def cuerpo_release(version: str, notas: str, plataformas: list[str]) -> dict:
    lineas = [n.strip() for n in notas.replace("|", ";").split(";") if n.strip()]
    descripcion = f"**Boomer Shooter {version}**\n\n"
    descripcion += "\n".join(f"- {n}" for n in lineas) if lineas else "Nueva version disponible."
    descripcion += f"\n\n{COPYRIGHT}"
    base = base_descargas(version)
    enlaces = []
    if "windows" in plataformas:
        enlaces.append({"name": "BoomerShooter.exe (Windows)",
                        "url": f"{base}/BoomerShooter.exe"})
    if "linux" in plataformas:
        enlaces.append({"name": "boomershooter.x86_64 (Linux)",
                        "url": f"{base}/boomershooter.x86_64"})
    return {
        "name": f"v{version}",
        "tag_name": f"v{version}",
        # El tag vive en GitHub; si no existe en GitLab, este lo crea desde main.
        # Sin "ref" la API responde 422 "Ref is not specified".
        "ref": os.environ.get("RELEASE_REF", "main"),
        "description": descripcion,
        "assets": {"links": enlaces},
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    p.add_argument("--notes", default=os.environ.get("CI_COMMIT_TAG_MESSAGE", ""))
    p.add_argument("--plataformas", default="windows,linux")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    version = args.version.lstrip("v")
    plataformas = [x.strip().lower() for x in args.plataformas.split(",") if x.strip()]
    datos = cuerpo_release(version, args.notes, plataformas)

    if args.dry_run:
        print(json.dumps(datos, ensure_ascii=False, indent=2))
        return 0

    cabecera, valor = token()
    if not cabecera:
        print("ERROR: falta CI_JOB_TOKEN o GITLAB_TOKEN.")
        return 2

    peticion = urllib.request.Request(
        f"{API}/projects/{PROYECTO}/releases",
        data=json.dumps(datos).encode("utf-8"),
        headers={cabecera: valor, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(peticion, timeout=60) as respuesta:
            salida = json.loads(respuesta.read().decode("utf-8"))
            print(f"release creada: {salida.get('tag_name')} -> {salida.get('_links', {}).get('self', '')}")
            return 0
    except urllib.error.HTTPError as error:
        detalle = error.read().decode("utf-8", "replace")[:300]
        if error.code in (400, 409) and ("already exists" in detalle or "has already been taken" in detalle):
            print(f"la release v{version} ya existia: no se toca")
            return 0
        print(f"ERROR {error.code}: {detalle}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
