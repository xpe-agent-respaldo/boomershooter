-- Charla de los bots. Plantillas COMPLETAS (bien escritas, con concordancia) con huecos que se
-- rellenan desde bancos grandes: {nombre} {apodo} {lugar} {arma} {n} {cosa} {gang} {mapa} {animo}.
-- La variedad sale de: plantillas x huecos x contexto (vida, distancia, oleada) x remates, y de que
-- cada bot recuerda lo ultimo que dijo para no repetirse. Todo en espanol neutro, sin concordancias rotas.
local M = {}

-- ---------- bancos de huecos (cada uno concuerda en genero/numero con su articulo) ----------
local H = {
  apodo   = { "campeon", "forastero", "chaval", "pieza", "colega", "valiente", "crack", "jefe", "novato", "veterano", "fenomeno", "artista", "campeona", "leyenda", "figura" },
  lugar   = { "este rincon", "este barrio", "esta zona", "este callejon", "esta esquina", "este patio", "esta calle", "este tramo", "esta ruina", "este pasillo" },
  arma    = { "la pistola", "el subfusil", "la escopeta", "el rifle", "mi punteria", "mi suerte", "mis puños", "mi paciencia" },
  cosa    = { "una radio", "unas pilas", "un casco", "una llave inglesa", "un termo", "unas botas", "un mapa viejo", "una linterna", "un cable", "un bidon" },
  animo   = { "tranquilo", "con calma", "sin prisa", "con cuidado", "a lo grande", "sin miedo", "con paciencia", "a tu ritmo" },
  num     = { "dos", "tres", "cuatro", "cinco", "seis", "siete" },
  hora    = { "esta noche", "hoy", "ahora mismo", "antes del amanecer", "en un rato", "esta tarde" },
  bicho   = { "escarabajos", "reptiles", "bichos", "esas cosas", "monstruos" },
}

-- ---------- plantillas por rol y situacion (cada una es una frase completa y correcta) ----------
local T = {}

T.pandilla = {
  aviso = {
    "Eh, {apodo}, te metiste en el territorio de {gang}.",
    "Mira quien anda por {lugar}. Se acabo el paseo, {nombre}.",
    "Oye, {apodo}, aqui mandamos nosotros. Da media vuelta.",
    "{gang} no perdona a los que entran sin permiso.",
    "Te estabamos esperando, {nombre}. Tarde, pero llegaste.",
    "Ni se te ocurra correr, {apodo}. Conocemos {lugar} mejor que tu.",
    "Pandilla, a formar. Tenemos visita en {lugar}.",
    "Cuidadito, {apodo}. {gang} te tiene en la mira.",
    "Vaya, vaya. {nombre} anda perdido por {lugar}.",
    "Aqui se paga peaje, {apodo}. Y tu no traes nada.",
    "Somos {num} contra uno, {nombre}. Haz las cuentas.",
    "Esto es de {gang}, {apodo}. Lo que pisas tambien.",
    "Quieto ahi, {nombre}. {gang} habla primero.",
    "No hay vuelta atras, {apodo}. Entraste a {lugar} por tu cuenta.",
    "Te vimos entrar hace rato, {nombre}. Fuiste valiente o tonto.",
    "Mucho gusto, {apodo}. Somos tu comite de despedida.",
  },
  disparo = {
    "Toma esto, {apodo}.", "Ahi va, {nombre}. Esquivalo si puedes.", "Para ti, de parte de {gang}.",
    "Recibe, {apodo}. Sin rencores.", "Cuenta hasta tres, {nombre}.", "Pa que aprendas, {apodo}.",
    "Uno de {gang} para {nombre}.", "Mira como suena {arma}, {apodo}.", "A ver si aguantas esta, {nombre}.",
    "Plomo caliente, {apodo}. De la casa.", "Se me acaba la paciencia, {nombre}.", "Ahi va otra, {apodo}.",
  },
  herido = {
    "Ay, me dio, {apodo}. Eso dolio de verdad.", "Maldita sea, estoy mal herido.", "Aguanten, hermanos, que {nombre} pega fuerte.",
    "Auch. Me las vas a pagar, {nombre}.", "No puede ser. Sigo en pie por poco.", "Me tienen tocado. Cubranme.",
    "Eso estuvo cerca. Casi no lo cuento, {apodo}.", "Duele, pero no me rindo, {nombre}.", "Uf. Me hace falta un respiro.",
  },
  victoria = {
    "Uno menos. Avisen al siguiente, {gang}.", "Asi se hace, {gang}. {nombre} ya no molesta.",
    "Jaja. Te lo dije, {apodo}, no ibas a salir entero.", "Listo. Que no se repita en {lugar}.",
    "Otro que se rinde. Siguiente, por favor.", "Bien jugado, {nombre}. Casi.", "Que descanse. Era valiente, al menos.",
    "Ya esta, {gang}. {lugar} vuelve a ser nuestro.",
  },
}

