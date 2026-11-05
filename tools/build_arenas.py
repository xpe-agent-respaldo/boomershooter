#!/usr/bin/env python3
"""Genera los tres mapas de arena de Boomer Shooter como escenas .tscn reales.

Cada arena hereda de TestLevel (jugador, HUD de oleadas, spawner, red) pero
REEMPLAZA por completo el nodo Map, el entorno, la luz y los puntos de spawn.
Asi dejan de ser "el mismo cuarto con cajas" y pasan a ser lugares distintos:

  RecyclingPlant  planta industrial: nave central, cintas, compactadoras, tuneles
  StormVillage    aldea de tormenta: casas con tejado, calles, torre, graneros
  SpaceArena      puesto lunar: crater, modulos, antenas, rocas (baja gravedad visual)

Uso:  python3 tools/build_arenas.py
Escribe Levels/RecyclingPlant.tscn, Levels/StormVillage.tscn, Levels/SpaceArena.tscn
"""
import math
import os
import random

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LEVELS = os.path.join(ROOT, "Levels")


class Scene:
    """Constructor minimalista de .tscn con materiales y nodos CSG con colision."""

    def __init__(self, name, music_script=None):
        self.name = name
        self.subs = []          # (id, texto)
        self.nodes = []         # texto de nodos
        self.mats = {}          # clave -> id
        self.n = 0
        self.music_script = music_script

    def _sid(self, prefix):
        self.n += 1
        return f"{prefix}_{self.n}"

    def material(self, key, color, rough=0.9, metal=0.0, emission=None, emit_energy=1.0):
        if key in self.mats:
            return self.mats[key]
        sid = self._sid("Mat")
        lines = [f'[sub_resource type="StandardMaterial3D" id="{sid}"]']
        lines.append("albedo_color = Color(%.3f, %.3f, %.3f, 1)" % color)
        lines.append(f"roughness = {rough}")
        if metal:
            lines.append(f"metallic = {metal}")
        if emission:
            lines.append("emission_enabled = true")
            lines.append("emission = Color(%.3f, %.3f, %.3f, 1)" % emission)
            lines.append(f"emission_energy_multiplier = {emit_energy}")
        self.subs.append((sid, "\n".join(lines)))
        self.mats[key] = sid
        return sid

    def box(self, name, pos, size, mat, parent="Map", rot_y=0.0, collide=True):
        rot = ""
        if rot_y:
            rot = f"\nrotation = Vector3(0, {math.radians(rot_y):.5f}, 0)"
        col = "\nuse_collision = true\ncollision_layer = 1\ncollision_mask = 0" if collide else ""
        self.nodes.append(
            f'[node name="{name}" type="CSGBox3D" parent="{parent}"]\n'
            f"position = Vector3({pos[0]}, {pos[1]}, {pos[2]}){rot}\n"
            f"size = Vector3({size[0]}, {size[1]}, {size[2]})"
            f"{col}\n"
            f'material = SubResource("{mat}")\n'
        )

    def cyl(self, name, pos, radius, height, mat, parent="Map", sides=14):
        self.nodes.append(
            f'[node name="{name}" type="CSGCylinder3D" parent="{parent}"]\n'
            f"position = Vector3({pos[0]}, {pos[1]}, {pos[2]})\n"
            f"radius = {radius}\nheight = {height}\nsides = {sides}\n"
            "use_collision = true\ncollision_layer = 1\ncollision_mask = 0\n"
            f'material = SubResource("{mat}")\n'
        )

    def sphere(self, name, pos, radius, mat, parent="Map", squash=1.0):
        sc = ""
        if squash != 1.0:
            sc = f"\nscale = Vector3(1, {squash}, 1)"
        self.nodes.append(
            f'[node name="{name}" type="CSGSphere3D" parent="{parent}"]\n'
            f"position = Vector3({pos[0]}, {pos[1]}, {pos[2]}){sc}\n"
            f"radius = {radius}\nradial_segments = 12\nrings = 8\n"
            "use_collision = true\ncollision_layer = 1\ncollision_mask = 0\n"
            f'material = SubResource("{mat}")\n'
        )

    def sign(self, name, pos, text, color, size=64):
        self.nodes.append(
            f'[node name="{name}" type="Label3D" parent="Map"]\n'
            f"position = Vector3({pos[0]}, {pos[1]}, {pos[2]})\n"
            f'text = "{text}"\nfont_size = {size}\noutline_size = 14\n'
            "modulate = Color(%.3f, %.3f, %.3f, 1)\nbillboard = 1\n" % color
        )

    def light(self, name, pos, color, energy, rng):
        self.nodes.append(
            f'[node name="{name}" type="OmniLight3D" parent="Map"]\n'
            f"position = Vector3({pos[0]}, {pos[1]}, {pos[2]})\n"
            "light_color = Color(%.3f, %.3f, %.3f, 1)\n" % color
            + f"light_energy = {energy}\nomni_range = {rng}\nshadow_enabled = false\n"
        )


