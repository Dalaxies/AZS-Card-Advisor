---
name: azeroth-survivors-addon
description: Build WoW 1.12.1 addons for Azeroth Survivors (benilla). Use when creating, debugging, or extending AZS addons, checking whether a 1.12 API name exists in this client before calling it (globals, functions, widget methods, events, CVars, TOC directives, Lua 5.0 limits, library support), reading run state (clock, phase, bosses, guardians, hero, spells, buffs, meter, debuffs, healing, boss damage, lairs, caches), predicting level-up cards (deck weights, power model, rank scaling), hiding the stock HUD, or handling AZS CHAT_MSG_ADDON messages.
---

# Azeroth Survivors Addon

Build World of Warcraft 1.12.1 addons for Azeroth Survivors (benilla / browser build).

Azeroth Survivors addons are stock 1.12 addons (`## Interface: 11200`, Lua + XML, stock frame API). The game exposes run state via `AZS_*` globals, filled before addons load and kept current. Data covers the current run only — out of a run tables are empty or stale.

## Workflow

1. **Gate on phase first.** `AZS_GetPhase()` returns `ready | playing | choosing | paused | dead | victory`, or nil. Return early unless the phase fits. Never trust tables without this check.
2. **Read state via functions, not raw tables where a helper exists:**
   - smooth clock: `AZS_GetRunTime()` (not `AZS_RUN.t`)
   - bosses alive: `AZS_GetBosses()`; bosses to come: `AZS_GetUpcomingBosses()`
   - guardians alive: `AZS_GetGuardians()`; meter: `AZS_GetMeter()`; healing: `AZS_GetHealing()`; boss damage: `AZS_GetBossMeter()`
   - debuffs on a boss/guardian: `AZS_GetDebuffs(id)`; lairs: `AZS_GetLairs()`
   - enemy kind: `AZS_UnitKind("target")`
3. **React to changes via `CHAT_MSG_ADDON`** (tables are already updated when your handler runs) or poll in `OnUpdate`. Throttle `OnUpdate` with an elapsed accumulator; updates arrive max 5x/sec and only on change.
4. **Hide HUD only for parts you replace**, only while enabled. Restore on disable.
5. **Install/test:** Windows/Linux: `benilla-config/AddOns/<AddonName>/` next to exe, loads on next world entry. Browser: Options → AddOns → install `.zip`. `.toc` must have `## Interface: 11200`.

## Hard rules (1.12 + AZS quirks)

- Lua 1.12 only: `this, event, arg1...`, `table.getn`, `math.mod`, `string.find`. No `string.gmatch`, no GUID APIs.
- No `_G` table: look up and set globals with `getglobal`/`setglobal`, as in the original game.
- Spawn `id` is unique within a run but cannot be mapped from a unit token. Match enemies by `name` (+ target). Boss names are unique per zone.
- `names` are localized (same as `UnitName`); `zone / class / phase / kind` keys are NOT localized — use keys for logic.
- Guardians: only `target` reports `guardian` via `AZS_UnitKind` / `AZS_TARGET.kind`; other units read as `elite`. Use `AZS_GetGuardians()` for the full list by id+name.
- Bosses: several can be alive at once, ordered by spawn. `AZS_GetUpcomingBosses()` is empty in endless mode — use `AZS_RUN.nb` / `AZS_RUN.nbn` instead.
- Meter numbers cover the whole run; the in-game Reset button affects only the stock window.
- Read-only API: nothing changes the run except HUD visibility.
- Raw numbers arrive as Lua numbers, flags as `0`/`1`. Each table has a `*_UPDATED` global with `GetTime()` of last change.

## Field gotchas

