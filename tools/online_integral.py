"""Prueba integral del online contra PRODUCCION: lo que hace un jugador real, de principio a fin."""
import os, json, base64, urllib.request, uuid, time, asyncio, websockets
H="boomershooter.onrender.com"; K=os.environ["NAKAMA_SERVER_KEY"]
def http(p,b=None,t=None):
    h={"Content-Type":"application/json","Authorization":("Bearer "+t) if t else "Basic "+base64.b64encode((K+":").encode()).decode()}
    r=urllib.request.Request("https://"+H+p,json.dumps(b).encode() if b is not None else None,h,"POST")
    try:
        x=urllib.request.urlopen(r,timeout=60); return x.status,json.load(x)
    except urllib.error.HTTPError as e: return e.code,e.read().decode()[:200]
def login(tag):
    c,j=http("/v2/account/authenticate/device?create=true&username=%s%d"%(tag,int(time.time()*1000)%1000000),{"id":str(uuid.uuid4())}); return j["token"]
def rpc(t,n,p): return http("/v2/rpc/%s?unwrap"%n,p,t)
def uid(tok): return json.loads(base64.urlsafe_b64decode(tok.split(".")[1]+"==")).get("uid")

class C:
    def __init__(s,tok,mid): s.tok=tok; s.mid=mid; s.ops=[]; s.estado={}; s.cerrado=False
    async def __aenter__(s):
        s.ws=await websockets.connect("wss://%s/ws?token=%s&format=json"%(H,s.tok),ping_interval=20)
        await s.ws.send(json.dumps({"cid":"1","match_join":{"match_id":s.mid}}))
        s.t=asyncio.create_task(s.leer()); await asyncio.sleep(1.5); return s
    async def __aexit__(s,*a):
        s.t.cancel()
        try: await s.ws.close()
        except Exception: pass
    async def leer(s):
        try:
            while True:
                m=json.loads(await s.ws.recv())
                if "match_data" in m:
                    md=m["match_data"]; op=int(md["op_code"])
                    try: pl=json.loads(base64.b64decode(md["data"]).decode() or "{}")
                    except Exception: pl={}
                    s.ops.append((op,pl))
                    if op==60: s.estado=pl
        except Exception: s.cerrado=True
    async def env(s,op,pl): await s.ws.send(json.dumps({"match_data_send":{"match_id":s.mid,"op_code":op,"data":base64.b64encode(json.dumps(pl).encode()).decode()}}))
    def vio(s,op): return [p for o,p in s.ops if o==op]

R=[]
def chk(nombre,ok,det=""):
    ok=bool(ok); R.append(ok); print(("  OK    " if ok else "  FALLA ")+nombre+(" | "+str(det) if det else ""))

async def main():
    ta,tb=login("ia"),login("ib"); ua,ub=uid(ta),uid(tb)
    # 1) crear sala con mapa pedido
    c,r=rpc(ta,"join_or_create",{"mode":"survival","map":"space_arena","name":"Prueba integral"})
    chk("crear sala con el mapa pedido",c==200 and isinstance(r,dict) and r.get("match_id"),r if c!=200 else r.get("map"))
    mid=r["match_id"]
    # 2) aparece en el listado
    await asyncio.sleep(1.5)
    c,l=rpc(tb,"list_rooms",{}); salas=(l.get("rooms") if isinstance(l,dict) else l) or []
    chk("la sala sale en el listado",any((x.get("match_id")==mid) for x in salas),"%d salas"%len(salas))
    # 3) el segundo entra DESDE el listado (mismo match)
    c,r2=rpc(tb,"join_or_create",{"mode":"survival","map":"space_arena"})
    chk("el segundo jugador cae en la misma sala",isinstance(r2,dict) and r2.get("match_id")==mid,r2.get("match_id","")[:8] if isinstance(r2,dict) else r2)
    async with C(ta,mid) as A, C(tb,mid) as B:
        await asyncio.sleep(3.5)
        chk("el servidor manda estado (op 60)",bool(A.estado) and bool(B.estado))
        chk("mapa correcto en el estado",A.estado.get("map")=="space_arena",A.estado.get("map"))
        chk("hay enemigos de oleada",len(A.estado.get("enemies") or [])>0,len(A.estado.get("enemies") or []))
        # 4) posiciones cruzadas
        await A.env(70,{"pos":{"x":3.0,"y":1.0,"z":-4.0},"rot":0.5}); await B.env(70,{"pos":{"x":-2.0,"y":1.0,"z":6.0},"rot":1.0})
        await asyncio.sleep(2)
        pa=[p for p in (A.estado.get("players") or []) if p.get("user_id")==ub]
        pb=[p for p in (B.estado.get("players") or []) if p.get("user_id")==ua]
        chk("A ve la posicion de B",bool(pa) and abs(float((pa[0].get("pos") or {}).get("z",0))-6.0)<1.0,pa[0].get("pos") if pa else "no esta")
        chk("B ve la posicion de A",bool(pb) and abs(float((pb[0].get("pos") or {}).get("x",0))-3.0)<1.0,pb[0].get("pos") if pb else "no esta")
        # 5) daño y muerte sincronizados
        en=(A.estado.get("enemies") or [])
        if en:
            for d in (60,60,999):
                await A.env(10,{"enemy_id":en[0]["id"],"damage":d,"pos":{"x":0,"y":1,"z":0}}); await asyncio.sleep(0.5)
            await asyncio.sleep(2)
            chk("la muerte llega al que disparo",len(A.vio(12))>0,len(A.vio(12)))
            chk("la muerte llega al companero",len(B.vio(12))>0,len(B.vio(12)))
        # 6) voz en los tres canales, cerca
        audio=base64.b64encode(bytes([0xAB]*160)).decode(); res={}
        for ch in ("prox","team","all"):
            n0=len(B.vio(92)); await A.env(92,{"channel":ch,"data":audio}); await asyncio.sleep(1.2)
            res[ch]=len(B.vio(92))-n0
        chk("voz llega por proximidad/equipo/todos",all(v>0 for v in res.values()),res)
        # 7) ayuda
        n0=len(B.ops); await A.env(80,{"reason":"help","pos":{"x":3,"y":1,"z":-4}}); await asyncio.sleep(1.5)
        nuevos=sorted(set(o for o,_ in B.ops[n0:]))
        chk("la peticion de ayuda llega al companero (algun aviso nuevo)",any(o in (80,81,82,83,85,87,88,89) for o in nuevos),"ops recibidos: %s"%nuevos)
        # 8) A se va: la sala sigue viva para B
    await asyncio.sleep(0.5)
    async with C(tb,mid) as B2:
        await asyncio.sleep(3)
        chk("tras irse A la sala sigue viva para B",bool(B2.estado) and not B2.cerrado)
    print("\nRESULTADO: %d/%d"%(sum(R),len(R)))
asyncio.run(main())
