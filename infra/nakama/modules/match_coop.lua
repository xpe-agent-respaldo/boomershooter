--[[
  BoomerShooter authoritative coop waves runtime (Nakama Lua).
  Handler name: coopwave. Protocol: docs/SERVER_RUNTIME.md
  Reserved opcodes: 4100 voice, 9001/9002 NakamaMultiplayerBridge.
]]

local nk = require("nakama")

-- Opcodes
local OP_SPAWN = 1
local OP_SPAWN_OK = 2
local OP_SPAWN_REJECT = 3
local OP_DAMAGE = 10
local OP_ENEMY_HEALTH = 11
local OP_ENEMY_DEATH = 12
local OP_DEATH = 20
local OP_PLAYER_DEATH = 21
local OP_REVIVE = 30
local OP_REVIVE_OK = 31
local OP_REVIVE_REJECT = 32
local OP_REWARD = 40
local OP_WAVE_STATE = 50
local OP_MATCH_STATE = 60
local OP_PLAYER_STATE = 70      -- posicion/orientacion (antes chocaba con OP_DEATH=20)
local OP_HELP_CALL = 80         -- "necesito ayuda" (jugador -> equipo)
local OP_TEAM_ALERT = 81        -- aviso del servidor a todo el equipo
local OP_PING = 82
local OP_BOT_HIT = 83           -- un jugador entrenado te acerto (daño entrante)
local OP_BOT_SHOT = 84          -- disparo de un jugador entrenado (para el sonido)
local OP_HIT_BOT = 85           -- le diste a un jugador entrenado
local OP_BOT_DEATH = 86         -- un jugador entrenado cayo
local OP_GANG_ALERT = 87        -- aviso: se acerca una pandilla (o alguien quiere hablarte)
local OP_BEFRIEND = 88          -- quiero hacerme amigo de este
local OP_BEFRIEND_OK = 89       -- sois amigos
local OP_MATCH_CLOSE = 90
local OP_MATCH_RESULT = 91
local OP_VOICE = 92          -- paquete de voz (mu-law 8 kHz) para el chat
local OP_BOT_SAY = 93        -- un bot dice una frase (texto ya armado por el servidor)
local OP_BOT_POS = 94        -- posiciones de los bots (compacto, 10 Hz) para que se vean andar de forma fluida
local OP_ERROR = 99
local OP_META = 9001           -- canal interno de NakamaMultiplayerBridge (0 = soy host, 1 = toma este peer id)

local TICK_RATE = 10
local MAX_PLAYERS = 20          -- aforo por defecto de una sala
local MAX_PLAYERS_HARD = 40     -- techo duro: medido, una sala de 40 gasta ~11 ms al llenarse
                                -- (el coste crece al cuadrado: 100 jugadores = 63 ms).
                                -- Para cientos de usuarios se reparten en MUCHAS salas.
local MIN_PLAYERS_START = 1
-- Mapas jugables online (el cliente carga la escena segun este id).
local MAPS = {
  recycling_plant = { label = "Planta de Reciclaje" },
  storm_village   = { label = "Aldea de la Tormenta" },
  space_arena     = { label = "Arena Espacial" },
}
local DEFAULT_MAP = "recycling_plant"
-- Bots: companeros simulados por el servidor. Cuentan como jugadores en la sala,
-- caminan por el mapa y se retiran solos cuando entran humanos (nunca ocupan su hueco).
local BOTS_DEFAULT = 3
local BOTS_MAX = 5              -- tope de bots por sala (companeros + pandilla + solitario + amigos)
local BOT_STEP = 2.2              -- metros por segundo
local BOT_NAMES = { "Rojo-7", "Cenizas", "Gancho", "Pelusa", "Oxido", "Tuerca", "Vaca", "Mecha" }
-- La calle: pandillas con nombre propio, gente que va por libre y buena gente con la
-- que se puede hacer amistad. Se distinguen por el color del visor y la etiqueta.
local GANGS = {
  { name = "Los Oxido",        members = { "Tuerca", "Gancho", "Chispa", "Mecha" } },
  { name = "Calavera Negra",   members = { "Hueso", "Sombra", "Vela", "Cala" } },
  { name = "Los Cables Sueltos", members = { "Pelado", "Corto", "Tenso", "Varo" } },
  { name = "Sindicato Neon",   members = { "Tubo", "Luces", "Neon", "Foco" } },
  { name = "La Chatarra",      members = { "Chato", "Fierro", "Lata", "Birra" } },
  { name = "Los Tres Tornillos", members = { "Perno", "Clavo", "Navaja", "Cobre" } },
}
local SOLO_NAMES = { "El Que Va Solo", "Perro Flaco", "Zanahoria", "Media Suela", "Ronco" }
local AMIGO_NAMES = { "Tato el Reciclador", "Dona Pila", "Chente el Manitas", "Nena Cable" }
local GANG_SIZE = 3                -- pandilleros por pandilla
local GANG_ALERT_DIST = 60.0       -- a esta distancia salta el aviso en pantalla
local GANG_CALM_DIST = 85.0        -- y no se repite hasta que se alejan
local GANG_RANGE = 22.0        -- alcance real de un disparo (antes 34 m: quitaba vida desde fuera de la vista)
local GANG_FIRE_S = 1.9
local GANG_DAMAGE = 4
local GANG_SPEED = 0.52            -- metros por tick de 100 ms = 5,2 m/s, a la velocidad de un jugador corriendo (antes 2,6 = 26 m/s: teletransporte)
local AMIGO_TALK_DIST = 9.0        -- a esta distancia puedes hacerte su amigo
local AMIGO_FOLLOW_DIST = 3.0
local MAX_ALIADOS = 3              -- aliados maximos por jugador
local AMIGOS_CANDIDATOS = 1        -- el tope de 5 bots por sala manda: solo hay un amigo reclutable
-- Chat de voz: el servidor decide quien oye a quien.
local VOICE_MAX_BYTES = 1400     -- 160 muestras mu-law = 216 caracteres en base64; 1400 deja aire
local VOICE_PROX_M = 24.0        -- alcance de la voz de proximidad, en metros
local VOICE_RATE_PER_S = 60      -- paquetes por segundo y jugador (20 ms cada uno = 50/s + margen)

local CALLE_RESPAWN_TICKS = 60
-- Sala de los Freestylers: jugadores entrenados. Se llaman por su alias, como cualquier jugador.
local FREESTYLER_NAMES = {
  "Vex-01", "NullPointer", "Fragmaster", "NoScope", "Zer0", "Kira-9",
  "Rushido", "Tilt", "Bl4ze", "Camper_X", "Pixel", "Havoc",
}
local FREESTYLE_BOTS = 4
local FREESTYLE_FIRE_S = 1.6     -- cadencia con la que cada uno dispara
local FREESTYLE_ACCURACY = 0.55   -- fallan casi la mitad: un humano entrenado, no un aimbot
local FREESTYLE_DAMAGE = 5
local FREESTYLE_RANGE = 28.0
local FREESTYLE_HP = 100          -- aguanta lo mismo que un jugador
local FREESTYLE_RESPAWN_TICKS = 40  -- vuelve al combate a los 4 segundos (10 ticks por segundo)
local MAP_MIN = { x = -120, y = -5, z = -120 }
local MAP_MAX = { x = 120, y = 40, z = 120 }
local SPAWN_RATE_WINDOW_S = 1.0
local SPAWN_RATE_MAX = 3
local DAMAGE_RATE_WINDOW_S = 1.0
local DAMAGE_RATE_MAX = 25
local MAX_DAMAGE_PER_HIT = 1000
local MIN_DAMAGE_PER_HIT = 1
local REVIVE_COOLDOWN_S = 8.0
local REVIVE_MAX_DIST = 4.5
local WAVE_BREAK_S = 4.0
local MATCH_EMPTY_GRACE_S = 30.0
local FRESH_ROOM_S = 45          -- ventana para reutilizar una sala recien creada (aun sin nadie conectado)
local CLOSE_VOTE_RATIO = 1.0
local ENEMY_BASE_HP = 100
local ENEMY_ELITE_HP = 350
local REWARD_PER_KILL = 10
local REWARD_PER_WAVE = 50
local REWARD_ELITE_BONUS = 75
local HELP_COOLDOWN_S = 4.0
local HELP_MAX_PER_MIN = 10
local DOWNED_BLEEDOUT_S = 45.0   -- tiempo para ser revivido antes de morir de verdad
local LOW_HP_ALERT_RATIO = 0.3

-- Modos de juego. Todos son cooperativos o de supervivencia autoritativos: el
-- servidor decide la dificultad, quien puede revivir y cuando termina.
local MODES = {
  coop_waves = { label = "Oleadas", revive = true,  lives = 0, wave_cap = 0,  hp_scale = 1.00, count_scale = 1.00 },
  survival   = { label = "Supervivencia", revive = false, lives = 1, wave_cap = 0, hp_scale = 1.15, count_scale = 1.25 },
  horde      = { label = "Horda", revive = true,  lives = 0, wave_cap = 15, hp_scale = 0.85, count_scale = 1.80 },
  boss_rush  = { label = "Jefes", revive = true,  lives = 0, wave_cap = 10, hp_scale = 1.30, count_scale = 0.60 },
  -- Puro enfrentamiento contra jugadores entrenados: no aparecen monstruos.
  freestylers = { label = "Matadero", revive = true, lives = 0, wave_cap = 0,
                  hp_scale = 1.0, count_scale = 0.0, pvp = true },
}

-- atan2 portatil: Lua 5.1 lo trae en math.atan2, Lua 5.4 solo math.atan(y,x).
local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

-- Skins de la tienda del juego. El servidor solo acepta estos ids.
local SKINS_VALIDAS = { neko_base = true, neko_fuego = true, neko_hielo = true, neko_toxica = true,
                        neko_sombra = true, neko_oro = true, neko_sangre = true, neko_hueso = true }

-- Skins que visten los bots segun su papel: la pandilla se ve amenazante, el amigo amable, y los
-- entrenados variados. Solo ids que existen en la tienda del juego (los mismos que SKINS_VALIDAS).
local SKINS_POR_ROL = {
  pandilla  = { "neko_sangre", "neko_sombra", "neko_toxica", "neko_fuego" },
  solo      = { "neko_hueso", "neko_sombra", "neko_base" },
  amigo     = { "neko_oro", "neko_hielo", "neko_base", "neko_hueso" },
  entrenado = { "neko_base", "neko_fuego", "neko_hielo", "neko_toxica", "neko_sombra", "neko_oro", "neko_sangre", "neko_hueso" },
}