- Count guardian kills with `AZS_RUN.gk`: the "is slain! Its lair yields treasure" line is engine text, never an addon message.
- `AZS_SetHudShown` writes the game's saved settings: an addon that hides a part and is then removed leaves it hidden until the player re-ticks it in Options. Restore what you hid.
- Probe a custom font on a hidden FontString before use — a failed load renders blank text. Fall back to `Fonts\\FRIZQT__.TTF`.
- A saved frame position is in that frame's own scale units: after a scale change, convert saved coordinates or clamp to screen or the frame lands off-screen.
- `GameTooltip_SetDefaultAnchor` parks the tooltip bottom-right — mind it when drawing something in that corner.
- `AZS_ZONE` is sent once per run: after a mid-run `/reload` it can be empty. Fall back to `GetRealZoneText()` plus `AZS_RUN.fin` for the zone facts.
- The phase string reports `playing` while the level-up picker is up — detect cards with `AZS_RUN.owed > 0`. Bar slots 1–6 mirror `AZS_SPELLS` order (racial last = slot 12); `GetActionCooldown` is not wired, never map by cooldown. Full source-verified model: `references/card-system.md`.
- Level-ups can be stored and taken later: the count is `AZS_RUN.sl` / `AZS_GetStoredLevels()`, `AZS_OpenStoredLevels()` takes them, and `AZS_IsStoringLevels()` / `AZS_SetStoringLevels(store)` read and set the storing toggle. Hide the stock "Level Up!" button with `AZS_SetHudShown("levels", false)` and draw your own.

## Using `references/client-api.md`

It is a lookup, not something to read end to end. To answer "can I call X":

1. Grep the file for `X`. Found under **API globals**, **Functions**, **Events**
   or **CVars** → it exists.
2. Found under the **missing** list in Globals → it is `nil`. Do not call it.
3. Not found at all → treat it as absent and feature-detect
   (`if (X) then ... end`) rather than assuming either way.

**A listed name does not promise a working feature.** This is a partial 1.12
implementation; a name can exist and still be a stub. The `debug*` family is the
standing example: `debuginfo` and friends exist and do nothing.

When the client is updated, its addon surface changes and this reference goes
stale. Re-derive it before trusting it: the client ships `scripts/api-coverage.sh`,
which asks its own VM what it exposes and diffs that against
`reference/lua_globals.tsv`; `cargo run -p benilla-ui --example dump_globals`
prints the live globals and `--example dump_widget_methods` the per-template
widget methods. Both are in the client's repo, not here.

## API quick map

Full field lists: see `references/api.md` (mirrors `addon_docs.md`).
The **client's whole addon surface** — every global, function, widget method,
event, CVar and TOC directive, plus the 1.12 limits and the library situation —
is `references/client-api.md`. Check a name there before using it: it is the
client's own captured reference, and a name being present does not promise the
feature is built.

**Functions:** `AZS_GetRunTime()`, `AZS_GetPhase()`, `AZS_GetRunLength()`, `AZS_GetBosses()`, `AZS_GetUpcomingBosses()`, `AZS_GetGuardians()`, `AZS_GetDebuffs(id)`, `AZS_GetMeter()`, `AZS_GetHealing()`, `AZS_GetBossMeter()`, `AZS_GetLairs()`, `AZS_UnitKind(unit)`, `AZS_GetStoredLevels()`, `AZS_OpenStoredLevels()`, `AZS_IsStoringLevels()`, `AZS_SetStoringLevels(store)`, `AZS_SetHudShown(part, shown)` / `AZS_IsHudShown(part)`.

**Tables:** `AZS_ZONE` (fixed facts, once per run), `AZS_RUN` (live run), `AZS_SCHEDULE` (`{index,at,name,final,state}`), `AZS_UNITS` (`{kind,id,name,hp,hpm,state}`, max 40), `AZS_DEBUFFS` (`{id,spell,stacks,duration,ends,permanent,dispel,icon,name}`), `AZS_TARGET`, `AZS_SPELLS` (`{key,spell,rank,cd,cdmax}`), `AZS_BUFFS` (`{spell,left}`), `AZS_METER`, `AZS_HEALING`, `AZS_BOSSMETER`, `AZS_CHESTS` (`{id,x,y,z,mx,my}`), `AZS_LAIRS` (`{index,state,name,id,left,x,y,z,mx,my}`), `AZS_TAKEN` (`{source,dmg}`), `AZS_STATS`.

**HUD parts:** `clock, bosses, tally, build, levels, banners, loot, meter`, plus `all`/nil. CVar equivalents: `hudClock` etc. (`"1"` shown / `"0"` hidden). Same as Options → Interface checkboxes; saved. `levels` is the stock "Level Up!" button.

