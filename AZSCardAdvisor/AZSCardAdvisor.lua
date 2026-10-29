-- AZSCardAdvisor.lua
-- Card-value advisor for Azeroth Survivors (WoW 1.12.1 addon)
--
-- LIMITATION: The addon API cannot see the actual cards being offered.
-- The offered cards never leave the native UI; there is no card/offer
-- prefix on CHAT_MSG_ADDON. This panel predicts which owned spells could
-- rank up and which new spells could be offered, plus passive/gear/damage
-- advice -- all from visible AZS_* data.

local panel = nil
local elapsed = 0
local UPDATE_INTERVAL = 0.25
local lineFrames = {}
local db = nil
local lastOwed = 0
local lastPhase = nil

-- Class ability pools (keys match AZS_SPELLS.key). Racial is excluded.
local CLASS_POOLS = {
	warrior = {"cleave", "whirlwind", "thunder_clap", "mortal_strike", "execute",
		   "demo_shout", "battle_shout", "bloodthirst", "rend", "shield_slam", "bloodrage"},
	paladin = {"consecration", "exorcism", "hammer_of_wrath", "holy_shock",
		   "holy_wrath", "judgement", "hammer_of_justice", "holy_light",
		   "divine_shield", "holy_shield", "redemption"},
	hunter = {"auto_shot", "arcane_shot", "multi_shot", "serpent_sting",
		  "volley", "explosive_trap", "concussive_shot", "aimed_shot",
		  "immolation_trap", "frost_trap", "hunters_mark"},
	rogue = {"sinister_strike", "eviscerate", "blade_flurry", "rupture",
		 "kidney_shot", "gouge", "ghostly_strike", "adrenaline_rush",
		 "backstab", "slice_and_dice", "seal_fate"},
	priest = {"smite", "sw_pain", "mind_blast", "holy_nova", "pw_shield",
		  "renew", "holy_fire", "mind_flay", "psychic_scream", "devouring_plague"},
	shaman = {"lightning_bolt", "chain_lightning", "earth_shock",
		  "flame_shock", "frost_shock", "lightning_shield", "magma_totem",
		  "searing_totem", "fire_nova", "healing_wave", "call_of_flame"},
	mage = {"fireball", "frostbolt", "arcane_missiles", "frost_nova",
		"arcane_explosion", "blizzard", "flamestrike", "fire_blast",
		"cone_of_cold", "blast_wave", "pyroblast", "ice_barrier", "polymorph"},
	warlock = {"shadow_bolt", "corruption", "immolate", "curse_of_agony",
		   "rain_of_fire", "hellfire", "death_coil", "searing_pain",
		   "drain_life", "fear", "soul_fire"},
	druid = {"wrath", "moonfire", "starfire", "hurricane", "insect_swarm",
		 "entangling_roots", "rejuvenation", "regrowth", "thorns",
		 "swipe", "faerie_fire"},
}

local CLASS_POWER = {
	warrior = {cleave=38.2, whirlwind=20.8, thunder_clap=11.6, mortal_strike=16.0, execute=40.0},
	paladin = {consecration=32.4, holy_wrath=21.3, judgement=13.0, hammer_of_wrath=10.7,
		   holy_shock=9.6, exorcism=7.2, hammer_of_justice=2.7},
	hunter = {volley=23.1, multi_shot=15.0, arcane_shot=13.0, aimed_shot=12.0, explosive_trap=11.0},
	rogue = {rupture=25.7, sinister_strike=17.6, blade_flurry=16.9, eviscerate=15.0},
	priest = {sw_pain=36.0, holy_nova=22.0, smite=11.7, mind_blast=9.1, holy_fire=6.3},
	shaman = {chain_lightning=24.0, lightning_shield=13.3, lightning_bolt=11.5, earth_shock=8.8},
	mage = {flamestrike=28.0, blizzard=24.3, cone_of_cold=23.6, fireball=20.0,
		arcane_explosion=18.6, blast_wave=16.1, pyroblast=11.7, arcane_missiles=9.5,
		frostbolt=9.2, fire_blast=7.4, frost_nova=7.3},
	warlock = {curse_of_agony=67.2, corruption=40.0, hellfire=31.2, rain_of_fire=27.7,
		   shadow_bolt=10.7, immolate=10.0, searing_pain=10.0, death_coil=5.2},
	druid = {insect_swarm=40.0, hurricane=28.4, wrath=10.8, moonfire=10.0, starfire=10.0},
}

