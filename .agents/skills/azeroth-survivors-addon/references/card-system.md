# Azeroth Survivors: the card system

How the game builds and shows choice cards, verified against the game's own
implementation and cross-checked against the shipped `AzerothSurvivors.exe`.

## Target and method

- Source of truth: the game's dealing code (`choices_for`, `describe_card`,
  `cast_at`), its rarity rules (`rarity`, `power`, `spell_tier`), its ability
  and passive tables (`AbilityDef`, `PASSIVES`, caps), and its rank-scaling
  (`Owned`).
- Cross-checked against the shipped client PE x86_64, SHA-256
  `67f1b30f61304128a274507446493d8f9340c51b737718bcc2903f7bc58ebddf`
  (an earlier build; see "Version drift" for where the live game differs).
- The client embeds its UI strings in plaintext, so a static string scan of the
  exe recovers the same card fields and texts the implementation shows.

## The card model

Every offer is one of five `Choice` kinds:

| kind | pool weight | card footer ("why") |
|---|---|---|
| `Upgrade(i)` (rank up an owned ability) | **1.2** | `Improves a spell you know` |
| `NewAbility(def)` (a spell from the class pool you lack) | **1.0** | `New spell` · `Takes a spell slot · {n}/6` |
| `UpPassive(i)` (rank up an owned passive) | **0.8** | `Empowers ...` |
| `NewPassive(p)` (a passive you lack) | **0.5** | `New talent` · `Takes a passive slot · {n}/6` |
| `Heal` (only when the pool is empty) | — | full restore |

The picker deals **three** cards by weighted sampling **without replacement**
(`pool.swap_remove`). So a rank-up is always slightly more likely than a new
spell, and a new spell more likely than a passive. Rings/trinkets/amulets are a
separate jewelry screen (guardian lair / battleground cache), not this deck.

### Caps

- `MAX_ABILITY_LEVEL = 8`, `MAX_ABILITIES = 6`
- `MAX_PASSIVE_LEVEL = 5`, `MAX_PASSIVES = 6`

A spell stops being offered for rank-ups at rank 8; the deck runs out of new
spells when you own all of the class pool (`Nothing left to learn`).

## Rarity is derived, not rolled

The game computes each card's rarity from what the pick *does* —
there is no random rarity roll. (An earlier note in this file inferred a
`[0.92, 0.05, 0.02, 0.02]` float table from the binary; that was wrong — those
floats are unrelated.) WoW item-quality colours:

| card | rarity |
|---|---|
| Rank-up to `MAX_ABILITY_LEVEL` (rank 8) | **Legendary** |
| Rank-up that adds a target (reaching rank 3, 5, or 7 on a multi-target kind) | **Epic** |
| Other rank-ups | **Uncommon** |
| New ability, strongest third of the class by `power()` | **Epic** |
| New ability, weakest third | **Uncommon** |
| New ability, middle third, or a defensive (no `power()`) | **Rare** |
| New passive | Uncommon |
| Passive to rank 5 / rank 4 / rank 2 / other | Epic / Rare / Common / Uncommon |
| Heal | Common |

`power()` (the game's own "how strong is this spell" metric) =
`per-cast damage × ticks × reach / cooldown`, where reach is derived from
`count` and `radius` by the spell's `Kind`. Defensive kinds have no `power()`
and sit at Rare.

## Rank scaling (the exact math)

Each rank of an ability changes it by a fixed formula — this is what a rank-up
card is actually worth:

| stat | per rank |
|---|---|
| damage / dot | `× (1 + 0.3·(rank-1))` → **+30% per rank** |
| cooldown | `base × 0.93^(rank-1)` → **−7% per rank** |
| targets (`count`) | **+1 at ranks 3, 5, 7** (the Epic milestones) |
| area (`radius`) | `× (1 + 0.08·(rank-1))` → **+8% per rank** |
| duration | `× (1 + 0.1·(rank-1))` → **+10% per rank** |

`describe_card` diffs `cast_at(rank)` vs `cast_at(rank+1)` and prints only the
lines that change: `Damage a » b`, `Cooldown a » b`, `Targets a » b`,
`Area a » b`, `Lasts a » b`. That is the text on the card.

## Passives

Ten fixed passives, each boosting one stat per level: `might` (+10% damage),
`fortitude` (+20% max hp), `pack` (+10% speed), `renew` (+regen),
`intellect` (+8% haste), `amplify` (+10% area), `detect` (magnet),
`wisdom` (+xp/growth), `wild` (armor), `kings` (crit). These are the "Your
bonuses" a build leans on; the `AZS_STATS` keys (`dmg`, `cd`, `area`, `crit`,
`reg`, `spd`, `xp`, `arm`, …) are these stats after passives and gear.

## Class ability pools (the new-spell deck)

The `run.class.pool` a new-spell card draws from, per class (keys match
`AZS_SPELLS.key`):