**Addon prefixes (`arg1`) → table:** `AZSZONE→AZS_ZONE`, `AZSRUN→AZS_RUN`, `AZSBOSSES→AZS_SCHEDULE`, `AZSUNITS→AZS_UNITS`, `AZSDEBUFFS→AZS_DEBUFFS`, `AZSTGT→AZS_TARGET`, `AZSSPELLS→AZS_SPELLS`, `AZSBUFFS→AZS_BUFFS`, `AZSMETER→AZS_METER`, `AZSHEAL→AZS_HEALING`, `AZSBOSSDMG→AZS_BOSSMETER`, `AZSCHESTS→AZS_CHESTS`, `AZSLAIRS→AZS_LAIRS`, `AZSTAKEN→AZS_TAKEN`, `AZS→AZS_STATS`. `key=value;` format for ZONE/RUN/TGT/STATS, `a,b,c;` entries for lists. Names never contain `;,=`.

**Keys:** zones `elwynn, duskwood, wsg, ab, feralas, arena, av, brm, aq`; classes `warrior, paladin, hunter, rogue, priest, shaman, mage, warlock, druid`; phases `ready, playing, choosing, paused, dead, victory`; kinds `final, boss, guardian, elite, normal`.

**Card system:** the game's choice cards (spell/ring/trinket/amulet kinds, `why` texts, rarity-rolled upgrades, class ability pools) are documented in `references/card-system.md`, reverse-engineered from the client. The addon channel never carries the offered cards — predict the deck client-side.

## Minimal patterns

```lua
-- .toc:
-- ## Interface: 11200
-- ## Title: My AZS Addon
-- MyAddon.lua
```

```lua
-- smooth gated poll
local f = CreateFrame("Frame");
local elapsed = 0;
f:SetScript("OnUpdate", function()
  elapsed = elapsed + arg1;
  if ( elapsed < 0.25 ) then return; end
  elapsed = 0;
  if ( AZS_GetPhase() ~= "playing" ) then return; end
  local t = AZS_GetRunTime();
end);
```

```lua
-- react to change
local f = CreateFrame("Frame");
f:RegisterEvent("CHAT_MSG_ADDON");
f:SetScript("OnEvent", function()
  if ( arg1 == "AZSUNITS" ) then
    -- AZS_UNITS already updated
  end
end);
```

```lua
AZS_SetHudShown("meter", false); -- hide one; "all"/nil for all
AZS_SetHudShown("clock", true);  -- restore
```

## Minimap button (menu entry)

Parent a `Button` to `Minimap`, park it by angle, drag to move, persist the
angle in `SavedVariables`, tooltip + click menu included:

```lua
local btn = CreateFrame("Button", "MyAddonMinimapButton", Minimap);
btn:SetWidth(31); btn:SetHeight(31);
local icon = btn:CreateTexture(nil, "BACKGROUND");
icon:SetWidth(20); icon:SetHeight(20);
icon:SetPoint("CENTER", btn, "CENTER", 0, 0);
icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark");
local border = btn:CreateTexture(nil, "OVERLAY");
border:SetWidth(53); border:SetHeight(53);
border:SetPoint("CENTER", btn, "CENTER", 0, 0);
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder");
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight");

local function place()
  local a = MyDB.mmAngle or (math.pi * 1.1);
  btn:ClearAllPoints();
  btn:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a));
end
place();

btn:RegisterForDrag("LeftButton");
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp");
btn:SetScript("OnDragStart", function()
  this:SetScript("OnUpdate", function() -- runs while held
    local mx, my = Minimap:GetCenter();
    local px, py = GetCursorPosition();
    local s = UIParent:GetScale();
    MyDB.mmAngle = math.atan2(py / s - my, px / s - mx);
    place();
  end);
end);
btn:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil); end);
btn:SetScript("OnClick", function()
  if ( arg1 == "RightButton" ) then ToggleMyMenu(); else ToggleMyAddon(); end
end);
btn:SetScript("OnEnter", function()
  GameTooltip:SetOwner(this, "ANCHOR_LEFT");
  GameTooltip:SetText("My Addon");
  GameTooltip:AddLine("Left-click: on/off", 1, 1, 1);
  GameTooltip:AddLine("Right-click: menu", 1, 1, 1);
  GameTooltip:Show();
end);
btn:SetScript("OnLeave", function() GameTooltip:Hide(); end);
```

Notes: a drag ending on the button also fires `OnClick`, so guard it with a
`dragged` flag (set in the `OnUpdate`, consumed in `OnClick`). Keep the button
at `MEDIUM` strata like the stock minimap buttons; popups/menus go `DIALOG`.
Radius 80 assumes the stock round minimap; if a square minimap is in play,
clamp the position to ride outside its border instead.