-- The 10 fixed passives: key -> stat they boost.
local PASSIVES = {
	{key = "might",   stat = "dmg", name = "Might",   desc = "+10% damage per level"},
	{key = "fortitude", stat = "hp",  name = "Fortitude", desc = "+20% max hp per level"},
	{key = "pack",    stat = "spd", name = "Pack",    desc = "+10% speed per level"},
	{key = "renew",   stat = "reg", name = "Renew",   desc = "+health regen per level"},
	{key = "intellect", stat = "cd",  name = "Intellect", desc = "+8% haste per level"},
	{key = "amplify", stat = "area", name = "Amplify", desc = "+10% area per level"},
	{key = "detect",  stat = "pick", name = "Detect",  desc = "pickup range / magnet"},
	{key = "wisdom",  stat = "xp",   name = "Wisdom",  desc = "+xp / growth per level"},
	{key = "wild",    stat = "arm",  name = "Wild",    desc = "armor / damage reduction per level"},
	{key = "kings",   stat = "crit", name = "Kings",   desc = "+crit per level"},
}

-----------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------
local function IsSpellOwned(key)
	local spells = AZS_SPELLS
	if not spells then return false, nil end
	for i = 1, table.getn(spells) do
		if spells[i].key == key then
			return true, spells[i].rank or 1
		end
	end
	return false, nil
end

local function GetSpellMeterShare(key)
	local lines = AZS_GetMeter()
	if not lines then return 0 end
	local lkey = string.lower(key)
	for i = 1, table.getn(lines) do
		local name = tostring(lines[i].name or "")
		if string.find(string.lower(name), lkey, 1, true) then
			return lines[i].share or 0
		end
	end
	return 0
end

local function PredictRankUpGain(key, rank)
	if not rank or rank >= 8 then return 0 end
	return GetSpellMeterShare(key) * 0.398
end

-----------------------------------------------------------------
-- Line recycling
-----------------------------------------------------------------
local function HideLines()
	for _, f in ipairs(lineFrames) do
		f:Hide()
	end
	lineFrames = {}
end

local function AddLine(parent, text, isBest, refY, color)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(300)
	f:SetHeight(16)
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, refY)

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	if isBest then
		bg:SetVertexColor(0.15, 0.55, 0.15, 0.85)
	elseif color then
		bg:SetVertexColor(color[1], color[2], color[3], 0.80)
	else
		bg:SetVertexColor(0.25, 0.25, 0.25, 0.80)
	end

	local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	txt:SetPoint("LEFT", f, "LEFT", 6, 0)
	txt:SetJustifyH("LEFT")
	txt:SetText(text)
	f:Show()
	table.insert(lineFrames, f)
	return refY - 18
end

local function AddHeader(parent, text, refY)
	return AddLine(parent, "|cffffff00" .. text .. "|r", false, refY)
end

-----------------------------------------------------------------
-- Panel sections
-----------------------------------------------------------------
local function RenderCardAdvisor(parent, y)
	local class = (AZS_ZONE and AZS_ZONE.class) or "warrior"
	local pool = CLASS_POOLS[class] or {}
	local power = CLASS_POWER[class] or {}

	y = AddHeader(parent, "Card Advisor (predictions only)", y)

	-- Rank-ups
	local rankups = {}
	local spells = AZS_SPELLS or {}
	local numSpells = table.getn(spells)
	for i = 1, numSpells do
		local s = spells[i]
		if s.key and s.rank and s.rank < 8 then
			if not (i == numSpells) then -- skip racial
				local gain = PredictRankUpGain(s.key, s.rank)
				table.insert(rankups, {key = s.key, rank = s.rank, gain = gain})
			end
		end
	end

	table.sort(rankups, function(a, b) return a.gain > b.gain end)

	local bestRankupKey = nil
	if table.getn(rankups) > 0 and rankups[1].gain > 0 then
		bestRankupKey = rankups[1].key
	end

	y = AddLine(parent, "  Rank-up (owned, below rank 8):", false, y)
	if table.getn(rankups) == 0 then
		y = AddLine(parent, "    none", false, y)
	else
		for i = 1, table.getn(rankups) do
			local r = rankups[i]
			local pct = string.format("%.0f%%", r.gain * 100)
			y = AddLine(parent, string.format("    %s (rank %d) ~ +%s DPS",
				r.key, r.rank, pct), (r.key == bestRankupKey), y)
		end
	end

	-- New spells
	local newspells = {}
	for i = 1, table.getn(pool) do
		local key = pool[i]
		local owned = IsSpellOwned(key)
		if not owned then
			local pw = power[key] or 0
			table.insert(newspells, {key = key, power = pw})
		end
	end

	table.sort(newspells, function(a, b) return a.power > b.power end)

	local bestNewKey = nil
	if table.getn(newspells) > 0 and newspells[1].power > 0 then
		bestNewKey = newspells[1].key
	end

	y = AddLine(parent, "  New spell (class pool):", false, y)
	if table.getn(newspells) == 0 then
		y = AddLine(parent, "    pool exhausted", false, y)
	else
		for i = 1, table.getn(newspells) do
			local n = newspells[i]
			y = AddLine(parent, string.format("    %s (power %.1f)",
				n.key, n.power), (n.key == bestNewKey), y)
		end
	end

	return y