T.solo = {
  aviso = {
    "Eh, {apodo}. No me sigas, voy solo.", "Psst. No te acerques, {nombre}.", "Esto es entre tu y yo, {apodo}.",
    "Sin pandillas, sin trucos. Solo tu y yo, {nombre}.", "Oye, {apodo}, me estas persiguiendo y no me gusta.",
    "Mira, {nombre}, no quiero problemas. Pero los tengo.", "Ni un paso mas, {apodo}. Te lo advierto.",
    "Voy por libre, {nombre}. Y asi me gusta.", "Te vi venir desde {lugar}, {apodo}.",
    "No insistas, {nombre}. No tengo nada para ti.", "Ultima vez que te lo digo, {apodo}: atras.",
    "Estoy cansado de que me sigan. Hoy te toca a ti, {nombre}.", "Aqui solo cabe uno, {apodo}. Y no eres tu.",
  },
  disparo = {
    "Toma, {apodo}.", "A lo solitario, {nombre}. Sin ayuda.", "Esquivalo si puedes, {apodo}.",
    "Esta es para ti, {nombre}.", "Sin pandilla y sin miedo, {apodo}.", "Prueba esto, {nombre}.", "Ahi va. Sin rencor, {apodo}.",
  },
  herido = {
    "Ay. Sin refuerzos, {apodo}, pero sigo.", "Maldita sea. Me diste, {nombre}.", "Eso dolio. No me rindo.",
    "Estoy solo y herido. Mala combinacion, {apodo}.", "Argh. Tampoco soy de piedra, {nombre}.",
  },
  victoria = {
    "Listo. Yo solo, como siempre.", "Uno menos, {apodo}. Sin ayuda de nadie.", "Asi se hace. Siguiente.",
    "Ya esta. Que nadie me siga, {nombre}.", "Sin pandillas y sin ayuda. Asi se gana.",
  },
}

