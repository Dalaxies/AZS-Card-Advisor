# AZS Card Advisor

A World of Warcraft 1.12.1 addon for **Azeroth Survivors** (benilla / browser build).

This addon predicts level-up card value from **visible run data** and surfaces passive, gear, and damage-taken advice to help you make better choices during the level-up picker.

## ⚠️ Important limitation

The Azeroth Survivors addon API is **read-only**. The actual three cards offered in the level-up picker **never leave the native UI** — there is no card/offer prefix on `CHAT_MSG_ADDON`, so no legitimate addon can read the dealt cards or put a DPS number under each specific one.

This advisor **predicts** which owned spells could rank up and which new spells could be offered, ranks them by estimated DPS gain / power, and highlights the best candidate in each category. You still match the prediction to what you see in the native picker yourself.

## Features

| Section | What it shows |
|---------|---------------|
| **Card Advisor** | Predicts rank-up DPS gain for owned spells below rank 8 (+30% dmg / −7% cooldown per rank ≈ +39.8% on that spell's meter share), and ranks unowned class-pool spells by the game's own `power()` metric. Highlights the best pick in each category. |
| **Passive Advisor** | Lists all 10 passives (`might`, `fortitude`, `pack`, `renew`, `intellect`, `amplify`, `detect`, `wisdom`, `wild`, `kings`) and flags uninvested stats as **RECOMMENDED**. |
| **Gear / Jewelry Value** | Shows your worn-gear stat totals (`g*` keys) and flags uninvested stats. Reminds that damage and haste are always 1.0 leverage on every spell. |
| **Damage Taken** | Breaks down `AZS_TAKEN` by source (`boss melee`, `boss spell`, `elite`, `mob melee`, `mob spell`, `area`) with percentages of total. |
| **Look For checklist** | Manual checkboxes for your class-pool spells. Tick spells as they appear in the picker; persists across runs (optional reset at run start). |
| **Sound alert** | Plays a UI sound when the level-up picker opens (`owed` transitions 0 → >0). |
| **Auto show/hide** | Panel shows during the `playing` phase and hides when the run ends (`ready` / `dead` / `victory`). |
| **Window position** | Remembers frame position across sessions via `SavedVariables`. |

## Install

### Benilla (Windows / Linux)

Copy the `AZSCardAdvisor/` folder into `benilla-config/AddOns/` next to the game executable. The addon loads on the next world entry.

### Browser

Zip the `AZSCardAdvisor/` folder and install via **Options → AddOns → install a `.zip`**.

## Usage

1. Start a run — the advisor panel appears automatically.
2. When the level-up picker is active, the **Card Advisor** section populates with predicted rank-up and new-spell candidates.
3. Use the **Look For** checklist to tick spells as they appear in the native picker.
4. Use the **Passive Advisor** and **Gear Value** sections to inform your build choices between levels.
5. The panel hides when the run ends and remembers its position.

### Panel header buttons

- **Class: `<class>` [LOCKED]** — toggles whether the advisor is locked to your current class (stored in SavedVariables).
- **Reset list at run start: ON/OFF** — toggles whether the Look For checklist is wiped when a new run begins.

## Files

| File | Purpose |
|------|---------|
| `AZSCardAdvisor/AZSCardAdvisor.toc` | Addon manifest (`## Interface: 11200`, `## SavedVariables: AZSCardAdvisorDB`) |
| `AZSCardAdvisor/AZSCardAdvisor.lua` | Addon logic (Lua 5.0 / WoW 1.12 compatible) |

## Included agent skill

The `.agents/skills/azeroth-survivors-addon/` folder contains the [azeroth-survivors-addon](https://github.com/HejAsh/azeroth-survivors-addon-skill) agent skill, which teaches coding agents how to build WoW 1.12.1 addons for Azeroth Survivors — reading `AZS_*` run state, hiding the stock HUD, handling `CHAT_MSG_ADDON` messages, and respecting 1.12 Lua constraints.

## API reference

The addon reads only these documented `AZS_*` functions and tables:

- `AZS_GetPhase()`, `AZS_GetRunTime()`
- `AZS_GetBosses()`, `AZS_GetUpcomingBosses()`
- `AZS_GetGuardians()`
- `AZS_GetMeter()`, `AZS_GetHealing()`, `AZS_GetBossMeter()`
- `AZS_GetDebuffs(id)`, `AZS_GetLairs()`
- `AZS_UnitKind(unit)`
- `AZS_GetStoredLevels()`
- `AZS_RUN`, `AZS_ZONE`, `AZS_SPELLS`, `AZS_STATS`, `AZS_TAKEN`, `AZS_BUFFS`

Nothing an addon calls changes the run — the API is read-only except for HUD visibility and level-up storing/taking.

## License

MIT