def render_scene(sc, env, sun, spawns, script_path=None):
    """Compone el texto final del .tscn heredando de TestLevel."""
    ext = ['[ext_resource type="PackedScene" path="res://Levels/ArenaBase.tscn" id="1_base"]']
    if script_path:
        ext.append(f'[ext_resource type="Script" path="{script_path}" id="2_script"]')
    load_steps = 1 + len(ext) + len(sc.subs) + len(env["subs"])
    out = [f"[gd_scene load_steps={load_steps} format=3]", ""]
    out += ext + [""]
    for _, text in sc.subs:
        out += [text, ""]
    for text in env["subs"]:
        out += [text, ""]

    head = f'[node name="{sc.name}" instance=ExtResource("1_base")]'
    if script_path:
        head += '\nscript = ExtResource("2_script")'
    out += [head, ""]

    # entorno propio del mapa
    out += [
        '[node name="WorldEnvironment" parent="Environment" index="0"]',
        f'environment = SubResource("{env["env_id"]}")',
        "",
        '[node name="DirectionalLight3D" parent="Environment" index="1"]',
        "transform = Transform3D(%s)" % sun["transform"],
        "light_color = Color(%.3f, %.3f, %.3f, 1)" % sun["color"],
        f'light_energy = {sun["energy"]}',
        "shadow_enabled = false",
        "",
    ]

    # ArenaBase trae Map vacio: solo se anade la geometria propia del mapa.
    out += ["\n".join(sc.nodes)]

    # spawns propios
    for i, (x, y, z) in enumerate(spawns, 1):
        if i <= 4:   # los cuatro que trae ArenaBase se reubican
            out += [f'[node name="SpawnPoint{i}" parent="SpawnPoints" index="{i-1}"]']
        else:        # el resto son nodos nuevos
            out += [f'[node name="SpawnPoint{i}" type="Marker3D" parent="SpawnPoints"]']
        out += [f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, {y}, {z})", ""]
    return "\n".join(out) + "\n"




# ---------------------------------------------------------------------------
# Verticalidad. Medido en el motor: salto simple 1.58 m, doble salto 2.03 m.
# Reglas: escalon <= 0.45 m (se sube andando), cornisa <= 1.2 m (un salto),
# todo lo mas alto solo por escalera o rampa.
# ---------------------------------------------------------------------------
STEP_H = 0.45


def stairs(sc, name, x, z, height, direction="+z", width=2.6, run=0.9, mat=None, parent="Map"):
    """Escalera de peldanos de STEP_H hasta `height`. direction: sentido en que se sube."""
    n = max(1, int(math.ceil(height / STEP_H)))
    step = height / n
    for i in range(n):
        off = i * run
        if direction == "+z":
            pos = (x, step * (i + 0.5), z + off)
            size = (width, step * (i + 1), run)
        elif direction == "-z":
            pos = (x, step * (i + 0.5), z - off)
            size = (width, step * (i + 1), run)
        elif direction == "+x":
            pos = (x + off, step * (i + 0.5), z)
            size = (run, step * (i + 1), width)
        else:
            pos = (x - off, step * (i + 0.5), z)
            size = (run, step * (i + 1), width)
        # cada peldano es un bloque macizo desde el suelo: sin huecos por debajo
        sc.box(f"{name}{i}", (pos[0], size[1] / 2, pos[2]), size, mat, parent=parent)
    return n * run


def ramp(sc, name, x, z, length, height, direction="+z", width=3.0, mat=None):
    """Rampa recta que SUBE desde el suelo en (x, z) hasta `height` tras `length` metros.

    El punto (x, z) es el PIE de la rampa (y=0). Se avanza hacia `direction`.
    Verificado: el eje local +Z debe apuntar hacia arriba; con pitch positivo en Godot
    apuntaria hacia abajo, por eso se usa el signo negativo en _ramp_basis.
    """
    ang = math.degrees(math.atan2(height, length))
    hyp = math.hypot(length, height)
    dx, dz = {"+z": (0, 1), "-z": (0, -1), "+x": (1, 0), "-x": (-1, 0)}[direction]
    yaw = {"+z": 0.0, "-z": 180.0, "+x": 90.0, "-x": -90.0}[direction]
    # centro de la rampa: a media longitud y media altura desde el pie
    cx = x + dx * length / 2
    cz = z + dz * length / 2
    sc.nodes.append(
        f'[node name="{name}" type="CSGBox3D" parent="Map"]\n'
        f"transform = Transform3D({_ramp_basis(yaw, ang)}, {cx}, {height / 2 - 0.25 / math.cos(math.radians(ang))}, {cz})\n"
        f"size = Vector3({width}, 0.5, {hyp:.3f})\n"
        "use_collision = true\ncollision_layer = 1\ncollision_mask = 0\n"
        f'material = SubResource("{mat}")\n')


