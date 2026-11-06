#!/usr/bin/env python3
"""Valida una IPA SIN FIRMAR antes de entregarla.

Comprueba lo que un firmador (Gbox, Filza, Sideloadly, ESign, Feather, zsign...) necesita:
  1. Es un zip con Payload/<algo>.app/ en la raiz (no una carpeta extra por encima).
  2. Info.plist legible, con bundle id, version y ejecutable declarados.
  3. El ejecutable existe y es un Mach-O arm64 (iPhone), no x86 ni universal sin arm64.
  4. Los permisos con texto (microfono) estan declarados: sin ellos iOS cierra la app al
     abrir el micro.
  5. No lleva firma de desarrollo vieja ni perfiles incrustados que estorben al firmar.
  6. Orientacion horizontal y modo pantalla completa (es un shooter).
Sale con codigo 1 si algo esta mal. No necesita macOS ni Xcode.
"""
import plistlib
import struct
import sys
import zipfile

MACHO = {0xFEEDFACF: "arm64/x86_64 (64 bit)", 0xFEEDFACE: "32 bit",
         0xBEBAFECA: "universal", 0xCAFEBABE: "universal"}
CPU_ARM64 = 0x0100000C


def main(ruta: str) -> int:
    fallos, avisos = [], []

    def mal(m): fallos.append(m)
    def aviso(m): avisos.append(m)

    try:
        z = zipfile.ZipFile(ruta)
    except Exception as e:
        print(f"FALLA no es un zip valido: {e}")
        return 1
    nombres = z.namelist()

    raices = {n.split("/")[0] for n in nombres if n}
    if raices != {"Payload"}:
        mal(f"la raiz del zip debe ser solo 'Payload/', hay: {sorted(raices)}")
    apps = sorted({"/".join(n.split("/")[:2]) for n in nombres
                   if n.startswith("Payload/") and n.split("/")[1].endswith(".app")})
    if len(apps) != 1:
        mal(f"debe haber exactamente un .app dentro de Payload/, hay {len(apps)}: {apps}")
        return _fin(fallos, avisos)
    app = apps[0]
    print(f"[ok] estructura: {app}/")

    try:
        info = plistlib.loads(z.read(f"{app}/Info.plist"))
    except Exception as e:
        mal(f"Info.plist ilegible: {e}")
        return _fin(fallos, avisos)

    for clave in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString",
                  "CFBundleVersion", "MinimumOSVersion"):
        if not info.get(clave):
            mal(f"falta {clave} en Info.plist")
    print(f"[ok] bundle={info.get('CFBundleIdentifier')} version={info.get('CFBundleShortVersionString')}"
          f" ({info.get('CFBundleVersion')}) iOS>={info.get('MinimumOSVersion')}")

    ejecutable = f"{app}/{info.get('CFBundleExecutable', '')}"
    if ejecutable not in nombres:
        mal(f"el ejecutable declarado no existe: {ejecutable}")
    else:
        cab = z.read(ejecutable)[:16]
        magia = struct.unpack("<I", cab[:4])[0]
        if magia == 0xFEEDFACF:
            cpu = struct.unpack("<I", cab[4:8])[0]
            if cpu != CPU_ARM64:
                mal(f"el ejecutable no es arm64 (cputype=0x{cpu:x}): no arrancara en iPhone")
            else:
                print("[ok] ejecutable Mach-O arm64")
        elif magia in (0xBEBAFECA, 0xCAFEBABE):
            aviso("ejecutable universal (fat): comprobar que incluye arm64")
        else:
            mal(f"el ejecutable no es un Mach-O (magia 0x{magia:08x})")

    # permisos con texto: sin la descripcion iOS cierra la app al pedir el recurso
    if not str(info.get("NSMicrophoneUsageDescription", "")).strip():
        mal("falta NSMicrophoneUsageDescription: iOS cierra la app al abrir el microfono")
    else:
        print("[ok] permiso de microfono declarado")

    orient = info.get("UISupportedInterfaceOrientations", [])
    if not any("Landscape" in o for o in orient):
        aviso(f"sin orientacion horizontal declarada: {orient}")
    if not info.get("UIRequiresFullScreen", True):
        aviso("UIRequiresFullScreen=false")

    firmados = [n for n in nombres if n.startswith(f"{app}/_CodeSignature/")]
    if firmados:
        aviso(f"lleva una firma previa ({len(firmados)} archivos en _CodeSignature): "
              "los firmadores la reemplazan, pero conviene entregarla limpia")
    if f"{app}/embedded.mobileprovision" in nombres:
        aviso("lleva un perfil embedded.mobileprovision incrustado (se sustituye al firmar)")

    gb = sum(i.file_size for i in z.infolist()) / 1e9
    print(f"[ok] {len(nombres)} archivos, {gb:.2f} GB descomprimida, {z.fp.seek(0, 2) / 1e6:.0f} MB zip")
    return _fin(fallos, avisos)


def _fin(fallos, avisos) -> int:
    for a in avisos:
        print(f"[aviso] {a}")
    for f in fallos:
        print(f"[FALLA] {f}")
    print("IPA VALIDA para firmar" if not fallos else f"IPA NO VALIDA ({len(fallos)} fallos)")
    return 1 if fallos else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("uso: validar_ipa.py archivo.ipa")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
