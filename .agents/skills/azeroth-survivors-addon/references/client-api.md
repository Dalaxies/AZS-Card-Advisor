# The client's addon API

Everything an addon can reach in Azeroth Survivors. This is the surface
itself; `references/api.md` documents the run tables (`AZS_*`) in detail.

## The surface

What a 1.12 addon can actually reach in this client:

| | count |
|---|---|
| API globals (functions, plus strings, numbers and tables they expose) | 1128 |
| bound global functions | 1153 |
| widget methods across 24 templates | 2305 |
| events | 394 |
| CVars | 381 |
| chat message types | 465 |

A further 20427 names come from stock FrameXML. They are real, but they are the
game's own UI internals, not API to depend on.

**A name being listed does not promise the feature works.** This is a partial
1.12 implementation: where a name is absent it is simply `nil`, so feature-detect
before you call it. The missing names are listed under Globals.

## Writing an addon

Drop a folder in `benilla-config/AddOns/<Name>/` beside the executable; it
loads on the next world entry. Browser builds: Options -> AddOns -> install a
`.zip`. Saved variables are written on logout.

### TOC directives

The reader tests these literals in order and the first match claims the line;
**any other directive is silently dropped** — there is no `## Dependencies:`,
it is `## Dep:`, and `## LoadWith:` is its own directive, not a synonym.

```
## Interface: 11200          version gate; may list several: 11507, 11508
## Title: My Addon           metadata
## Notes: ...                metadata
## Author: ...               metadata
## Version: 1.0              metadata
## X-Anything: value         metadata (the X- prefix is the literal)
## Revision: 12345           stored as a number
## OptionalDep: Other        load order hint
## RequiredDep: Other
## Dep: Other                same list as RequiredDep
## LoadWith: Other
## SavedVariables: MyDB      account-wide file
## SavedVariablesPerCharacter: MyDB   loaded after the account file, so it wins
## DefaultState: disabled    enabled unless this says disabled
## LoadOnDemand: 1
## Secure: 1
```

Anything else on a `#` line is a comment; any other line is a file to load.
`## Interface:` takes a comma-separated list (`11200` or `11507, 11508`) and is
compared as numbers; the first is what the version gate compares.

### Saved variables

`## SavedVariables:` globals come from the account-wide file,
`## SavedVariablesPerCharacter:` from the per-character one, loaded **after**
so its values win. A frame position you save is in that frame's own scale
units — clamp or convert after a UI-scale change or it lands off-screen.

## Lua core

A Lua 5.0-era 1.12.1 VM. `table.getn`/`setn` are the length ops (there is no
`#`), `math.mod` is `fmod`, and a family of bare aliases is installed:

```
strlen strsub strupper strlower strrep strfind strbyte strchar gsub
tinsert tremove getn format
ceil floor abs max min sqrt mod random randomseed PI
sin cos tan asin acos atan atan2 rad deg exp log log10 frexp ldexp   (degrees)
getglobal setglobal
```

Deliberately **absent** — they are 2.0+ or 5.1, and an addon that reaches for
one gets `nil`:

```
strsplit strjoin strconcat strtrim wipe tostringall tContains
strmatch gmatch strrev securecall hooksecurefunc issecure issecurevariable hook
CopyTable Mixin table.pack table.unpack table.move
```

There is **no `_G` table** in this VM: look up and set globals with
`getglobal`/`setglobal`, as in the original game.

The `#` length operator and `goto` are also 5.1+/5.2+. Lua 5.0's parser
rejects `...` in a call's argument list, which is not obvious and fails at load.
Feature-detect anything you are unsure of (`if (GetActionCooldown) then ...`).

### Stubs

`debuginfo`, `debugload`, `debugprint`, `debugdump`, `debugbreak` and
`debugtimestamp` exist and do **nothing** — they are the reference client's own
no-ops. `debugprofilestart`/`debugprofilestop` are real. A call that returns
zero without side effects is not a working API.

## The run API

The game fills these before any addon loads and keeps them current; see
`references/api.md` for every field.

```
AZS_GetRunTime() AZS_GetPhase() AZS_GetRunLength() AZS_GetBosses()
AZS_GetUpcomingBosses() AZS_GetGuardians() AZS_GetMeter() AZS_UnitKind(unit)
AZS_GetStoredLevels() AZS_OpenStoredLevels() AZS_IsStoringLevels() AZS_SetStoringLevels(store)
AZS_SetHudShown(part, shown) AZS_IsHudShown(part)
```

Tables: `AZS_ZONE` `AZS_RUN` `AZS_SCHEDULE` `AZS_UNITS` `AZS_TARGET`
`AZS_SPELLS` `AZS_BUFFS` `AZS_METER` `AZS_TAKEN` `AZS_STATS`, each with a
matching `<name>_UPDATED` holding the `GetTime()` of its last change.

They arrive as `CHAT_MSG_ADDON` lines; the prefixes are
`AZSZONE` `AZSRUN` `AZSBOSSES` `AZSUNITS` `AZSTGT` `AZSSPELLS` `AZSBUFFS`
`AZSMETER` `AZSTAKEN`, plus `AZS` for the stats line. The game's own parser
registers before any addon, so the tables are already updated when your
handler runs.

```lua
local f = CreateFrame("Frame");
f:RegisterEvent("CHAT_MSG_ADDON");
f:SetScript("OnEvent", function()
    if (arg1 == "AZSMETER") then
        -- AZS_METER already holds the new list; arg2 is the raw line
    end
end);
```

**There is no gear feed.** `AZS_STATS.g*` are per-stat totals for the whole
worn set; nothing tells an addon which items you hold.

## Addon management verbs

All eight take an index or a name, and a bad index raises:

```
GetAddOnInfo  GetAddOnMetadata  GetAddOnDependencies  EnableAddOn  DisableAddOn
IsAddOnLoadOnDemand  IsAddOnLoaded  LoadAddOn
```

`LoadAddOn` and `IsAddOnLoaded` exist, so a `libs/`-style layout can load —
but see the note on libraries below before relying on it.

**Libraries: Ace2/Ace3 cannot run.** `strsplit`, `strtrim`, `wipe`,
`securecall`, `hooksecurefunc`, `CopyTable` and `Mixin` are all absent, on
this client and a real 1.12 — Ace targets 2.4/3.3.5. Use a small in-file
shim, the way that era's own libraries (Titan, IcedT) were single-file
drop-ins.

## Globals

1128 names are the client's own API. The other 20427 are FrameXML — real, but stock
UI internals; feature-detect before depending on them.


Of the 1128 API globals, **1074 are present** in the running VM and 53 are not.

(`this`, `event` and `arg1`-`arg10` are excluded from the count: they are
handler locals, set only while an event fires, so a top-level dump of
`_G` cannot see them.)

Missing — these resolve to `nil`, so do not call them:

```
AcceptSkillUps AddSkillUp AppendToFile BuyRandomPicks BuySkillTier CloseLottery DeleteFile
GMRequestPlayerInfo GMSurveyAnswerSubmit GMSurveyCommentSubmit GMSurveyQuestion GMSurveySubmit
GetActiveLevel GetAvailableLevel GetCraftSkillLine GetJackpotAmount GetLFGResults
GetLFGTypeEntries GetLFGTypes GetLastLotteryNumbers GetLotteryPrizeInfo GetMinigameState
GetMinigameType GetMoneyPrizes GetNextDrawTime GetNumLFGResults GetNumLotteryPrizes
GetNumPastDrawResults GetPastDrawResult GetTradeSkillItemStats GetTrainerServiceStepIncrease
GetTrainerSkillLineFilter GetTrainerSkillLines IsTrainerServiceSkillStep IsVendorActive
LFGQuery MakeMinigameMove OpenTrainer ReadFile RemoveSkillUp ReplaceTradeEnchant
ResetPerformanceValues SetTrainerSkillLineFilter SubmitNumbers ToggleCollision
ToggleCollisionDisplay TogglePerformanceDisplay TogglePerformanceValues TogglePlayerBounds
TogglePortals ToggleTris UnitCanAssist UnitIsTrivial
```