def _ramp_basis(yaw_deg, pitch_deg):
    """Rotacion Ry(yaw) * Rx(-pitch): el extremo local +Z SUBE (comprobado numericamente)."""
    y, p = math.radians(yaw_deg), math.radians(-pitch_deg)
    cy, sy, cp, sp = math.cos(y), math.sin(y), math.cos(p), math.sin(p)
    m = [[cy, sy * sp, sy * cp], [0, cp, -sp], [-sy, cy * sp, cy * cp]]
    return ", ".join("%.5f" % v for row in m for v in row)


def enterable_house(sc, name, x, z, w, d, h, wall_mat, roof_mat, floor_mat, door_side="+z",
                    door_w=2.4, door_h=2.6, wall_t=0.5, with_loft=True, stair_mat=None):
    """Casa con interior hueco, puerta, ventanas y desvan con escalera y acceso a azotea.

    Las paredes son 4 bloques con un hueco real en la puerta. Dentro hay suelo propio
    y, si with_loft, un entrepiso al que se sube por una escalera interior.
    """
    # suelo interior elevado 0.1 para marcar la entrada
    sc.box(f"{name}Floor", (x, 0.05, z), (w, 0.1, d), floor_mat)
    # paredes: la del lado de la puerta se parte en dos con un dintel
    sides = {
        "+z": ((x, z + d / 2), True), "-z": ((x, z - d / 2), True),
        "+x": ((x + w / 2, z), False), "-x": ((x - w / 2, z), False),
    }
    for side, ((cx, cz), along_x) in sides.items():
        length = w if along_x else d
        size = (length, h, wall_t) if along_x else (wall_t, h, length)
        if side == door_side:
            half = (length - door_w) / 2
            off = (door_w + half) / 2
            for sgn, tag in ((-1, "A"), (1, "B")):
                if along_x:
                    sc.box(f"{name}Wall{side}{tag}", (cx + sgn * (door_w / 2 + half / 2), h / 2, cz),
                           (half, h, wall_t), wall_mat)
                else:
                    sc.box(f"{name}Wall{side}{tag}", (cx, h / 2, cz + sgn * (door_w / 2 + half / 2)),
                           (wall_t, h, half), wall_mat)
            # dintel sobre la puerta
            lh = h - door_h
            if along_x:
                sc.box(f"{name}Lintel{side}", (cx, door_h + lh / 2, cz), (door_w, lh, wall_t), wall_mat)
            else:
                sc.box(f"{name}Lintel{side}", (cx, door_h + lh / 2, cz), (wall_t, lh, door_w), wall_mat)
        else:
            sc.box(f"{name}Wall{side}", (cx, h / 2, cz), size, wall_mat)
    # techo / azotea transitable
    sc.box(f"{name}Roof", (x, h + 0.15, z), (w + 0.6, 0.3, d + 0.6), roof_mat)
    # parapeto bajo en la azotea para cobertura
    for tag, (px, pz, sx, sz) in {
        "N": (x, z - d / 2, w + 0.6, 0.3), "S": (x, z + d / 2, w + 0.6, 0.3),
        "E": (x + w / 2, z, 0.3, d + 0.6), "W": (x - w / 2, z, 0.3, d + 0.6)}.items():
        sc.box(f"{name}Parapet{tag}", (px, h + 0.3 + 0.45, pz), (sx, 0.9, sz), roof_mat)
    if with_loft:
        # Entrepiso a 2.7 m en el fondo de la casa, con la escalera ENTERA dentro: arranca
        # pasada la pared de la fachada (no en ella; antes la fachada cortaba la escalera a
        # los 0.9 m de altura) y sube hacia el fondo hasta tocar el entrepiso.
        loft_h = 2.7
        run = 0.9
        n = max(1, int(math.ceil(loft_h / STEP_H)))
        stair_len = n * run                                  # 5.4 m de recorrido
        back = -1 if door_side == "+z" else 1                 # sentido hacia el fondo
        front = z - back * (d / 2)                            # z de la fachada con la puerta
        stairs_start = front + back * (wall_t / 2 + 0.6)      # pie de la escalera, dentro
        stairs_end = stairs_start + back * stair_len
        loft_back = z + back * (d / 2 - wall_t / 2)           # pared del fondo (cara interior)
        loft_len = abs(loft_back - stairs_end)
        loft_z = (stairs_end + loft_back) / 2
        sc.box(f"{name}Loft", (x, loft_h, loft_z), (w - wall_t * 2, 0.3, max(loft_len, 1.0)), floor_mat)
        stairs(sc, f"{name}Stair", x - w / 2 + wall_t + 1.3, stairs_start, loft_h,
               direction=("+z" if back == 1 else "-z"), width=2.0, run=run, mat=stair_mat or floor_mat)