- **warrior**: cleave, whirlwind, thunder_clap, mortal_strike, execute, demo_shout, battle_shout, bloodthirst, rend, shield_slam, bloodrage
- **paladin**: consecration, exorcism, hammer_of_wrath, holy_shock, holy_wrath, judgement, hammer_of_justice, holy_light, divine_shield, holy_shield, redemption
- **hunter**: auto_shot, arcane_shot, multi_shot, serpent_sting, volley, explosive_trap, concussive_shot, aimed_shot, immolation_trap, frost_trap, hunters_mark
- **rogue**: sinister_strike, eviscerate, blade_flurry, rupture, kidney_shot, gouge, ghostly_strike, adrenaline_rush, backstab, slice_and_dice, seal_fate
- **priest**: smite, sw_pain, mind_blast, holy_nova, pw_shield, renew, holy_fire, mind_flay, psychic_scream, devouring_plague
- **shaman**: lightning_bolt, chain_lightning, earth_shock, flame_shock, frost_shock, lightning_shield, magma_totem, searing_totem, fire_nova, healing_wave, call_of_flame
- **mage**: fireball, frostbolt, arcane_missiles, frost_nova, arcane_explosion, blizzard, flamestrike, fire_blast, cone_of_cold, blast_wave, pyroblast, ice_barrier, polymorph
- **warlock**: shadow_bolt, corruption, immolate, curse_of_agony, rain_of_fire, hellfire, death_coil, searing_pain, drain_life, fear, soul_fire
- **druid**: wrath, moonfire, starfire, hurricane, insect_swarm, entangling_roots, rejuvenation, regrowth, thorns, swipe, faerie_fire

The racial is not in these pools; the last `AZS_SPELLS` entry stays the racial
and is excluded from predictions.

## What reaches addons

The addon channel carries only the ten documented prefixes — a full prefix scan
of the exe found no card/offer prefix. The offered cards never leave the native
UI, so an addon can predict the deck but never see the hand. The same holds for
engine announcements: the guardian toast ("is slain! Its lair yields treasure")
is native text, not an addon message — count guardian kills from `AZS_RUN.gk`.

## The game's own power() metric

The game ranks a class's spells against each other with one formula, used to
tier NEW-spell rarities and (in this fork) to sort suggestions:

```
reach(Bolt|Strike) = count + radius*0.4     reach(Melee|Orbit|Dot) = count
reach(Nova|Cone|Ground|GroundSelf|Aura) = 1 + radius*0.6
reach(Chain) = count + 1                    defensive kinds = unranked (Rare)
per  = damage > 0 ? damage : dot * max(duration, 1)
ticks = Ground/GroundSelf with duration ? duration : 1
power = per * ticks * reach / max(cooldown, 0.2)
```

Computed from the shipped ability table (rank-1 stats), strongest first:

| class | power ranking |
|---|---|
| paladin | consecration 32.4 · holy_wrath 21.3 · judgement 13.0 · hammer_of_wrath 10.7 · holy_shock 9.6 · exorcism 7.2 · hammer_of_justice 2.7 |
| mage | flamestrike 28 · blizzard 24.3 · cone_of_cold 23.6 · fireball 20 · arcane_explosion 18.6 · blast_wave 16.1 · pyroblast 11.7 · arcane_missiles 9.5 · frostbolt 9.2 · fire_blast 7.4 · frost_nova 7.3 |
| warlock | curse_of_agony 67.2 · corruption 40 · hellfire 31.2 · rain_of_fire 27.7 · shadow_bolt 10.7 · immolate/searing_pain 10 · death_coil 5.2 |
| priest | sw_pain 36 · holy_nova 22 · smite 11.7 · mind_blast 9.1 · holy_fire 6.3 |
| warrior | execute 40 · cleave 38.2 · sweeping_strikes 43 · whirlwind 20.8 · heroic_strike 17.5 · mortal_strike 16 · thunder_clap 11.6 |
| druid | insect_swarm 40 · hurricane 28.4 · wrath 10.8 · moonfire/starfire 10 |
| hunter | volley 23.1 · multi_shot 15 · arcane_shot 13 · aimed_shot 12 · explosive_trap 11 |
| rogue | rupture 25.7 · sinister_strike 17.6 · blade_flurry 16.9 · eviscerate 15 |
| shaman | chain_lightning 24 · lightning_shield 13.3 · lightning_bolt 11.5 · earth_shock 8.8 |

Defensive/utility kinds (divine_shield, pw_shield, totems, thorns, heals) have
no `power()` — the game treats them as Rare new-spell cards and pure utility.

## Per-stat leverage: which stat helps *your* build

The same `reach` terms say how sensitive each spell is to each stat. Divide the
term's radius/count part by the whole, and you get the fraction of that spell's
damage a stat drives:

| stat | leverage on a spell |
|---|---|
| `dmg`, haste (`cd`) | 1.0 — every spell, unconditionally |
| `area` | Nova/Cone/Ground/GroundSelf/Aura: `r·0.6/(1+r·0.6)` · Bolt/Strike: `r·0.4/(count+r·0.4)` · else 0 |
| `cnt` | Bolt/Strike: `count/(count+r·0.4)` · Chain: `count/(count+1)` · Melee/Orbit/Dot: 1.0 · else 0 |
| `doth`, `dots` | Dot kinds, and Ground/GroundSelf with a duration |
| `crit` | your crit's share of damage: `c(cm−1) / (1 + c(cm−1))` |
| `echo` | `echo / (1 + echo)` |

Weight by each spell's share of the run's damage (`AZS_GetMeter`) and you get
the share of *your* damage a stat drives. Two consequences an addon should honour:

- **Damage and haste always score 1.0**, so they can never be "the best stat" by
  leverage — they are the baseline, not the answer. Rank by `amount × leverage`.
- The value of a piece of gear for a given build is
  `gearBonus(stat) × leverage(stat)`. This is what makes a crit ring and an area
  amulet comparable, and it is specific to the spells actually owned.

**What is not available:** there is no jewelry inventory in the addon API. `g*`
stats are per-stat totals for the whole worn set, so an addon can price gear but
can never attribute a bonus to the individual amulet, ring or trinket. Say so
rather than inventing a per-piece breakdown; the meter's `proc` lines, which
carry a talent's or the amulet's own name, are the only per-piece trace.

**Card-value comparison an addon can make**: a rank-up card is worth
`power(spell) × 0.3` (the +30% damage step); a new-spell card is worth
`power(spell)` (a whole new source). Early (few spells, open slots) new spells
usually win; late, the carry's rank-ups do.

## Prediction model an addon can support

- **Rank-up candidates**: owned, non-racial spells below rank 8 — each will be
  offered again at weight 1.2. Value the next rank by the scaling table above
  (+30% dmg, −7% cd, and note the +1-target Epic milestones at 3/5/7).
- **New-spell candidates**: `CLASS_POOLS[class]` minus owned, at weight 1.0,
  offered while you hold fewer than 6 spells. Rank them by the game's own
  `power()` tiers (Epic/Rare/Uncommon) if you want to match the game's taste.
- **Rarity of a shown card**: derivable from the card's rank/kind alone — a
  rank-8 or 3/5/7-target card is Legendary/Epic and worth taking over a plain
  Uncommon rank-up.
- **Cap**: pool minus owned empty → `Nothing left to learn`.

## Version drift

The live `AzerothSurvivors.exe` (Aethus's build) rolls **per-card upgrade
magnitudes** ("+19% duration", "+6% damage", "+43% damage / −20% cooldown") and
shows ranks above 8 (e.g. "Rank 10 » 11"), so its `MAX_ABILITY_LEVEL` and the
"rarity decides how strong it is" wording mean the magnitudes vary per card
there, unlike the baseline's fixed per-rank formulas. The **structure**
(deck, weights, derived rarity tiers, target milestones, footer texts) is the
same; treat the exact constants here as the open-source baseline and the live
game as a tuned variant.

## What the source teaches addon developers

Lessons from reading the game's Rust source that only make sense from the
inside — each one changes how an addon should be written:

- **The addon API is a mirror, not the engine.** `AZS_*` tables are built by a
  server→client whisper feed consumed by a built-in Lua parser that registers
  before any addon. Addons read a snapshot; the game's truth lives in Bevy ECS.
  That is why offers, magnitudes, and RNG never reach you.
- **`AZS_GetPhase()` lies during the picker.** The game's own state machine
  uses `Phase::LevelUp` while the addon layer still reports `playing`. Gate
  "cards are on screen" on `AZS_RUN.owed > 0`, not the phase string.
- **Ranks are pure formulas, not tables.** Every rank applies `+30% dmg,
  −7% cd, +8% area, +10% duration, +1 target at 3/5/7` — so an addon can
  compute a card's exact value from the current meter without seeing it.
- **`AZS_SPELLS` order is acquisition order with the racial last**, and the
  bar's action slots 1–6 mirror that order (slot 12 = racial). That is the
  only reliable spell→slot mapping: the client's `GetActionCooldown` is not
  wired to the game's real cooldowns (always 0.0), so never map by cooldown.
- **Passives are a fixed global set of 10**, shared by
  all classes; they surface in addons only as meter `proc` lines and
  `AZS_STATS` keys — there is no passive list in the addon API.
- **The deck weights are public knowledge**: 1.2 rank-up / 1.0 new spell /
  0.8 passive rank / 0.5 new passive, three cards, no replacement. Advice can
  state real odds instead of guessing.
- **The engine is a Lua 5.0-era 1.12 emulation** over Rust:
  stock 1.12 idioms work, but anything the emulator didn't implement is nil —
  feature-detect globals (`if (GetActionCooldown)`) rather than assume.

## Unknowns

- The live game's per-card magnitude roll ranges and how rarity gates them.
- Exact `power()` weights if the live game retuned `damage`/`cooldown`/`count`.
- Whether jewelry offers are drawn from zone-specific tables
  (`armory.zone_drops` string suggests so).
