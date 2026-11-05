#!/usr/bin/env python3
"""Replica en SQLite la logica de record_match_result (004) y comprueba los logros.

No sustituye probar en Postgres, pero valida la regla de negocio: acumulacion entre partidas,
umbrales exactos, logros que no se duplican y mejor oleada como maximo (no suma).
Los umbrales se leen del propio 004 para que test y migracion no se desincronicen.
"""
import re, sqlite3, os

SQL = open(os.path.join(os.path.dirname(__file__), "..", "migrations", "004_achievements_capacity.sql")).read()
# \s* y no \s+: en la migracion alguna fila va sin espacio tras la coma ('matches_played',25)
rows = re.findall(r"\('(\w+)',\s*'[^']*',\s*'[^']*',\s*'(\w+)',\s*'(\w+)',\s*(\d+),\s*(\d+),\s*(true|false)", SQL)
# columnas: id, categoria, metrica, umbral, puntos, oculto
ACH = {r[0]: dict(metric=r[2], thr=int(r[3]), pts=int(r[4]), hidden=r[5] == "true") for r in rows}

db = sqlite3.connect(":memory:")
db.execute("create table s(uid, total_kills, elite_kills, boss_kills, revives, times_downed, help_calls, best_wave, matches_played, matches_won, playtime_seconds)")
db.execute("create table pa(uid, aid, primary key(uid, aid))")
COLS = ["total_kills","elite_kills","boss_kills","revives","times_downed","help_calls","best_wave","matches_played","playtime_seconds"]

def record(uid, kills=0, elite=0, boss=0, revives=0, downed=0, helps=0, wave=0, won=False, seconds=0):
    cur = db.execute("select * from s where uid=?", (uid,)).fetchone()
    if cur is None:
        db.execute("insert into s values(?,?,?,?,?,?,?,?,?,?,?)",
                   (uid, max(kills,0), max(elite,0), max(boss,0), max(revives,0), max(downed,0), max(helps,0),
                    max(wave,0), 1, int(won), max(seconds,0)))
    else:
        db.execute("""update s set total_kills=total_kills+?, elite_kills=elite_kills+?, boss_kills=boss_kills+?,
                      revives=revives+?, times_downed=times_downed+?, help_calls=help_calls+?,
                      best_wave=max(best_wave,?), matches_played=matches_played+1,
                      matches_won=matches_won+?, playtime_seconds=playtime_seconds+? where uid=?""",
                   (max(kills,0), max(elite,0), max(boss,0), max(revives,0), max(downed,0), max(helps,0),
                    max(wave,0), int(won), max(seconds,0), uid))
    row = dict(zip(["uid"]+COLS[:7]+["matches_played","matches_won","playtime_seconds"],
                   db.execute("select * from s where uid=?", (uid,)).fetchone()))
    new = []
    for aid, a in ACH.items():
        if row[a["metric"]] >= a["thr"]:
            if db.execute("insert or ignore into pa values(?,?)", (uid, aid)).rowcount:
                new.append(aid)
    return new

ok = bad = 0
def check(n, c):
    global ok, bad
    print(("  ok   " if c else "  FALLA ") + n); ok += c; bad += (not c)

print("[logros]")
check("el catalogo tiene 14 logros", len(ACH) == 14)
check("los umbrales se leyeron bien (exterminador=100 kills)", ACH["exterminator"]["thr"] == 100)
check("primera partida con 1 kill -> primera sangre", record("a", kills=1, wave=1) == ["first_blood"])
check("99 kills acumuladas NO dan exterminador (1 + 98)", "exterminator" not in record("a", kills=98, wave=3))
check("la kill 100 desbloquea exterminador", "exterminator" in record("a", kills=1, wave=3))
check("no se vuelve a desbloquear lo ya ganado", record("a", kills=5, wave=3) == [])
check("la mejor oleada es maximo, no suma", db.execute("select best_wave from s where uid='a'").fetchone()[0] == 3)
n = record("b", wave=10)
check("llegar a la oleada 10 da wave_5 y wave_10", set(n) == {"wave_5", "wave_10"})
check("un resultado negativo (trampa) no resta", record("c", kills=-500, revives=-9) == [] and db.execute("select total_kills from s where uid='c'").fetchone()[0] == 0)
n = record("d", seconds=36000)
check("10 horas de juego -> maraton", "marathon" in n)
n = record("e", downed=20)
check("20 caidas -> logro secreto", "back_from_dead" in n and ACH["back_from_dead"]["hidden"])
check("el total de puntos ofrecidos es coherente", sum(a["pts"] for a in ACH.values()) == 10+25+60+30+50+30+70+10+15+35+80+20+40+20)
print(f"\n{ok} correctas, {bad} fallidas")
raise SystemExit(1 if bad else 0)
