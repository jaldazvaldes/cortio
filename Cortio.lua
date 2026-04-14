BINDING_HEADER_CORTIO_HEADER = "Cortio - Asignacion de Cortes"
BINDING_NAME_CLICK_CortioMarkSABT_LeftButton = "Poner/Quitar Marca de Corte"

Cortio = Cortio or {}

-- Prefix registration moved to PLAYER_ENTERING_WORLD for reliability

-- Taint debug: detect ADDON_ACTION_BLOCKED
local blockedFrame = CreateFrame("Frame")
blockedFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
blockedFrame:SetScript("OnEvent", function(_, _, addon, func)
    if addon == "Cortio" then
        Cortio.Data:LogError("TAINT", "Action blocked: " .. tostring(func))
        print("|cFF00FFFF[Cortio]|r |cFFFF0000TAINT: Action blocked:|r " .. tostring(func))
    end
end)

-- ============================================================
-- Unified player lookup: GUID > full name > Ambiguate > short name
-- Used by both CHAT_MSG_ADDON and COMBAT_LOG_EVENT_UNFILTERED
-- ============================================================
local function FindRosterPlayerByGUIDOrName(sourceGUID, sourceName)
    local resolvedBy = nil

    -- 1. GUID match (most reliable — unique per player)
    if sourceGUID then
        for pName, data in pairs(Cortio.RosterList) do
            if data.guid and data.guid == sourceGUID then
                return pName, "GUID"
            end
        end
    end

    -- 2. Exact full name match
    if sourceName then
        if Cortio.RosterList[sourceName] then
            return sourceName, "FullName"
        end

        -- 3. Ambiguate match (handles cross-realm names)
        local ambigSource = Ambiguate(sourceName, "short")
        if Cortio.RosterList[ambigSource] then
            return ambigSource, "Ambiguate"
        end

        -- 4. Short name match (least reliable, last resort)
        local shortName = Cortio.Data:ShortName(sourceName)
        for pName, _ in pairs(Cortio.RosterList) do
            if Ambiguate(pName, "short") == ambigSource then
                return pName, "AmbiguateLoop"
            end
        end
        for pName, _ in pairs(Cortio.RosterList) do
            if Cortio.Data:ShortName(pName) == shortName then
                return pName, "ShortName"
            end
        end
    end

    return nil, nil
end

-- Legacy wrapper for addon messages (no GUID available from chat)
local function FindRosterPlayer(sender)
    local player, _ = FindRosterPlayerByGUIDOrName(nil, sender)
    return player
end