T.amigo = {
  aviso = {
    "Hola, {nombre}. Parece que no tienes amigos por aqui. Pulsa F.",
    "Que tal, {apodo}. Me caes bien. ¿Hacemos equipo? Pulsa F.",
    "Menos mal que te encuentro, {nombre}. Me siento seguro contigo.", "Oye, {apodo}, ¿puedo ir contigo? Pulsa F.",
    "Buenas, {nombre}. Yo cubro tu espalda si tu cubres la mia.", "Por fin alguien normal, {apodo}. Pulsa F y vamos juntos.",
    "Mira, {nombre}, traigo {cosa}. Te la regalo si me dejas acompañarte.", "Cuanto tiempo sin ver una cara amable, {apodo}.",
    "Hola, {nombre}. Tengo {cosa} y buena punteria. ¿Te sirvo de algo? Pulsa F.",
    "No te asustes, {apodo}, soy de los buenos. Pulsa F y lo comprobamos.", "Que alegria verte, {nombre}. Esto estaba muy solo.",
    "Dicen que {nombre} es de fiar. Pulsa F y lo confirmo.", "Juntos duramos mas, {apodo}. Pulsa F.",
    "Soy {apodo} de verdad, no de pandilla. Pulsa F.",
  },
  siguiendo = {
    "Te sigo, {nombre}. {animo}.", "Voy detras de ti, {apodo}.", "Aqui estoy, {nombre}. Sin quedarme atras.",
    "Lidera tu, {apodo}. Yo cubro.", "Vamos {animo}, {nombre}.", "No te preocupes, {apodo}. Te cubro por detras.",
    "Si ves algo raro, avisa, {nombre}.", "Seguimos juntos, {apodo}. Asi me gusta.",
  },
  disparo = {
    "Te cubro, {nombre}.", "Yo me encargo, {apodo}.", "Agachate, {nombre}.", "Ahi va por ti, {apodo}.",
    "Tranquilo, {nombre}. Estoy contigo.", "Atras, {apodo}. Yo limpio.",
  },
  herido = {
    "Ay, me dieron. Ayudame, {nombre}.", "Auch. Estoy mal, {apodo}. No me dejes.", "Necesito ayuda, {nombre}.",
    "Eso dolio. Aguanto, {apodo}, pero poco.", "Cuidado, {nombre}. Estoy en las ultimas.",
  },
  victoria = {
    "Genial, {nombre}. Lo logramos juntos.", "Bien hecho, {apodo}. Invito yo.", "Eso es. Eres un crack, {nombre}.",
    "Sobrevivimos, {apodo}. Chocalas.", "Que bueno que estabas aqui, {nombre}.",
  },
}

T.entrenado = {
  aviso = {
    "GG, equipo. Entramos {animo} por {lugar}.", "Listo, {nombre}. Rotamos por la izquierda.", "Ready. Hold en {lugar}, chicos.",
    "Vamos, {apodo}. Sin tilt y a lo nuestro.", "A ver, {nombre}. Flanqueamos por arriba y cerramos.", "Okay, equipo. {num} segundos y empujamos.",
    "Dale, {apodo}. Cubrimos {lugar} y listo.", "Sin lag, chicos. Esta ronda es nuestra.", "Cuidado con {lugar}, {nombre}. Se oye movimiento.",
    "Atentos, equipo. Hay {bicho} cerca de {lugar}.", "{nombre}, tu cubres el centro. Yo voy por el flanco.",
    "Calma, {apodo}. Esto lo ganamos con cabeza.",
  },
  disparo = {
    "Headshot, {apodo}.", "Tomen, {nombre}. Con cariño.", "Ahi va. Con {arma}, sin mirar.", "Cuenta, {apodo}. Una menos.",
    "Recibe, {nombre}. Sin tilt.", "Mira que mira tengo, {apodo}.",
  },
  herido = {
    "Ay, lag. Cubranme, {nombre}.", "Auch. Estoy bajo de vida, {apodo}.", "Me dieron. Necesito medkit, chicos.",
    "Cuidado, {nombre}. Casi cero de vida.", "Aguanto, pero poco. Que alguien me cubra.",
  },
  victoria = {
    "GG, equipo. Ronda para nosotros.", "Ez, {nombre}. Otra?", "Bien jugado, {apodo}. Revancha cuando quieras.",
    "Wp, {nombre}. Limpiamos {lugar}.", "Ganamos {animo}. Asi se hace, equipo.",
  },
}

-- Capa extra segun lo que pasa de verdad: se pega al final de la frase con probabilidad.
local EXTRA = {
  vida_baja = { "Me queda poca vida.", "Estoy a un golpe de caer.", "Veo las estrellas.", "Me tiemblan las manos." },
  vida_alta = { "Hoy me siento imparable.", "Ni un rasguño todavia.", "Voy sobrado.", "Estoy como nuevo." },
  cerca     = { "Te tengo muy cerca.", "Casi te toco.", "Se te oye respirar.", "Estas a dos pasos." },
  lejos     = { "Te veo de lejos.", "No corras tanto.", "Asoma la cabeza.", "Te sigo desde aqui." },
  oleada    = { "Esta oleada viene fuerte.", "Los {bicho} no paran.", "Se acerca otra tanda.", "Esto se pone feo." },
}