### API globals

```
AbandonQuest AbandonSkill AcceptAreaSpiritHeal AcceptBattlefieldPort AcceptDuel AcceptGroup
AcceptGuild AcceptQuest AcceptResurrect AcceptSkillUps AcceptTrade AcceptXPLoss ActionHasRange
AddChatWindowChannel AddChatWindowMessages AddFriend AddIgnore AddOrDelIgnore AddQuestWatch
AddSkillUp AddTradeMoney AppendToFile AssistByName AssistUnit AttackTarget AutoEquipCursorItem
BankButtonIDToInvSlotID BeginTrade BindEnchant BuyGuildCharter BuyMerchantItem BuyRandomPicks
BuySkillTier BuyStableSlot BuyTrainerService BuybackItem CalculateAuctionDeposit
CameraOrSelectOrMoveStart CameraOrSelectOrMoveStop CameraZoomIn CameraZoomOut CanEditGuildInfo
CanEditMOTD CanEditOfficerNote CanEditPublicNote CanGuildDemote CanGuildInvite CanGuildPromote
CanGuildRemove CanInspect CanJoinBattlefieldAsGroup CanMerchantRepair CanSendAuctionQuery
CanShowResetInstances CanSignPetition CanViewOfficerNote CancelAreaSpiritHeal CancelAuction
CancelDuel CancelLogout CancelMeetingStoneRequest CancelPendingEquip CancelPlayerBuff
CancelSkillUps CancelTrackingBuff CancelTrade CancelTradeAccept CastPetAction
CastShapeshiftForm CastSpell CastSpellByName ChangeActionBarPage ChangeChatColor ChannelBan
ChannelInvite ChannelKick ChannelModerate ChannelModerator ChannelMute
ChannelToggleAnnouncements ChannelUnban ChannelUnmoderator ChannelUnmute CheckBinderDist
CheckInbox CheckInteractDistance CheckPetUntrainerDist CheckReadyCheckTime
CheckSpiritHealerDist CheckTalentMasterDist ClearCursor ClearInspectPlayer ClearSendMail
ClearTarget ClearTutorials ClickAuctionSellItemButton ClickSendMailItemButton ClickStablePet
ClickTargetTradeButton ClickTradeButton CloseAuctionHouse CloseBankFrame CloseBattlefield
CloseCraft CloseGossip CloseGuildRegistrar CloseGuildRoster CloseItemText CloseLoot
CloseLottery CloseMail CloseMerchant ClosePetStables ClosePetition CloseQuest
CloseTabardCreation CloseTaxiMap CloseTrade CloseTradeSkill CloseTrainer CollapseCraftSkillLine
CollapseFactionHeader CollapseQuestHeader CollapseSkillHeader CollapseTradeSkillSubClass
CollapseTrainerSkillLine CompleteQuest ConfirmAcceptQuest ConfirmBindOnUse ConfirmBinder
ConfirmLootRoll ConfirmPetUnlearn ConfirmReadyCheck ConfirmSummon ConfirmTalentWipe ConsoleExec
ContainerIDToInventoryID ConvertToRaid CreateFont CreateFrame CreateMacro
CreateMiniWorldMapArrowFrame CreateWorldMapArrowFrame CursorCanGoInSlot CursorHasItem
CursorHasMoney CursorHasSpell DeclineGroup DeclineGuild DeclineQuest DeclineResurrect DelIgnore
DeleteCursorItem DeleteFile DeleteGMTicket DeleteInboxItem DeleteMacro DemoteAssistant
DisableAddOn DisableAllAddOns DisplayChannelOwner DoCraft DoEmote DoReadyCheck DoTradeSkill
DropCursorMoney DropItemOnUnit EditMacro EnableAddOn EnableAllAddOns EnumerateFrames
EnumerateServerChannels EquipCursorItem EquipPendingItem ExpandCraftSkillLine
ExpandFactionHeader ExpandQuestHeader ExpandSkillHeader ExpandTradeSkillSubClass
ExpandTrainerSkillLine FactionToggleAtWar FlagTutorial FlipCameraYaw FollowByName FollowUnit
ForceLogout ForceQuit FrameXML_Debug GMRequestPlayerInfo GMSurveyAnswerSubmit
GMSurveyCommentSubmit GMSurveyQuestion GMSurveySubmit GetAbandonQuestItems GetAbandonQuestName
GetActionAutocast GetActionBarToggles GetActionCooldown GetActionCount GetActionText
GetActionTexture GetActiveLevel GetActiveTitle GetAddOnDependencies GetAddOnInfo
GetAddOnMetadata GetAdjustedSkillPoints GetAreaSpiritHealerTime GetAuctionHouseDepositRate
GetAuctionInvTypes GetAuctionItemClasses GetAuctionItemInfo GetAuctionItemLink
GetAuctionItemSubClasses GetAuctionItemTimeLeft GetAuctionSellItemInfo GetAvailableLevel
GetAvailableTitle GetBagName GetBankSlotCost GetBaseMip GetBattlefieldEstimatedWaitTime
GetBattlefieldFlagPosition GetBattlefieldInfo GetBattlefieldInstanceExpiration
GetBattlefieldInstanceInfo GetBattlefieldInstanceRunTime GetBattlefieldMapIconScale
GetBattlefieldPortExpiration GetBattlefieldPosition GetBattlefieldScore GetBattlefieldStatData
GetBattlefieldStatInfo GetBattlefieldStatus GetBattlefieldTimeWaited GetBattlefieldWinner
GetBidderAuctionItems GetBillingTimeRested GetBindLocation GetBinding GetBindingAction
GetBindingKey GetBlockChance GetBonusBarOffset GetBuildInfo GetBuybackItemInfo GetCVar
GetCVarDefault GetChannelList GetChannelName GetChatTypeIndex GetChatWindowChannels
GetChatWindowInfo GetChatWindowMessages GetCoinIcon GetComboPoints GetContainerItemCooldown
GetContainerItemInfo GetContainerItemLink GetContainerNumSlots GetCorpseMapPosition
GetCorpseRecoveryDelay GetCraftButtonToken GetCraftDescription GetCraftDisplaySkillLine
GetCraftIcon GetCraftInfo GetCraftItemLink GetCraftName GetCraftNumReagents GetCraftReagentInfo
GetCraftReagentItemLink GetCraftSelectionIndex GetCraftSkillLine GetCraftSpellFocus
GetCurrentBindingSet GetCurrentMapContinent GetCurrentMapZone GetCurrentMultisampleFormat
GetCurrentResolution GetCursorMoney GetCursorPosition GetDamageBonusStat GetDebugStats
GetDefaultLanguage GetDodgeChance GetDoodadAnim GetFactionInfo GetFarclip GetFirstTradeSkill
GetFramerate GetFriendInfo GetGMStatus GetGMTicket GetGMTicketCategories GetGameTime GetGamma
GetGossipActiveQuests GetGossipAvailableQuests GetGossipOptions GetGossipText GetGreetingText
GetGuildCharterCost GetGuildInfo GetGuildInfoText GetGuildRecruitmentMode GetGuildRosterInfo
GetGuildRosterLastOnline GetGuildRosterMOTD GetGuildRosterSelection GetGuildRosterShowOffline
GetIgnoreName GetInboxHeaderInfo GetInboxInvoiceInfo GetInboxItem GetInboxNumItems GetInboxText
GetInspectHonorData GetInspectPVPRankProgress GetInstanceBootTimeRemaining
GetInventoryAlertStatus GetInventoryItemBroken GetInventoryItemCooldown GetInventoryItemCount
GetInventoryItemLink GetInventoryItemQuality GetInventoryItemTexture GetInventorySlotInfo
GetItemInfo GetItemQualityColor GetJackpotAmount GetLFGResults GetLFGTypeEntries GetLFGTypes
GetLanguageByIndex GetLastLotteryNumbers GetLocale GetLookingForGroup GetLootMethod
GetLootRollItemInfo GetLootRollItemLink GetLootRollTimeLeft GetLootSlotInfo GetLootSlotLink
GetLootThreshold GetLotteryPrizeInfo GetMacroIconInfo GetMacroIndexByName GetMacroInfo
GetMapContinents GetMapInfo GetMapLandmarkInfo GetMapOverlayInfo GetMapZones
GetMasterLootCandidate GetMeetingStoneStatusText GetMerchantItemInfo GetMerchantItemLink
GetMerchantItemMaxStack GetMerchantNumItems GetMinigameState GetMinigameType GetMinimapZoneText
GetMoney GetMoneyPrizes GetMouseFocus GetMultisampleFormats GetNetStats GetNextDrawTime
GetNextStableSlotCost GetNumActiveQuests GetNumAddOns GetNumAuctionItems GetNumAvailableQuests
GetNumBankSlots GetNumBattlefieldFlagPositions GetNumBattlefieldPositions
GetNumBattlefieldScores GetNumBattlefieldStats GetNumBattlefields GetNumBindings
GetNumBuybackItems GetNumCrafts GetNumFactions GetNumFrames GetNumFriends GetNumGuildMembers
GetNumIgnores GetNumLFGResults GetNumLaguages GetNumLootItems GetNumLotteryPrizes
GetNumMacroIcons GetNumMacros GetNumMapLandmarks GetNumMapOverlays GetNumPackages
GetNumPartyMembers GetNumPastDrawResults GetNumPetitionNames GetNumQuestChoices
GetNumQuestItems GetNumQuestLeaderBoards GetNumQuestLogChoices GetNumQuestLogEntries
GetNumQuestLogRewards GetNumQuestRewards GetNumQuestWatches GetNumRaidMembers GetNumRoutes
GetNumSavedInstances GetNumShapeshiftForms GetNumSkillLines GetNumSpellTabs GetNumStablePets
GetNumStableSlots GetNumStationeries GetNumTalentTabs GetNumTalents GetNumTradeSkills
GetNumTrainerServices GetNumWhoResults GetNumWorldStateUI GetObjectiveText GetOwnerAuctionItems
GetPVPLastWeekStats GetPVPLifetimeStats GetPVPRankInfo GetPVPRankProgress GetPVPSessionStats
GetPVPThisWeekStats GetPVPYesterdayStats GetPackageInfo GetParryChance GetPartyLeaderIndex
GetPartyMember GetPastDrawResult GetPetActionCooldown GetPetActionInfo GetPetActionsUsable
GetPetExperience GetPetFoodTypes GetPetHappiness GetPetIcon GetPetLoyalty GetPetTimeRemaining
GetPetTrainingPoints GetPetitionInfo GetPetitionNameInfo GetPlayerBuff
GetPlayerBuffApplications GetPlayerBuffDispelType GetPlayerBuffTexture GetPlayerBuffTimeLeft
GetPlayerMapPosition GetPlayerTradeMoney GetProgressText GetQuestBackgroundMaterial
GetQuestGreenRange GetQuestIndexForTimer GetQuestIndexForWatch GetQuestItemInfo
GetQuestItemLink GetQuestLogChoiceInfo GetQuestLogItemLink GetQuestLogLeaderBoard
GetQuestLogPushable GetQuestLogQuestText GetQuestLogRequiredMoney GetQuestLogRewardInfo
GetQuestLogRewardMoney GetQuestLogRewardSpell GetQuestLogSelection GetQuestLogTimeLeft
GetQuestLogTitle GetQuestMoneyToGet GetQuestReward GetQuestText GetQuestTimers
GetRaidRosterInfo GetRaidRosterSelection GetRaidTargetIndex GetRealZoneText GetRealmName
GetRefreshRates GetReleaseTimeRemaining GetRepairAllCost GetResSicknessDuration GetRestState
GetRewardMoney GetRewardSpell GetRewardText GetSavedInstanceInfo GetScreenHeight
GetScreenResolutions GetScreenWidth GetSelectedAuctionItem GetSelectedBattlefield
GetSelectedFaction GetSelectedFriend GetSelectedIgnore GetSelectedSkill GetSelectedStablePet
GetSelectedStationeryTexture GetSendMailCOD GetSendMailItem GetSendMailMoney GetSendMailPrice
GetShapeshiftFormCooldown GetShapeshiftFormInfo GetSkillLineInfo GetSpellAutocast
GetSpellCooldown GetSpellName GetSpellTabInfo GetSpellTexture GetStablePetFoodTypes
GetStablePetInfo GetStationeryInfo GetSubZoneText GetSummonConfirmAreaName
GetSummonConfirmSummoner GetSummonConfirmTimeLeft GetTabardCreationCost GetTabardInfo
GetTalentInfo GetTalentPrereqs GetTalentTabInfo GetTargetTradeMoney GetTerrainMip GetTexLodBias
GetTime GetTimeToWellRested GetTitleText GetTrackingTexture GetTradePlayerItemInfo
GetTradePlayerItemLink GetTradeSkillCooldown GetTradeSkillIcon GetTradeSkillInfo
GetTradeSkillInvSlotFilter GetTradeSkillInvSlots GetTradeSkillItemLink GetTradeSkillItemStats
GetTradeSkillLine GetTradeSkillNumMade GetTradeSkillNumReagents GetTradeSkillReagentInfo
GetTradeSkillReagentItemLink GetTradeSkillSelectionIndex GetTradeSkillSubClassFilter
GetTradeSkillSubClasses GetTradeSkillTools GetTradeTargetItemInfo GetTradeTargetItemLink
GetTradeskillRepeatCount GetTrainerGreetingText GetTrainerSelectionIndex
GetTrainerServiceAbilityReq GetTrainerServiceCost GetTrainerServiceDescription
GetTrainerServiceIcon GetTrainerServiceInfo GetTrainerServiceLevelReq
GetTrainerServiceNumAbilityReq GetTrainerServiceSkillLine GetTrainerServiceSkillReq
GetTrainerServiceStepIncrease GetTrainerServiceStepReq GetTrainerServiceTypeFilter
GetTrainerSkillLineFilter GetTrainerSkillLines GetVideoCaps GetWatchedFactionInfo
GetWaterDetail GetWeaponEnchantInfo GetWhoInfo GetWorldDetail GetWorldLocMapPosition
GetWorldStateUIInfo GetXPExhaustion GetZonePVPInfo GetZoneText GiveMasterLoot
GuildControlAddRank GuildControlDelRank GuildControlGetNumRanks GuildControlGetRankFlags
GuildControlGetRankName GuildControlSaveRank GuildControlSetRank GuildControlSetRankFlag
GuildDemoteByName GuildDisband GuildInfo GuildInviteByName GuildLeave GuildPromoteByName
GuildRoster GuildRosterSetOfficerNote GuildRosterSetPublicNote GuildSetLeaderByName
GuildSetMOTD GuildUninviteByName HasAction HasFullControl HasInspectHonorData HasKey HasNewMail
HasPetSpells HasPetUI HasSoulstone HasWandEquipped HideFriendNameplates HideNameplates
HideRepairCursor InCinematic InRepairMode InboxItemCanDelete InitiateTrade InviteByName
InviteToParty IsActionInRange IsAddOnLoadOnDemand IsAddOnLoaded IsAltKeyDown IsAttackAction
IsAuctionSortReversed IsAutoRepeatAction IsConsumableAction IsControlKeyDown IsCurrentAction
IsCurrentCast IsCurrentQuestFailed IsEquippedAction IsFactionInactive IsFishingLoot
IsGuildLeader IsInGuild IsInInstance IsInMeetingStoneQueue IsInventoryItemLocked IsLinuxClient
IsMacClient IsMouselooking IsPartyLeader IsPetAttackActive IsQuestCompletable IsQuestWatched
IsRaidLeader IsRaidOfficer IsResting IsShiftKeyDown IsSpellPassive IsTalentTrainer
IsTradeskillTrainer IsTrainerServiceLearnSpell IsTrainerServiceSkillStep
IsTrainerServiceTradeSkill IsUnitOnQuest IsUsableAction IsVendorActive IsWindowsClient
ItemTextGetCreator ItemTextGetItem ItemTextGetMaterial ItemTextGetPage ItemTextGetText
ItemTextHasNextPage ItemTextNextPage ItemTextPrevPage JoinBattlefield JoinChannelByName Jump
KeyRingButtonIDToInvSlotID LFGQuery LearnTalent LeaveBattlefield LeaveChannelByName LeaveParty
ListChannelByName ListChannels LoadAddOn LoadBindings LoggingChat LoggingCombat Logout LootSlot
LootSlotIsCoin LootSlotIsItem MakeMinigameMove MouselookStart MouselookStop MoveBackwardStart
MoveBackwardStop MoveForwardStart MoveForwardStop MoveViewDownStart MoveViewDownStop
MoveViewInStart MoveViewInStop MoveViewLeftStart MoveViewLeftStop MoveViewOutStart
MoveViewOutStop MoveViewRightStart MoveViewRightStop MoveViewUpStart MoveViewUpStop NewGMTicket
NextView NoPlayTime NotWhileDeadError NotifyInspect NumTaxiNodes OfferPetition OffhandHasWeapon
OpenTrainer OpeningCinematic PI PartialPlayTime PetAbandon PetAggressiveMode PetAttack
PetCanBeAbandoned PetCanBeRenamed PetDefensiveMode PetDismiss PetFollow PetHasActionBar
PetPassiveMode PetRename PetStopAttack PetWait PickupAction PickupBagFromSlot
PickupContainerItem PickupInventoryItem PickupMacro PickupMerchantItem PickupPetAction
PickupPlayerMoney PickupSpell PickupStablePet PickupTradeMoney PitchDownStart PitchDownStop
PitchUpStart PitchUpStop PlaceAction PlaceAuctionBid PlayMusic PlaySound PlaySoundFile
PlayerHasSpells PositionMiniWorldMapArrowFrame PositionWorldMapArrowFrame PrevView
ProcessMapClick PromoteByName PromoteToAssistant PromoteToPartyLeader PurchaseSlot
PutItemInBackpack PutItemInBag QueryAuctionItems QuestChooseRewardError QuestLogPushQuest Quit
RandomRoll ReadFile RegisterCVar RegisterForSave ReloadUI RemoveChatWindowChannel
RemoveChatWindowMessages RemoveFriend RemoveQuestWatch RemoveSkillUp RenamePetition
RepairAllItems ReplaceEnchant ReplaceTradeEnchant RepopMe RequestBattlefieldPositions
RequestBattlefieldScoreData RequestInspectHonorData RequestRaidInfo RequestTimePlayed
ResetChatColors ResetCursor ResetDisabledAddOns ResetInstances ResetPerformanceValues
ResetTutorials ResetView RestartGx RestoreVideoDefaults ResurrectHasSickness ResurrectHasTimer
RetrieveCorpse ReturnInboxItem RollOnLoot RunBinding RunScript SaveBindings SaveView Screenshot
SelectActiveQuest SelectAvailableQuest SelectCraft SelectGossipActiveQuest
SelectGossipAvailableQuest SelectGossipOption SelectPackage SelectQuestLogEntry
SelectStationery SelectTradeSkill SelectTrainerService SendAddonMessage SendChatMessage
SendMail SendWho SetAbandonQuest SetActionBarToggles SetBagPortaitTexture SetBaseMip
SetBattlefieldScoreFaction SetBinding SetCVar SetChannelOwner SetChannelPassword
SetChatWindowAlpha SetChatWindowColor SetChatWindowDocked SetChatWindowLocked SetChatWindowName
SetChatWindowShown SetChatWindowSize SetConsoleKey SetCursor SetDoodadAnim SetEuropeanNumbers
SetFactionActive SetFactionInactive SetFarclip SetGamma SetGuildInfoText
SetGuildRecruitmentMode SetGuildRosterSelection SetGuildRosterShowOffline
SetInventoryPortaitTexture SetLayoutMode SetLookingForGroup SetLootMethod SetLootPortrait
SetLootThreshold SetMapToCurrentZone SetMapZoom SetMultisampleFormat SetPetStablePaperdoll
SetPortraitTexture SetPortraitToTexture SetRaidRosterSelection SetRaidSubgroup SetRaidTarget
SetScreenResolution SetSelectedAuctionItem SetSelectedBattlefield SetSelectedFaction
SetSelectedFriend SetSelectedIgnore SetSelectedSkill SetSendMailCOD SetSendMailMoney SetTaxiMap
SetTerrainMip SetTexLodBias SetTradeMoney SetTradeSkillInvSlotFilter
SetTradeSkillSubClassFilter SetTrainerServiceTypeFilter SetTrainerSkillLineFilter SetView
SetWatchedFactionIndex SetWaterDetail SetWhoToUI SetWorldDetail SetupFullscreenScale
ShowBattlefieldList ShowBuybackSellCursor ShowCloak ShowContainerSellCursor
ShowFriendNameplates ShowFriends ShowHelm ShowInspectCursor ShowInventorySellCursor
ShowMerchantSellCursor ShowMiniWorldMapArrowFrame ShowNameplates ShowRepairCursor
ShowWorldMapArrowFrame ShowingCloak ShowingHelm SignPetition SitOrStand SortAuctionItems
SortGuildRoster SortWho SpellCanTargetUnit SpellIsTargeting SpellStopCasting SpellStopTargeting
SpellTargetUnit SplitContainerItem StablePet StartAuction StartDuel StartDuelUnit StopCinematic
StopMusic StrafeLeftStart StrafeLeftStop StrafeRightStart StrafeRightStop Stuck SubmitNumbers
SwapRaidSubgroup TakeInboxItem TakeInboxMoney TakeInboxTextItem TakeTaxiNode TargetByName
TargetLastEnemy TargetLastTarget TargetNearestEnemy TargetNearestFriend
TargetNearestPartyMember TargetNearestRaidMember TargetUnit TaxiGetDestX TaxiGetDestY
TaxiGetSrcX TaxiGetSrcY TaxiNodeCost TaxiNodeGetType TaxiNodeName TaxiNodePosition
TaxiNodeSetCurrent ToggleAutoRun ToggleCollision ToggleCollisionDisplay ToggleMouseMove
TogglePVP TogglePerformanceDisplay TogglePerformanceValues TogglePetAutocast TogglePlayerBounds
TogglePortals ToggleRun ToggleSheath ToggleSpellAutocast ToggleTris TurnInGuildCharter
TurnLeftStart TurnLeftStop TurnOrActionStart TurnOrActionStop TurnRightStart TurnRightStop
TutorialsEnabled UninviteByName UninviteFromParty UninviteFromRaid UnitAffectingCombat
UnitArmor UnitAttackBothHands UnitAttackPower UnitAttackSpeed UnitBuff UnitCanAssist
UnitCanAttack UnitCanCooperate UnitCharacterPoints UnitClass UnitClassification
UnitCreatureFamily UnitCreatureType UnitDamage UnitDebuff UnitDefense UnitExists
UnitFactionGroup UnitHasRelicSlot UnitHealth UnitHealthMax UnitInParty UnitInRaid UnitIsCharmed
UnitIsCivilian UnitIsConnected UnitIsCorpse UnitIsDead UnitIsDeadOrGhost UnitIsEnemy
UnitIsFriend UnitIsGhost UnitIsPVP UnitIsPVPFreeForAll UnitIsPartyLeader UnitIsPlayer
UnitIsPlusMob UnitIsTapped UnitIsTappedByPlayer UnitIsTrivial UnitIsUnit UnitIsVisible
UnitLevel UnitMana UnitManaMax UnitName UnitOnTaxi UnitPVPName UnitPVPRank UnitPlayerControlled
UnitPlayerOrPetInParty UnitPlayerOrPetInRaid UnitPowerType UnitRace UnitRangedAttack
UnitRangedAttackPower UnitRangedDamage UnitReaction UnitResistance UnitSex UnitStat UnitXP
UnitXPMax UnstablePet UpdateGMTicket UpdateInventoryAlertStatus UpdateMapHighlight UpdateSpells
UpdateWorldMapArrowFrames UseAction UseContainerItem UseInventoryItem UseSoulstone
__framescript_meta __pow abs acos asin assert atan atan2 bit ceil collectgarbage cos date
debugbreak debugdump debuginfo debugload debugprint debugprofilestart debugprofilestop
debugstack debugtimestamp deg error exp floor foreach foreachi format frexp gcinfo
geterrorhandler getfenv getglobal getmetatable getn gsub ipairs ldexp loadstring log log10 math
mod next pairs pcall rad random randomseed rawequal rawget rawset seterrorhandler setfenv
setglobal setmetatable sin sort sqrt strbyte strchar strfind string strlen strlower strrep
strsub strupper table tan this tinsert tonumber tostring tremove type unpack xpcall
```