-- Debug toggle (enable with CortioDB.debugCombatLog = true or /ct debugcl)
local function DebugCL(...)
    if not CortioDB or not CortioDB.debugCombatLog then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    print("|cFF00FFFF[Cortio]|r |cFFAADDFF[CL]|r " .. table.concat(parts, " "))
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("UNIT_DIED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, ...)

    if event == "PLAYER_ENTERING_WORLD" then
        Cortio.Roster:EnsurePlayerInfo()
        
        -- Register addon message prefix (verified at each zone load)
        if not C_ChatInfo.IsAddonMessagePrefixRegistered(Cortio.Data.COMM_PREFIX) then
            local regOk = C_ChatInfo.RegisterAddonMessagePrefix(Cortio.Data.COMM_PREFIX)
            if not regOk then
                C_Timer.After(2, function()
                    C_ChatInfo.RegisterAddonMessagePrefix(Cortio.Data.COMM_PREFIX)
                end)
            end
        end
        
        Cortio.Marks.Active = {}
        for unit, _ in pairs(Cortio.UI.ActiveNameplates) do
            Cortio.UI:ReleaseNameplateFrame(unit)
        end
        
        if not CortioDB then CortioDB = {} end
        if not CortioDB.errors then CortioDB.errors = {} end
        
        Cortio.Roster:RebuildWithRetry()
        Cortio.Roster:AutoRegisterByClass()
        Cortio.Roster:RegisterPartyWatchers()
        Cortio.Marks:QueueSecureBtnUpdate()
        
        C_Timer.After(1, function() Cortio.Roster:AutoRegisterByClass(); Cortio.Roster:RegisterPartyWatchers() end)
        C_Timer.After(2, function() Cortio.Net:SendGroupMessage("V1|SYNCREQ", "SyncReq") end)
        C_Timer.After(3, function() Cortio.Roster:AutoRegisterByClass(); Cortio.Roster:RegisterPartyWatchers(); Cortio.UI:UpdatePanel() end)
        C_Timer.After(5, function() Cortio.Net:SendGroupMessage("V1|SYNCREQ", "SyncReq") end)
        
        Cortio.UI:SetupKickIcon()
        
        C_Timer.After(0.5, function()
            if CortioDB and CortioDB.scale then Cortio.UI.Panel:SetScale(CortioDB.scale) end
            Cortio.UI:CreateSettingsMenu()
        end)
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        Cortio.Marks:QueueSecureBtnUpdate()
        
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then
        Cortio.UI:UpdateNameplate(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" or event == "FORBIDDEN_NAME_PLATE_UNIT_REMOVED" then
        for _, mark in ipairs(Cortio.Marks.Active) do
            if mark.nameplateUnit == arg1 then
                mark.nameplateUnit = nil
            end
        end
        Cortio.UI:ReleaseNameplateFrame(arg1)
        
    elseif event == "GROUP_ROSTER_UPDATE" then
        Cortio.Roster:Rebuild()
        Cortio.Roster:AutoRegisterByClass()
        Cortio.Roster:RegisterPartyWatchers()
        Cortio.RegisterPartyInterruptWatchers()
        Cortio.UI:UpdatePanel()
        if not InCombatLockdown() then
            Cortio.Marks:QueueSecureBtnUpdate()
        end
        C_Timer.After(1, function()
            Cortio.Roster:RegisterPartyWatchers()
            Cortio.Roster:AutoRegisterByClass()
            Cortio.RegisterPartyInterruptWatchers()
            Cortio.UI:UpdatePanel()
            Cortio.Net:SendGroupMessage("V1|SYNCREQ", "SyncReq")
        end)
        C_Timer.After(3, function()
            Cortio.Roster:RegisterPartyWatchers()
            Cortio.Roster:AutoRegisterByClass()
            Cortio.RegisterPartyInterruptWatchers()
        end)


        
    elseif event == "INSPECT_READY" then
        Cortio.Roster:OnInspectReady(arg1)

    elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        Cortio.Roster:Rebuild()
        Cortio.Roster:AutoRegisterByClass()
        Cortio.UI:UpdatePanel()
        Cortio.UI:SetupKickIcon()

    elseif event == "UNIT_DIED" then
        local cleared = false
        local ok, isTargetStr = pcall(function() return arg1 == "target" end)
        isTargetStr = ok and isTargetStr
        
        for i = #Cortio.Marks.Active, 1, -1 do
            local mark = Cortio.Marks.Active[i]
            local shouldClear = false

            if mark.nameplateUnit then
                if Cortio.Taint:SafeIsMatch(mark.nameplateUnit, arg1) then
                    shouldClear = true
                end
            end

            if not shouldClear and mark.playerName == Cortio.PlayerName and not mark.nameplateUnit then
                if isTargetStr or Cortio.Taint:SafeIsMatch(arg1, "target") then
                    shouldClear = true
                end
            end

            if shouldClear then
                if mark.playerName == Cortio.PlayerName then
                    Cortio.Net:SendGroupMessage("V1|UNMARK", "Send")
                end
                table.remove(Cortio.Marks.Active, i)
                cleared = true
            end
        end
        if cleared then Cortio.UI:UpdatePanel() end
        
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == Cortio.Data.COMM_PREFIX then
            local _, sender = ...
            if CortioDB and CortioDB.debugLogs then print("|cFF00FFFF[Cortio]|r |cFF00FF00ADDON_MSG|r prefix=" .. tostring(arg1) .. " msg=" .. tostring(arg2) .. " sender=" .. tostring(sender)) end
            if not sender then return end
            local ambigSender = Ambiguate(sender, "short")
            local ambigPlayer = Cortio.PlayerName and Ambiguate(Cortio.PlayerName, "short") or ""
            if sender == Cortio.PlayerName or ambigSender == ambigPlayer then
                if CortioDB and CortioDB.debugLogs then print("|cFF00FFFF[Cortio]|r ADDON_MSG filtered (self): " .. tostring(sender)) end
                return
            end
            
            Cortio.Net:LogReceived(arg1, arg2, sender)
            
            -- V1 protocol uses | separator; legacy uses :
            local version, action, p2, p3, p4, p5, p6
            if arg2:sub(1, 3) == "V1|" then
                version, action, p2, p3, p4, p5, p6 = strsplit("|", arg2, 7)
            else
                action, p2, p3, p4, p5, p6 = strsplit(":", arg2, 7)
            end
            local rPlayer = FindRosterPlayer(sender) or sender
            
            if action == "SYNCREQ" then
                C_Timer.After(0.5 + math.random() * 1.5, function() Cortio.Marks:BroadcastCurrentMark() end)
            elseif action == "CD" then
                local cdDuration = tonumber(p2)
                print("|cFF00FFFF[Cortio]|r |cFFFFFF00CD RECEIVED|r from=" .. tostring(rPlayer) .. " dur=" .. tostring(cdDuration) .. " inRoster=" .. tostring(Cortio.RosterList[rPlayer] ~= nil))
                if cdDuration and cdDuration > 0 then
                    Cortio.Data:SafeCall("Remote_CD", function()
                        local now = GetTime()
                        for _, mark in ipairs(Cortio.Marks.Active) do
                            if mark.playerName == rPlayer then
                                mark.remoteCDEnd = now + cdDuration
                                mark.remoteCDDuration = cdDuration
                            end
                        end
                        if Cortio.RosterList[rPlayer] then
                            Cortio.RosterList[rPlayer].cdEnd = now + cdDuration
                            Cortio.RosterList[rPlayer].cdTotal = cdDuration
                            print("|cFF00FFFF[Cortio]|r |cFF00FF00CD SET|r " .. rPlayer .. " cdEnd=" .. string.format("%.1f", now + cdDuration) .. " total=" .. cdDuration)
                        else
                            print("|cFF00FFFF[Cortio]|r |cFFFF0000CD FAIL|r player '" .. rPlayer .. "' NOT in RosterList")
                        end
                        Cortio.UI:UpdatePanel()
                        Cortio.StartPanelTicker()
                    end)
                end
            elseif action and p2 and p3 then
                local cls, specIcon, markIdStr, markerSlotStr = p2, p3, p4, p5
                local tGUID = (p6 and p6 ~= "") and p6 or nil
                local mId = markIdStr and tonumber(markIdStr) or nil
                local markerSlot = markerSlotStr and tonumber(markerSlotStr) or 0
                if action == "MARK" then
                    Cortio.Marks:ClearPlayerMark(rPlayer)

                    local ourSlotBefore = Cortio.Marks:GetPlayerMarkerSlotSafe()

                    local uToken = nil
                    for i = 1, 4 do
                        local u = "party" .. i
                        if UnitExists(u) then
                            if Cortio.RosterList[rPlayer] and Cortio.RosterList[rPlayer].unit == u then
                                uToken = u .. "target"
                                break
                            end
                        end
                    end
                    if not uToken then
                        for i = 1, 4 do
                            local u = "party" .. i
                            if UnitExists(u) then
                                local ok, n, r = pcall(UnitName, u)
                                if ok and n then
                                    local fN = (r and r ~= "") and (n.."-"..r) or n
                                    local sN = strsplit("-", rPlayer)
                                    if fN == rPlayer or n == sN or strsplit("-",fN) == sN then
                                        uToken = u .. "target"
                                        break
                                    end
                                end
                            end
                        end
                    end

                    local newMark = {
                        playerName = rPlayer,
                        playerClass = cls,
                        specIcon = specIcon,
                        remoteCDEnd = 0,
                        remoteCDDuration = 0,
                        nameplateUnit = nil,
                        unitToken = uToken,
                        markerSlot = markerSlot
                    }
                    table.insert(Cortio.Marks.Active, newMark)

                    local ourSlotFixed = not CortioDB or (CortioDB.markerSlot or 0) == 0
                    if ourSlotFixed and markerSlot > 0 and markerSlot == ourSlotBefore then
                        Cortio.Marks:QueueSecureBtnUpdate()
                    end
                elseif action == "UNMARK" then
                    Cortio.Marks:ClearPlayerMark(rPlayer)
                end
                Cortio.UI:UpdatePanel()
                Cortio.UI:UpdateAllNameplates()
            end
    end
    end
end)

-- ============================================================
-- MACRO MESSAGE PARSER (For marker synchronization)
-- We parse messages generated by the SecureActionButton macro because
-- SendAddonMessage result=11 blocks hidden cross-client sync.
-- Texts from hardware macros are readable clean strings.
-- ============================================================
local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("CHAT_MSG_PARTY")
chatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
chatFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
chatFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
chatFrame:RegisterEvent("CHAT_MSG_RAID")
chatFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")

chatFrame:SetScript("OnEvent", function(self, event, arg1)
    if not arg1 then return end
    -- arg1 from CHAT_MSG can be a secret string in WoW 12.0.
    -- We CANNOT use text:match() because that indexes the tainted string.
    -- Use pcall(string.match, text, pattern) instead.
    local ok, text = pcall(tostring, arg1)
    if not ok or not text then return end
    
    -- Parse macro format: "[Cortio] Assigned {rt8} (Annarya)"
    local matchOk, slotStr, playerName = pcall(string.match, text, "%[Cortio%] Assigned %{rt(%d+)%} %((.-)%)")
    if not matchOk or not slotStr or not playerName then return end
    
    local slot = tonumber(slotStr)
    if not slot or slot <= 0 then return end
    
    local myShort = Cortio.PlayerName and Cortio.Data:ShortName(Cortio.PlayerName) or ""
    if playerName == myShort then return end
    
    -- Find player in roster
    local rPlayer = nil
    if Cortio.RosterList then
        for rName, _ in pairs(Cortio.RosterList) do
            local short = Cortio.Data:ShortName(rName)
            if short == playerName or Ambiguate(rName, "short") == playerName then
                rPlayer = rName
                break
            end
        end
    end
    
    if rPlayer and Cortio.RosterList[rPlayer] then
        Cortio.Marks:ClearPlayerMark(rPlayer)
        
        local uToken = nil
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then
                local okN, n = pcall(UnitName, u)
                if okN and n then
                    if n == strsplit("-", rPlayer) or n == playerName then
                        uToken = u .. "target"
                        break
                    end
                end
            end
        end
        
        local rClass = Cortio.RosterList[rPlayer].class or "UNKNOWN"
        table.insert(Cortio.Marks.Active, {
            playerName = rPlayer,
            playerClass = rClass,
            specIcon = "0", 
            remoteCDEnd = 0,
            remoteCDDuration = 0,
            nameplateUnit = nil,
            unitToken = uToken,
            markerSlot = slot
        })
        
        Cortio.UI:UpdatePanel()
        Cortio.UI:UpdateAllNameplates()
        if CortioDB and CortioDB.debugLogs then print("|cFF00FFFF[Cortio]|r |cFF00FF00MACRO SYNC|r assigned {rt" .. slot .. "} to " .. rPlayer) end
    end
end)

-- ============================================================
-- SIGNAL CORRELATION ENGINE (BliZzi/WilduTools approach)
--
-- Detects party member interrupts WITHOUT reading tainted spellIDs.
-- Instead of trying to resolve "secret values", we correlate timestamps:
--
--   1) UNIT_SPELLCAST_SUCCEEDED on party/partypet → "cast" signal
--   2) UNIT_SPELLCAST_INTERRUPTED on nameplates   → "interrupt" signal  
--   3) UNIT_AURA on nameplates                    → "aura" signal (suppress false positives)
--
-- Signals are correlated within a 55ms window. When a cast matches
-- an interrupt, we trigger the CD for that player.
-- ============================================================
local signalTape       = {}
local signalSeq        = 0
local needsCorrelation = false
local lastCorrelateAt  = 0