# ---------------------------------------------------------------------------
# Entornos (cielo, niebla, luz) por mapa
# ---------------------------------------------------------------------------
def make_env(tag, sky_top, sky_hor, ground, fog_col, fog_density, ambient=None, ambient_energy=0.6):
    sky_id, mat_id, env_id = f"Sky_{tag}", f"SkyMat_{tag}", f"Env_{tag}"
    mat = (f'[sub_resource type="ProceduralSkyMaterial" id="{mat_id}"]\n'
           "sky_top_color = Color(%.3f, %.3f, %.3f, 1)\n"
           "sky_horizon_color = Color(%.3f, %.3f, %.3f, 1)\n"
           "ground_bottom_color = Color(%.3f, %.3f, %.3f, 1)\n"
           "ground_horizon_color = Color(%.3f, %.3f, %.3f, 1)" % (sky_top + sky_hor + ground + sky_hor))
    sky = f'[sub_resource type="Sky" id="{sky_id}"]\nsky_material = SubResource("{mat_id}")'
    amb = ambient or sky_hor
    env = (f'[sub_resource type="Environment" id="{env_id}"]\n'
           "background_mode = 2\n"
           f'sky = SubResource("{sky_id}")\n'
           "ambient_light_source = 2\n"
           "ambient_light_color = Color(%.3f, %.3f, %.3f, 1)\n"
           f"ambient_light_energy = {ambient_energy}\n"
           "tonemap_mode = 2\nglow_enabled = false\nfog_enabled = true\n"
           "fog_light_color = Color(%.3f, %.3f, %.3f, 1)\n"
           f"fog_density = {fog_density}" % (amb + fog_col))
    return {"subs": [mat, sky, env], "env_id": env_id}


def sun_transform(pitch_deg, yaw_deg):
    p, y = math.radians(pitch_deg), math.radians(yaw_deg)
    cp, sp, cy, sy = math.cos(p), math.sin(p), math.cos(y), math.sin(y)
    # rotacion Y(yaw) * X(pitch)
    b = [[cy, sy * sp, sy * cp], [0, cp, -sp], [-sy, cy * sp, cy * cp]]
    return ", ".join("%.5f" % v for row in b for v in row) + ", 0, 0, 0"


def perimeter(sc, half, height, mat, thick=2.0):
    """Cuatro muros perimetrales con colision."""
    sc.box("WallN", (0, height / 2, -half), (half * 2 + thick, height, thick), mat)
    sc.box("WallS", (0, height / 2, half), (half * 2 + thick, height, thick), mat)
    sc.box("WallE", (half, height / 2, 0), (thick, height, half * 2 + thick), mat)
    sc.box("WallW", (-half, height / 2, 0), (thick, height, half * 2 + thick), mat)