end

local function RenderPassiveAdvisor(parent, y)
	local stats = AZS_STATS or {}
	y = AddHeader(parent, "Passive Advisor", y)

	local scored = {}
	for i = 1, table.getn(PASSIVES) do
		local p = PASSIVES[i]
		local val = stats[p.stat] or 0
		local score = 0
		if val <= 0 then score = 100 end -- uninvested: high priority
		table.insert(scored, {passive = p, val = val, score = score})
	end

	table.sort(scored, function(a, b) return a.score > b.score end)

	local anyRec = false
	for i = 1, table.getn(scored) do
		local s = scored[i]
		local p = s.passive
		local valStr = string.format("%.0f", s.val)
		local rec = s.score > 0
		if rec then anyRec = true end
		y = AddLine(parent, string.format("  %s: %s (current %s) %s",
			p.name, p.desc, valStr, rec and "|cff00ff00RECOMMENDED|r" or ""),
			rec, y)
	end

	if not anyRec then
		y = AddLine(parent, "  All passive stats invested.", false, y)
	end

	return y
end

local function RenderGearValue(parent, y)
	local stats = AZS_STATS or {}
	y = AddHeader(parent, "Gear / Jewelry Value", y)

	local gearStats = {
		{key = "gdmg", name = "Damage",   note = "baseline 1.0 leverage on every spell"},
		{key = "gcd",  name = "Haste (cd)", note = "baseline 1.0 leverage on every spell"},
		{key = "gcrit", name = "Crit",   note = "value scales with your crit dmg multiplier"},
		{key = "garea", name = "Area",   note = "helps AoE / cone / ground spells"},
		{key = "gcnt",  name = "Targets", note = "helps multi-target spells"},
		{key = "garm",  name = "Armor",  note = "damage reduction (60% max)"},
		{key = "greg",  name = "Regen",  note = "health per second"},
		{key = "gspd",  name = "Speed",  note = "movement speed"},
		{key = "ghp",   name = "Max HP", note = "survivability"},
	}

	table.sort(gearStats, function(a, b)
		local av = stats[a.key] or 0
		local bv = stats[b.key] or 0
		if (av > 0) ~= (bv > 0) then return av > 0 end
		return av > bv
	end)

	for i = 1, table.getn(gearStats) do
		local g = gearStats[i]
		local val = stats[g.key] or 0
		local invested = val > 0
		y = AddLine(parent, string.format("  %s: %.0f%% %s",
			g.name, val * 100, invested and "" or "|cffff7f00 (uninvested)|r"),
			false, y, invested and nil or {1, 0.5, 0})
	end

	y = AddLine(parent, "  Tip: damage + haste are always 1.0 leverage; rank by amount × leverage.", false, y)
	return y
end

local function RenderDamageTaken(parent, y)
	local taken = AZS_TAKEN or {}
	y = AddHeader(parent, "Damage Taken (by source)", y)

	if table.getn(taken) == 0 then
		y = AddLine(parent, "  none recorded", false, y)
		return y
	end

	table.sort(taken, function(a, b) return a.dmg > b.dmg end)

	local total = 0
	for i = 1, table.getn(taken) do
		total = total + (taken[i].dmg or 0)
	end

	for i = 1, table.getn(taken) do
		local t = taken[i]
		local pct = total > 0 and string.format("%.0f%%", 100 * t.dmg / total) or "0%"
		y = AddLine(parent, string.format("  %s: %d (%s)", t.source, t.dmg, pct), false, y)
	end

	return y
end