-- ---------- utilidades ----------
local function elegir(lista, rnd) return lista[rnd(1, #lista)] end

local function llenar(txt, ctx, rnd)
  txt = txt:gsub("{(%w+)}", function(k)
    if k == "nombre" then return ctx.nombre or "amigo" end
    if k == "gang" then return ctx.gang or "la pandilla" end
    if k == "mapa" then return ctx.mapa or "el mapa" end
    if H[k] then return elegir(H[k], rnd) end
    return ""
  end)
  return txt
end

local function puntuar(frase)
  frase = frase:gsub("%s+", " "):gsub("%s+([,%.!?])", "%1"):gsub("^%s+", ""):gsub("%s+$", "")
  return (frase:gsub("^%l", string.upper))
end

-- Cuantas frases DISTINTAS puede generar un rol en una situacion (plantillas x huecos x capas).
function M.combinaciones(rol, situacion)
  local lista = T[rol] and T[rol][situacion]
  if not lista then return 0 end
  local total = 0
  for _, t in ipairs(lista) do
    local n = 1
    for k in t:gmatch("{(%w+)}") do
      if H[k] then n = n * #H[k] end
    end
    total = total + n
  end
  -- las capas de contexto multiplican (cada una opcional)
  local capas = 1
  for _, c in pairs(EXTRA) do capas = capas + #c end
  return total * capas
end

function M.total()
  local t = 0
  for rol, sits in pairs(T) do for sit in pairs(sits) do t = t + M.combinaciones(rol, sit) end end
  return t
end

-- ctx = {nombre, gang, mapa, vida (0-1), dist (m), oleada}; memoria = tabla del bot (no repite lo reciente).
function M.decir(rol, situacion, ctx, memoria, rnd)
  rnd = rnd or math.random
  local sits = T[rol] or T.entrenado
  local lista = sits[situacion] or sits.aviso
  memoria = memoria or {}
  ctx = ctx or {}
  local mejor
  for _ = 1, 40 do   -- 40 intentos: con pocas plantillas, 10 se agotaban y salia una repetida
    local frase = llenar(elegir(lista, rnd), ctx, rnd)
    -- capa de contexto: solo si encaja con lo que pasa
    local capa
    -- las frases que piden algo (pregunta, "Pulsa F") o que ya hablan de vida no llevan capa extra
    local cerrada = frase:find("%?") or frase:find("Pulsa F") or frase:find("vida") or frase:find("herido")
    if situacion ~= "victoria" and not cerrada then
      if ctx.vida and ctx.vida < 0.3 and rnd(1, 2) == 1 then capa = EXTRA.vida_baja
      elseif ctx.vida and ctx.vida > 0.9 and situacion ~= "herido" and rnd(1, 4) == 1 then capa = EXTRA.vida_alta
      elseif ctx.dist and ctx.dist < 8 and rnd(1, 3) == 1 then capa = EXTRA.cerca
      elseif ctx.dist and ctx.dist > 25 and rnd(1, 3) == 1 then capa = EXTRA.lejos
      elseif ctx.oleada and ctx.oleada >= 3 and rnd(1, 4) == 1 then capa = EXTRA.oleada end
    end
    if capa then frase = frase .. " " .. llenar(elegir(capa, rnd), ctx, rnd) end
    frase = puntuar(frase)
    mejor = frase
    local repetida = false
    for _, previa in ipairs(memoria) do if previa == frase then repetida = true break end end
    if not repetida then break end
  end
  memoria[#memoria + 1] = mejor
  if #memoria > 16 then table.remove(memoria, 1) end
  return mejor
end

return M