# ---------------------------------------------------------------------------
# 1) PLANTA DE RECICLAJE
# ---------------------------------------------------------------------------
def build_recycling():
    sc = Scene("RecyclingPlant")
    concrete = sc.material("concrete", (0.26, 0.25, 0.27), 0.95)
    dark = sc.material("dark", (0.12, 0.12, 0.14), 0.9, 0.3)
    rust = sc.material("rust", (0.45, 0.20, 0.10), 0.9, 0.2)
    steel = sc.material("steel", (0.36, 0.38, 0.42), 0.5, 0.7)
    hazard = sc.material("hazard", (0.85, 0.62, 0.05), 0.7)
    glow = sc.material("glow", (0.2, 0.05, 0.02), 0.6, emission=(1.0, 0.35, 0.08), emit_energy=1.6)
    toxic = sc.material("toxic", (0.05, 0.2, 0.05), 0.4, emission=(0.2, 0.9, 0.25), emit_energy=1.2)

    H = 30
    sc.box("Floor", (0, -0.5, 0), (62, 1, 62), concrete)
    perimeter(sc, H, 14, dark)
    sc.box("Ceiling", (0, 15, 0), (62, 1, 62), dark, collide=False)

    # franjas de peligro en el suelo
    for i, z in enumerate((-18, -6, 6, 18)):
        sc.box(f"HazardStripe{i}", (0, 0.02, z), (58, 0.04, 0.8), hazard, collide=False)

    # nave central: clasificadora con chimenea
    sc.box("Sorter", (0, 3, 0), (10, 6, 8), steel)
    sc.box("SorterTop", (0, 6.6, 0), (12, 1.2, 10), rust)
    sc.cyl("Chimney", (0, 11, 0), 1.6, 9, rust)
    sc.box("SorterGlow", (0, 3, 4.05), (6, 1.4, 0.1), glow, collide=False)

    # cintas transportadoras laterales
    for side, x in (("W", -17), ("E", 17)):
        sc.box(f"Belt{side}", (x, 0.6, 0), (4, 1.2, 40), dark)
        for k, z in enumerate(range(-16, 17, 8)):
            sc.box(f"BeltPost{side}{k}", (x, 2.2, z), (0.6, 2.4, 0.6), steel)
        sc.box(f"BeltRail{side}", (x, 3.4, 0), (0.5, 0.5, 40), hazard, collide=False)

    # compactadoras al norte (dos prensas con hueco central)
    sc.box("CompactorL", (-9, 3.5, -22), (9, 7, 6), steel)
    sc.box("CompactorR", (9, 3.5, -22), (9, 7, 6), steel)
    sc.box("CompactorTopL", (-9, 7.6, -22), (10, 1.2, 7), rust)
    sc.box("CompactorTopR", (9, 7.6, -22), (10, 1.2, 7), rust)
    sc.box("CompactorGlowL", (-9, 3.5, -18.95), (5, 1.6, 0.1), glow, collide=False)
    sc.box("CompactorGlowR", (9, 3.5, -18.95), (5, 1.6, 0.1), glow, collide=False)

    # pasarela elevada con dos rampas de acceso
    sc.box("Catwalk", (0, 5, 22), (30, 0.8, 5), steel)
    sc.box("CatwalkRailF", (0, 6.2, 24.4), (30, 1.6, 0.3), hazard, collide=False)
    sc.box("RampW", (-18, 2.5, 22), (7, 0.7, 5), steel, rot_y=0)
    sc.box("RampE", (18, 2.5, 22), (7, 0.7, 5), steel, rot_y=0)
    for k, x in enumerate((-13, -7, 7, 13)):
        sc.box(f"CatwalkLeg{k}", (x, 2.2, 22), (0.8, 4.4, 0.8), dark)

    # contenedores y barriles como cobertura
    random.seed(11)
    spots = [(-8, 10), (8, 11), (-24, -8), (24, 9), (-4, -10), (5, -9),
             (-22, 16), (22, -14), (-12, 18), (12, 19)]
    for i, (x, z) in enumerate(spots):
        w, d = random.choice([(4, 2.4), (3, 3), (5, 2.6)])
        sc.box(f"Container{i}", (x, 1.4, z), (w, 2.8, d), random.choice([rust, steel, hazard]),
               rot_y=random.choice([0, 20, -25, 45]))
    for i, (x, z) in enumerate([(-6, 3), (6, -4), (-26, 2), (26, -2), (0, -14), (-14, 8), (14, -8)]):
        sc.cyl(f"Barrel{i}", (x, 0.9, z), 0.8, 1.8, toxic if i % 3 == 0 else rust)

    # luces de ambiente
    for i, (x, z) in enumerate([(-18, -18), (18, -18), (-18, 18), (18, 18), (0, 0)]):
        sc.light(f"Lamp{i}", (x, 8, z), (1.0, 0.62, 0.3), 2.2, 22)
    sc.sign("PlantSign", (0, 9.5, 14), "RECYCLING PLANT", (1.0, 0.55, 0.18), 70)

    env = make_env("Plant", (0.04, 0.04, 0.06), (0.22, 0.14, 0.10), (0.03, 0.03, 0.04),
                   (0.20, 0.13, 0.09), 0.012, ambient=(0.35, 0.26, 0.22), ambient_energy=0.8)
    sun = {"transform": sun_transform(-58, 30), "color": (1.0, 0.72, 0.5), "energy": 0.7}
    spawns = [(-24, 1, -24), (24, 1, -24), (-24, 1, 14), (24, 1, 14), (0, 1, -12), (-26, 1, 0)]
    return render_scene(sc, env, sun, spawns)