local function RenderLookFor(parent, y)
	local class = (AZS_ZONE and AZS_ZONE.class) or "warrior"
	local pool = CLASS_POOLS[class] or {}
	local lookFor = db.lookFor or {}

	y = AddHeader(parent, "Look For (manual checklist)", y)
	y = AddLine(parent, "Tick spells as they appear in the picker:", false, y)

	local anyChecked = false
	for i = 1, table.getn(pool) do
		local key = pool[i]
		local checked = lookFor[key] == true
		local mark = checked and "[x] " or "[ ] "
		if checked then anyChecked = true end

		local f = CreateFrame("Button", nil, parent)
		f:SetWidth(300)
		f:SetHeight(18)
		f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(f)
		bg:SetTexture("Interface\\Buttons\\WHITE8X8")
		bg:SetVertexColor(0.25, 0.25, 0.25, 0.80)

		local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		txt:SetPoint("LEFT", f, "LEFT", 6, 0)
		txt:SetJustifyH("LEFT")
		txt:SetText(mark .. key)
		f:Show()

		f:SetScript("OnClick", function()
			lookFor[key] = not lookFor[key]
			db.lookFor = lookFor
			RefreshContent()
		end)

		table.insert(lineFrames, f)
		y = y - 20
	end

	if not anyChecked then
		y = AddLine(parent, "  (none ticked yet)", false, y)
	end

	-- Manual reset button for the look-for checklist
	local resetBtn = CreateFrame("Button", nil, parent)
	resetBtn:SetWidth(120)
	resetBtn:SetHeight(18)
	resetBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	resetBtn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = true, tileSize = 8, edgeSize = 1,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	resetBtn:SetBackdropColor(0.4, 0.2, 0.2, 0.8)
	resetBtn:SetBackdropBorderColor(0.6, 0.4, 0.4, 1)

	local resetTxt = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	resetTxt:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
	resetTxt:SetText("Reset Checklist")

	resetBtn:SetScript("OnClick", function()
		db.lookFor = {}
		RefreshContent()
	end)
	table.insert(lineFrames, resetBtn)
	y = y - 22

	return y
end

-----------------------------------------------------------------
-- Main refresh
-----------------------------------------------------------------
local function RefreshContent()
	if not panel then return end
	local content = panel.content
	if not content then return end

	if not AZS_RUN or (AZS_RUN.owed or 0) <= 0 then
		content:Hide()
		return
	end
	content:Show()

	HideLines()

	local y = -10
	y = RenderCardAdvisor(content, y)
	y = AddLine(content, "", false, y) -- spacer
	y = RenderPassiveAdvisor(content, y)
	y = AddLine(content, "", false, y) -- spacer
	y = RenderGearValue(content, y)
	y = AddLine(content, "", false, y) -- spacer
	y = RenderDamageTaken(content, y)
	y = AddLine(content, "", false, y) -- spacer
	y = RenderLookFor(content, y)

	content:SetHeight(math.max(300, math.abs(y) + 20))
end

-----------------------------------------------------------------
-- Sound alert when cards become available
-----------------------------------------------------------------
local function CheckSoundAlert()
	if not AZS_RUN then return end
	local owed = AZS_RUN.owed or 0
	if owed > 0 and lastOwed <= 0 then
		if PlaySound then PlaySound("igMainMenuOptionCheckBoxOn") end
	end
	lastOwed = owed
end

-----------------------------------------------------------------
-- Run lifecycle: show during playing, optionally reset lookFor at run start
-----------------------------------------------------------------
local function UpdateVisibility()
	if not panel then return end
	local ph = AZS_GetPhase and AZS_GetPhase()

	-- Reset look-for checklist when a new run begins, if enabled
	if ph == "playing" and lastPhase ~= "playing" then
		if db.resetOnRunStart then
			db.lookFor = {}
		end
	end

	lastPhase = ph

	if ph == "playing" then
		panel:Show()
	else
		panel:Hide()
	end
end

-----------------------------------------------------------------
-- Position persistence
-----------------------------------------------------------------
local function SavePosition()
	if not panel or not db then return end
	local point, _, relativePoint, x, y = panel:GetPoint()
	db.point = point
	db.relativePoint = relativePoint
	db.x = x
	db.y = y
end

local function RestorePosition()
	if not panel or not db then return end
	panel:ClearAllPoints()
	if db.point and db.x ~= nil and db.y ~= nil then
		local sw = GetScreenWidth()
		local sh = GetScreenHeight()
		local x = db.x
		local y = db.y
		if x < 0 then x = 0 end
		if y > 0 then y = 0 end
		if x > sw then x = sw end
		if y < -sh then y = -sh end
		panel:SetPoint(db.point, UIParent, db.relativePoint or "CENTER", x, y)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