-- Timing constants (tuned from BliZzi's production values)
local SIGNAL_RETENTION   = 0.35    -- seconds to keep signals
local CORRELATE_INTERVAL = 0.04    -- min seconds between correlations
local MATCH_WINDOW       = 0.055   -- cast ↔ interrupt match window
local AURA_SUPPRESS      = 0.028   -- aura within this window suppresses interrupt

-- Recent casts: tracks the last known interrupt cast per player for correlation
local recentCasts = {}  -- name → { t = GetTime(), spellID = number }

local function PushSignal(kind, unit)
    signalSeq = signalSeq + 1
    signalTape[#signalTape + 1] = {
        seq      = signalSeq,
        kind     = kind,       -- "cast" | "interrupt" | "aura"
        unit     = unit,
        at       = GetTime(),
        consumed = false,
    }
    needsCorrelation = true
end

local function PruneSignalTape(now)
    local kept = {}
    local minAt = now - SIGNAL_RETENTION
    for i = 1, #signalTape do
        local s = signalTape[i]
        if s and s.at and s.at >= minAt then
            kept[#kept + 1] = s
        end
    end
    signalTape = kept
end

-- Resolve which party member name owns a unit (handles partypet → owner)
-- NOTE: Uses plain UnitName (like BliZzi), NOT SafeUnitName.
-- SafeUnitName's issecretvalue() check is too aggressive for party names
-- and returns nil, killing the entire correlation chain.
local function ResolvePartyName(unit)
    if not unit then return nil, nil end
    if unit:find("^partypet") then
        local idx = unit:match("partypet(%d)")
        if idx then
            local ownerUnit = "party" .. idx
            return UnitName(ownerUnit), ownerUnit
        end
        return nil, nil
    end
    return UnitName(unit), unit
end

-- Trigger a party member's interrupt CD when correlation confirms an interrupt
local function TriggerPartyCooldown(unit, memberName)
    if not memberName then return end

    -- Find in roster
    local matchedPlayer = FindRosterPlayerByGUIDOrName(nil, memberName)
    if not matchedPlayer then
        local okG, guid = pcall(UnitGUID, unit)
        if okG and guid then
            matchedPlayer = FindRosterPlayerByGUIDOrName(guid, memberName)
        end
    end

    -- Auto-register if not in roster
    if not matchedPlayer then
        local okG, guid = pcall(UnitGUID, unit)
        local okCls, _, engClass = pcall(UnitClass, unit)
        if okCls and engClass and Cortio.Data.CLASS_INTERRUPT_SPELLID[engClass] then
            Cortio.RosterList[memberName] = {
                unit = unit, guid = (okG and guid) or nil, class = engClass,
                specIcon = "0", specId = 0, cdEnd = 0, cdTotal = 0, lastResult = nil,
            }
            matchedPlayer = memberName
            print("|cFF00FFFF[Cortio]|r |cFF00FF00SIGNAL|r Auto-registered: " .. memberName .. " class=" .. engClass)
        end
    end

    if not matchedPlayer then return end

    local rosterData = Cortio.RosterList[matchedPlayer]
    if not rosterData then return end

    -- Compute cooldown
    local cdTotal
    if rosterData.specId and rosterData.specId > 0 and Cortio.Data.SPEC_INTERRUPTS then
        local specData = Cortio.Data.SPEC_INTERRUPTS[rosterData.specId]
        if specData then cdTotal = specData.baseCD end
    end
    if not cdTotal then cdTotal = Cortio.Data:GetClassInterruptCD(rosterData.class) or 15 end

    local now = GetTime()
    rosterData.cdEnd = now + cdTotal
    rosterData.cdTotal = cdTotal
    rosterData.lastResult = "USED"

    print("|cFF00FFFF[Cortio]|r |cFF00FF00SIGNAL MATCH|r " .. matchedPlayer
        .. " interrupted! cd=" .. cdTotal .. "s")

    if Cortio.UI then Cortio.UI:UpdatePanel() end
    Cortio.StartPanelTicker()
end

local function CorrelateSignals()
    local now = GetTime()
    if not needsCorrelation then return end
    if now - lastCorrelateAt < CORRELATE_INTERVAL then return end
    lastCorrelateAt = now
    PruneSignalTape(now)

    local casts      = {}
    local interrupts = {}
    local auras      = {}

    for i = 1, #signalTape do
        local s = signalTape[i]
        if s and not s.consumed then
            if s.kind == "cast"      then casts[#casts + 1] = s
            elseif s.kind == "interrupt" then interrupts[#interrupts + 1] = s
            elseif s.kind == "aura"      then auras[#auras + 1] = s
            end
        end
    end

    if #interrupts == 0 or #casts == 0 then
        needsCorrelation = false
        return
    end

    -- Take the freshest interrupt signal
    table.sort(interrupts, function(a, b) return (a.at or 0) < (b.at or 0) end)
    local freshest = interrupts[#interrupts]

    -- If multiple interrupt signals arrived nearly simultaneously (<18ms),
    -- it's likely a multi-hit (AoE stun, etc.) — suppress all of them
    local clustered = 0
    for i = 1, #interrupts do
        if math.abs((interrupts[i].at or 0) - (freshest.at or 0)) <= 0.018 then
            clustered = clustered + 1
        end
    end
    if clustered > 1 then
        for i = 1, #interrupts do interrupts[i].consumed = true end
        needsCorrelation = false
        return
    end

    -- Suppress if an aura event on the same nameplate arrived within 28ms
    -- (indicates a buff/debuff change, not a real interrupt)
    for i = 1, #auras do
        if auras[i].unit == freshest.unit then
            if math.abs((freshest.at or 0) - (auras[i].at or 0)) <= AURA_SUPPRESS then
                freshest.consumed = true
                needsCorrelation = false
                return
            end
        end
    end

    -- Find the best matching cast signal within 55ms window
    local bestCast = nil
    local bestDiff = math.huge
    for i = 1, #casts do
        local diff = math.abs((freshest.at or 0) - (casts[i].at or 0))
        if diff <= MATCH_WINDOW and diff < bestDiff then
            bestDiff = diff
            bestCast = casts[i]
        end
    end

    freshest.consumed = true

    if bestCast then
        bestCast.consumed = true
        local memberName, ownerUnit = ResolvePartyName(bestCast.unit)
        if memberName and ownerUnit then
            TriggerPartyCooldown(ownerUnit, memberName)
        end

        print("|cFF00FFFF[Cortio]|r |cFF88FFAA[CORR]|r matched cast(" 
            .. tostring(bestCast.unit) .. ") ↔ interrupt(" 
            .. tostring(freshest.unit) .. ") Δ=" 
            .. string.format("%.3f", bestDiff) .. "s")
    end

    needsCorrelation = false
end

-- ============================================================
-- Unified interrupt detection frame
-- Handles: party casts, nameplate interrupts, nameplate auras
-- ============================================================
local _interruptFrame = CreateFrame("Frame")
_interruptFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
_interruptFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
_interruptFrame:RegisterEvent("UNIT_AURA")

_interruptFrame:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not unit then return end

        -- Own player/pet: detect interrupt spell IMMEDIATELY (like BliZzi).
        -- This catches both successful AND failed kicks.
        -- The CD polling ticker is a backup; this is the primary detection.
        if unit == "player" or unit == "pet" then
            local _, spellID = ...
            if spellID then
                local spellName = Cortio.Taint:SafeResolveSpell(spellID)
                if spellName and Cortio.Data.INTERRUPT_NAME_TO_CD[spellName] then
                    -- Push signal for correlation (confirms success if nameplate fires too)
                    recentCasts["__player"] = { t = GetTime(), spellID = 0 }
                    PushSignal("cast", "player")
                    
                    -- DIRECT CD update (like BliZzi's OnOwnKick)
                    local cdDur = Cortio.Data.INTERRUPT_NAME_TO_CD[spellName]
                    local now = GetTime()
                    local playerName = UnitName("player")
                    if playerName and Cortio.RosterList then
                        for rName, rData in pairs(Cortio.RosterList) do
                            local short = strsplit("-", rName) or rName
                            if short == playerName or rName == playerName then
                                rData.cdEnd = now + cdDur
                                rData.cdTotal = cdDur
                                rData.lastResult = "USED"
                                break
                            end
                        end
                    end
                    if Cortio.UI then Cortio.UI:UpdatePanel() end
                    Cortio.StartPanelTicker()
                    pcall(Cortio.UI.UpdateKickCooldown, Cortio.UI)
                    
                    -- Broadcast to party
                    Cortio.Net:SendGroupMessage("V1|CD|" .. cdDur, "CD")
                    
                    print("|cFF00FFFF[Cortio]|r |cFF00FF00OWN KICK|r " .. spellName .. " cd=" .. cdDur .. "s")
                end
            end
            return
        end

        -- Only party/partypet units
        if not unit:find("^party") then return end

        local memberName, ownerUnit = ResolvePartyName(unit)
        if not memberName then return end

        -- Try to resolve the spell (may fail if tainted — that's OK)
        local _, spellID = ...
        local spellName = nil
        if spellID then
            spellName = Cortio.Taint:SafeResolveSpell(spellID)
        end

        if spellName and Cortio.Data.INTERRUPT_NAME_TO_CD[spellName] then
            -- Clean spell name resolved! Record as a known interrupt cast.
            local cls = Cortio.Data.INTERRUPT_NAME_TO_CLASS[spellName]
            local sid = Cortio.Data.CLASS_INTERRUPT_SPELLID[cls] or 0
            recentCasts[memberName] = { t = GetTime(), spellID = sid }
            PushSignal("cast", unit)
        else
            -- Spell name is tainted or not an interrupt.
            -- FALLBACK (BliZzi approach): Use the registered interrupt for
            -- this player — but ONLY if their interrupt is NOT currently on CD.
            local matchedPlayer = FindRosterPlayerByGUIDOrName(nil, memberName)
            if not matchedPlayer then
                local okG, guid = pcall(UnitGUID, unit)
                if okG and guid then
                    matchedPlayer = FindRosterPlayerByGUIDOrName(guid, memberName)
                end
            end
            if matchedPlayer then
                local rosterData = Cortio.RosterList[matchedPlayer]
                if rosterData then
                    local isOnCD = rosterData.cdEnd and rosterData.cdEnd > GetTime()
                    if not isOnCD then
                        local sid = Cortio.Data.CLASS_INTERRUPT_SPELLID[rosterData.class]
                        if sid then
                            recentCasts[memberName] = { t = GetTime(), spellID = sid }
                            PushSignal("cast", unit)
                        end
                    end
                end
            end
        end

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- Only care about nameplate units (mobs being interrupted)
        if unit and unit:find("^nameplate") then
            PushSignal("interrupt", unit)
        end

    elseif event == "UNIT_AURA" then
        -- Only care about nameplate units (for false-positive suppression)
        if unit and unit:find("^nameplate") then
            PushSignal("aura", unit)
        end
    end
end)

-- Run correlation every frame via OnUpdate
_interruptFrame:SetScript("OnUpdate", function()
    if needsCorrelation then
        CorrelateSignals()
    end
end)

-- ============================================================
-- CLEAN CD POLLING TICKER: detects OWN interrupts WITHOUT any tainted data
-- Runs in a clean execution context (initialized at module load).
-- Reads only clean data: UnitName("player"), static spellID tables,
-- and C_Spell.GetSpellCooldown with clean spell IDs.
-- Handles: local UI update + SendAddonMessage + SendChatMessage fallback
-- ============================================================
local _cleanLastCDStart = 0
local _cleanLastBroadcastTime = 0

C_Timer.After(3, function()
    C_Timer.NewTicker(0.3, function()
        -- Get player info from CLEAN sources
        local playerName = UnitName("player")
        local _, playerClass = UnitClass("player")
        if not playerName or not playerClass then return end
        
        -- Get the interrupt spell ID from STATIC table (clean data)
        local interruptSpellID = Cortio.Data.CLASS_INTERRUPT_SPELLID[playerClass]
        if not interruptSpellID then return end
        
        -- Check the cooldown of OUR OWN interrupt (clean API call with clean spellID)
        local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, interruptSpellID)
        if not ok or not cdInfo then return end
        
        local duration = cdInfo.duration
        local startTime = cdInfo.startTime
        if not duration or not startTime then return end
        
        -- Clean the values just in case
        local cleanDur = tonumber(tostring(duration))
        local cleanStart = tonumber(tostring(startTime))
        if not cleanDur or not cleanStart then return end
        
        -- Check if interrupt is on CD (>1.5s to exclude GCD)
        if cleanDur > 1.5 and cleanStart > 0 then
            -- Is this a NEW cooldown start?
            if math.abs(cleanStart - _cleanLastCDStart) > 1 then
                _cleanLastCDStart = cleanStart
                
                -- Throttle
                local now = GetTime()
                if now - _cleanLastBroadcastTime < 2 then return end
                _cleanLastBroadcastTime = now
                
                local cdDur = math.floor(cleanDur + 0.5)
                
                -- === UPDATE LOCAL UI ===
                if Cortio.RosterList then
                    for rName, rData in pairs(Cortio.RosterList) do
                        local short = strsplit("-", rName) or rName
                        if short == playerName or rName == playerName then
                            rData.cdEnd = now + cdDur
                            rData.cdTotal = cdDur
                            break
                        end
                    end
                end
                Cortio.UI:UpdatePanel()
                Cortio.StartPanelTicker()
                pcall(Cortio.UI.UpdateKickCooldown, Cortio.UI)
                
                -- === BROADCAST via SendAddonMessage (keep trying, might work outside instances) ===
                Cortio.Net:SendGroupMessage("V1|CD|" .. cdDur, "CD")
                
                if CortioDB and CortioDB.debugLogs then print("|cFF00FFFF[Cortio]|r |cFF00FF00CLEAN INTERRUPT|r CD=" .. cdDur .. "s") end
            end
        end
    end)
end)

-- ============================================================
-- PARTY WATCHER SETUP (backward-compat stub)
-- Signal Correlation uses _interruptFrame which listens globally
-- for UNIT_SPELLCAST_SUCCEEDED, UNIT_SPELLCAST_INTERRUPTED, UNIT_AURA.
-- No per-unit registration needed — this function is a no-op.
-- ============================================================
function Cortio.RegisterPartyInterruptWatchers()
    if Cortio._partyFrame2 then Cortio._partyFrame2:UnregisterAllEvents() end
end

C_Timer.After(2, function() Cortio.RegisterPartyInterruptWatchers() end)


-- Smart panel ticker: only runs when CDs are active
Cortio.PanelTicker = nil

function Cortio.StartPanelTicker()
    if Cortio.PanelTicker then return end
    Cortio.PanelTicker = C_Timer.NewTicker(0.25, function()
        if Cortio.UI.Panel and Cortio.UI.Panel:IsShown() then
            Cortio.UI:UpdatePanel()
        end
        Cortio.UI:UpdateAllNameplates()
        
        local hasWork = false
        local now = GetTime()
        for _, data in pairs(Cortio.RosterList) do
            if data.cdEnd and data.cdEnd > now then
                hasWork = true
                break
            end
        end
        if not hasWork then
            for _ in pairs(Cortio.UI.ActiveNameplates) do
                hasWork = true
                break
            end
        end
        if not hasWork and not (Cortio.UI.Panel and Cortio.UI.Panel:IsShown()) then
            Cortio.PanelTicker:Cancel()
            Cortio.PanelTicker = nil
        end
    end)
end

hooksecurefunc(Cortio.UI, "UpdatePanel", function()
    local now = GetTime()
    for _, data in pairs(Cortio.RosterList) do
        if data.cdEnd and data.cdEnd > now then
            Cortio.StartPanelTicker()
            return
        end
    end
end)

print("|cFF00FFFF[Cortio]|r Cargado. Asigna la tecla en: ESC -> Atajos -> AddOns -> Cortio")