## Functions

1153 globals are bound as functions. The kind list is the argument types the
client reads (`?` optional, `|` alternatives).

```
AbandonQuest() AbandonSkill() AcceptAreaSpiritHeal() AcceptBattlefieldPort() AcceptContest()
AcceptDuel() AcceptEULA() AcceptGroup() AcceptGuild() AcceptQuest() AcceptResurrect()
AcceptScanning() AcceptSkillUps() AcceptTOS() AcceptTrade() AcceptXPLoss()
ActionHasRange(nil) | (number) AddChatWindowChannel() | (number) AddChatWindowMessages()
AddFriend() AddIgnore() AddOrDelIgnore() AddQuestWatch() AddSkillUp() AddTradeMoney() AppendToFile?
AssistByName() AssistUnit() AttackTarget() AutoEquipCursorItem() BankButtonIDToInvSlotID(number)
BeginTrade() BindEnchant() BuyGuildCharter(nil) | (number) BuyMerchantItem() BuyRandomPicks()
BuySkillTier() BuyStableSlot() BuyTrainerService() BuybackItem() CalculateAuctionDeposit(number)
CameraOrSelectOrMoveStart() CameraOrSelectOrMoveStop() CameraZoomIn() CameraZoomOut()
CanEditGuildInfo(nil) | (number) CanEditMOTD(nil) | (number) CanEditOfficerNote(nil) | (number)
CanEditPublicNote(nil) | (number) CanGuildDemote(nil) | (number) CanGuildInvite(nil) | (number)
CanGuildPromote(nil) | (number) CanGuildRemove(nil) | (number) CanInspect(nil) | (number)
CanJoinBattlefieldAsGroup(nil) | (number) CanMerchantRepair(nil) | (number)
CanSendAuctionQuery(nil) | (number) CanShowResetInstances(nil) | (number)
CanSignPetition(nil) | (number) CanViewOfficerNote(nil) | (number) CancelAreaSpiritHeal()
CancelAuction() CancelDuel() CancelLogout() CancelMeetingStoneRequest() CancelPendingEquip()
CancelPlayerBuff() CancelRealmListQuery() CancelSkillUps() CancelTrackingBuff() CancelTrade()
CancelTradeAccept() CastPetAction() CastShapeshiftForm() CastSpell() CastSpellByName()
ChangeActionBarPage() ChangeChatColor() ChangeRealm() ChannelBan() ChannelInvite() ChannelKick()
ChannelModerate() ChannelModerator() ChannelMute() ChannelToggleAnnouncements() ChannelUnban()
ChannelUnmoderator() ChannelUnmute() CheckBinderDist(nil) | (number) CheckInbox()
CheckInteractDistance(nil) | (number) CheckPetUntrainerDist(nil) | (number) CheckReadyCheckTime()
CheckSpiritHealerDist(nil) | (number) CheckTalentMasterDist(nil) | (number) ClearCursor()
ClearInspectPlayer() ClearSendMail() ClearTarget(nil) | (number) ClearTutorials()
ClickAuctionSellItemButton() ClickSendMailItemButton() ClickStablePet(nil) | (number)
ClickTargetTradeButton() ClickTradeButton() CloseAuctionHouse() CloseBankFrame() CloseBattlefield()
CloseCraft() CloseGossip() CloseGuildRegistrar() CloseGuildRoster() CloseItemText() CloseLoot()
CloseLottery() CloseMail() CloseMerchant() ClosePetStables() ClosePetition() CloseQuest()
CloseTabardCreation() CloseTaxiMap() CloseTrade() CloseTradeSkill() CloseTrainer()
CollapseCraftSkillLine() CollapseFactionHeader() CollapseQuestHeader() CollapseSkillHeader()
CollapseTradeSkillSubClass() CollapseTrainerSkillLine() CompleteQuest() ConfirmAcceptQuest()
ConfirmBindOnUse() ConfirmBinder() ConfirmLootRoll() ConfirmPetUnlearn() ConfirmReadyCheck()
ConfirmSummon() ConfirmTalentWipe() ConsoleExec() ContainerIDToInventoryID(number)
ContestAccepted(nil) | (number) ConvertToRaid() CreateCharacter() CreateFont(any) CreateFrame(any)
CreateMacro() | (number) CreateMiniWorldMapArrowFrame() CreateWorldMapArrowFrame()
CursorCanGoInSlot(nil) | (number) CursorHasItem(nil) | (number) CursorHasMoney(nil) | (number)
CursorHasSpell(nil) | (number) CycleCharCustomization() DeclineGroup() DeclineGuild()
DeclineQuest() DeclineResurrect() DefaultServerLogin() DelIgnore() DeleteCharacter()
DeleteCursorItem() DeleteFile? DeleteGMTicket() DeleteInboxItem() DeleteMacro() DemoteAssistant()
DisableAddOn() DisableAddOn() DisableAllAddOns() DisableAllAddOns() DisconnectFromServer()
DisplayChannelOwner() DoCraft() DoEmote() DoReadyCheck() DoTradeSkill() DropCursorMoney()
DropItemOnUnit() EULAAccepted(nil) | (number) EditMacro() | (number) EnableAddOn() EnableAddOn()
EnableAllAddOns() EnableAllAddOns() EnterWorld() EnumerateFrames(any) | (nil)
EnumerateServerChannels? EquipCursorItem() EquipPendingItem() ExpandCraftSkillLine()
ExpandFactionHeader() ExpandQuestHeader() ExpandSkillHeader() ExpandTradeSkillSubClass()
ExpandTrainerSkillLine() FactionToggleAtWar() FlagTutorial() FlipCameraYaw() FollowByName()
FollowUnit() ForceLogout() ForceQuit() FrameXML_Debug(number) GMRequestPlayerInfo?
GMSurveyAnswerSubmit() GMSurveyCommentSubmit() GMSurveyQuestion(nil) | (string?) GMSurveySubmit()
GetAbandonQuestItems? GetAbandonQuestName(nil) | (string?)
GetActionAutocast(nil,nil) | (nil,number) | (number,nil) | (number,number) GetActionBarToggles?
GetActionCooldown(number,number,number) GetActionCount(number) GetActionText(nil) | (string?)
GetActionTexture(nil) | (string?) GetActiveLevel(number) GetActiveTitle(string?)
GetAddOnDependencies? GetAddOnDependencies? GetAddOnEnableState(number) GetAddOnInfo? GetAddOnInfo?
GetAddOnMetadata(string?) GetAdjustedSkillPoints(number) GetAreaSpiritHealerTime(number)
GetAuctionHouseDepositRate(number) GetAuctionInvTypes? GetAuctionItemClasses? GetAuctionItemInfo?
GetAuctionItemLink() | (string?) GetAuctionItemSubClasses? GetAuctionItemTimeLeft(number)
GetAuctionSellItemInfo(nil,nil,number,number,nil,number) | (string?,string?,number,number,nil,number) | (string?,string?,number,number,number,number)
GetAvailableLevel(number) GetAvailableRaces? GetAvailableTitle(string?) GetBagName(nil) | (string?)
GetBankSlotCost(number) GetBaseMip(number) GetBattlefieldEstimatedWaitTime(number)
GetBattlefieldFlagPosition(number,number,nil) | (number,number,string?)
GetBattlefieldInfo() | (string?,number,number,number,number,number,number,number) | (string?,string?,number,number,number,number,number,number,number)
GetBattlefieldInstanceExpiration(number) GetBattlefieldInstanceInfo() | (number)
GetBattlefieldInstanceRunTime(number) GetBattlefieldMapIconScale(number)
GetBattlefieldPortExpiration(number)
GetBattlefieldPosition(number,number,nil) | (number,number,string?)
GetBattlefieldScore(nil,number,number,number,number,number,number,nil,nil) | (string?,number,number,number,number,number,number,nil,nil) | (string?,number,number,number,number,number,number,nil,string?) | (string?,number,number,number,number,number,number,string?,nil) | (string?,number,number,number,number,number,number,string?,string?)
GetBattlefieldStatData(number) GetBattlefieldStatInfo(nil,nil,nil) | (string?,string?,string?)
GetBattlefieldStatus(nil,nil,number,number,number) | (string,nil,number,number,number) | (string,string?,number,number,number)
GetBattlefieldTimeWaited(number) GetBattlefieldWinner(nil) | (number) GetBidderAuctionItems()
GetBillingPlan(number,number,number) GetBillingTimeRemaining(number) GetBillingTimeRested(number)
GetBillingTimeRested(number) GetBindLocation(string?) GetBinding? GetBindingAction(string?)
GetBindingKey? GetBlockChance(number) GetBonusBarOffset(number) GetBuildInfo(string,string,string)
GetBuildInfo(string?,string?,string,string,string)
GetBuybackItemInfo(nil,nil,number,number,number,number) | (string?,string?,number,number,number,nil) | (string?,string?,number,number,number,number)
GetCVar(string?) GetCVarDefault(nil) | (string?) GetChannelList?
GetChannelName(number,string?,number) GetCharacterCreateFacing(number)
GetCharacterInfo(nil,nil,nil,number,nil,nil,number,nil) | (string?,string?,string?,number,nil,string?,number,nil) | (string?,string?,string?,number,nil,string?,number,number) | (string?,string?,string?,number,string?,string?,number,nil) | (string?,string?,string?,number,string?,string?,number,number)
GetCharacterListUpdate() GetCharacterSelectFacing(number) GetChatTypeIndex(number)
GetChatWindowChannels?
GetChatWindowInfo() | (string?,number,number,number,number,number,nil,nil,nil) | (string?,number,number,number,number,number,nil,nil,number) | (string?,number,number,number,number,number,nil,number,nil) | (string?,number,number,number,number,number,nil,number,number) | (string?,number,number,number,number,number,number,nil,nil) | (string?,number,number,number,number,number,number,nil,number) | (string?,number,number,number,number,number,number,number,nil) | (string?,number,number,number,number,number,number,number,number)
GetChatWindowMessages? GetClassesForRace? GetCoinIcon(string?) GetComboPoints(number)
GetContainerItemCooldown(number,number,number)
GetContainerItemInfo() | (string?,number,nil,number,nil) | (string?,number,nil,number,number) | (string?,number,number,number,nil) | (string?,number,number,number,number)
GetContainerItemLink() | (string?) GetContainerNumSlots(number) GetCorpseMapPosition(number,number)
GetCorpseRecoveryDelay(number) GetCraftButtonToken(string?) GetCraftDescription(nil) | (string?)
GetCraftDisplaySkillLine(nil,number,number) | (string?,number,number) GetCraftIcon(nil) | (string?)
GetCraftInfo(nil,nil,nil,number,nil,number,number) | (string?,nil,string,number,nil,number,number) | (string?,nil,string,number,number,number,number) | (string?,string?,string?,number,nil,number,number)
GetCraftItemLink() | (string?) GetCraftName(nil) | (string?) GetCraftNumReagents(number)
GetCraftReagentInfo(nil,nil,nil,nil) | (nil,nil,number,number) | (string?,string?,number,number)
GetCraftReagentItemLink(nil) | (string?) GetCraftSelectionIndex(number)
GetCraftSkillLine(nil) | (string?) GetCraftSpellFocus? GetCurrentBindingSet(number)
GetCurrentMapContinent(number) GetCurrentMapZone(number) GetCurrentMultisampleFormat(number)
GetCurrentResolution(number) GetCursorMoney(number) GetCursorPosition(number,number)
GetCursorPosition(number,number) GetDamageBonusStat(number) GetDebugStats()
GetDefaultLanguage() | (string?) GetDodgeChance(number) GetDoodadAnim(number)
GetFacialHairCustomization(string) | (string?) GetFactionForRace(nil,nil) | (string?,string?)
GetFactionInfo? GetFarclip(number) GetFirstTradeSkill(number) GetFramerate(number)
GetFriendInfo(string?,number,string?,string?,nil,string?) | (string?,number,string?,string?,number,string?)
GetGMStatus() GetGMTicket() GetGMTicketCategories() GetGameTime(number,number) GetGamma(number)
GetGossipActiveQuests? GetGossipAvailableQuests? GetGossipOptions? GetGossipText(string?)
GetGreetingText(string?) GetGuildCharterCost(number)
GetGuildInfo(nil,nil,number) | (string?,string?,number) GetGuildInfoText(string?)
GetGuildRecruitmentMode(number) GetGuildRosterInfo?
GetGuildRosterLastOnline(nil,nil,nil,nil) | (number,number,number,number)
GetGuildRosterMOTD(string?) GetGuildRosterSelection(number)
GetGuildRosterShowOffline(nil) | (number) GetHairCustomization(string) | (string?)
GetIgnoreName(string?) GetInboxHeaderInfo?
GetInboxInvoiceInfo(nil,nil,nil,number,number,number,number) | (string,string?,string?,number,number,number,number)
GetInboxItem(nil,nil,number,number,nil) | (string?,string?,number,number,nil) | (string?,string?,number,number,number)
GetInboxNumItems(number) GetInboxText?
GetInspectHonorData(number,number,number,number,number,number,number,number,number,number,number,number)
GetInspectPVPRankProgress(number) GetInstanceBootTimeRemaining(number)
GetInventoryAlertStatus(number) GetInventoryItemBroken(nil) | (number)
GetInventoryItemCooldown(number,number,number) GetInventoryItemCount(number)
GetInventoryItemLink() | (string?) GetInventoryItemQuality(nil) | (number)
GetInventoryItemTexture(nil) | (string?)
GetInventorySlotInfo(number,string?,nil) | (number,string?,number)
GetItemInfo() | (string?,string?,number,number,string?,string?,number,string?,string?)
GetItemQualityColor(number,number,number,string?) GetJackpotAmount(number) GetLFGResults?
GetLFGTypeEntries? GetLFGTypes? GetLanguageByIndex() | (string?) GetLastLotteryNumbers()
GetLocale(string?) GetLocale(string?) GetLookingForGroup?
GetLootMethod(string,nil) | (string,number)
GetLootRollItemInfo(nil,nil,number,number,nil) | (string?,string?,number,number,nil) | (string?,string?,number,number,number)
GetLootRollItemLink() | (string?) GetLootRollTimeLeft(number)
GetLootSlotInfo(string?,string?,number,number) GetLootSlotLink(string?) GetLootThreshold(number)
GetLotteryPrizeInfo(string?,string?,number,number,nil) | (string?,string?,number,number,number)
GetMacroIconInfo(string?) GetMacroIndexByName(number)
GetMacroInfo(nil,nil,nil,nil) | (string?,nil,string?,nil) | (string?,nil,string?,number) | (string?,string?,string?,nil) | (string?,string?,string?,number)
GetMapContinents? GetMapInfo(string?,number,number)
GetMapLandmarkInfo(nil,nil,number,number,number) | (string?,nil,number,number,number) | (string?,string?,number,number,number)
GetMapOverlayInfo(nil,number,number,number,number,number,number) | (string?,number,number,number,number,number,number)
GetMapZones? GetMasterLootCandidate(nil) | (string?) GetMeetingStoneStatusText(string?)
GetMerchantItemInfo(nil,nil,number,number,number,number) | (nil,string?,number,number,number,nil) | (nil,string?,number,number,number,number) | (string?,string?,number,number,number,nil) | (string?,string?,number,number,number,number)
GetMerchantItemLink() | (string?) GetMerchantItemMaxStack(number) GetMerchantNumItems(number)
GetMinigameState() GetMinigameType(nil) | (string?) GetMinimapZoneText(string?) GetMoney(number)
GetMoneyPrizes(number,number,number) GetMouseFocus(any) | (nil) GetMovieResolution(number)
GetMovieSubtitles(nil) | (number) GetMultisampleFormats?
GetNameForRace(nil,nil) | (string?,string?) GetNetStats(number,number,number)
GetNextDrawTime(number) GetNextStableSlotCost(number) GetNumActiveQuests(number)
GetNumAddOns(number) GetNumAddOns(number) GetNumAuctionItems() | (number,number)
GetNumAvailableQuests(number) GetNumBankSlots(number,nil) | (number,number)
GetNumBattlefieldFlagPositions(number) GetNumBattlefieldPositions(number)
GetNumBattlefieldScores(number) GetNumBattlefieldStats(number) GetNumBattlefields(number)
GetNumBindings(number) GetNumBuybackItems(number) GetNumCharacters(number) GetNumCrafts(number)
GetNumFactions(number) GetNumFrames(number) GetNumFriends(number) GetNumGuildMembers(number)
GetNumIgnores(number) GetNumLFGResults(number,number) GetNumLaguages() | (number)
GetNumLootItems(number) GetNumLotteryPrizes(number) GetNumMacroIcons(number)
GetNumMacros(number,number) GetNumMapLandmarks(number) GetNumMapOverlays(number)
GetNumPackages(number) GetNumPartyMembers(number) GetNumPastDrawResults(number)
GetNumPetitionNames(number) GetNumQuestChoices(number) GetNumQuestItems(number)
GetNumQuestLeaderBoards(number) GetNumQuestLogChoices(number) GetNumQuestLogEntries(number,number)
GetNumQuestLogRewards(number) GetNumQuestRewards(number) GetNumQuestWatches(number)
GetNumRaidMembers(number) GetNumRealms(number) GetNumRoutes(number) GetNumSavedInstances(number)
GetNumShapeshiftForms(number) GetNumSkillLines(number) GetNumSpellTabs(number)
GetNumStablePets(number) GetNumStableSlots(number) GetNumStationeries(number)
GetNumTalentTabs(number) GetNumTalents(number) GetNumTradeSkills(number)
GetNumTrainerServices(number) GetNumWhoResults(number,number) GetNumWorldStateUI(number)
GetObjectiveText(string?) GetOwnerAuctionItems() GetPVPLastWeekStats(number,number,number,number)
GetPVPLifetimeStats(number,number,number) GetPVPRankInfo(nil,number) | (string?,number)
GetPVPRankProgress(number) GetPVPSessionStats(number,number) GetPVPThisWeekStats(number,number)
GetPVPYesterdayStats(number,number,number)
GetPackageInfo(nil,nil,number) | (string?,string?,number) GetParryChance(number)
GetPartyLeaderIndex(number) GetPartyMember(nil) | (number)
GetPastDrawResult(number,number,number,number,number) GetPetActionCooldown(number,number,number)
GetPetActionInfo? GetPetActionsUsable(nil) | (number) GetPetExperience(number,number)
GetPetFoodTypes? GetPetHappiness(nil,number,number) | (number,number,number)
GetPetIcon(nil) | (string?) GetPetLoyalty(nil) | (string?) GetPetTimeRemaining(nil) | (number)
GetPetTrainingPoints(number,number)
GetPetitionInfo(nil,nil,nil,number,nil,nil) | (string,string?,string?,number,nil,nil) | (string,string?,string?,number,nil,number) | (string,string?,string?,number,string?,nil) | (string,string?,string?,number,string?,number)
GetPetitionNameInfo(nil) | (string?) GetPlayerBuff(number,number) GetPlayerBuffApplications(number)
GetPlayerBuffDispelType(nil) | (string?) GetPlayerBuffTexture(nil) | (string?)
GetPlayerBuffTimeLeft(number) GetPlayerMapPosition(number,number) GetPlayerTradeMoney(number)
GetProgressText(string?) GetQuestBackgroundMaterial(nil) | (string?) GetQuestGreenRange(number)
GetQuestIndexForTimer(nil) | (number) GetQuestIndexForWatch(nil) | (number)
GetQuestItemInfo(string?,string?,number,number,nil) | (string?,string?,number,number,number)
GetQuestItemLink(nil) | (string?)
GetQuestLogChoiceInfo(nil,nil,number,number,nil) | (string?,string?,number,number,nil) | (string?,string?,number,number,number)
GetQuestLogItemLink(nil) | (string?)
GetQuestLogLeaderBoard(nil,nil,nil) | (string?,string,nil) | (string?,string,number)
GetQuestLogPushable(nil) | (number) GetQuestLogQuestText(nil,nil) | (string?,string?)
GetQuestLogRequiredMoney(number)
GetQuestLogRewardInfo(nil,nil,number,number,nil) | (string?,string?,number,number,nil) | (string?,string?,number,number,number)
GetQuestLogRewardMoney(number)
GetQuestLogRewardSpell(nil,nil,nil) | (nil,string?,nil) | (nil,string?,number) | (string?,string?,nil) | (string?,string?,number)
GetQuestLogSelection(number) GetQuestLogTimeLeft(nil) | (number)
GetQuestLogTitle(string?,number,string?,nil,nil,nil) | (string?,number,string?,nil,nil,number) | (string?,number,string?,number,nil,nil) | (string?,number,string?,number,nil,number) | (string?,number,string?,number,number,nil) | (string?,number,string?,number,number,number)
GetQuestMoneyToGet(number) GetQuestReward() GetQuestText(string?) GetQuestTimers?
GetRaidRosterInfo? GetRaidRosterSelection(number) GetRaidTargetIndex(nil) | (number)
GetRandomName(string?) GetRealZoneText(string?) GetRealmCategories? GetRealmInfo?
GetRealmName(string?) GetRefreshRates? GetReleaseTimeRemaining(number)
GetRepairAllCost(number) | (number,nil) | (number,number) GetResSicknessDuration(nil) | (string?)
GetRestState(nil,nil,nil) | (number,string?,number) GetRewardMoney(number)
GetRewardSpell(nil,nil,nil) | (nil,string?,nil) | (nil,string?,number) | (string?,string?,nil) | (string?,string?,number)
GetRewardText(string?) GetSavedAccountName(string?)
GetSavedInstanceInfo(nil,number,nil) | (string?,number,number) GetScreenHeight(number)
GetScreenHeight(number) GetScreenResolutions? GetScreenWidth(number) GetScreenWidth(number)
GetScriptMemory(number) GetSelectedAuctionItem(number) GetSelectedBattlefield(number)
GetSelectedCategory(number) GetSelectedClass(string?,string?) GetSelectedFaction(number)
GetSelectedFriend(number) GetSelectedIgnore(number) GetSelectedRace(number) GetSelectedSex(number)
GetSelectedSkill(number) GetSelectedStablePet(number) GetSelectedStationeryTexture(nil) | (string?)
GetSendMailCOD(number) GetSendMailItem(nil,nil,number,number) | (string?,string?,number,number)
GetSendMailMoney(number) GetSendMailPrice(number)
GetServerName(string?,nil,nil) | (string?,nil,number) | (string?,number,nil) | (string?,number,number)
GetShapeshiftFormCooldown(number,number,number)
GetShapeshiftFormInfo(nil,nil,nil,nil) | (nil,string?,nil,nil) | (nil,string?,nil,number) | (nil,string?,number,nil) | (nil,string?,number,number) | (string?,string?,nil,nil) | (string?,string?,nil,number) | (string?,string?,number,nil) | (string?,string?,number,number)
GetSkillLineInfo? GetSpellAutocast(nil,nil) | (nil,number) | (number,nil) | (number,number)
GetSpellCooldown(number,number,number) GetSpellName(nil,nil) | (string?,string?)
GetSpellTabInfo(nil,nil,number,number) | (string?,nil,number,number) | (string?,string,number,number) | (string?,string?,number,number)
GetSpellTexture(nil) | (string?) GetStablePetFoodTypes?
GetStablePetInfo(nil,nil,number,nil,nil) | (string?,string?,number,string?,nil) | (string?,string?,number,string?,string?)
GetStationeryInfo(nil,nil,nil) | (string?,string?,nil) | (string?,string?,number)
GetSubZoneText(string?) GetSummonConfirmAreaName(string?) GetSummonConfirmSummoner(string?)
GetSummonConfirmTimeLeft(number) GetTabardCreationCost(number) GetTabardInfo()
GetTalentInfo(nil,nil,number,number,number,number,nil,nil) | (string?,nil,number,number,number,number,nil,nil) | (string?,nil,number,number,number,number,nil,number) | (string?,nil,number,number,number,number,number,nil) | (string?,nil,number,number,number,number,number,number) | (string?,string?,number,number,number,number,nil,nil) | (string?,string?,number,number,number,number,nil,number) | (string?,string?,number,number,number,number,number,nil) | (string?,string?,number,number,number,number,number,number)
GetTalentPrereqs?
GetTalentTabInfo(nil,nil,number,nil) | (string?,nil,number,string?) | (string?,string?,number,string?)
GetTargetTradeMoney(number) GetTerrainMip(number) GetTexLodBias(number) GetTime(number)
GetTimeToWellRested(nil) GetTitleText(string?) GetTrackingTexture(nil) | (string?)
GetTradePlayerItemInfo(nil,nil,number,number,nil) | (string?,string?,number,number,nil) | (string?,string?,number,number,string?)
GetTradePlayerItemLink() | (string?) GetTradeSkillCooldown(nil) | (number)
GetTradeSkillIcon(nil) | (string?)
GetTradeSkillInfo(nil,nil,number,nil) | (string?,string,number,nil) | (string?,string,number,number) | (string?,string?,number,nil)
GetTradeSkillInvSlotFilter(nil) | (number) GetTradeSkillInvSlots?
GetTradeSkillItemLink() | (string?) GetTradeSkillItemStats?
GetTradeSkillLine(string,number,number) | (string?,number,number)
GetTradeSkillNumMade(number,number) GetTradeSkillNumReagents(number)
GetTradeSkillReagentInfo(nil,nil,nil,nil) | (nil,nil,number,number) | (string?,string?,number,number)
GetTradeSkillReagentItemLink(nil) | (string?) GetTradeSkillSelectionIndex(number)
GetTradeSkillSubClassFilter(nil) | (number) GetTradeSkillSubClasses? GetTradeSkillTools?
GetTradeTargetItemInfo(nil,nil,number,number,nil,nil) | (string?,string?,number,number,nil,nil) | (string?,string?,number,number,nil,string?) | (string?,string?,number,number,number,nil) | (string?,string?,number,number,number,string?)
GetTradeTargetItemLink() | (string?) GetTradeskillRepeatCount(number)
GetTrainerGreetingText(string?) GetTrainerSelectionIndex(number)
GetTrainerServiceAbilityReq(nil,nil) | (nil,number) | (string?,nil) | (string?,number)
GetTrainerServiceCost(number,number,number) GetTrainerServiceDescription(nil) | (string?)
GetTrainerServiceIcon(nil) | (string?)
GetTrainerServiceInfo(string?,string?,string?,nil) | (string?,string?,string?,number)
GetTrainerServiceLevelReq(number) GetTrainerServiceNumAbilityReq(number)
GetTrainerServiceSkillLine(nil) | (string?)
GetTrainerServiceSkillReq(nil,number,nil) | (nil,number,number) | (string?,number,nil) | (string?,number,number)
GetTrainerServiceStepIncrease(nil) | (string?)
GetTrainerServiceStepReq(nil,nil) | (nil,number) | (string?,nil) | (string?,number)
GetTrainerServiceTypeFilter(nil) | (number) GetTrainerSkillLineFilter(nil) | (number)
GetTrainerSkillLines? GetVideoCaps?
GetWatchedFactionInfo(nil,number,number,number,number) | (string?,number,number,number,number)
GetWaterDetail(number)
GetWeaponEnchantInfo(nil,nil,nil,nil,nil,nil) | (nil,nil,nil,number,nil,number) | (nil,nil,nil,number,number,number) | (number,nil,number,nil,nil,nil) | (number,nil,number,number,nil,number) | (number,nil,number,number,number,number) | (number,number,number,nil,nil,nil) | (number,number,number,number,nil,number) | (number,number,number,number,number,number)
GetWhoInfo(nil,nil,number,nil,nil,nil) | (string?,string?,number,string?,string?,string?)
GetWorldDetail(number) GetWorldLocMapPosition(number,number)
GetWorldStateUIInfo(number) | (number,string?,string?,string?,string?,string?,string?,number,number,number)
GetXPExhaustion(nil) | (number)
GetZonePVPInfo(nil,nil,nil) | (nil,nil,number) | (string,string?,nil) | (string,string?,number)
GetZoneText(string?) GiveMasterLoot() GuildControlAddRank() GuildControlDelRank()
GuildControlGetNumRanks(number) GuildControlGetRankFlags? GuildControlGetRankName(nil) | (string?)
GuildControlSaveRank() GuildControlSetRank() GuildControlSetRankFlag() GuildDemoteByName()
GuildDisband() GuildInfo() GuildInviteByName() GuildLeave() GuildPromoteByName() GuildRoster()
GuildRosterSetOfficerNote() GuildRosterSetPublicNote() GuildSetLeaderByName() GuildSetMOTD()
GuildUninviteByName() HasAction(nil) | (number) HasCharCustomization(nil) | (number)
HasFullControl(nil) | (number) HasInspectHonorData(nil) | (number) HasKey(nil) | (number)
HasNewMail(nil) | (number) HasPetSpells(nil,nil) | (number,string) | (number,string?)
HasPetUI(nil,nil) | (number,nil) | (number,number) HasSoulstone(nil) | (string) | (string?)
HasWandEquipped(nil) | (number) HideCursor() HideFriendNameplates() HideNameplates()
HideRepairCursor() InCinematic(nil) | (number) InRepairMode(nil) | (number)
InboxItemCanDelete(nil) | (number) InitiateTrade() InviteByName() InviteToParty()
IsActionInRange(nil) | (number) IsAddOnLoadOnDemand(nil) | (number) IsAddOnLoaded(nil) | (number)
IsAddonVersionCheckEnabled(nil) | (number) IsAltKeyDown(nil) | (number)
IsAttackAction(nil) | (number) IsAuctionSortReversed() | (nil) | (number)
[note: this file was truncated at line ~675 of 2362 during fetch; grep it locally for any name you need to feature-detect]