-----------------------------------------------------------------
-- Panel creation
-----------------------------------------------------------------
local function CreatePanel()
	if panel then return panel end

	panel = CreateFrame("Frame", "AZSCardAdvisorPanel", UIParent)
	panel:SetWidth(360)
	panel:SetHeight(560)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:SetScript("OnMouseDown", function() this:StartMoving() end)
	panel:SetScript("OnMouseUp", function()
		this:StopMovingOrSizing()
		SavePosition()
	end)
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 }
	})
	panel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", panel, "TOP", 0, -12)
	title:SetText("AZS Card Advisor")

	-- Class lock toggle button
	local lockBtn = CreateFrame("Button", nil, panel)
	lockBtn:SetWidth(120)
	lockBtn:SetHeight(20)
	lockBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -38)
	lockBtn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = true, tileSize = 8, edgeSize = 1,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	lockBtn:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
	lockBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

	local lockTxt = lockBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	lockTxt:SetPoint("CENTER", lockBtn, "CENTER", 0, 0)

	local function UpdateLockText()
		local class = (AZS_ZONE and AZS_ZONE.class) or "?"
		local locked = db.lockClass ~= false
		lockTxt:SetText(locked and ("Class: " .. class .. " [LOCKED]") or "Class: unlocked")
	end
	lockBtn:SetScript("OnClick", function()
		db.lockClass = not db.lockClass
		UpdateLockText()
	end)
	panel.lockTxt = lockTxt

	-- Reset-on-run-start toggle button
	local resetToggleBtn = CreateFrame("Button", nil, panel)
	resetToggleBtn:SetWidth(140)
	resetToggleBtn:SetHeight(20)
	resetToggleBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -38)
	resetToggleBtn:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = true, tileSize = 8, edgeSize = 1,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	resetToggleBtn:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
	resetToggleBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

	local resetToggleTxt = resetToggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	resetToggleTxt:SetPoint("CENTER", resetToggleBtn, "CENTER", 0, 0)

	panel.UpdateResetToggleText = function()
		local on = db.resetOnRunStart ~= false
		resetToggleTxt:SetText(on and "Reset list at run start: ON" or "Reset list at run start: OFF")
	end
	resetToggleBtn:SetScript("OnClick", function()
		db.resetOnRunStart = not db.resetOnRunStart
		panel.UpdateResetToggleText()
	end)
	panel.resetToggleTxt = resetToggleTxt

	local note = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	note:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -60)
	note:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -60)
	note:SetJustifyH("CENTER")
	note:SetText("Actual cards are hidden from addons. Predictions only.")

	local scroll = CreateFrame("ScrollFrame", "AZSCardAdvisorScroll", panel)
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -82)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, -10)
	scroll:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\ChatFrame\\ChatFrameBorder",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 }
	})
	scroll:SetBackdropColor(0, 0, 0, 0.6)

	local content = CreateFrame("Frame", "AZSCardAdvisorContent", scroll)
	content:SetWidth(310)
	content:SetHeight(10)
	scroll:SetScrollChild(content)

	panel.content = content
	RestorePosition()
	panel:Hide()
	return panel
end

-----------------------------------------------------------------
-- Event frame
-----------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function()
	if arg1 == "AZSCardAdvisor" then
		db = getglobal("AZSCardAdvisorDB")
		if not db then
			db = {}
			setglobal("AZSCardAdvisorDB", db)
		end
		if db.lockClass == nil then db.lockClass = true end
		if db.resetOnRunStart == nil then db.resetOnRunStart = true end
		if not db.lookFor then db.lookFor = {} end

		CreatePanel()
		RestorePosition()
		if panel.lockTxt then
			local class = (AZS_ZONE and AZS_ZONE.class) or "?"
			local locked = db.lockClass ~= false
			panel.lockTxt:SetText(locked and ("Class: " .. class .. " [LOCKED]") or "Class: unlocked")
		end
		if panel.resetToggleTxt then
			panel.UpdateResetToggleText()
		end
	end
end)

f:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed < UPDATE_INTERVAL then return end
	elapsed = 0

	CreatePanel()
	UpdateVisibility()
	CheckSoundAlert()
	RefreshContent()

	-- Keep lock text in sync if class changes mid-run (unlikely but safe)
	if panel and panel.lockTxt then
		local class = (AZS_ZONE and AZS_ZONE.class) or "?"
		local locked = db.lockClass ~= false
		panel.lockTxt:SetText(locked and ("Class: " .. class .. " [LOCKED]") or "Class: unlocked")
	end

	-- Keep reset toggle text in sync
	if panel and panel.resetToggleTxt then
		panel.UpdateResetToggleText()
	end
end)