# ---------------------------------------------------------------------------
# 2) ALDEA DE TORMENTA  (referencia: casas blancas con tejado rojo, torre de ladrillo)
# ---------------------------------------------------------------------------
def build_village():
    sc = Scene("StormVillage")
    grass = sc.material("grass", (0.20, 0.34, 0.12), 1.0)
    path = sc.material("path", (0.42, 0.38, 0.33), 1.0)
    plaster = sc.material("plaster", (0.86, 0.84, 0.88), 0.9)
    roof = sc.material("roof", (0.55, 0.16, 0.10), 0.85)
    brick = sc.material("brick", (0.52, 0.50, 0.55), 0.95)
    wood = sc.material("wood", (0.30, 0.16, 0.08), 0.9)
    leaf = sc.material("leaf", (0.12, 0.38, 0.12), 0.95)
    trunk = sc.material("trunk", (0.25, 0.15, 0.09), 1.0)
    wheat = sc.material("wheat", (0.78, 0.60, 0.12), 1.0)
    window = sc.material("window", (0.10, 0.18, 0.40), 0.3, emission=(0.2, 0.35, 0.8), emit_energy=0.6)
    stone = sc.material("stone", (0.30, 0.30, 0.32), 1.0)

    H = 34
    sc.box("Ground", (0, -0.5, 0), (72, 1, 72), grass)
    # muros de piedra bajos + setos que delimitan el pueblo
    perimeter(sc, H, 5, stone)
    # camino principal en cruz
    sc.box("PathNS", (0, 0.03, 0), (5, 0.06, 68), path, collide=False)
    sc.box("PathEW", (0, 0.04, 2), (68, 0.06, 5), path, collide=False)
    sc.cyl("Plaza", (0, 0.05, 2), 7, 0.1, path, sides=24)

    floor_wood = sc.material("floorWood", (0.34, 0.22, 0.13), 0.9)

    def decor(name, x, z, w, d, h):
        """Tejado a dos aguas y puerta pintada encima del volumen hueco."""
        sc.box(f"{name}RoofRidge", (x, h + 1.0, z), (w - 1.2, 0.6, d - 1.2), roof, collide=False)

    # casas con interior: se entra por la puerta y se sube al desvan y a la azotea
    for nm, x, z, w, d, h, door in [
        ("HouseA", -18, -14, 10, 8, 4.6, "+z"),
        ("HouseB", 18, -16, 9, 9, 4.6, "+z"),
        ("HouseC", -20, 14, 9, 8, 4.6, "-z"),
        ("HouseD", 20, 12, 10, 9, 4.6, "-z"),
        ("HouseE", -6, -26, 8, 7, 4.6, "+z"),
        ("HouseF", 8, 25, 8, 7, 4.6, "-z"),
    ]:
        enterable_house(sc, nm, x, z, w, d, h, plaster, roof, floor_wood, door_side=door,
                        stair_mat=wood)
        decor(nm, x, z, w, d, h)
        sc.box(f"{nm}WinL", (x - w / 3, h * 0.55, z + (d / 2 if door != "+z" else -d / 2)),
               (1.2, 1.1, 0.12), window, collide=False)
        # escalera exterior de 3 peldanos hasta la azotea para poder subir sin entrar
        stairs(sc, f"{nm}Out", x + w / 2 + 1.4, z - d / 2 + 0.6, h + 0.3, direction="+z",
               width=1.8, run=0.9, mat=wood)

    # Torre de ladrillo con mirador a 8.1 m. Se sube por una rampa lateral larga (30 grados)
    # que arranca en el suelo y llega al borde del mirador; sin tramos ni giros que se atasquen.
    tx, tz = 0, -16
    sc.box("TowerBase", (tx, 4.0, tz), (6, 8.0, 6), brick)
    sc.box("TowerDeck", (tx, 8.15, tz), (9, 0.3, 9), roof)
    # Barandilla alrededor del mirador. El lado sur (por donde llega la rampa, en x=3) lleva
    # un hueco de 3.6 m: sin el, la barandilla tapaba justo la boca de la rampa.
    sc.box("TowerRailN", (tx, 8.85, tz - 4.5), (9, 1.1, 0.4), brick)
    sc.box("TowerRailE", (tx + 4.5, 8.85, tz), (0.4, 1.1, 9), brick)
    sc.box("TowerRailW", (tx - 4.5, 8.85, tz), (0.4, 1.1, 9), brick)
    # sur: dos tramos, uno a cada lado del hueco (el hueco cubre x de 1.2 a 4.8)
    sc.box("TowerRailS1", (tx - 1.65, 8.85, tz + 4.5), (5.7, 1.1, 0.4), brick)
    sc.box("TowerRailS2", (tx + 4.65, 8.85, tz + 4.5), (0.3, 1.1, 0.4), brick, collide=False)
    # 13.5 m horizontales a 31.6 grados: alcanza 8.3 JUSTO en el borde de la cubierta (z=-11.5)
    ramp(sc, "TowerRamp", tx + 3.0, tz + 18.0, 13.5, 8.3, direction="-z", width=2.6, mat=wood)

    # granero con sacos y carreta
    sc.box("BarnWalls", (26, 3, -2), (6, 6, 10), plaster)
    sc.box("BarnRoof", (26, 6.8, -2), (7.6, 0.7, 11.6), roof)
    sc.box("BarnOpening", (22.95, 2, -2), (0.1, 3.4, 4), dark_mat(sc), collide=False)
    for i, (x, z) in enumerate([(23.4, 1), (23.4, -5), (24.2, 3)]):
        sc.box(f"Sack{i}", (x, 0.5, z), (0.9, 1.0, 0.8), wheat)

    # campos de trigo (cobertura baja) y arboles con copa
    for i, (x, z) in enumerate([(-28, -4), (-28, 4), (-24, 0), (28, 18), (28, 24)]):
        sc.box(f"Wheat{i}", (x, 0.7, z), (4, 1.4, 5), wheat)
    random.seed(5)
    for i, (x, z) in enumerate([(-9, 8), (10, -6), (-12, -4), (13, 18), (-3, 22), (6, -28), (-30, 22), (30, -22)]):
        sc.cyl(f"Trunk{i}", (x, 2.2, z), 0.55, 4.4, trunk, sides=8)
        sc.sphere(f"Leaf{i}", (x, 5.6, z), 2.8 + random.random(), leaf, squash=0.85)

    # cobertura: muretes, carros, barriles
    for i, (x, z, yaw) in enumerate([(-8, 4, 15), (8, 6, -20), (-3, 12, 0), (4, -6, 40), (-14, -2, 70), (14, 2, -35)]):
        sc.box(f"Wall{i}", (x, 0.8, z), (3.6, 1.6, 0.7), stone, rot_y=yaw)
    for i, (x, z) in enumerate([(-9, -10), (10, 0), (-1, 18), (16, -8)]):
        sc.cyl(f"Barrel{i}", (x, 0.7, z), 0.6, 1.4, wood)

    sc.light("Flash0", (0, 12, 0), (0.55, 0.65, 1.0), 1.6, 40)
    sc.sign("VillageSign", (0, 9, -2), "STORM VILLAGE", (1.0, 0.55, 0.2), 64)

    env = make_env("Village", (0.34, 0.42, 0.62), (0.62, 0.58, 0.66), (0.10, 0.12, 0.08),
                   (0.50, 0.52, 0.60), 0.010, ambient=(0.55, 0.58, 0.68), ambient_energy=0.9)
    sun = {"transform": sun_transform(-48, -35), "color": (1.0, 0.88, 0.72), "energy": 1.1}
    spawns = [(-28, 1, -26), (28, 1, -26), (-28, 1, 26), (28, 1, 26), (0, 1, 30), (-30, 1, 0)]
    return render_scene(sc, env, sun, spawns)


