#!/usr/bin/env python3
"""Anade el escondite (cabina de nave estrellada) al mapa espacial. Idempotente: si ya esta, lo reemplaza.

Esta en (-18, -32), el hueco plano con mas espacio libre del mapa (medido contra las 153 piezas).
Entrada de 2 m mirando al centro del mapa, rendija de vigilancia al lado opuesto, techo a 3.4 m.
Mismos materiales y capa de colision que el resto del mapa (Mat_4 casco metalico, Mat_3 interior).
"""
import re, sys
RUTA = "Levels/SpaceArena.tscn"
CX, CZ = -18.0, -32.0          # centro de la cabina
L = 8.0                        # lado exterior
GROSOR = 0.5
ALTO = 3.4
PUERTA = 2.0
MARCA = "; --- ESCONDITE_INICIO"
FIN = "; --- ESCONDITE_FIN"

def caja(nombre, x, y, z, sx, sy, sz, mat):
    return (f'[node name="{nombre}" type="CSGBox3D" parent="Map"]\n'
            f'position = Vector3({x:.2f}, {y:.2f}, {z:.2f})\n'
            f'size = Vector3({sx:.2f}, {sy:.2f}, {sz:.2f})\n'
            'use_collision = true\ncollision_layer = 1\ncollision_mask = 0\n'
            f'material = SubResource("{mat}")\n')

mitad = L / 2
piezas = []
# muro norte (lejos del centro del mapa, que esta hacia +x/+z): completo
piezas.append(caja("EsconditeNorte", CX, ALTO/2, CZ - mitad + GROSOR/2, L, ALTO, GROSOR, "Mat_4"))
# muro oeste: completo
piezas.append(caja("EsconditeOeste", CX - mitad + GROSOR/2, ALTO/2, CZ, GROSOR, ALTO, L, "Mat_4"))
# muro este: con RENDIJA de vigilancia (dos tramos bajos + dintel alto)
ranura_y0, ranura_y1 = 1.5, 2.0
piezas.append(caja("EsconditeEsteBajo", CX + mitad - GROSOR/2, ranura_y0/2, CZ, GROSOR, ranura_y0, L, "Mat_4"))
piezas.append(caja("EsconditeEsteAlto", CX + mitad - GROSOR/2, (ranura_y1+ALTO)/2, CZ, GROSOR, ALTO-ranura_y1, L, "Mat_4"))
# muro sur: con PUERTA estrecha hacia el centro (dos tramos laterales)
tramo = (L - PUERTA) / 2
piezas.append(caja("EsconditeSurA", CX - mitad + tramo/2, ALTO/2, CZ + mitad - GROSOR/2, tramo, ALTO, GROSOR, "Mat_4"))
piezas.append(caja("EsconditeSurB", CX + mitad - tramo/2, ALTO/2, CZ + mitad - GROSOR/2, tramo, ALTO, GROSOR, "Mat_4"))
# dintel sobre la puerta
piezas.append(caja("EsconditeDintel", CX, ALTO - 0.4, CZ + mitad - GROSOR/2, PUERTA, 0.8, GROSOR, "Mat_4"))
# techo
piezas.append(caja("EsconditeTecho", CX, ALTO + 0.15, CZ, L, 0.3, L, "Mat_3"))
# caja de municion (decoracion) al fondo
piezas.append(caja("EsconditeCaja", CX - 2.4, 0.45, CZ - 2.6, 1.4, 0.9, 1.0, "Mat_3"))
luz = ('[node name="EsconditeLuz" type="OmniLight3D" parent="Map"]\n'
       f'position = Vector3({CX:.2f}, 2.6, {CZ:.2f})\n'
       'light_color = Color(0.45, 0.62, 1, 1)\nlight_energy = 1.4\nomni_range = 7.0\n')
bloque = MARCA + "\n" + "\n".join(piezas) + "\n" + luz + FIN + "\n"

t = open(RUTA, encoding="utf-8").read()
t = re.sub(r"# --- ESCONDITE_INICIO.*?# --- ESCONDITE_FIN\n", "", t, flags=re.S)
t = re.sub(re.escape(MARCA) + r".*?" + re.escape(FIN) + r"\n", "", t, flags=re.S)
t = t.rstrip("\n") + "\n\n" + bloque
open(RUTA, "w", encoding="utf-8").write(t)
print("escondite anadido:", len(piezas), "piezas + 1 luz en", (CX, CZ))
