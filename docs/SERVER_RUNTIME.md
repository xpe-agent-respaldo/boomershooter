# Nakama server runtime — coop waves

This document describes the authoritative Lua runtime shipped under `infra/nakama/modules/`.
Nakama image: `heroiclabs/nakama:3.30.0` (see `infra/nakama/Dockerfile`).

## Goals

- Matchmaker tickets with `mode:coop_waves` create an **authoritative** match using handler `"coopwave"`.
- The server owns enemy HP, wave progression, rewards, revive validation and match close.
- Clients must not be trusted for damage totals, kill claims or wave rewards.

## Module layout

| File | Role |
| --- | --- |
| `infra/nakama/modules/match_coop.lua` | Full match logic + `matchmaker_matched` registration |
| `infra/nakama/modules/coopwave.lua` | Thin alias: `return require("match_coop")` so `nk.match_create("coopwave", ...)` resolves |

## Matchmaker

Client (existing `Scripts/online_manager.gd`):

```gdscript
socket.add_matchmaker_async("+properties.mode:coop_waves", 2, 20, {"mode": "coop_waves"})
```

Server hook `matchmaker_matched`:

1. Inspect each matched user`s properties / query for `mode`.
2. Keep **homogeneous** groups. Prefer `coop_waves`.
3. If mixed modes appear in one matched set, only the `coop_waves` subset is used; others are logged and dropped.
4. Create match with handler name `"coopwave"` and return its match id so Nakama joins the players.

## Match lifecycle / states

| Phase | Meaning |
| --- | --- |
| `lobby` | Players joining; short delay before wave 1 |
| `break` | Inter-wave pause (`WAVE_BREAK_S = 4`) |
| `combat` | Wave active; enemies owned by server |
| `wave_complete` | Brief internal state before break |
| `closed` | Results sent; match loop returns `nil` and ends |

Enemy count formula (mirrors local `SpawnManager`):

```text
min(42, 4 + wave*2 + floor(wave/3))
```

Elite enemy on every 3rd wave (last spawn of that wave).

## Opcodes

**Do not reuse** `4100` (voice), `9001` / `9002` (NakamaMultiplayerBridge internals).

### Client → server

| Code | Name | JSON payload | Server action |
| ---: | --- | --- | --- |
| 1 | `OP_SPAWN` | `{ "pos": { "x", "y", "z" } }` | Bounds + rate check → `OP_SPAWN_OK` / `OP_SPAWN_REJECT` |
| 10 | `OP_DAMAGE` | `{ "enemy_id": "e1", "damage": 25, "pos"?: {...} }` | Validate rate/damage/enemy; apply HP; emit health/death/reward |
| 20 | `OP_DEATH` | `{ "pos"?: {...}, "cause"?: "string" }` | Mark player dead; broadcast; team wipe closes match |
| 30 | `OP_REVIVE` | `{ "target_id": "userId", "medic_pos": {...}, "target_pos": {...} }` | Cooldown + distance ≤ 4.5 → OK/REJECT |
| 90 | `OP_MATCH_CLOSE` | `{ "reason"?: "string", "force"?: false }` | Unanimous vote among present players, or `force` if alone |

### Server → clients

| Code | Name | JSON payload |
| ---: | --- | --- |
| 2 | `OP_SPAWN_OK` | `{ user_id, pos, wave, phase }` |
| 3 | `OP_SPAWN_REJECT` | `{ reason, ... }` |
| 11 | `OP_ENEMY_HEALTH` | `{ enemy_id, hp, max_hp, by, damage }` |
| 12 | `OP_ENEMY_DEATH` | `{ enemy_id, by, elite, wave, pos }` |
| 21 | `OP_PLAYER_DEATH` | `{ user_id, pos, wave, cause }` |
| 31 | `OP_REVIVE_OK` | `{ medic_id, target_id, pos }` |
| 32 | `OP_REVIVE_REJECT` | `{ reason, ... }` |
| 40 | `OP_REWARD` | `{ reason, rewards: [{ user_id, amount, total }], wave?, enemy_id? }` |
| 50 | `OP_WAVE_STATE` | `{ event, wave, ... }` events: `wave_break`, `wave_started`, `wave_completed` |
| 60 | `OP_MATCH_STATE` | Snapshot: phase, wave, players[], enemies[] |
| 90 | `OP_MATCH_CLOSE` | `{ ok, reason?, pending?, votes?, present? }` |
| 91 | `OP_MATCH_RESULT` | Final scores before terminate |
| 99 | `OP_ERROR` | `{ op, reason, ... }` |

## Anti-cheat (basic)

- Spawn rate: max 3 / second / presence.
- Damage rate: max 25 / second / presence (blocks impossible fire rates).
- Damage per hit clamped to `[1, 1000]`; NaN/Inf rejected.
- Positions must sit inside map AABB `[-120,-5,-120]..[120,40,120]`.
- Revive: 8 s cooldown, max distance 4.5 units, medic must be alive, target down and present.
- Rewards only emitted by server (kill + wave clear). Never trust client-sent score.

## Rewards (server)

| Event | Amount |
| --- | --- |
| Kill | 10 (+75 if elite) |
| Wave clear (alive players) | 50 (+75 if wave had elite) |

## Godot client integration notes

**Do not treat this section as applied code** — `Scripts/` is intentionally untouched. Implement later:

1. Keep bridge + voice as today (`4100`, `9001`, `9002`).
2. After `match_ready`, also route **gameplay** opcodes from `socket.received_match_state`:
   - Extend `_on_received_match_state` (or a sibling) to `match` on `op_code` and `JSON.parse` the data string.
3. Dispatch outbound with:

```gdscript
# Example only — not applied
var payload := JSON.stringify({"enemy_id": id, "damage": dmg})
await socket.send_match_state_async(bridge.match_id, 10, payload) # OP_DAMAGE
```

4. Suggested client responsibilities:
   - On join: send `OP_SPAWN` with arena spawn position; wait for `OP_SPAWN_OK`.
   - On hit confirmed locally for FX only: still send `OP_DAMAGE` and **apply HP only from** `OP_ENEMY_HEALTH` / `OP_ENEMY_DEATH`.
   - On local death: `OP_DEATH`; on teammate interact: `OP_REVIVE`.
   - Drive HUD from `OP_WAVE_STATE` / `OP_REWARD` / `OP_MATCH_RESULT` instead of local-only wave director when online.
   - Optionally disable or slave `SpawnManager` authority while in an authoritative match (server spawns enemy ids in `wave_started.enemies`).
5. Collision map for opcodes already in use:

| Code | Owner |
| ---: | --- |
| 4100 | Voice signalling (`OnlineManager.VOICE_SIGNAL_OP_CODE`) |
| 9001–9002 | `NakamaMultiplayerBridge` |
| 1–99 (listed above) | Coop authoritative runtime |

## Deploy on Render

Service is defined in root `render.yaml`:

- `dockerfilePath: ./infra/nakama/Dockerfile`
- `dockerContext: .` (required so `COPY infra/nakama/modules` works)
- `autoDeploy: true`

Steps:

1. Commit `infra/nakama/modules/**`, `Dockerfile`, `start-nakama.sh`, this doc.
2. Push to the branch connected to the Render service `nakama-boomer-shooter`.
3. Render rebuilds the Docker image (modules copied to `/nakama/data/modules`).
4. `start-nakama.sh` runs migrations then Nakama with `--runtime.path /nakama/data/modules`.
5. Confirm env vars still set: `DATABASE_URL`, `NAKAMA_SERVER_KEY`, `NAKAMA_CONSOLE_USERNAME`, `NAKAMA_CONSOLE_PASSWORD`.
6. In Render logs look for `coopwave match_init` / `matchmaker_matched coop_waves` after a client queues.
7. Smoke test: two clients `queue_coop_waves` → same match id → `OP_MATCH_STATE` arrives.

Local image build (optional):

```bash
docker build -f infra/nakama/Dockerfile -t boomer-nakama .
```

## Ops constants (tune in Lua)

Defined at top of `match_coop.lua`: tick rate 10 Hz, max players 20 (matchmaker ceiling; design target still 1–4), map bounds, rate limits, revive rules, reward table.