-- Reparto estable: el mismo bot (por su numero) siempre viste la misma skin, sin azar que cambie
-- el aspecto a mitad de partida. Un hash del id evita que toda la pandilla lleve la misma.
local function skin_para(rol, id)
  local lista = SKINS_POR_ROL[rol] or SKINS_POR_ROL.entrenado
  local h = 0
  for i = 1, #tostring(id) do h = (h * 31 + string.byte(tostring(id), i)) % 100003 end
  return lista[(h % #lista) + 1]
end

-- Plano caminable MEDIDO de cada mapa (ver map_floor.lua). Los bots solo pisan celdas que existen.
local FLOOR = require("map_floor")
local CHARLA = require("charla_bots")

-- Plan de poblacion POR MODO. Antes todos los modos metian lo mismo (3 bots + pandilla + solitario +
-- amigo) y la gente aparecia toda junta. Ahora cada modo decide quien hay en la sala:
--   companions = compañeros bot que cuentan como jugadores; calle = pandilla/solitario/amigo;
--   gang = pandilleros; solo = solitarios hostiles; amigo = buena gente reclutable.
-- TOPE: companions + gang + solo + amigos <= BOTS_MAX (5) en TODOS los modos.
local PLAN = {
  coop_waves  = { companions = 1, calle = true,  gang = 2, solo = 1, amigo = 1 },   -- 1+2+1+1 = 5
  survival    = { companions = 0, calle = true,  gang = 0, solo = 1, amigo = 0 },   -- 1
  horde       = { companions = 3, calle = false, gang = 0, solo = 0, amigo = 0 },   -- 3
  boss_rush   = { companions = 2, calle = false, gang = 0, solo = 0, amigo = 0 },   -- 2
  freestylers = { companions = 4, calle = false, gang = 0, solo = 0, amigo = 0 },   -- 4
}
local function plan_de(state)
  return PLAN[state.mode or "coop_waves"] or PLAN.coop_waves
end

-- Indice { ["x,z"]=true } por mapa, para saber en O(1) si una celda existe.
local FLOOR_SET = {}
local function suelo_set(mapa)
  local m = FLOOR[mapa] and mapa or DEFAULT_MAP
  if FLOOR_SET[m] then return FLOOR_SET[m] end
  local set = {}
  -- el valor es la ALTURA del suelo de esa celda (siempre truthy, 0.0 incluido en Lua)
  for _, c in ipairs(FLOOR[m]) do set[c[1] .. "," .. c[2]] = c[3] or 0.0 end
  FLOOR_SET[m] = set
  return set
end

-- Altura REAL del suelo en una posicion (celda de 2 m mas cercana). Si no hay celda, conserva la actual.
local function altura_suelo(state, x, z, por_defecto)
  local set = suelo_set(state.map or DEFAULT_MAP)
  local h = set[(math.floor(x / 2 + 0.5) * 2) .. "," .. (math.floor(z / 2 + 0.5) * 2)]
  if h == nil then return por_defecto or 0.0 end
  return h
end

-- Celda de 2 m: MISMO redondeo que el cliente y los tests (floor(x/2+0.5)*2).
local function celda_de(x, z)
  return math.floor(x / 2 + 0.5) * 2, math.floor(z / 2 + 0.5) * 2
end

-- Linea de vision aproximada sobre el plano medido: recorre el segmento de a a b cada ~1 m y
-- exige SUELO real en cada paso, sin saltos de altura de mas de 1.6 m (una pared, una caja alta
-- o un hueco cortan la vista). Antes el bot daba a traves de edificios y desde 34-70 m.
local function hay_vision(state, a, b)
  local set = suelo_set(state.map or DEFAULT_MAP)
  local dx, dz = b.x - a.x, b.z - a.z
  local largo = math.sqrt(dx * dx + dz * dz)
  if largo < 1.0 then return true end
  local pasos = math.ceil(largo / 1.0)
  local y_prev = a.y or 0.0
  for i = 1, pasos - 1 do
    local f = i / pasos
    local cx, cz = celda_de(a.x + dx * f, a.z + dz * f)
    local h = set[cx .. "," .. cz]
    if h == nil then return false end
    if math.abs(h - y_prev) > 1.6 then return false end
    y_prev = h
  end
  return true
end

-- Mueve al bot (dx,dz) SOLO si la celda de llegada esta medida en el plano. Asi no se cuela en un
-- hueco de medicion (celda sin rayo valido entre dos celdas buenas) ni corta la esquina de una celda
-- que no existe. Si el paso recto esta bloqueado intenta deslizarse por un eje; si tampoco puede,
-- vuelve al centro de su celda (siempre medida) para recalcular en el siguiente tick.
local function paso_seguro(state, p, dx, dz)
  local set = suelo_set(state.map or DEFAULT_MAP)
  local function intentar(ax, az)
    if ax == 0 and az == 0 then return false end
    local nx, nz = p.pos.x + ax, p.pos.z + az
    local cx, cz = celda_de(nx, nz)
    local h = set[cx .. "," .. cz]
    if h == nil then return false end
    p.pos.x, p.pos.z, p.pos.y = nx, nz, h
    return true
  end
  if intentar(dx, dz) then return true end
  if intentar(dx, 0) then return true end
  if intentar(0, dz) then return true end
  local cx, cz = celda_de(p.pos.x, p.pos.z)
  local h = set[cx .. "," .. cz]
  if h ~= nil then p.pos.x, p.pos.z, p.pos.y = cx + 0.0, cz + 0.0, h end
  return false
end

-- Un paso por celdas CONTIGUAS: de la celda actual a una vecina (8 direcciones) que exista.
-- Asi el bot nunca cruza una pared, una caja ni un hueco en linea recta. Devuelve {x,y,z} o nil.
local function vecina_real(state, pos)
  local set = suelo_set(state.map or DEFAULT_MAP)
  local cx, cz = math.floor(pos.x / 2 + 0.5) * 2, math.floor(pos.z / 2 + 0.5) * 2
  local dirs = { {2,0},{-2,0},{0,2},{0,-2},{2,2},{2,-2},{-2,2},{-2,-2} }
  local libres = {}
  for _, d in ipairs(dirs) do
    local nx, nz = cx + d[1], cz + d[2]
    -- las diagonales solo valen si las dos celdas laterales tambien existen (no se corta una esquina)
    local ok = set[nx .. "," .. nz]
    if ok and d[1] ~= 0 and d[2] ~= 0 then ok = set[(cx + d[1]) .. "," .. cz] and set[cx .. "," .. (cz + d[2])] end
    if ok then libres[#libres + 1] = { x = nx + 0.0, y = set[nx .. "," .. nz] + 0.0, z = nz + 0.0 } end
  end
  if #libres == 0 then return nil end
  return libres[math.random(1, #libres)], libres
end

-- Avanza `largo` metros hacia `destino` SIN salir del suelo medido: en cada paso elige la celda
-- vecina que mas acerca al objetivo (descenso voraz). Si esta encajonado, prueba un giro lateral.
-- Antes la persecucion iba en linea recta y atravesaba paredes, cajas y huecos.
local function paso_hacia(state, p, destino, largo)
  local set = suelo_set(state.map or DEFAULT_MAP)
  local restante = largo
  local guardia = 0
  while restante > 0.01 and guardia < 4 do
    guardia = guardia + 1
    local cx, cz = math.floor(p.pos.x / 2 + 0.5) * 2, math.floor(p.pos.z / 2 + 0.5) * 2
    -- celda "siguiente" = la vecina libre mas cercana al destino (o la actual si ya es la mejor)
    local mejor, mejor_d = nil, (cx - destino.x) ^ 2 + (cz - destino.z) ^ 2
    for _, d in ipairs({ {2,0},{-2,0},{0,2},{0,-2},{2,2},{2,-2},{-2,2},{-2,-2} }) do
      local nx, nz = cx + d[1], cz + d[2]
      local ok = set[nx .. "," .. nz]
      if ok and d[1] ~= 0 and d[2] ~= 0 then ok = set[(cx + d[1]) .. "," .. cz] and set[cx .. "," .. (cz + d[2])] end
      if ok then
        local dd = (nx - destino.x) ^ 2 + (nz - destino.z) ^ 2
        if dd < mejor_d then mejor, mejor_d = { x = nx + 0.0, z = nz + 0.0 }, dd end
      end
    end
    if mejor == nil then return false end      -- ya esta lo mas cerca posible por suelo real
    local dx, dz = mejor.x - p.pos.x, mejor.z - p.pos.z
    local l = math.sqrt(dx * dx + dz * dz)
    if l < 0.01 then return false end
    local avance = math.min(l, restante)
    p.yaw = atan2(-dx, -dz)
    restante = restante - avance
    -- el paso pasa por el guardia de suelo: nunca aterriza en una celda sin medir
    if not paso_seguro(state, p, dx / l * avance, dz / l * avance) then return false end
  end
  return true
end

-- Una celda de suelo real del mapa, lejos de `lejos_de` (si se da). Devuelve {x,y,z}.
local function celda_real(state, lejos_de, min_dist)
  local celdas = FLOOR[state.map or DEFAULT_MAP] or FLOOR[DEFAULT_MAP]
  local n = #celdas
  if n == 0 then return { x = 0, y = 0, z = 0 } end
  for _ = 1, 25 do
    local c = celdas[math.random(1, n)]
    if lejos_de == nil then return { x = c[1] + 0.0, y = (c[3] or 0.0) + 0.0, z = c[2] + 0.0 } end
    local dx, dz = c[1] - lejos_de.x, c[2] - lejos_de.z
    if math.sqrt(dx * dx + dz * dz) >= (min_dist or 12) then
      return { x = c[1] + 0.0, y = (c[3] or 0.0) + 0.0, z = c[2] + 0.0 }
    end
  end
  local c = celdas[math.random(1, n)]
  return { x = c[1] + 0.0, y = (c[3] or 0.0) + 0.0, z = c[2] + 0.0 }
end

-- Tipo de oleada segun el numero. Cada 5 es jefe, cada 3 trae elites, cada 4 es horda.
local function wave_kind(wave, mode)
  if mode == "boss_rush" then return (wave % 2 == 0) and "boss" or "elite" end
  if wave % 5 == 0 then return "boss" end
  if wave % 4 == 0 then return "horde" end
  if wave % 3 == 0 then return "elite" end
  return "normal"
end

local function now_s()
  return os.time()
end

local function decode_data(data)
  if data == nil then return nil end
  if type(data) == "table" then return data end
  local ok, parsed = pcall(nk.json_decode, data)
  if ok and type(parsed) == "table" then return parsed end
  return nil
end

local function encode(tbl)
  return nk.json_encode(tbl)
end

local function broadcast(dispatcher, op, tbl, presences)
  dispatcher.broadcast_message(op, encode(tbl), presences, nil, true)
end

local function send_one(dispatcher, op, tbl, presence)
  dispatcher.broadcast_message(op, encode(tbl), { presence }, nil, true)
end

-- El cliente usa NakamaMultiplayerBridge, que solo pasa a "conectado" (y solo entonces
-- arranca la partida) cuando recibe dos mensajes del op 9001: uno diciendo quien es el
-- host y otro asignandole un peer id. Como el servidor es autoritativo, es el servidor
-- quien los manda; sin esto la sala se creaba y el juego se quedaba en "creado".
local function send_meta(dispatcher, destino, cuerpo, remitente)
  if destino == nil or remitente == nil then return end
  dispatcher.broadcast_message(OP_META, encode(cuerpo), { destino }, remitente, true)
end

local function send_meta_dispatcher_hit(dispatcher, destino, cuerpo)
  dispatcher.broadcast_message(OP_BOT_HIT, encode(cuerpo), { destino }, nil, true)
end

local function presencia_host(state)
  if state.host_session_id == nil or state.host_session_id == "" then return nil end
  for _, pr in pairs(state.presences) do
    if pr.session_id == state.host_session_id then return pr end
  end
  return nil
end

local function asignar_peer(state, presence)
  local sid = presence.session_id
  if state.peer_ids[sid] ~= nil then return state.peer_ids[sid] end
  local id
  if state.host_session_id == nil or state.host_session_id == "" or presencia_host(state) == nil then
    state.host_session_id = sid
    id = 1
  else
    id = state.next_peer_id or 2
    state.next_peer_id = id + 1
  end
  state.peer_ids[sid] = id
  return id
end

local function in_map_bounds(pos)
  if type(pos) ~= "table" then return false end
  local x = tonumber(pos.x or pos[1])
  local y = tonumber(pos.y or pos[2])
  local z = tonumber(pos.z or pos[3])
  if x == nil or y == nil or z == nil then return false end
  return x >= MAP_MIN.x and x <= MAP_MAX.x
     and y >= MAP_MIN.y and y <= MAP_MAX.y
     and z >= MAP_MIN.z and z <= MAP_MAX.z
end

local function vec_dist(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return 9999 end
  local ax = tonumber(a.x or a[1]) or 0
  local ay = tonumber(a.y or a[2]) or 0
  local az = tonumber(a.z or a[3]) or 0
  local bx = tonumber(b.x or b[1]) or 0
  local by = tonumber(b.y or b[2]) or 0
  local bz = tonumber(b.z or b[3]) or 0
  local dx, dy, dz = ax - bx, ay - by, az - bz
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function presence_key(p)
  return tostring(p.user_id) .. ":" .. tostring(p.session_id)
end

local function enemy_count_for_wave(wave, mode, kind)
  local w = math.max(1, math.floor(tonumber(wave) or 1))
  local cfg = MODES[mode or "coop_waves"] or MODES.coop_waves
  local count = 4 + w * 2 + math.floor(w / 3)
  if kind == "horde" then count = math.floor(count * 1.6) end
  if kind == "boss" then count = math.max(3, math.floor(count * 0.4)) end
  count = math.floor(count * cfg.count_scale)
  if count > 60 then count = 60 end
  if count < 2 then count = 2 end
  return count
end

local function rate_allow(bucket, key, window_s, max_count, t)
  local e = bucket[key]
  if e == nil or (t - e.window_start) >= window_s then
    bucket[key] = { window_start = t, count = 1 }
    return true
  end
  if e.count >= max_count then return false end
  e.count = e.count + 1
  return true
end

local function ensure_player(state, presence)
  local id = presence.user_id
  local p = state.players[id]
  if p == nil then
    p = {
      user_id = id,
      session_id = presence.session_id,
      username = presence.username or id,
      alive = true,
      dead = false,
      pos = { x = 0, y = 1, z = 0 },
      kills = 0,
      elite_kills = 0,
      boss_kills = 0,
      revives = 0,
      times_downed = 0,
      help_calls = 0,
      damage_dealt = 0,
      rewards = 0,
      last_revive_at = 0,
      joined_tick = state.tick or 0,
    }
    state.players[id] = p
  else
    p.session_id = presence.session_id
    p.username = presence.username or p.username
  end
  return p
end

-- Etiqueta publica de la sala: es lo que ve el listado de salas del lobby.
local function room_label(state)
  local humans = 0
  for _ in pairs(state.presences) do humans = humans + 1 end
  local bots = 0
  for _, p in pairs(state.players) do if p.bot then bots = bots + 1 end end
  return nk.json_encode({
    mode = state.mode,
    t = state.created_s or now_s(),
    map = state.map or DEFAULT_MAP,
    name = state.room_name or "Sala",
    code = state.code or "",
    open = state.phase ~= "closed" and not state.private and humans < (state.max_players or MAX_PLAYERS),
    private = state.private == true,
    max = state.max_players or MAX_PLAYERS,
    players = humans,
    bots = bots,
    monsters = state.monsters ~= false,
    wave = state.wave or 0,
    phase = state.phase,
  })
end

local function refresh_label(state, dispatcher)
  local label = room_label(state)
  if label ~= state._last_label then
    state._last_label = label
    pcall(nk.match_label_update, label)
  end
end

local function bot_id(i) return "bot-" .. tostring(i) end

local function add_bot(state, i)
  local id = bot_id(i)
  if state.players[id] then return end
  local ang = (i * 2.399) % (2 * math.pi)
  local alias = BOT_NAMES[((i - 1) % #BOT_NAMES) + 1]
  if state.mode == "freestylers" then
    alias = FREESTYLER_NAMES[((i - 1) % #FREESTYLER_NAMES) + 1]
  end
  state.players[id] = {
    user_id = id, session_id = id, username = alias,
    next_fire = 0, hp = FREESTYLE_HP, respawn_at = 0,
    bot = true, alive = true, dead = false, skin = skin_para("entrenado", id),
    pos = celda_real(state),
    target = nil, kills = 0, elite_kills = 0, boss_kills = 0, revives = 0, times_downed = 0,
    help_calls = 0, damage_dealt = 0, rewards = 0, last_revive_at = 0, joined_tick = state.tick or 0,
  }
end

local function remove_bot(state, i) state.players[bot_id(i)] = nil end

-- Los bots rellenan hasta `bots_wanted`, pero SIEMPRE dejan sitio a los humanos.
local function sync_bots(state)
  local humans = 0
  for _ in pairs(state.presences) do humans = humans + 1 end
  local room_for_bots = math.max(0, (state.max_players or MAX_PLAYERS) - humans)
  local por_modo = plan_de(state).companions
  -- el modo manda: un cliente no puede llenar el Matadero de companeros ni vaciar las Oleadas.
  -- Lo unico que puede pedir la sala es "sin bots" (bots = 0).
  local deseados = (state.bots_wanted ~= nil and state.bots_wanted <= 0) and 0 or por_modo
  local want = math.min(deseados, BOTS_MAX, room_for_bots)
  for i = 1, BOTS_MAX do
    if i <= want then add_bot(state, i) else remove_bot(state, i) end
  end
end

-- Cada bot camina celda a celda por suelo medido, manteniendo un rumbo (no zigzaguea) y
-- girando al toparse con un obstaculo. Antes iba en linea recta a un punto de +-55 m.
local function move_bots(state, dt)
  for _, p in pairs(state.players) do
    if p.bot and not p.dead and p.side == nil or (p.bot and not p.dead and p.side == "entrenado") then
      -- celda destino inmediata (a 2 m); al llegar se elige la siguiente
      if p.target == nil or vec_dist(p.pos, p.target) < 0.4 then
        -- AL LLEGAR se ancla al centro EXACTO de la celda: antes quedaba a medio metro y, al elegir la
        -- siguiente desde la celda redondeada, avanzaba y retrocedia temblando en el borde hasta pisar
        -- una celda que no existe (bot "flotando" fuera del mapa).
        if p.target ~= nil then
          p.pos.x, p.pos.z = p.target.x, p.target.z
          p.pos.y = altura_suelo(state, p.pos.x, p.pos.z, p.pos.y)
        end
        local candidatas = nil
        local _, todas = vecina_real(state, p.pos)
        candidatas = todas
        if candidatas and #candidatas > 0 then
          -- prefiere seguir en la misma direccion para recorrer el mapa en vez de dar vueltas en el sitio
          local mejor, mejor_puntos = nil, -9
          for _, c in ipairs(candidatas) do
            local puntos = math.random() * 0.8
            if p.rumbo_x then
              local dx, dz = c.x - p.pos.x, c.z - p.pos.z
              local l = math.sqrt(dx * dx + dz * dz)
              if l > 0 then puntos = puntos + (dx / l * p.rumbo_x + dz / l * p.rumbo_z) end
            end
            if puntos > mejor_puntos then mejor, mejor_puntos = c, puntos end
          end
          p.target = mejor
          local dx, dz = mejor.x - p.pos.x, mejor.z - p.pos.z
          local l = math.sqrt(dx * dx + dz * dz)
          if l > 0 then p.rumbo_x, p.rumbo_z = dx / l, dz / l end
        else
          -- atrapado en una celda aislada: se recoloca de golpe en otra celda real. El destino ES la
          -- celda donde aparece: antes quedaba apuntando a un punto a 20 m y el bot lo recorria en
          -- linea recta atravesando huecos (el bot "andaba por los aires" en el Matadero).
          local nueva = celda_real(state)
          p.pos = { x = nueva.x, y = nueva.y or 0.0, z = nueva.z }
          p.target = { x = nueva.x, y = nueva.y or 0.0, z = nueva.z }
          p.rumbo_x, p.rumbo_z = nil, nil
        end
      end
      local dx, dz = p.target.x - p.pos.x, p.target.z - p.pos.z
      local d = math.sqrt(dx * dx + dz * dz)
      if d > 0.01 then
        local step = math.min(d, BOT_STEP * dt)
        p.yaw = atan2(-dx, -dz)
        paso_seguro(state, p, dx / d * step, dz / d * step)
      end
      p.pos.y = altura_suelo(state, p.pos.x, p.pos.z, p.pos.y)
    end
  end
end

local function count_presences(state)
  local n = 0
  for _ in pairs(state.presences) do n = n + 1 end
  return n
end

local function snapshot_players(state)
  local list = {}
  for id, p in pairs(state.players) do
    list[#list + 1] = {
      user_id = id,
      username = p.username,
      alive = not p.dead,
      kills = p.kills,
      damage_dealt = p.damage_dealt,
      rewards = p.rewards,
      pos = p.pos,
      bot = p.bot == true,
      -- quien es quien: "amigo" se puede reclutar, "pandilla" viene a por ti, "solo" va por libre
      side = p.side or (p.bot and "entrenado" or "humano"),
      gang = p.gang or "",
      friend = p.friend == true,
      yaw = p.yaw or 0,
      skin = p.skin or "",
    }
  end
  return list
end

local function snapshot_enemies(state)
  local list = {}
  for id, e in pairs(state.enemies) do
    if not e.dead then
      list[#list + 1] = {
        id = id, hp = e.hp, max_hp = e.max_hp, elite = e.elite, pos = e.pos, wave = e.wave,
      }
    end
  end
  return list
end

local function build_match_state_payload(state)
  return {
    mode = state.mode,
    map = state.map or DEFAULT_MAP,
    room_name = state.room_name or "Sala",
    phase = state.phase,
    wave = state.wave,
    wave_active = state.wave_active,
    enemies_alive = state.enemies_alive,
    enemies_total_wave = state.enemies_total_wave,
    has_elite = state.has_elite,
    wave_kind = state.wave_kind or "normal",
    tick = state.tick,
    players = snapshot_players(state),
    enemies = snapshot_enemies(state),
  }
end

-- Posiciones de los bots en un mensaje pequeno. El snapshot completo (jugadores + enemigos) solo
-- sale 1 vez por segundo; con eso un bot que anda a 2,2 m/s daba un salto y se quedaba quieto el
-- resto del segundo ("estatuas"). Esto va a 10 Hz y solo lleva id, x, y, z, yaw y si esta vivo.
local function posiciones_bots(state)
  local lista = {}
  for id, p in pairs(state.players) do
    if p.bot and p.pos then
      lista[#lista + 1] = {
        id = id,
        x = math.floor(p.pos.x * 100 + 0.5) / 100,
        y = math.floor(p.pos.y * 100 + 0.5) / 100,
        z = math.floor(p.pos.z * 100 + 0.5) / 100,
        yaw = math.floor((p.yaw or 0) * 100 + 0.5) / 100,
        a = (not p.dead) and 1 or 0,
      }
    end
  end
  return lista
end

local function next_enemy_id(state)
  state.enemy_seq = (state.enemy_seq or 0) + 1
  return "e" .. tostring(state.enemy_seq)
end

local WAVE_ANNOUNCE = {
  normal = nil,
  elite  = "ELITES EN CAMINO. Agrupense.",
  horde  = "HORDA. Busquen una posicion alta o una casa.",
  boss   = "JEFE. Todos juntos, y que nadie se quede atras.",
}

local function es_pvp(state)
  local cfg = MODES[state.mode or ""] or {}
  return cfg.pvp == true
end

-- Los jugadores entrenados persiguen al humano mas cercano y disparan sin fallar.
local function freestyle_tick(state, dispatcher, t)
  local humanos = {}
  for _, presencia in pairs(state.presences) do
    local p = state.players[presencia.user_id]
    if p ~= nil and not p.dead then humanos[#humanos + 1] = p end
  end
  if #humanos == 0 then return end
  for _, p in pairs(state.players) do
    if p.bot then
      if p.dead then
        if (state.tick or 0) >= (p.respawn_at or 0) then
          p.dead = false
          p.hp = FREESTYLE_HP
          -- reaparece en suelo real y lejos de los jugadores (antes: un circulo de 22 m a ciegas,
          -- que en la Aldea caia en paredes y huecos)
          local cerca = humanos[1] and humanos[1].pos or { x = 0, z = 0 }
          p.pos = celda_real(state, cerca, 18)
          p.target = nil
        end
      else
      local objetivo, mejor = nil, nil
      for _, h in ipairs(humanos) do
        local d = vec_dist(p.pos, h.pos)
        if mejor == nil or d < mejor then objetivo, mejor = h, d end
      end
      if objetivo ~= nil then
        -- se acercan hasta media distancia y orbitan
        if mejor > 14.0 then
          paso_hacia(state, p, objetivo.pos, BOT_STEP * 1.7 * 0.1)
        end
        p.yaw = atan2(objetivo.pos.x - p.pos.x, objetivo.pos.z - p.pos.z)
        -- solo dispara quien VE al objetivo y esta a tiro: nada de dano a traves de paredes
        if mejor <= FREESTYLE_RANGE and t >= (p.next_fire or 0) and hay_vision(state, p.pos, objetivo.pos) then
          p.next_fire = t + FREESTYLE_FIRE_S
          -- la punteria baja con la distancia: de cerca acierta mas, de lejos falla mas
          local prob = FREESTYLE_ACCURACY * (1.0 - 0.5 * (mejor / FREESTYLE_RANGE))
          local acierta = math.random() <= prob
          if acierta then
            local dano = FREESTYLE_DAMAGE + math.random(0, 4)
            local destino = state.presences[objetivo.user_id]
            if destino ~= nil then
              send_meta_dispatcher_hit(dispatcher, destino, {
                damage = dano, from = { x = p.pos.x, y = p.pos.y, z = p.pos.z },
                name = p.username,
              })
            end
          end
          -- el disparo se ve SIEMPRE (fogonazo y sonido), y "hit" dice si dio de verdad
          broadcast(dispatcher, OP_BOT_SHOT, {
            user_id = p.user_id, name = p.username,
            pos = { x = p.pos.x, y = p.pos.y, z = p.pos.z },
            target_user_id = objetivo.user_id, hit = acierta,
          })
        end
      end
      end
    end
  end
end

-- Un jugador le acerto a un entrenado: baja su vida, y si cae se queda 4 s fuera.
local function handle_voice(state, dispatcher, presence, payload, t)
  -- La voz funciona aunque el jugador aun no haya aparecido (spawn): el primer
  -- paquete de posicion llega al instante, pero si se retrasa no queremos una sala muda.
  local yo = state.players[presence.user_id] or { pos = nil, team = nil }
  local datos = payload.data
  if type(datos) ~= "string" or #datos == 0 or #datos > VOICE_MAX_BYTES then return state end
  local canal = tostring(payload.channel or "prox")
  if canal ~= "prox" and canal ~= "team" and canal ~= "all" then canal = "prox" end

  -- limite de ritmo: un cliente no puede inundar la sala con voz
  state.voice_rate = state.voice_rate or {}
  local cubo = state.voice_rate[presence.user_id]
  if cubo == nil or (t - cubo.t0) >= 1.0 then
    cubo = { t0 = t, n = 0 }
    state.voice_rate[presence.user_id] = cubo
  end
  cubo.n = cubo.n + 1
  if cubo.n > VOICE_RATE_PER_S then return state end

  local destinos = {}
  local margen = VOICE_PROX_M * VOICE_PROX_M
  for _, otro in pairs(state.presences) do
    if otro.user_id ~= presence.user_id then
      local suyo = state.players[otro.user_id]
      local incluir = false
      if canal == "all" then
        incluir = true
      elseif canal == "team" then
        incluir = (yo.team == nil) or (suyo ~= nil and suyo.team == yo.team)
      elseif yo.pos == nil or suyo == nil then
        -- sin posicion todavia: se oye a todos antes que dejar la sala muda
        incluir = (yo.pos == nil)
      elseif not suyo.dead and suyo.pos ~= nil then
        local dx = (suyo.pos.x or 0) - (yo.pos.x or 0)
        local dz = (suyo.pos.z or 0) - (yo.pos.z or 0)
        incluir = (dx * dx + dz * dz) <= margen
      end
      if incluir then destinos[#destinos + 1] = otro end
    end
  end
  if #destinos > 0 then
    broadcast(dispatcher, OP_VOICE, {
      from = presence.session_id,
      channel = canal,
      data = datos,
    }, destinos)
    state.voice_relayed = (state.voice_relayed or 0) + 1
  end
  return state
end


-- Un bot dice algo. Presupuesto para que cientos de bots no saturen la red ni el chat:
--  * cada bot habla como mucho cada BOT_SAY_GAP_S segundos
--  * la sala entera, como mucho BOT_SAY_ROOM_PER_S frases por segundo
--  * solo llega a los jugadores que lo tienen a menos de BOT_SAY_RANGE metros (si no, no se oye)
local BOT_SAY_GAP_S = 9.0
local BOT_SAY_ROOM_PER_S = 3
local BOT_SAY_RANGE = 45.0

local function bot_dice(state, dispatcher, p, situacion, t, objetivo)
  if p == nil or p.bot ~= true or p.dead then return end
  if t < (p.next_say or 0) then return end
  state.say_win = state.say_win or { t0 = t, n = 0 }
  if t - state.say_win.t0 >= 1.0 then state.say_win.t0, state.say_win.n = t, 0 end
  if state.say_win.n >= BOT_SAY_ROOM_PER_S then return end
  local rol = p.side or "entrenado"
  state.charla_rol = state.charla_rol or {}
  state.charla_rol[rol] = state.charla_rol[rol] or {}
  p.charla = state.charla_rol[rol]   -- memoria del GRUPO, no del bot suelto
  local sit = situacion
  if rol == "amigo" and p.friend and situacion == "aviso" then sit = "siguiendo" end
  local ctx = {
    nombre = objetivo and objetivo.username or "amigo", gang = p.gang ~= "" and p.gang or state.gang_name,
    mapa = state.map, vida = (p.hp or 100) / (p.max_hp or 100),
    dist = objetivo and vec_dist(p.pos, objetivo.pos) or nil, oleada = state.wave,
  }
  local texto = CHARLA.decir(rol, sit, ctx, p.charla, math.random)
  p.next_say = t + BOT_SAY_GAP_S * (0.7 + math.random() * 0.8)   -- no hablan a intervalos exactos
  state.say_win.n = state.say_win.n + 1
  -- A quien va dirigido: un aliado SOLO le habla a su dueno. Los demas bots se lo
  -- dicen unicamente al jugador con el que estan tratando, nunca a la sala entera
  -- (antes cualquiera que pasara cerca recibia charla de bots que no eran su equipo).
  local destinos = {}
  if p.owner ~= nil and state.presences[p.owner] ~= nil then
    destinos[1] = state.presences[p.owner]
  else
    local oyente = objetivo
    if oyente == nil or oyente.bot == true then
      -- mas_cerca_a se declara mas abajo en el archivo: aqui se busca en linea
      local dist = math.huge
      oyente = nil
      for _, h in pairs(state.players) do
        if h.bot ~= true and not h.dead then
          local d = vec_dist(p.pos, h.pos)
          if d < dist then oyente, dist = h, d end
        end
      end
    end
    if oyente ~= nil and oyente.bot ~= true and vec_dist(p.pos, oyente.pos) <= BOT_SAY_RANGE
       and state.presences[oyente.user_id] ~= nil then
      destinos[1] = state.presences[oyente.user_id]
    end
  end
  for _, pres in pairs(destinos) do
    send_one(dispatcher, OP_BOT_SAY, { user_id = p.user_id, name = p.username, text = texto, rol = rol }, pres)
  end
end

local function handle_hit_bot(state, dispatcher, presence, payload, t)
  local objetivo = state.players[tostring(payload.user_id or "")]
  if objetivo == nil or objetivo.bot ~= true or objetivo.dead then return state end
  if not rate_allow(state.rate_damage, presence.session_id, DAMAGE_RATE_WINDOW_S, DAMAGE_RATE_MAX, t) then
    return state
  end
  local dano = math.max(MIN_DAMAGE_PER_HIT, math.min(MAX_DAMAGE_PER_HIT, math.floor(tonumber(payload.damage) or 0)))
  objetivo.hp = (objetivo.hp or FREESTYLE_HP) - dano
  local tirador = state.players[presence.user_id]
  if tirador ~= nil then
    tirador.damage_dealt = (tirador.damage_dealt or 0) + dano
  end
  -- le dolio: si sigue vivo, lo dice (el presupuesto de charla evita que hable sin parar)
  if objetivo.hp > 0 and math.random() < 0.5 then bot_dice(state, dispatcher, objetivo, "herido", t, tirador) end
  if objetivo.hp <= 0 then
    -- los de su bando reaccionan: uno de ellos celebra o se lamenta segun el bando
    for _, otro in pairs(state.players) do
      if otro ~= objetivo and otro.bot == true and not otro.dead and otro.side == objetivo.side
         and vec_dist(otro.pos, objetivo.pos) < 30.0 then
        bot_dice(state, dispatcher, otro, objetivo.side == "pandilla" and "herido" or "aviso", t, tirador)
        break
      end
    end
    objetivo.dead = true
    objetivo.hp = 0
    objetivo.respawn_at = (state.tick or 0) + (es_pvp(state) and FREESTYLE_RESPAWN_TICKS or CALLE_RESPAWN_TICKS)
    if objetivo.side == "amigo" then
      -- al caer queda libre: su dueno puede reclutar a otro
      objetivo.friend = false
      objetivo.owner = nil
    end
    objetivo.next_fire = t + 4.0
    if tirador ~= nil then
      tirador.kills = (tirador.kills or 0) + 1
      tirador.rewards = (tirador.rewards or 0) + REWARD_PER_KILL
    end
    broadcast(dispatcher, OP_BOT_DEATH, {
      user_id = objetivo.user_id, name = objetivo.username,
      killer_user_id = presence.user_id, roster = false,
    })
  end
  return state
end

-- Envoltorio defensivo: si algo falla aqui, se registra y la sala sigue viva en vez
-- de cerrarse de golpe (Nakama desconecta a todos si el bucle revienta).
local function handle_hit_bot_seguro(state, dispatcher, presence, payload, t)
  local ok, err = pcall(handle_hit_bot, state, dispatcher, presence, payload, t)
  if not ok then nk.logger_error("hit_bot_fallo: " .. tostring(err)) end
  return state
end

-- ============================ LA CALLE ============================
-- En cualquier sala y en cualquier modo hay gente por la calle: pandillas que vienen a
-- por ti (con aviso en pantalla), gente que va por libre y buena gente con la que se
-- puede hacer amistad. Se distinguen a simple vista por el color y por la etiqueta.

local function humanos_en_pie(state)
  local lista = {}
  for _, p in pairs(state.players) do
    if p.bot ~= true and not p.dead then lista[#lista + 1] = p end
  end
  return lista
end

local function mas_cerca_a(state, pos)
  local mejor, dist = nil, math.huge
  for _, h in ipairs(humanos_en_pie(state)) do
    local d = vec_dist(pos, h.pos)
    if d < dist then mejor, dist = h, d end
  end
  return mejor, dist
end

local function crear_gente(state, id, alias, side, gang, pos)
  state.players[id] = {
    user_id = id, session_id = id, username = alias,
    bot = true, alive = true, dead = false, side = side, gang = gang or "", skin = skin_para(side, id),
    hp = 100, max_hp = 100, next_fire = 0, respawn_at = 0, friend = false, owner = nil,
    pos = pos, yaw = 0, target = nil,
    kills = 0, elite_kills = 0, boss_kills = 0, revives = 0, times_downed = 0,
    help_calls = 0, damage_dealt = 0, rewards = 0, last_revive_at = 0,
    joined_tick = state.tick or 0, avisado = false,
  }
end

-- Se llama al empezar la partida (y si alguien limpia la calle, se repone).
-- La poblacion sale del PLAN del modo: no todos los modos llevan pandilla, solitario y amigo.
local function sembrar_calle(state)
  if state.calle_sembrada then return end
  state.calle_sembrada = true
  local plan = plan_de(state)
  state.gang_ids = {}
  if not plan.calle then return end
  -- "Sala vacia": si la sala pide cero bots, tampoco hay gente de la calle (pandilla, solitario, amigos).
  if state.bots_wanted ~= nil and state.bots_wanted <= 0 then return end
  math.randomseed((state.tick or 0) + os.time())
  local origen = celda_real(state)
  if (plan.gang or 0) > 0 then
    local g = GANGS[math.random(1, #GANGS)]
    state.gang_name = g.name
    -- la pandilla nace junta, en un mismo rincon del mapa, lejos del centro donde aparecen los jugadores
    local base = celda_real(state, { x = 0, z = 0 }, 14)
    for i = 1, math.min(plan.gang, GANG_SIZE, #g.members) do
      local id = "pdl-" .. i
      local c = celda_real(state, base, 0)
      -- cerca del lider (a menos de ~6 m) pero siempre en suelo real
      for _ = 1, 12 do
        local t = celda_real(state)
        if math.abs(t.x - base.x) <= 6 and math.abs(t.z - base.z) <= 6 then c = t; break end
      end
      crear_gente(state, id, g.members[i], "pandilla", g.name, c)
      state.gang_ids[#state.gang_ids + 1] = id
    end
  end
  for i = 1, (plan.solo or 0) do
    local nombre = SOLO_NAMES[math.random(1, #SOLO_NAMES)]
    crear_gente(state, "solo-" .. i, nombre, "solo", "", celda_real(state, { x = 0, z = 0 }, 18))
  end
  -- Varios buenos para repartir: cada jugador puede llevar hasta MAX_ALIADOS, y cada
  -- aliado tiene un unico dueno, asi que hacen falta candidatos suficientes.
  local cuantos_amigos = 0
  if (plan.amigo or 0) > 0 then cuantos_amigos = math.max(plan.amigo, AMIGOS_CANDIDATOS) end
  local inicio = math.random(1, #AMIGO_NAMES)
  for i = 1, cuantos_amigos do
    -- nombres distintos, sin repetir, para que nadie confunda a dos aliados
    local nombre = AMIGO_NAMES[(inicio + i - 2) % #AMIGO_NAMES + 1]
    crear_gente(state, "ami-" .. i, nombre, "amigo", "", celda_real(state, { x = 0, z = 0 }, 10))
  end
end

local function mover_hacia(p, destino, velocidad, mantener, state)
  local d = vec_dist(p.pos, destino.pos)
  if d <= mantener then return end
  if state ~= nil then
    paso_hacia(state, p, destino.pos, velocidad)
    return
  end
  local dx = (destino.pos.x - p.pos.x) / d
  local dz = (destino.pos.z - p.pos.z) / d
  p.pos = { x = p.pos.x + dx * velocidad, y = p.pos.y, z = p.pos.z + dz * velocidad }
  p.yaw = math.atan(dx, dz)
end

local function calle_tick(state, dispatcher, t)
  sembrar_calle(state)
  local humanos = humanos_en_pie(state)
  if #humanos == 0 then return end

  for _, id in ipairs(state.gang_ids or {}) do
    local p = state.players[id]
    if p ~= nil then
      if p.dead then
        if (state.tick or 0) >= (p.respawn_at or 0) then
          p.dead = false; p.hp = 100; p.avisado = false
          local ref = (state.gang_ids and state.players[state.gang_ids[1]] and not state.players[state.gang_ids[1]].dead)
                      and state.players[state.gang_ids[1]].pos or { x = 0, z = 0 }
          p.pos = celda_real(state, ref, 14)
        end
      else
        local objetivo, d = mas_cerca_a(state, p.pos)
        if objetivo ~= nil then
          -- aviso en pantalla la primera vez que se acercan
          if d <= GANG_ALERT_DIST and not p.avisado then
            p.avisado = true
            broadcast(dispatcher, OP_GANG_ALERT, {
              kind = "pandilla", gang = state.gang_name or "la pandilla",
              count = #(state.gang_ids or {}), dist = math.floor(d), nombre = p.username,
            })
            bot_dice(state, dispatcher, p, "aviso", t, objetivo)
          elseif d > GANG_CALM_DIST then
            p.avisado = false
          end
          mover_hacia(p, objetivo, GANG_SPEED, 9.0, state)
          if d <= GANG_RANGE and t >= (p.next_fire or 0) and hay_vision(state, p.pos, objetivo.pos) then
            p.next_fire = t + GANG_FIRE_S
            if math.random() < 0.25 then bot_dice(state, dispatcher, p, "disparo", t, objetivo) end
            local acierta = math.random() <= (0.75 - 0.4 * (d / GANG_RANGE))
            broadcast(dispatcher, OP_BOT_SHOT, {
              user_id = p.user_id, name = p.username, pos = p.pos,
              target_user_id = objetivo.user_id, hit = acierta,
            })
            if acierta then
              send_one(dispatcher, OP_BOT_HIT, {
                damage = GANG_DAMAGE, from = p.pos, nombre = p.username,
              }, state.presences[objetivo.user_id])
            end
          end
        end
      end
    end
  end

  -- el que va por libre
  local solo = state.players["solo-1"]
  if solo ~= nil and not solo.dead then
    local objetivo, d = mas_cerca_a(state, solo.pos)
    if objetivo ~= nil then
      if d <= GANG_ALERT_DIST and not solo.avisado then
        solo.avisado = true
        broadcast(dispatcher, OP_GANG_ALERT, {
          kind = "solo", gang = "", count = 1, dist = math.floor(d), nombre = solo.username,
        })
        bot_dice(state, dispatcher, solo, "aviso", t, objetivo)
      elseif d > GANG_CALM_DIST then
        solo.avisado = false
      end
      mover_hacia(solo, objetivo, GANG_SPEED * 0.85, 12.0, state)
      if d <= GANG_RANGE and t >= (solo.next_fire or 0) and hay_vision(state, solo.pos, objetivo.pos) then
        solo.next_fire = t + GANG_FIRE_S * 1.4
        local acierta = math.random() <= (0.75 - 0.4 * (d / GANG_RANGE))
        broadcast(dispatcher, OP_BOT_SHOT, {
          user_id = solo.user_id, name = solo.username, pos = solo.pos,
          target_user_id = objetivo.user_id, hit = acierta,
        })
        if acierta then
          send_one(dispatcher, OP_BOT_HIT, {
            damage = GANG_DAMAGE - 1, from = solo.pos, nombre = solo.username,
          }, state.presences[objetivo.user_id])
        end
      end
    end
  end

  -- La buena gente: cada aliado pertenece a UN jugador y solo sigue y le habla a el.
  -- Los que estan libres se acercan al jugador mas cercano a ofrecerse.
  for _, amigo in pairs(state.players) do
    if amigo.bot == true and amigo.side == "amigo" and not amigo.dead then
      local dueno = nil
      if amigo.owner ~= nil then dueno = state.players[amigo.owner] end
      if amigo.friend and dueno ~= nil and not dueno.dead and state.presences[dueno.user_id] ~= nil then
        mover_hacia(amigo, dueno, GANG_SPEED, AMIGO_FOLLOW_DIST, state)
        if math.random() < 0.01 then bot_dice(state, dispatcher, amigo, "aviso", t, dueno) end
      else
        if amigo.friend then
          -- el dueno se cayo o se fue: el aliado queda libre otra vez
          amigo.friend = false
          amigo.owner = nil
        end
        local objetivo, d = mas_cerca_a(state, amigo.pos)
        if objetivo ~= nil then
          mover_hacia(amigo, objetivo, GANG_SPEED * 0.7, AMIGO_TALK_DIST - 1.0, state)
          if d <= AMIGO_TALK_DIST and not amigo.avisado then
            amigo.avisado = true
            send_one(dispatcher, OP_GANG_ALERT, {
              kind = "amigo", gang = "", count = 1, dist = math.floor(d),
              nombre = amigo.username, user_id = amigo.user_id, tecla = "F",
            }, state.presences[objetivo.user_id])
            bot_dice(state, dispatcher, amigo, "aviso", t, objetivo)
          end
        end
      end
    end
  end
end

-- Cuantos buenos lleva ahora mismo este jugador (fuente de verdad: los bots).
local function contar_aliados(state, user_id)
  local n = 0
  for _, p in pairs(state.players) do
    if p.bot == true and p.side == "amigo" and p.friend == true and p.owner == user_id then n = n + 1 end
  end
  return n
end

-- Hacerse amigo: solo cuenta si es de los buenos y lo tienes cerca.
local function handle_befriend(state, dispatcher, presence, payload, t)
  local amigo = state.players[tostring(payload.user_id or "")]
  if amigo == nil or amigo.side ~= "amigo" or amigo.dead then return state end
  local yo = state.players[presence.user_id]
  if yo == nil or yo.dead then return state end
  if vec_dist(yo.pos, amigo.pos) > AMIGO_TALK_DIST + 2.0 then return state end
  -- Nadie puede robar el aliado de otro, y cada jugador lleva como mucho MAX_ALIADOS.
  if amigo.owner ~= nil and amigo.owner ~= yo.user_id and amigo.friend then
    send_one(dispatcher, OP_TEAM_ALERT, {
      kind = "aviso", severity = 0,
      text = amigo.username .. " ya acompana a otro jugador.",
    }, presence)
    return state
  end
  if contar_aliados(state, yo.user_id) >= MAX_ALIADOS and amigo.owner ~= yo.user_id then
    send_one(dispatcher, OP_TEAM_ALERT, {
      kind = "aviso", severity = 0,
      text = "Solo puedes llevar " .. MAX_ALIADOS .. " aliados. Libres uno para hablar con otro.",
    }, presence)
    return state
  end
  amigo.friend = true
  amigo.owner = yo.user_id
  yo.friends = contar_aliados(state, yo.user_id)
  amigo.next_say = 0
  bot_dice(state, dispatcher, amigo, "victoria", os.time() + 0.0, yo)
  send_one(dispatcher, OP_BEFRIEND_OK, {
    user_id = amigo.user_id, nombre = amigo.username, total = yo.friends,
  }, presence)
  broadcast(dispatcher, OP_TEAM_ALERT, {
    kind = "amigo", text = tostring(yo.username) .. " y " .. tostring(amigo.username) .. " ahora son amigos",
  })
  return state
end

local function spawn_wave_enemies(state, dispatcher)
  if es_pvp(state) then return end   -- puro enfrentamiento: ni un monstruo
  if state.monsters == false then return end   -- sala configurada sin monstruos
  local wave = state.wave
  local mode = state.mode
  local cfg = MODES[mode] or MODES.coop_waves
  local kind = wave_kind(wave, mode)
  local count = enemy_count_for_wave(wave, mode, kind)
  local has_elite = (kind == "elite" or kind == "boss")
  state.has_elite = has_elite
  state.wave_kind = kind
  state.enemies_total_wave = count
  state.enemies_alive = 0
  state.wave_active = true
  state.phase = "combat"
  local slots = {
    { x = 40, y = 1, z = 40 },
    { x = -40, y = 1, z = 40 },
    { x = 40, y = 1, z = -40 },
    { x = -40, y = 1, z = -40 },
    { x = 55, y = 1, z = 0 },
    { x = -55, y = 1, z = 0 },
    { x = 0, y = 1, z = 55 },
    { x = 0, y = 1, z = -55 },
  }
  local spawned = {}
  for i = 1, count do
    local slot = slots[((i - 1) % #slots) + 1]
    local boss = (kind == "boss" and i == count)
    local elite = boss or (kind == "elite" and i > count - math.max(1, math.floor(count / 4)))
    local hp = ENEMY_BASE_HP
    if elite then hp = ENEMY_ELITE_HP end
    if boss then hp = ENEMY_ELITE_HP * 6 end
    hp = math.floor(hp * (1.0 + (wave - 1) * 0.05) * cfg.hp_scale)
    local id = next_enemy_id(state)
    local enemy = {
      id = id, hp = hp, max_hp = hp, elite = elite, boss = boss, dead = false, wave = wave,
      pos = { x = slot.x, y = slot.y, z = slot.z },
    }
    state.enemies[id] = enemy
    state.enemies_alive = state.enemies_alive + 1
    spawned[#spawned + 1] = { id = id, hp = hp, max_hp = hp, elite = elite, boss = boss, pos = enemy.pos }
  end
  broadcast(dispatcher, OP_WAVE_STATE, {
    event = "wave_started", wave = wave, enemy_count = count, has_elite = has_elite,
    kind = kind, mode = mode, enemies = spawned, break_seconds = 0,
  })
  if WAVE_ANNOUNCE[kind] then
    broadcast(dispatcher, OP_TEAM_ALERT, {
      kind = "wave_" .. kind, wave = wave, text = WAVE_ANNOUNCE[kind], severity = (kind == "boss") and 3 or 2,
    })
  end
  broadcast(dispatcher, OP_MATCH_STATE, build_match_state_payload(state))
end

local function begin_wave_break(state, dispatcher)
  state.phase = "break"
  state.wave_active = false
  state.break_ends_at = now_s() + WAVE_BREAK_S
  broadcast(dispatcher, OP_WAVE_STATE, {
    event = "wave_break", wave = state.wave, next_wave = state.wave + 1, break_seconds = WAVE_BREAK_S,
  })
end

local function complete_wave(state, dispatcher)
  local wave = state.wave
  state.phase = "wave_complete"
  state.wave_active = false
  local rewarded = {}
  for id, p in pairs(state.players) do
    if state.presences[id] and not p.dead then
      local amount = REWARD_PER_WAVE + (state.has_elite and REWARD_ELITE_BONUS or 0)
      p.rewards = p.rewards + amount
      rewarded[#rewarded + 1] = { user_id = id, amount = amount, total = p.rewards, reason = "wave_clear" }
    end
  end
  broadcast(dispatcher, OP_REWARD, { wave = wave, rewards = rewarded, reason = "wave_clear" })
  broadcast(dispatcher, OP_WAVE_STATE, { event = "wave_completed", wave = wave })
  begin_wave_break(state, dispatcher)
end

-- Estadisticas finales por jugador, con los nombres de parametro de
-- public.record_match_result (supabase/migrations/004). Las calcula el servidor: el
-- cliente nunca envia kills ni logros, asi no se pueden falsificar.
local function final_stats(state)
  local list = {}
  local seconds = math.floor((state.tick or 0) / TICK_RATE)
  local won = (state.mode == "horde" or state.mode == "boss_rush") and
    (MODES[state.mode].wave_cap > 0 and state.wave > MODES[state.mode].wave_cap)
  for id, p in pairs(state.players) do
    -- los bots nunca se guardan: su id no es un UUID y romperia el registro
    if not p.bot then
    list[#list + 1] = {
      user_id = id, username = p.username,
      p_kills = p.kills, p_elite_kills = p.elite_kills, p_boss_kills = p.boss_kills,
      p_revives = p.revives, p_downed = p.times_downed, p_help_calls = p.help_calls,
      p_wave = state.wave, p_won = won and true or false, p_seconds = seconds,
    }
    end
  end
  return list
end

local function try_close_match(state, dispatcher, reason)
  if state.phase == "closed" then return state end
  state.phase = "closed"
  local results = {
    mode = state.mode, reason = reason or "closed", wave_reached = state.wave,
    players = snapshot_players(state), duration_ticks = state.tick,
    stats = final_stats(state),
  }
  broadcast(dispatcher, OP_MATCH_RESULT, results)
  broadcast(dispatcher, OP_MATCH_CLOSE, { ok = true, reason = reason or "closed", wave_reached = state.wave })
  return nil
end

local function all_players_dead(state)
  local any = false
  for id, p in pairs(state.players) do
    if state.presences[id] then
      any = true
      if not p.dead then return false end
    end
  end
  return any
end

local function handle_spawn(state, dispatcher, presence, payload, t)
  local key = presence_key(presence)
  if not rate_allow(state.rate_spawn, key, SPAWN_RATE_WINDOW_S, SPAWN_RATE_MAX, t) then
    send_one(dispatcher, OP_SPAWN_REJECT, { reason = "rate_limit" }, presence)
    return state
  end
  local pos = payload.pos or payload.position
  if not in_map_bounds(pos) then
    send_one(dispatcher, OP_SPAWN_REJECT, { reason = "out_of_bounds", pos = pos }, presence)
    return state
  end
  if count_presences(state) > (state.max_players or MAX_PLAYERS) then
    send_one(dispatcher, OP_SPAWN_REJECT, { reason = "match_full" }, presence)
    return state
  end
  local player = ensure_player(state, presence)
  player.pos = {
    x = tonumber(pos.x or pos[1]),
    y = tonumber(pos.y or pos[2]),
    z = tonumber(pos.z or pos[3]),
  }
  player.dead = false
  player.alive = true
  send_one(dispatcher, OP_SPAWN_OK, {
    user_id = presence.user_id, pos = player.pos, wave = state.wave, phase = state.phase,
  }, presence)
  broadcast(dispatcher, OP_MATCH_STATE, {
    event = "player_spawn", user_id = presence.user_id, pos = player.pos, players = snapshot_players(state),
  })
  return state
end

local function handle_damage(state, dispatcher, presence, payload, t)
  local key = presence_key(presence)
  if not rate_allow(state.rate_damage, key, DAMAGE_RATE_WINDOW_S, DAMAGE_RATE_MAX, t) then
    send_one(dispatcher, OP_ERROR, { op = OP_DAMAGE, reason = "fire_rate" }, presence)
    return state
  end
  local player = state.players[presence.user_id]
  if player == nil or player.dead then
    send_one(dispatcher, OP_ERROR, { op = OP_DAMAGE, reason = "dead_or_unknown" }, presence)
    return state
  end
  local enemy_id = tostring(payload.enemy_id or payload.id or "")
  local dmg = tonumber(payload.damage or payload.amount or 0) or 0
  if enemy_id == "" then
    send_one(dispatcher, OP_ERROR, { op = OP_DAMAGE, reason = "missing_enemy_id" }, presence)
    return state
  end
  if dmg < MIN_DAMAGE_PER_HIT or dmg > MAX_DAMAGE_PER_HIT then
    send_one(dispatcher, OP_ERROR, { op = OP_DAMAGE, reason = "absurd_damage", damage = dmg }, presence)
    return state
  end
  if dmg ~= dmg or dmg == math.huge or dmg == -math.huge then
    send_one(dispatcher, OP_ERROR, { op = OP_DAMAGE, reason = "invalid_damage" }, presence)
    return state
  end
  dmg = math.floor(dmg)
  local enemy = state.enemies[enemy_id]
  if enemy == nil or enemy.dead then
    send_one(dispatcher, OP_ERROR, { op = OP_DAMAGE, reason = "enemy_gone", enemy_id = enemy_id }, presence)
    return state
  end
  if payload.pos and not in_map_bounds(payload.pos) then
    send_one(dispatcher, OP_ERROR, { op = OP_DAMAGE, reason = "shooter_oob" }, presence)
    return state
  end
  enemy.hp = enemy.hp - dmg
  player.damage_dealt = player.damage_dealt + dmg
  if enemy.hp > 0 then
    broadcast(dispatcher, OP_ENEMY_HEALTH, {
      enemy_id = enemy_id, hp = enemy.hp, max_hp = enemy.max_hp, by = presence.user_id, damage = dmg,
    })
  else
    enemy.hp = 0
    enemy.dead = true
    state.enemies_alive = math.max(0, (state.enemies_alive or 1) - 1)
    player.kills = player.kills + 1
    if enemy.boss then player.boss_kills = player.boss_kills + 1
    elseif enemy.elite then player.elite_kills = player.elite_kills + 1 end
    local kill_reward = REWARD_PER_KILL + (enemy.elite and REWARD_ELITE_BONUS or 0)
    player.rewards = player.rewards + kill_reward
    broadcast(dispatcher, OP_ENEMY_DEATH, {
      enemy_id = enemy_id, by = presence.user_id, elite = enemy.elite, wave = state.wave, pos = enemy.pos,
    })
    broadcast(dispatcher, OP_REWARD, {
      reason = "kill", enemy_id = enemy_id,
      rewards = { { user_id = presence.user_id, amount = kill_reward, total = player.rewards } },
    })
    if state.wave_active and state.enemies_alive <= 0 then
      complete_wave(state, dispatcher)
    end
  end
  return state
end

local function nearest_enemy_dist(state, pos)
  local best = nil
  for _, e in pairs(state.enemies) do
    if not e.dead then
      local d = vec_dist(pos, e.pos)
      if best == nil or d < best then best = d end
    end
  end
  return best
end

local function handle_death(state, dispatcher, presence, payload, t)
  local player = ensure_player(state, presence)
  if player.dead then return state end
  if payload and payload.pos and in_map_bounds(payload.pos) then
    player.pos = {
      x = tonumber(payload.pos.x or payload.pos[1]),
      y = tonumber(payload.pos.y or payload.pos[2]),
      z = tonumber(payload.pos.z or payload.pos[3]),
    }
  end
  local cfg = MODES[state.mode] or MODES.coop_waves
  player.dead = true
  player.alive = false
  player.deaths = (player.deaths or 0) + 1
  player.times_downed = player.times_downed + 1
  -- En modos con revivir, el jugador queda DERRIBADO un rato y el equipo puede levantarlo.
  player.downed_until = cfg.revive and (t + DOWNED_BLEEDOUT_S) or nil
  local cause = payload and payload.cause or "unknown"
  broadcast(dispatcher, OP_PLAYER_DEATH, {
    user_id = presence.user_id, username = player.username, pos = player.pos, wave = state.wave,
    cause = cause, can_revive = cfg.revive, bleedout = cfg.revive and DOWNED_BLEEDOUT_S or 0,
  })
  local threat = nearest_enemy_dist(state, player.pos)
  broadcast(dispatcher, OP_TEAM_ALERT, {
    kind = "player_down", user_id = presence.user_id, username = player.username, pos = player.pos,
    text = player.username .. (cfg.revive and " esta caido. Vayan a levantarlo." or " ha muerto."),
    severity = 3, can_revive = cfg.revive, threat_dist = threat,
  })
  if all_players_dead(state) then
    return try_close_match(state, dispatcher, "team_wipe")
  end
  return state
end

-- Quien lleva demasiado tiempo caido se desangra y ya no se puede revivir.
local function expire_downed(state, dispatcher, t)
  for id, p in pairs(state.players) do
    if p.dead and p.downed_until and t >= p.downed_until then
      p.downed_until = nil
      p.bled_out = true
      broadcast(dispatcher, OP_TEAM_ALERT, {
        kind = "player_lost", user_id = id, username = p.username,
        text = p.username .. " se ha desangrado.", severity = 2,
      })
    end
  end
end

-- "Necesito ayuda": el jugador lo pide, el servidor lo valida y avisa al equipo con posicion.
local function handle_help_call(state, dispatcher, presence, payload, t)
  local player = state.players[presence.user_id]
  if player == nil then return state end
  state.rate_help = state.rate_help or {}
  local key = presence_key(presence)
  local last = state.rate_help[key]
  if last and (t - last) < HELP_COOLDOWN_S then
    send_one(dispatcher, OP_ERROR, { op = OP_HELP_CALL, reason = "help_cooldown" }, presence)
    return state
  end
  state.rate_help[key] = t
  player.help_calls = player.help_calls + 1
  local reason = tostring(payload.reason or "help")
  local texts = {
    help = " necesita ayuda.",
    monster = " esta acorralado por un monstruo.",
    low_hp = " tiene poca vida.",
    no_ammo = " se quedo sin municion.",
  }
  local pos = payload.pos
  if pos and in_map_bounds(pos) then
    player.pos = { x = tonumber(pos.x or pos[1]), y = tonumber(pos.y or pos[2]), z = tonumber(pos.z or pos[3]) }
  end
  broadcast(dispatcher, OP_TEAM_ALERT, {
    kind = "help", reason = reason, user_id = presence.user_id, username = player.username,
    pos = player.pos, text = player.username .. (texts[reason] or texts.help),
    severity = (reason == "monster" or reason == "low_hp") and 3 or 2,
    threat_dist = nearest_enemy_dist(state, player.pos),
  })
  return state
end

-- Marcador en el mapa ("ven aqui", "peligro") visible para todo el equipo.
local function handle_ping(state, dispatcher, presence, payload, t)
  local player = state.players[presence.user_id]
  if player == nil or player.dead then return state end
  if not in_map_bounds(payload.pos) then return state end
  state.rate_ping = state.rate_ping or {}
  local key = presence_key(presence)
  if state.rate_ping[key] and (t - state.rate_ping[key]) < 1.0 then return state end
  state.rate_ping[key] = t
  broadcast(dispatcher, OP_PING, {
    user_id = presence.user_id, username = player.username, pos = payload.pos,
    kind = tostring(payload.kind or "here"),
  })
  return state
end

local function handle_revive(state, dispatcher, presence, payload, t)
  local medic = state.players[presence.user_id]
  if medic == nil or medic.dead then
    send_one(dispatcher, OP_REVIVE_REJECT, { reason = "medic_dead" }, presence)
    return state
  end
  local target_id = tostring(payload.target_id or payload.user_id or "")
  if target_id == "" or target_id == presence.user_id then
    send_one(dispatcher, OP_REVIVE_REJECT, { reason = "bad_target" }, presence)
    return state
  end
  local target = state.players[target_id]
  if target == nil or not target.dead then
    send_one(dispatcher, OP_REVIVE_REJECT, { reason = "target_not_down" }, presence)
    return state
  end
  if not (MODES[state.mode] or MODES.coop_waves).revive then
    send_one(dispatcher, OP_REVIVE_REJECT, { reason = "mode_no_revive" }, presence)
    return state
  end
  if target.bled_out then
    send_one(dispatcher, OP_REVIVE_REJECT, { reason = "bled_out" }, presence)
    return state
  end
  if not state.presences[target_id] then
    send_one(dispatcher, OP_REVIVE_REJECT, { reason = "target_left" }, presence)
    return state
  end
  if (t - (medic.last_revive_at or 0)) < REVIVE_COOLDOWN_S then
    send_one(dispatcher, OP_REVIVE_REJECT, {
      reason = "cooldown",
      remaining = REVIVE_COOLDOWN_S - (t - (medic.last_revive_at or 0)),
    }, presence)
    return state
  end
  local medic_pos = payload.medic_pos or payload.pos or medic.pos
  local target_pos = payload.target_pos or target.pos
  if not in_map_bounds(medic_pos) or not in_map_bounds(target_pos) then
    send_one(dispatcher, OP_REVIVE_REJECT, { reason = "out_of_bounds" }, presence)
    return state
  end
  if vec_dist(medic_pos, target_pos) > REVIVE_MAX_DIST then
    send_one(dispatcher, OP_REVIVE_REJECT, {
      reason = "too_far", distance = vec_dist(medic_pos, target_pos), max = REVIVE_MAX_DIST,
    }, presence)
    return state
  end
  medic.last_revive_at = t
  medic.pos = {
    x = tonumber(medic_pos.x or medic_pos[1]),
    y = tonumber(medic_pos.y or medic_pos[2]),
    z = tonumber(medic_pos.z or medic_pos[3]),
  }
  target.dead = false
  target.alive = true
  target.downed_until = nil
  target.pos = {
    x = tonumber(target_pos.x or target_pos[1]),
    y = tonumber(target_pos.y or target_pos[2]),
    z = tonumber(target_pos.z or target_pos[3]),
  }
  local medic = state.players[presence.user_id]
  if medic then medic.revives = medic.revives + 1 end
  broadcast(dispatcher, OP_REVIVE_OK, {
    medic_id = presence.user_id, target_id = target_id, pos = target.pos,
  })
  broadcast(dispatcher, OP_TEAM_ALERT, {
    kind = "revived", user_id = target_id, username = target.username,
    text = target.username .. " vuelve a la pelea.", severity = 1,
  })
  return state
end

local function handle_match_close(state, dispatcher, presence, payload, t)
  state.close_votes = state.close_votes or {}
  state.close_votes[presence.user_id] = true
  local present = count_presences(state)
  local votes = 0
  for id, _ in pairs(state.close_votes) do
    if state.presences[id] then votes = votes + 1 end
  end
  local force = payload and payload.force == true and present <= 1
  if force or (present > 0 and votes >= present * CLOSE_VOTE_RATIO) then
    return try_close_match(state, dispatcher, payload and payload.reason or "vote_close")
  end
  broadcast(dispatcher, OP_MATCH_CLOSE, {
    ok = false, pending = true, votes = votes, present = present, by = presence.user_id,
  })
  return state
end

local M = {}

function M.match_init(context, setupstate)
  setupstate = setupstate or {}
  local mode = tostring(setupstate.mode or "coop_waves")
  -- el aforo se calcula ANTES de armar el estado: en Lua una variable local usada en la
  -- tabla antes de declararse vale nil y la sala caia siempre al aforo por defecto.
  local cap = math.floor(tonumber(setupstate.max_players) or MAX_PLAYERS)
  cap = math.max(1, math.min(cap, MAX_PLAYERS_HARD))
  local state = {
    mode = mode,
    phase = "lobby",
    created_s = now_s(),
    host_session_id = "",
    peer_ids = {},
    next_peer_id = 2,
    wave = 0,
    wave_active = false,
    has_elite = false,
    break_ends_at = now_s() + 3,
    enemies = {},
    enemies_alive = 0,
    enemies_total_wave = 0,
    enemy_seq = 0,
    players = {},
    presences = {},
    rate_spawn = {},
    rate_damage = {},
    close_votes = {},
    tick = 0,
    empty_since = nil,
    created_at = now_s(),
    invited = setupstate.invited or {},
    max_players = cap,
    map = MAPS[tostring(setupstate.map or "")] and tostring(setupstate.map) or DEFAULT_MAP,
    room_name = tostring(setupstate.room_name or "Sala"):sub(1, 24),
    private = setupstate.private == true,
    code = tostring(setupstate.code or ""):upper():sub(1, 8),
    bots_wanted = math.max(0, math.min(math.floor(tonumber(setupstate.bots) or BOTS_DEFAULT), BOTS_MAX)),
    -- Sala sin monstruos: nadie genera oleadas. Solo se desactiva si se pide EXPLICITAMENTE (false);
    -- una sala antigua o sin el campo conserva sus monstruos.
    monsters = setupstate.monsters ~= false,
    last_bot_tick = 0,
  }
  sync_bots(state)
  state._last_label = room_label(state)
  local label = state._last_label
  nk.logger_info(("coopwave match_init mode=%s"):format(mode))
  return state, TICK_RATE, label
end

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata)
  if state.phase == "closed" then return state, false, "match_closed" end
  if count_presences(state) >= (state.max_players or MAX_PLAYERS) then return state, false, "match_full" end
  return state, true
end

function M.match_join(context, dispatcher, tick, state, presences)
  for _, presence in ipairs(presences) do
    state.presences[presence.user_id] = presence
    state.session_of = state.session_of or {}
    state.session_of[presence.user_id] = presence.session_id
    ensure_player(state, presence)
    state.empty_since = nil
  end
  sync_bots(state)
  refresh_label(state, dispatcher)
  -- Handshake del cliente: el primero que entra queda de host; cada uno recibe su peer id.
  for _, presence in ipairs(presences) do
    local mi_id = asignar_peer(state, presence)
    local host = presencia_host(state)
    if host ~= nil then
      send_meta(dispatcher, presence, { type = 0 }, host)       -- soy el host
      for _, destino in pairs(state.presences) do
        send_meta(dispatcher, destino, {                        -- tu peer id es este
          type = 1, session_id = presence.session_id, peer_id = mi_id,
        }, host)
      end
    end
  end
  broadcast(dispatcher, OP_MATCH_STATE, build_match_state_payload(state))
  return state
end

function M.match_leave(context, dispatcher, tick, state, presences)
  for _, presence in ipairs(presences) do
    state.presences[presence.user_id] = nil
    if state.close_votes then state.close_votes[presence.user_id] = nil end
  end
  if count_presences(state) == 0 then state.empty_since = now_s() end
  -- Si se va el host, el siguiente pasa a serlo y se le comunica a todos.
  for _, presence in ipairs(presences) do
    local sid = presence.session_id
    if state.peer_ids[sid] ~= nil then state.peer_ids[sid] = nil end
    if state.session_of ~= nil then state.session_of[presence.user_id] = nil end
    if state.host_session_id == sid then state.host_session_id = "" end
  end
  if state.host_session_id == "" then
    for _, pr in pairs(state.presences) do
      state.host_session_id = pr.session_id
      state.peer_ids[pr.session_id] = 1
      local nuevo_host = pr
      for _, destino in pairs(state.presences) do
        send_meta(dispatcher, destino, { type = 0 }, nuevo_host)
        for _, otro in pairs(state.presences) do
          send_meta(dispatcher, destino, {
            type = 1, session_id = otro.session_id, peer_id = state.peer_ids[otro.session_id] or 0,
          }, nuevo_host)
        end
      end
      break
    end
  end
  sync_bots(state)
  refresh_label(state, dispatcher)
  if count_presences(state) > 0 and all_players_dead(state) then
    return try_close_match(state, dispatcher, "team_wipe_after_leave")
  end
  return state
end

-- Red de seguridad: ningun bot se queda en una celda sin medir ni con una Y que no sea la del
-- plano. Si por cualquier camino (reaparicion, persecucion, empuje) acaba en un hueco, se le
-- recoloca en la celda medida mas cercana (nunca a ciegas ni a 20 m).
local function afianzar_bots(state)
  local set = suelo_set(state.map or DEFAULT_MAP)
  for _, p in pairs(state.players) do
    if p and p.bot and p.pos then
      local cx, cz = celda_de(p.pos.x, p.pos.z)
      local h = set[cx .. "," .. cz]
      if h == nil then
        local mejor, mejor_d = nil, nil
        for r = 1, 8 do
          for dx = -r, r do
            for dz = -r, r do
              if math.max(math.abs(dx), math.abs(dz)) == r then
                local hx = set[(cx + dx * 2) .. "," .. (cz + dz * 2)]
                if hx ~= nil then
                  local d = dx * dx + dz * dz
                  if mejor_d == nil or d < mejor_d then mejor, mejor_d = { cx + dx * 2, cz + dz * 2, hx }, d end
                end
              end
            end
          end
          if mejor ~= nil then break end
        end
        if mejor == nil then
          local c = celda_real(state)
          mejor = { c.x, c.z, c.y or 0.0 }
        end
        p.pos.x, p.pos.z, p.pos.y = mejor[1] + 0.0, mejor[2] + 0.0, mejor[3] + 0.0
        p.target = nil
      else
        p.pos.y = h
      end
    end
  end
end

function M.match_loop(context, dispatcher, tick, state, messages)
  state.tick = tick
  local t = now_s()
  if count_presences(state) == 0 then
    if state.empty_since == nil then
      state.empty_since = t
    elseif (t - state.empty_since) >= MATCH_EMPTY_GRACE_S then
      return try_close_match(state, dispatcher, "empty")
    end
  end
  if state.phase == "lobby" or state.phase == "break" then
    if state.monsters == false and not es_pvp(state) then
      -- Sala sin monstruos: no hay oleadas que contar ni esperar. Queda en fase "free" (libre).
      state.phase = "free"
      state.wave_active = false
      state.break_ends_at = nil
    elseif state.break_ends_at and t >= state.break_ends_at and count_presences(state) >= MIN_PLAYERS_START then
      state.wave = state.wave + 1
      state.break_ends_at = nil
      spawn_wave_enemies(state, dispatcher)
    end
  end
  calle_tick(state, dispatcher, t)
  -- Un solo dueno por bot y tick: en el Matadero los entrenados los lleva freestyle_tick (persecucion
  -- real por celdas). Antes move_bots los empujaba a la vez hacia un objetivo viejo y el tira y afloja
  -- dejaba al bot clavado en el borde de una celda sin medir.
  if es_pvp(state) then freestyle_tick(state, dispatcher, t) else move_bots(state, 1 / TICK_RATE) end
  afianzar_bots(state)
  if count_presences(state) > 0 then
    local lista = posiciones_bots(state)
    if #lista > 0 then broadcast(dispatcher, OP_BOT_POS, { b = lista, tick = tick }) end
  end
  expire_downed(state, dispatcher, t)
  if tick % TICK_RATE == 0 then
    refresh_label(state, dispatcher)
    -- los bots viajan en el estado del mapa para que los clientes los dibujen
    if count_presences(state) > 0 and state.bots_wanted and state.bots_wanted > 0 then
      broadcast(dispatcher, OP_MATCH_STATE, build_match_state_payload(state))
    end
  end
  for _, message in ipairs(messages) do
    local op = message.op_code
    local presence = message.sender
    local payload = decode_data(message.data) or {}
    if op == OP_SPAWN then
      state = handle_spawn(state, dispatcher, presence, payload, t)
    elseif op == OP_DAMAGE then
      state = handle_damage(state, dispatcher, presence, payload, t)
    elseif op == OP_HIT_BOT then
      state = handle_hit_bot_seguro(state, dispatcher, presence, payload, t)
    elseif op == OP_VOICE then
      state = handle_voice(state, dispatcher, presence, payload, t)
    elseif op == OP_BEFRIEND then
      state = handle_befriend(state, dispatcher, presence, payload, t)
    elseif op == OP_DEATH then
      state = handle_death(state, dispatcher, presence, payload, t)
    elseif op == OP_REVIVE then
      state = handle_revive(state, dispatcher, presence, payload, t)
    elseif op == OP_HELP_CALL then
      state = handle_help_call(state, dispatcher, presence, payload, t)
    elseif op == OP_PING then
      state = handle_ping(state, dispatcher, presence, payload, t)
    elseif op == OP_PLAYER_STATE then
      -- Posicion/orientacion. Antes solo se guardaba y nunca se reenviaba, asi que los
      -- jugadores no se veian moverse entre si. Ahora se retransmite al resto del equipo.
      local pos = payload.pos
      if not pos and payload.p then
        pos = { x = payload.p[1], y = payload.p[2], z = payload.p[3] }
      end
      local pl = state.players[presence.user_id]
      local valida = false
      -- skin de la tienda: solo ids conocidos (neko_*), nunca texto libre del cliente
      local sk = tostring(payload.sk or "")
      if pl and SKINS_VALIDAS[sk] then pl.skin = sk end
      if pl and pos and in_map_bounds(pos) then
        pl.pos = { x = tonumber(pos.x or pos[1]), y = tonumber(pos.y or pos[2]), z = tonumber(pos.z or pos[3]) }
        valida = true
      end
      local otros = {}
      for uid, pr in pairs(state.presences) do
        if uid ~= presence.user_id then otros[#otros + 1] = pr end
      end
      if #otros > 0 and valida then
        broadcast(dispatcher, OP_PLAYER_STATE, {
          user_id = presence.user_id,
          username = presence.username,
          skin = pl and pl.skin or "",
          pos = pl and pl.pos or pos,
          rot = payload.rot or payload.r,
        }, otros)
      end
    elseif op == OP_MATCH_CLOSE then
      state = handle_match_close(state, dispatcher, presence, payload, t)
    elseif op == 4100 or op == 9001 or op == 9002 then
      -- ignore voice/bridge
    else
      send_one(dispatcher, OP_ERROR, { op = op, reason = "unknown_opcode" }, presence)
    end
    if state == nil then return nil end
  end
  return state
end

function M.match_terminate(context, dispatcher, tick, state, grace_seconds)
  nk.logger_info(("coopwave terminate tick=%s grace=%s"):format(tostring(tick), tostring(grace_seconds)))
  return state
end

function M.match_signal(context, dispatcher, tick, state, data)
  return state, data
end

local function user_mode(user)
  if not user then return nil end
  local props = user.string_properties or user.properties or {}
  if type(props) == "table" then
    local m = props.mode
    if m ~= nil and MODES[tostring(m)] then return tostring(m) end
  end
  -- Respaldo: el modo viene en la query ("+properties.mode:horde"). Antes solo se
  -- reconocia coop_waves, asi que survival, horde y boss_rush nunca se podian jugar online.
  local query = user.query or ""
  if type(query) == "string" then
    for mode in pairs(MODES) do
      if string.find(query, "properties.mode:" .. mode, 1, true) then return mode end
    end
  end
  return nil
end

local function split_by_mode(users)
  local groups = {}
  local order = {}
  for _, u in ipairs(users) do
    local mode = user_mode(u) or "coop_waves"
    if groups[mode] == nil then
      groups[mode] = {}
      order[#order + 1] = mode
    end
    local g = groups[mode]
    g[#g + 1] = u
  end
  return groups, order
end

local function create_coop_match(users, mode)
  local invited = {}
  for _, u in ipairs(users) do
    invited[#invited + 1] = u.presence or u
  end
  -- La sala nace con el aforo del modo, no con un numero fijo. Margen para quien llegue
  -- despues (relleno) hasta el techo duro; asi cientos de usuarios caen en MUCHAS salas.
  local cap = math.min(MAX_PLAYERS_HARD, math.max(#invited, MAX_PLAYERS))
  local setup = { mode = mode or "coop_waves", invited = invited, max_players = cap }
  return nk.match_create("coopwave", setup)
end

-- Nakama permite devolver UN solo match_id por grupo emparejado. Como el cliente ya pide
-- un unico modo por ticket (properties.mode:<modo>), el grupo es homogeneo; si no lo fuera,
-- gana el modo con mas jugadores y se avisa en el log en lugar de descartar en silencio.
local function matchmaker_matched(context, matched_users)
  if matched_users == nil or #matched_users == 0 then return nil end
  local groups, order = split_by_mode(matched_users)
  local best, best_n = nil, -1
  for _, mode in ipairs(order) do
    if #groups[mode] > best_n then best, best_n = mode, #groups[mode] end
  end
  for _, mode in ipairs(order) do
    if mode ~= best then
      nk.logger_warn(("matchmaker_matched grupo mixto: mode=%s n=%d queda fuera"):format(mode, #groups[mode]))
    end
  end
  local match_id = create_coop_match(groups[best], best)
  nk.logger_info(("matchmaker_matched mode=%s n=%d match=%s"):format(best, #groups[best], tostring(match_id)))
  return match_id
end
-- Plazas PROMETIDAS. Cuando llegan muchos jugadores a la vez, ninguno esta aun conectado por websocket,
-- asi que `size` de todas las salas vale 0 y el emparejador las llenaba sin limite (match_full).
-- Cada vez que se reparte un jugador a una sala se apunta una reserva que caduca a los RESERVA_TTL_S
-- segundos (tiempo de sobra para conectar); el aforo real = conectados + reservas vivas.
-- Vive en memoria del modulo: vale para una sola instancia de Nakama, que es la que tenemos.
local RESERVA_TTL_S = 20
local reservas = {}   -- match_id -> lista de instantes de caducidad

local function reservas_vivas(match_id)
  local lista = reservas[match_id]
  if not lista then return 0 end
  local ahora = now_s()
  local vivas = {}
  for _, caduca in ipairs(lista) do if caduca > ahora then vivas[#vivas + 1] = caduca end end
  reservas[match_id] = vivas
  return #vivas
end

local function reservar(match_id)
  reservas[match_id] = reservas[match_id] or {}
  table.insert(reservas[match_id], now_s() + RESERVA_TTL_S)
end

-- RPC "join_or_create": entra a una sala publica abierta del modo pedido o crea una nueva.
-- Resuelve tres cosas a la vez: (1) el matchmaker de Nakama exige minimo 2 jugadores, asi que
-- una persona sola nunca encontraba partida; (2) salas publicas; (3) con cientos de usuarios
-- se llenan salas de ~20 una tras otra en lugar de esperar emparejamientos.
-- Entrada:  {"mode": "coop_waves", "private": false}
-- Salida:   {"match_id": "...", "mode": "...", "created": true|false}
local function rpc_join_or_create(context, payload)
  local req = {}
  if payload and payload ~= "" then
    local ok, parsed = pcall(nk.json_decode, payload)
    if ok and type(parsed) == "table" then req = parsed end
  end
  local mode = tostring(req.mode or "coop_waves")
  if not MODES[mode] then mode = "coop_waves" end
  -- Entrar a una sala concreta (la de un amigo): se comprueba que siga abierta y con hueco.
  if req.match_id ~= nil and tostring(req.match_id) ~= "" then
    local target = tostring(req.match_id)
    -- Se consulta la sala directamente: buscar en el listado fallaba cuando habia
    -- muchas salas abiertas (la sala del amigo quedaba fuera de los primeros 50).
    local info, tamano, cap = nil, nil, MAX_PLAYERS
    if nk.match_get then
      local ok, got = pcall(nk.match_get, target, true)
      if ok and got then info = got end
    end
    if info then
      tamano = tonumber(info.size) or 0
      local okl, label = pcall(nk.json_decode, info.label or "{}")
      if okl and type(label) == "table" then cap = tonumber(label.max) or MAX_PLAYERS end
    else
      for _, m in ipairs(nk.match_list(50, true, nil, 0, nil, nil) or {}) do
        if m.match_id == target then
          tamano = tonumber(m.size) or 0
          local okl, label = pcall(nk.json_decode, m.label or "{}")
          if okl and type(label) == "table" then cap = tonumber(label.max) or MAX_PLAYERS end
          break
        end
      end
    end
    if tamano == nil then return nk.json_encode({ error = "match_not_found" }) end
    if tamano + reservas_vivas(target) < cap then
      reservar(target)
      return nk.json_encode({ match_id = target, mode = mode, created = false })
    end
    return nk.json_encode({ error = "match_full" })
  end
  if req.private ~= true then
    -- salas abiertas del modo, con hueco; se prefiere la mas llena (agrupa jugadores)
    -- min_size = 0: una sala recien creada aun no tiene a nadie conectado por websocket;
    -- con min_size = 1 se ignoraba y dos jugadores casi simultaneos acababan en salas distintas.
    -- Se prefieren salas del MISMO mapa y con humanos dentro: las salas viejas llenas de
    -- bots inflaban el tamano y hacian que dos amigos acabaran en salas distintas.
    local want_map = tostring(req.map or "")
    local found = nk.match_list(20, true, nil, 0, nil, nil)
    local best, best_score = nil, -1
    for _, m in ipairs(found or {}) do
      local ok, label = pcall(nk.json_decode, m.label or "{}")
      if ok and type(label) == "table" and label.mode == mode and label.open ~= false
          and (tonumber(m.size) or 0) + reservas_vivas(m.match_id) < (tonumber(label.max) or MAX_PLAYERS) then
        local humans = (tonumber(label.players) or 0) + reservas_vivas(m.match_id)
        local edad = now_s() - (tonumber(label.t) or 0)
        local recien = edad >= 0 and edad <= FRESH_ROOM_S
        -- Si pediste un mapa concreto, solo valen salas de ESE mapa: antes te metia en la
        -- sala de otro mapa que ya tenia gente y el mapa elegido se ignoraba.
        local mismo_mapa = (want_map == "") or (label.map == want_map)
        if mismo_mapa and (humans > 0 or recien) then
          local score = humans
          if score > best_score then best, best_score = m, score end
        end
      end
    end
    if best then
      reservar(best.match_id)
      return nk.json_encode({ match_id = best.match_id, mode = mode, created = false })
    end
  end
  local map = tostring(req.map or DEFAULT_MAP)
  if not MAPS[map] then map = DEFAULT_MAP end
  local nombre = tostring(req.name or "")
  if nombre == "" and context ~= nil and context.user_id then
    -- el nombre por defecto lleva a quien la abrio, asi se distingue en el listado
    local ok, cuenta = pcall(nk.account_get_id, context.user_id)
    if ok and cuenta and cuenta.user then
      nombre = "Sala de " .. tostring(cuenta.user.username or "jugador")
    end
  end
  if nombre == "" then nombre = "Sala abierta" end
  local match_id = nk.match_create("coopwave", {
    mode = mode, max_players = MAX_PLAYERS, private = req.private == true,
    map = map, room_name = nombre, bots = req.bots,
  })
  reservar(match_id)
  return nk.json_encode({ match_id = match_id, mode = mode, created = true })
end


-- ---------------------------------------------------------------------------------------------
-- Codigo de sala: 5 caracteres que se pueden decir en voz alta. Sin 0/O ni 1/I/L (se confunden).
-- ---------------------------------------------------------------------------------------------
local CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
local CODE_LEN = 5

local function normalizar_codigo(texto)
  -- tolera espacios, guiones y minusculas ("k7m-2q " -> "K7M2Q")
  return (tostring(texto or ""):upper():gsub("[^%w]", ""))
end

local function generar_codigo()
  local out = {}
  for i = 1, CODE_LEN do
    local k = math.random(1, #CODE_ALPHABET)
    out[i] = CODE_ALPHABET:sub(k, k)
  end
  return table.concat(out)
end

-- Todas las salas vivas (publicas y privadas). El listado publico las filtra por su cuenta.
local function salas_vivas()
  local out = {}
  for _, m in ipairs(nk.match_list(100, true, nil, 0, nil, nil) or {}) do
    local ok, label = pcall(nk.json_decode, m.label or "{}")
    if ok and type(label) == "table" then out[#out + 1] = { m = m, label = label } end
  end
  return out
end

local function buscar_por_codigo(codigo)
  for _, e in ipairs(salas_vivas()) do
    if normalizar_codigo(e.label.code) == codigo then return e.m, e.label end
  end
  return nil
end

-- RPC "create_room": SIEMPRE crea una sala nueva y devuelve su codigo. Nunca se mete en otra.
-- Entrada:  {"mode","map","name","private":true|false,"bots"}
-- Salida:   {"match_id","code","private","mode","map","name"}
local function rpc_create_room(context, payload)
  local req = {}
  if payload and payload ~= "" then
    local ok, parsed = pcall(nk.json_decode, payload)
    if ok and type(parsed) == "table" then req = parsed end
  end
  local mode = tostring(req.mode or "coop_waves")
  if not MODES[mode] then mode = "coop_waves" end
  local map = tostring(req.map or DEFAULT_MAP)
  if not MAPS[map] then map = DEFAULT_MAP end
  local nombre = tostring(req.name or ""):gsub("[%c]", ""):sub(1, 24)
  if nombre == "" and context ~= nil and context.user_id then
    local ok, cuenta = pcall(nk.account_get_id, context.user_id)
    if ok and cuenta and cuenta.user then
      nombre = "Sala de " .. tostring(cuenta.user.username or "jugador")
    end
  end
  if nombre == "" then nombre = "Sala abierta" end
  -- codigo unico entre las salas vivas
  local vivos = {}
  for _, e in ipairs(salas_vivas()) do vivos[normalizar_codigo(e.label.code)] = true end
  local codigo = generar_codigo()
  for _ = 1, 30 do
    if not vivos[codigo] then break end
    codigo = generar_codigo()
  end
  local privada = req.private == true
  local aforo = math.floor(tonumber(req.max_players) or MAX_PLAYERS)
  aforo = math.max(1, math.min(aforo, MAX_PLAYERS_HARD))
  local bots = req.bots
  if bots ~= nil then bots = math.max(0, math.min(math.floor(tonumber(bots) or BOTS_DEFAULT), BOTS_MAX)) end
  local match_id = nk.match_create("coopwave", {
    mode = mode, max_players = aforo, private = privada, code = codigo,
    map = map, room_name = nombre, bots = bots, monsters = req.monsters ~= false,
  })
  reservar(match_id)
  return nk.json_encode({
    match_id = match_id, code = codigo, private = privada, mode = mode, map = map, name = nombre,
    max_players = aforo, monsters = req.monsters ~= false, bots = bots,
  })
end

-- RPC "join_room": entra a una sala EXISTENTE por su codigo. Nunca crea nada.
-- Entrada:  {"code":"K7M2Q"}
-- Salida:   {"match_id","code",...}  o  {"error": "code_invalid"|"code_not_found"|"match_full"|"match_closed"}
local function rpc_join_room(context, payload)
  local req = {}
  if payload and payload ~= "" then
    local ok, parsed = pcall(nk.json_decode, payload)
    if ok and type(parsed) == "table" then req = parsed end
  end
  local codigo = normalizar_codigo(req.code)
  if #codigo ~= CODE_LEN then return nk.json_encode({ error = "code_invalid" }) end
  local m, label = buscar_por_codigo(codigo)
  if not m then return nk.json_encode({ error = "code_not_found" }) end
  if label.phase == "closed" then return nk.json_encode({ error = "match_closed" }) end
  local cap = tonumber(label.max) or MAX_PLAYERS
  if (tonumber(m.size) or 0) + reservas_vivas(m.match_id) >= cap then
    return nk.json_encode({ error = "match_full" })
  end
  reservar(m.match_id)
  return nk.json_encode({
    match_id = m.match_id, code = codigo, private = label.private == true,
    mode = label.mode or "coop_waves", map = label.map or DEFAULT_MAP, name = label.name or "Sala",
  })
end

-- RPC "list_rooms": lo que enseña el lobby antes de entrar. Devuelve cada sala
-- publica con su modo, mapa, jugadores y oleada, para poder elegir a cual unirse.
-- Entrada:  {} (opcional {"mode": "coop_waves"} para filtrar)
-- Salida:   {"rooms":[{match_id, mode, map, map_label, name, players, bots, max, wave, joinable}]}
local function rpc_list_rooms(context, payload)
  local req = {}
  if payload and payload ~= "" then
    local ok, parsed = pcall(nk.json_decode, payload)
    if ok and type(parsed) == "table" then req = parsed end
  end
  local want = req.mode and tostring(req.mode) or nil
  local rooms = {}
  local found = nk.match_list(30, true, nil, 0, nil, nil)
  for _, m in ipairs(found or {}) do
    local ok, label = pcall(nk.json_decode, m.label or "{}")
    if ok and type(label) == "table" and label.open ~= false and label.private ~= true then
      local map_id = tostring(label.map or DEFAULT_MAP)
      local players = tonumber(label.players) or 0
      local cap = tonumber(label.max) or MAX_PLAYERS
      if (want == nil or label.mode == want) and players < cap then
        rooms[#rooms + 1] = {
          match_id = m.match_id,
          mode = label.mode or "coop_waves",
          mode_label = (MODES[label.mode or "coop_waves"] or {}).label or "Oleadas",
          map = map_id,
          map_label = (MAPS[map_id] or {}).label or map_id,
          name = label.name or "Sala",
          code = tostring(label.code or ""),
          players = players,
          bots = tonumber(label.bots) or 0,
          max = cap,
          monsters = label.monsters ~= false,
          wave = tonumber(label.wave) or 0,
          joinable = true,
        }
      end
    end
  end
  -- salas con mas gente primero: asi el lobby agrupa en lugar de dispersar
  table.sort(rooms, function(a, b) return a.players > b.players end)
  -- Si no queda ninguna sala abierta se abre una de guardia: el listado del lobby
  -- nunca aparece vacio y siempre hay sitio al que entrar.
  if #rooms == 0 then
    local puede = true
    local okr, leido = pcall(nk.storage_read, { { collection = "system", key = "keeper", user_id = context.user_id } })
    if okr and leido and leido[1] and leido[1].value then
      puede = (now_s() - (tonumber(leido[1].value.t) or 0)) > 40
    end
    if puede then
      local mapas = { "recycling_plant", "storm_village", "space_arena" }
      local mapa = mapas[(math.floor(now_s() / 40) % #mapas) + 1]
      local okc, nueva = pcall(nk.match_create, "coopwave", {
        mode = "freestylers", max_players = MAX_PLAYERS, map = mapa,
        room_name = "Casa Boomer Shooter", bots = BOTS_MAX,
      })
      if okc and nueva then
        pcall(nk.storage_write, { { collection = "system", key = "keeper",
          value = { t = now_s() }, permission_read = 0, permission_write = 0 } })
        table.insert(rooms, {
          match_id = nueva, mode = "freestylers", mode_label = (MODES.freestylers or {}).label or "Matadero",
          map = mapa, map_label = (MAPS[mapa] or {}).label or mapa, name = "Casa Boomer Shooter",
          players = 0, bots = BOTS_MAX, max = MAX_PLAYERS, wave = 0, joinable = true,
        })
      end
    end
  end
  return nk.json_encode({ rooms = rooms, count = #rooms })
end

nk.register_rpc(rpc_list_rooms, "list_rooms")
M.rpc_list_rooms = rpc_list_rooms

nk.register_rpc(rpc_create_room, "create_room")
M.rpc_create_room = rpc_create_room
nk.register_rpc(rpc_join_room, "join_room")
M.rpc_join_room = rpc_join_room

nk.register_rpc(rpc_join_or_create, "join_or_create")
M.rpc_join_or_create = rpc_join_or_create

nk.register_matchmaker_matched(matchmaker_matched)
M.matchmaker_matched = matchmaker_matched
M._user_mode = user_mode

return M