def dark_mat(sc):
    return sc.material("barnDark", (0.04, 0.03, 0.03), 1.0)


# ---------------------------------------------------------------------------
# 3) ARENA LUNAR  (referencia: picos oscuros, cielo violeta)
# ---------------------------------------------------------------------------
def build_space():
    sc = Scene("SpaceArena")
    regolith = sc.material("regolith", (0.20, 0.19, 0.22), 1.0)
    rock = sc.material("rock", (0.15, 0.15, 0.18), 1.0)
    rockhi = sc.material("rockhi", (0.30, 0.28, 0.34), 1.0)
    hull = sc.material("hull", (0.55, 0.58, 0.64), 0.4, 0.6)
    panel = sc.material("panel", (0.10, 0.14, 0.26), 0.3, 0.5)
    beacon = sc.material("beacon", (0.1, 0.02, 0.05), 0.5, emission=(1.0, 0.1, 0.3), emit_energy=2.4)
    cyan = sc.material("cyan", (0.02, 0.1, 0.14), 0.4, emission=(0.2, 0.85, 1.0), emit_energy=1.8)

    H = 36
    sc.box("Ground", (0, -0.5, 0), (76, 1, 76), regolith)
    # crater central: aro de rocas
    for i in range(14):
        a = i / 14 * math.tau
        x, z = math.cos(a) * 11, math.sin(a) * 11
        s = 2.4 + (i % 3) * 0.7
        sc.sphere(f"CraterRock{i}", (round(x, 2), 0.6, round(z, 2)), s, rock, squash=0.55)

    # picos perimetrales (silueta de la referencia): torres de roca altas
    random.seed(21)
    for i in range(26):
        a = i / 26 * math.tau
        r = H - random.random() * 2
        x, z = round(math.cos(a) * r, 2), round(math.sin(a) * r, 2)
        h = random.randint(9, 22)
        w = random.randint(4, 8)
        sc.box(f"Peak{i}", (x, h / 2, z), (w, h, w), rockhi if i % 2 else rock, rot_y=random.randint(0, 90))
        sc.box(f"PeakTip{i}", (x, h + 1.8, z), (w * 0.45, 4, w * 0.45), rockhi, rot_y=random.randint(0, 90))
    perimeter(sc, H + 1, 6, rock, thick=2.5)

    # modulos habitables
    sc.box("ModuleMain", (0, 2.6, -2), (12, 5.2, 8), hull)
    sc.cyl("Dome", (0, 5.4, -2), 4.4, 1.2, panel, sides=20)
    sc.box("ModuleWindow", (0, 3.2, 2.05), (8, 1.2, 0.1), cyan, collide=False)
    sc.box("ModuleDoor", (0, 1.3, 2.05), (2, 2.6, 0.1), beacon, collide=False)
    sc.box("ModuleWingW", (-10, 2.0, -2), (8, 4, 5), hull)
    sc.box("ModuleWingE", (10, 2.0, -2), (8, 4, 5), hull)
    sc.box("Corridor", (0, 1.6, -12), (4, 3.2, 14), hull)

    # antenas y paneles solares
    for i, (x, z) in enumerate([(-22, 14), (22, 14), (-22, -20), (22, -20)]):
        sc.cyl(f"Antenna{i}", (x, 4, z), 0.35, 8, hull, sides=8)
        sc.sphere(f"Dish{i}", (x, 8.4, z), 1.6, hull, squash=0.4)
        sc.sphere(f"Beacon{i}", (x, 9.4, z), 0.35, beacon)
    for i, x in enumerate((-8, 0, 8)):
        sc.box(f"Solar{i}", (x, 1.2, 20), (6, 0.4, 3.2), panel, rot_y=0)
        sc.box(f"SolarLeg{i}", (x, 0.6, 20), (0.5, 1.2, 0.5), hull)

    # contenedores de carga y rocas sueltas
    random.seed(33)
    for i, (x, z) in enumerate([(-14, 8), (14, 8), (-16, -10), (16, -10), (-6, 14), (7, 15), (-26, 2), (26, 2)]):
        sc.box(f"Crate{i}", (x, 1.2, z), (3.2, 2.4, 3.2), hull, rot_y=random.choice([0, 25, -30]))
    for i in range(9):
        x, z = random.uniform(-28, 28), random.uniform(-28, 28)
        if abs(x) < 8 and abs(z) < 8:
            continue
        sc.sphere(f"Boulder{i}", (round(x, 2), 0.8, round(z, 2)), random.uniform(1.2, 2.2), rock, squash=0.7)

    sc.light("Core", (0, 6, 4), (0.3, 0.8, 1.0), 2.4, 26)
    sc.light("Alarm0", (-10, 5, 4), (1.0, 0.2, 0.3), 1.8, 18)
    sc.light("Alarm1", (10, 5, 4), (1.0, 0.2, 0.3), 1.8, 18)
    sc.sign("MoonSign", (0, 10, 8), "LUNAR OUTPOST", (0.6, 0.8, 1.0), 64)

    env = make_env("Moon", (0.012, 0.014, 0.06), (0.28, 0.16, 0.38), (0.01, 0.01, 0.02),
                   (0.30, 0.18, 0.40), 0.006, ambient=(0.30, 0.28, 0.48), ambient_energy=0.8)
    sun = {"transform": sun_transform(-35, 150), "color": (0.62, 0.68, 1.0), "energy": 1.0}
    spawns = [(-26, 1, -26), (26, 1, -26), (-26, 1, 24), (26, 1, 24), (0, 1, -26), (0, 1, 26)]
    return render_scene(sc, env, sun, spawns, script_path="res://Scripts/space_arena.gd")


if __name__ == "__main__":
    builds = {
        "RecyclingPlant.tscn": build_recycling,
        "StormVillage.tscn": build_village,
        "SpaceArena.tscn": build_space,
    }
    for fname, fn in builds.items():
        text = fn()
        with open(os.path.join(LEVELS, fname), "w") as f:
            f.write(text)
        print(f"{fname}: {len(text)//1024} KB, {text.count('[node')} nodos")
