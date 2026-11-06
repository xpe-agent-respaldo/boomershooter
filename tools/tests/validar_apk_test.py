#!/usr/bin/env python3
"""Prueba el validador de APK con APKs sinteticos: uno bueno y varios rotos."""
import io, os, struct, sys, tempfile, zipfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import validar_apk as V

fallos = 0
def check(n, ok, det=""):
    global fallos
    print(("  ok   " if ok else "  FALLA ") + n + ("" if ok else f"  [{det}]"))
    if not ok: fallos += 1

def axml(paquete, permisos, version="1.3.1"):
    """Construye un AndroidManifest binario minimo (UTF-16) como el que genera Godot/aapt."""
    cad = ["package", "versionName", "name", "manifest", "uses-permission", paquete, version] + list(permisos)
    def idx(s): return cad.index(s)
    datos, offs, pos = b"", [], 0
    for s in cad:
        offs.append(pos)
        b = struct.pack("<H", len(s)) + s.encode("utf-16-le") + b"\x00\x00"
        datos += b; pos += len(b)
    while len(datos) % 4: datos += b"\x00"
    ini = 28 + 4 * len(cad)
    pool = struct.pack("<HHI", 0x0001, 28, ini + len(datos)) + struct.pack("<IIIII", len(cad), 0, 0, ini, 0)
    pool += struct.pack("<%dI" % len(cad), *offs) + datos
    def elemento(nombre, attrs):
        # nodo: tipo, cabecera(16), tam, linea, comentario | attrExt: ns, name, attrStart(20), attrSize(20), count, id, class, style
        a = b""
        for nom, val in attrs:
            a += struct.pack("<iii", -1, idx(nom), idx(val)) + struct.pack("<HBBI", 8, 0, 0x03, idx(val))
        ext = struct.pack("<iiHHHHHH", -1, idx(nombre), 20, 20, len(attrs), 0, 0, 0)
        tam = 16 + len(ext) + len(a)
        return struct.pack("<HHIii", 0x0102, 16, tam, 1, -1) + ext + a
    cuerpo = elemento("manifest", [("package", paquete), ("versionName", version)])
    for p in permisos:
        cuerpo += elemento("uses-permission", [("name", p)])
    total = 8 + len(pool) + len(cuerpo)
    return struct.pack("<HHI", 0x0003, 8, total) + pool + cuerpo

def apk(permisos, paquete="com.boomershooter.game", arm64=True, online=True, vieja=False, firmado=True, dex=True):  # online: archivo suelto
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("AndroidManifest.xml", axml(paquete, permisos))
        if dex: z.writestr("classes.dex", b"dex\n035\0")
        if online: z.writestr("assets/online_defaults.cfg", b"[online]\nhost=\"x.onrender.com\"\n")
        z.writestr("assets/datos.gd", (V.CLAVE_VIEJA if vieja else b"nada"))
        if arm64: z.writestr("lib/arm64-v8a/libgodot_android.so", b"\x7fELF")
        if firmado: z.writestr("META-INF/CERT.SF", b"firma"); z.writestr("META-INF/CERT.RSA", b"x")
    f = tempfile.NamedTemporaryFile(suffix=".apk", delete=False); f.write(buf.getvalue()); f.close()
    return f.name

BUENOS = ["android.permission.INTERNET", "android.permission.RECORD_AUDIO", "android.permission.VIBRATE"]
def corre(ruta):
    import contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        return V.main(ruta)

print("\n[lector del manifiesto]")
m = V.leer_axml(axml("com.boomershooter.game", BUENOS))
check("lee el paquete", m["package"] == "com.boomershooter.game", str(m["package"]))
check("lee la version", m["version"] == "1.3.1", str(m["version"]))
check("lee los 3 permisos", m["permisos"] == set(BUENOS), str(m["permisos"]))

print("\n[validador]")
check("un APK correcto pasa", corre(apk(BUENOS)) == 0)
check("sin permiso de microfono FALLA (el chat de voz no andaria)", corre(apk(["android.permission.INTERNET", "android.permission.VIBRATE"])) == 1)
check("sin internet FALLA (online muerto)", corre(apk(["android.permission.RECORD_AUDIO", "android.permission.VIBRATE"])) == 1)
check("pidiendo camara FALLA (permiso de mas)", corre(apk(BUENOS + ["android.permission.CAMERA"])) == 1)
check("pidiendo ubicacion FALLA", corre(apk(BUENOS + ["android.permission.ACCESS_FINE_LOCATION"])) == 1)
check("paquete equivocado FALLA", corre(apk(BUENOS, paquete="com.otro.juego")) == 1)
check("sin libreria arm64 FALLA", corre(apk(BUENOS, arm64=False)) == 1)
check("sin online_defaults.cfg FALLA", corre(apk(BUENOS, online=False)) == 1)
check("con la clave vieja dentro FALLA", corre(apk(BUENOS, vieja=True)) == 1)
check("sin firmar FALLA", corre(apk(BUENOS, firmado=False)) == 1)
check("sin classes.dex FALLA", corre(apk(BUENOS, dex=False)) == 1)
check("un archivo que no es zip FALLA", corre(__file__) == 1)

print(f"\n{'TODO BIEN' if fallos == 0 else str(fallos) + ' FALLOS'}")
sys.exit(1 if fallos else 0)
