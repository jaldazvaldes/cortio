BINDING_HEADER_INTERRUPTIO_HEADER = "Interruptio - Asignacion de Cortes"
BINDING_NAME_CLICK_InterruptioMarkSABT_LeftButton = "Poner/Quitar Marca de Corte"

Interruptio = Interruptio or {}

-- Prefix registration moved to PLAYER_ENTERING_WORLD for reliability

-- Taint debug: detect ADDON_ACTION_BLOCKED
local blockedFrame = CreateFrame("Frame")
blockedFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
blockedFrame:SetScript("OnEvent", function(_, _, addon, func)
    if addon == "Interruptio" then
        Interruptio.Data:LogError("TAINT", "Action blocked: " .. tostring(func))
        print("|cFF00FFFF[Interruptio]|r |cFFFF0000TAINT: Action blocked:|r " .. tostring(func))
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
        for pName, data in pairs(Interruptio.RosterList) do
            if data.guid and data.guid == sourceGUID then
                return pName, "GUID"
            end
        end
    end

    -- 2. Exact full name match
    if sourceName then
        if Interruptio.RosterList[sourceName] then
            return sourceName, "FullName"
        end

        -- 3. Ambiguate match (handles cross-realm names)
        local ambigSource = Ambiguate(sourceName, "short")
        if Interruptio.RosterList[ambigSource] then
            return ambigSource, "Ambiguate"
        end

        -- 4. Short name match (least reliable, last resort)
        local shortName = Interruptio.Data:ShortName(sourceName)
        for pName, _ in pairs(Interruptio.RosterList) do
            if Ambiguate(pName, "short") == ambigSource then
                return pName, "AmbiguateLoop"
            end
        end
        for pName, _ in pairs(Interruptio.RosterList) do
            if Interruptio.Data:ShortName(pName) == shortName then
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

-- Debug toggle (enable with InterruptioDB.debugCombatLog = true or /it debugcl)
local function DebugCL(...)
    if not InterruptioDB or not InterruptioDB.debugCombatLog then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    print("|cFF00FFFF[Interruptio]|r |cFFAADDFF[CL]|r " .. table.concat(parts, " "))
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
eventFrame:RegisterEvent("RAID_TARGET_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, ...)

    if event == "PLAYER_ENTERING_WORLD" then
        Interruptio.Roster:EnsurePlayerInfo()
        
        -- Register addon message prefix (verified at each zone load)
        if not C_ChatInfo.IsAddonMessagePrefixRegistered(Interruptio.Data.COMM_PREFIX) then
            local regOk = C_ChatInfo.RegisterAddonMessagePrefix(Interruptio.Data.COMM_PREFIX)
            if not regOk then
                C_Timer.After(2, function()
                    C_ChatInfo.RegisterAddonMessagePrefix(Interruptio.Data.COMM_PREFIX)
                end)
            end
        end
        
        Interruptio.Marks.Active = {}
        for unit, _ in pairs(Interruptio.UI.ActiveNameplates) do
            Interruptio.UI:ReleaseNameplateFrame(unit)
        end
        
        if not InterruptioDB then InterruptioDB = {} end
        if not InterruptioDB.errors then InterruptioDB.errors = {} end
        
        Interruptio.Roster:RebuildWithRetry()
        Interruptio.Roster:AutoRegisterByClass()
        Interruptio.Roster:RegisterPartyWatchers()
        Interruptio.Marks:QueueSecureBtnUpdate()
        
        C_Timer.After(1, function() Interruptio.Roster:AutoRegisterByClass(); Interruptio.Roster:RegisterPartyWatchers() end)
        C_Timer.After(2, function() Interruptio.Net:SendGroupMessage("V1|SYNCREQ", "SyncReq") end)
        C_Timer.After(3, function() Interruptio.Roster:AutoRegisterByClass(); Interruptio.Roster:RegisterPartyWatchers(); Interruptio.UI:UpdatePanel() end)
        C_Timer.After(5, function() Interruptio.Net:SendGroupMessage("V1|SYNCREQ", "SyncReq") end)
        
        Interruptio.UI:SetupKickIcon()
        
        C_Timer.After(0.5, function()
            if InterruptioDB and InterruptioDB.scale then Interruptio.UI.Panel:SetScale(InterruptioDB.scale) end
            Interruptio.UI:CreateSettingsMenu()
        end)
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        Interruptio.Marks:QueueSecureBtnUpdate()
        
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then
        Interruptio.UI:UpdateNameplate(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" or event == "FORBIDDEN_NAME_PLATE_UNIT_REMOVED" then
        for _, mark in ipairs(Interruptio.Marks.Active) do
            if mark.nameplateUnit == arg1 then
                mark.nameplateUnit = nil
            end
        end
        Interruptio.UI:ReleaseNameplateFrame(arg1)
        
    elseif event == "GROUP_ROSTER_UPDATE" then
        Interruptio.SetActive(not IsInRaid())
        if not Interruptio._active then return end
        Interruptio.Roster:Rebuild()
        Interruptio.Roster:AutoRegisterByClass()
        Interruptio.Roster:RegisterPartyWatchers()
        Interruptio.RegisterPartyInterruptWatchers()
        Interruptio.UI:UpdatePanel()
        if not InCombatLockdown() then
            Interruptio.Marks:QueueSecureBtnUpdate()
        end
        C_Timer.After(1, function()
            if not Interruptio._active then return end
            Interruptio.Roster:RegisterPartyWatchers()
            Interruptio.Roster:AutoRegisterByClass()
            Interruptio.RegisterPartyInterruptWatchers()
            Interruptio.UI:UpdatePanel()
            Interruptio.Net:SendGroupMessage("V1|SYNCREQ", "SyncReq")
        end)
        C_Timer.After(3, function()
            if not Interruptio._active then return end
            Interruptio.Roster:RegisterPartyWatchers()
            Interruptio.Roster:AutoRegisterByClass()
            Interruptio.RegisterPartyInterruptWatchers()
        end)


        
    elseif event == "INSPECT_READY" then
        Interruptio.Roster:OnInspectReady(arg1)

    elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        Interruptio.Roster:Rebuild()
        Interruptio.Roster:AutoRegisterByClass()
        Interruptio.UI:UpdatePanel()
        Interruptio.UI:SetupKickIcon()

    elseif event == "RAID_TARGET_UPDATE" then
        -- Raid marker icons changed on mobs — refresh nameplate matching
        Interruptio.Data:SafeCall("RaidTargetUpdate", function()
            Interruptio.UI:UpdateAllNameplates()
        end)

    elseif event == "UNIT_DIED" then
        local cleared = false
        local ok, isTargetStr = pcall(function() return arg1 == "target" end)
        isTargetStr = ok and isTargetStr
        
        for i = #Interruptio.Marks.Active, 1, -1 do
            local mark = Interruptio.Marks.Active[i]
            local shouldClear = false

            if mark.nameplateUnit then
                if Interruptio.Taint:SafeIsMatch(mark.nameplateUnit, arg1) then
                    shouldClear = true
                end
            end

            if not shouldClear and mark.playerName == Interruptio.PlayerName and not mark.nameplateUnit then
                if isTargetStr or Interruptio.Taint:SafeIsMatch(arg1, "target") then
                    shouldClear = true
                end
            end

            if shouldClear then
                if mark.playerName == Interruptio.PlayerName then
                    Interruptio.Net:SendGroupMessage("V1|UNMARK", "Send")
                end
                table.remove(Interruptio.Marks.Active, i)
                cleared = true
            end
        end
        if cleared then Interruptio.UI:UpdatePanel() end
        
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == Interruptio.Data.COMM_PREFIX then
            local _, sender = ...
            if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFF00FF00ADDON_MSG|r prefix=" .. tostring(arg1) .. " msg=" .. tostring(arg2) .. " sender=" .. tostring(sender)) end
            if not sender then return end
            local ambigSender = Ambiguate(sender, "short")
            local ambigPlayer = Interruptio.PlayerName and Ambiguate(Interruptio.PlayerName, "short") or ""
            if sender == Interruptio.PlayerName or ambigSender == ambigPlayer then
                if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r ADDON_MSG filtered (self): " .. tostring(sender)) end
                return
            end
            
            Interruptio.Net:LogReceived(arg1, arg2, sender)
            
            -- V1 protocol uses | separator; legacy uses :
            local version, action, p2, p3, p4, p5, p6
            if arg2:sub(1, 3) == "V1|" then
                version, action, p2, p3, p4, p5, p6 = strsplit("|", arg2, 7)
            else
                action, p2, p3, p4, p5, p6 = strsplit(":", arg2, 7)
            end
            local rPlayer = FindRosterPlayer(sender) or sender
            
            if action == "SYNCREQ" then
                C_Timer.After(0.5 + math.random() * 1.5, function() Interruptio.Marks:BroadcastCurrentMark() end)
            elseif action == "CD" then
                local cdDuration = tonumber(p2)
                if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFFFFFF00CD RECEIVED|r from=" .. tostring(rPlayer) .. " dur=" .. tostring(cdDuration) .. " inRoster=" .. tostring(Interruptio.RosterList[rPlayer] ~= nil)) end
                if cdDuration and cdDuration > 0 then
                    Interruptio.Data:SafeCall("Remote_CD", function()
                        local now = GetTime()
                        for _, mark in ipairs(Interruptio.Marks.Active) do
                            if mark.playerName == rPlayer then
                                mark.remoteCDEnd = now + cdDuration
                                mark.remoteCDDuration = cdDuration
                            end
                        end
                        if Interruptio.RosterList[rPlayer] then
                            Interruptio.RosterList[rPlayer].cdEnd = now + cdDuration
                            Interruptio.RosterList[rPlayer].cdTotal = cdDuration
                            if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFF00FF00CD SET|r " .. rPlayer .. " cdEnd=" .. string.format("%.1f", now + cdDuration) .. " total=" .. cdDuration) end
                        else
                            if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFFFF0000CD FAIL|r player '" .. rPlayer .. "' NOT in RosterList") end
                        end
                        Interruptio.UI:UpdatePanel()
                        Interruptio.StartPanelTicker()
                    end)
                end
            elseif action and p2 and p3 then
                local cls, specIcon, markIdStr, markerSlotStr = p2, p3, p4, p5
                local tGUID = (p6 and p6 ~= "") and p6 or nil
                local mId = markIdStr and tonumber(markIdStr) or nil
                local markerSlot = markerSlotStr and tonumber(markerSlotStr) or 0
                if action == "MARK" then
                    Interruptio.Marks:ClearPlayerMark(rPlayer)

                    local ourSlotBefore = Interruptio.Marks:GetPlayerMarkerSlotSafe()

                    local uToken = nil
                    for i = 1, 4 do
                        local u = "party" .. i
                        if UnitExists(u) then
                            if Interruptio.RosterList[rPlayer] and Interruptio.RosterList[rPlayer].unit == u then
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
                    table.insert(Interruptio.Marks.Active, newMark)

                    local ourSlotFixed = not InterruptioDB or (InterruptioDB.markerSlot or 0) == 0
                    if ourSlotFixed and markerSlot > 0 and markerSlot == ourSlotBefore then
                        Interruptio.Marks:QueueSecureBtnUpdate()
                    end
                elseif action == "UNMARK" then
                    Interruptio.Marks:ClearPlayerMark(rPlayer)
                end
                Interruptio.UI:UpdatePanel()
                Interruptio.UI:UpdateAllNameplates()
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

chatFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if not arg1 then return end
    
    -- WoW 12.0: chat message text can be tainted.
    -- Strategy: use string.format + pcall to detaint, same as BliZzi's SafeUnitName.
    local ok1, cleanText = pcall(string.format, "%s", arg1)
    if not ok1 or not cleanText then return end
    
    -- Verify detainted text is usable
    local ok2 = pcall(rawset, {}, cleanText, true)
    if not ok2 then return end
    
    -- Parse macro format: "[Interruptio] Assigned {rt8} (Annarya)"
    local slotStr, playerName = string.match(cleanText, "%[Interruptio%] Assigned %{rt(%d+)%} %((.-)%)")
    if not slotStr or not playerName then return end
    
    local slot = tonumber(slotStr)
    if not slot or slot <= 0 then return end
    
    if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFFFF88FF[CHAT SYNC]|r Received mark: {rt" .. slot .. "} → " .. playerName) end
    
    -- Don't skip own messages — we need self-consistency.
    -- But DO skip if we already processed this mark locally.
    local myShort = Interruptio.PlayerName and Interruptio.Data:ShortName(Interruptio.PlayerName) or ""
    
    -- Find player in roster (try multiple match strategies)
    local rPlayer = nil
    if Interruptio.RosterList then
        for rName, _ in pairs(Interruptio.RosterList) do
            local short = Interruptio.Data:ShortName(rName)
            if short == playerName then
                rPlayer = rName
                break
            end
        end
        -- Fallback: try Ambiguate
        if not rPlayer then
            for rName, _ in pairs(Interruptio.RosterList) do
                if Ambiguate(rName, "short") == playerName then
                    rPlayer = rName
                    break
                end
            end
        end
    end
    
    if not rPlayer then
        if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFFFF8800[CHAT SYNC]|r Player '" .. playerName .. "' not in roster") end
        return
    end
    
    if not Interruptio.RosterList[rPlayer] then return end
    
    -- Skip if this is our own mark (we already processed it locally)
    local short = Interruptio.Data:ShortName(rPlayer)
    if short == myShort then return end
    
    Interruptio.Marks:ClearPlayerMark(rPlayer)
    
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
    
    local rClass = Interruptio.RosterList[rPlayer].class or "UNKNOWN"
    table.insert(Interruptio.Marks.Active, {
        playerName = rPlayer,
        playerClass = rClass,
        specIcon = "0", 
        remoteCDEnd = 0,
        remoteCDDuration = 0,
        nameplateUnit = nil,
        unitToken = uToken,
        markerSlot = slot
    })
    
    Interruptio.UI:UpdatePanel()
    Interruptio.UI:UpdateAllNameplates()
    if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFF00FF00[CHAT SYNC]|r ✓ Assigned {rt" .. slot .. "} to " .. rPlayer) end
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
        if okCls and engClass and Interruptio.Data.CLASS_INTERRUPT_SPELLID[engClass] then
            Interruptio.RosterList[memberName] = {
                unit = unit, guid = (okG and guid) or nil, class = engClass,
                specIcon = "0", specId = 0, cdEnd = 0, cdTotal = 0, lastResult = nil,
            }
            matchedPlayer = memberName
            if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFF00FF00SIGNAL|r Auto-registered: " .. memberName .. " class=" .. engClass) end
        end
    end

    if not matchedPlayer then return end

    local rosterData = Interruptio.RosterList[matchedPlayer]
    if not rosterData then return end

    -- Compute cooldown
    local cdTotal
    if rosterData.specId and rosterData.specId > 0 and Interruptio.Data.SPEC_INTERRUPTS then
        local specData = Interruptio.Data.SPEC_INTERRUPTS[rosterData.specId]
        if specData then cdTotal = specData.baseCD end
    end
    if not cdTotal then cdTotal = Interruptio.Data:GetClassInterruptCD(rosterData.class) or 15 end

    local now = GetTime()
    rosterData.cdEnd = now + cdTotal
    rosterData.cdTotal = cdTotal
    rosterData.lastResult = "USED"

    if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFF00FF00SIGNAL MATCH|r " .. matchedPlayer .. " interrupted! cd=" .. cdTotal .. "s") end

    if Interruptio.UI then Interruptio.UI:UpdatePanel() end
    Interruptio.StartPanelTicker()
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

        if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFF88FFAA[CORR]|r matched cast(" .. tostring(bestCast.unit) .. ") ↔ interrupt(" .. tostring(freshest.unit) .. ") Δ=" .. string.format("%.3f", bestDiff) .. "s") end
    end

    needsCorrelation = false
end

-- ============================================================
-- Unified interrupt detection frame
-- Handles: party casts, nameplate interrupts, nameplate auras
-- ============================================================
local _interruptFrame = CreateFrame("Frame")

-- ============================================================
-- Interruptio.SetActive: single point of control for raid disable
-- Registers/unregisters events instead of checking IsInRaid()
-- every frame — zero CPU overhead when inactive.
-- ============================================================
Interruptio._active = false
function Interruptio.SetActive(active)
    if active == Interruptio._active then return end
    Interruptio._active = active
    if active then
        _interruptFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        _interruptFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        _interruptFrame:RegisterEvent("UNIT_AURA")
    else
        _interruptFrame:UnregisterAllEvents()
        if Interruptio.UI and Interruptio.UI.Panel then Interruptio.UI.Panel:Hide() end
        if Interruptio.PanelTicker then Interruptio.PanelTicker:Cancel(); Interruptio.PanelTicker = nil end
    end
end
-- Start active (solo/party). GROUP_ROSTER_UPDATE will deactivate in raids.
Interruptio.SetActive(true)

_interruptFrame:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not unit then return end

        -- Own player/pet: detect interrupt spell IMMEDIATELY (like BliZzi).
        -- This catches both successful AND failed kicks.
        -- The CD polling ticker is a backup; this is the primary detection.
        if unit == "player" or unit == "pet" then
            local _, spellID = ...
            if spellID then
                local spellName = Interruptio.Taint:SafeResolveSpell(spellID)
                if spellName and Interruptio.Data.INTERRUPT_NAME_TO_CD[spellName] then
                    -- Push signal for correlation (confirms success if nameplate fires too)
                    PushSignal("cast", "player")
                    
                    -- DIRECT CD update (like BliZzi's OnOwnKick)
                    local cdDur = Interruptio.Data.INTERRUPT_NAME_TO_CD[spellName]
                    local now = GetTime()
                    local playerName = UnitName("player")
                    if playerName and Interruptio.RosterList then
                        for rName, rData in pairs(Interruptio.RosterList) do
                            local short = strsplit("-", rName) or rName
                            if short == playerName or rName == playerName then
                                rData.cdEnd = now + cdDur
                                rData.cdTotal = cdDur
                                rData.lastResult = "USED"
                                break
                            end
                        end
                    end
                    if Interruptio.UI then Interruptio.UI:UpdatePanel() end
                    Interruptio.StartPanelTicker()
                    pcall(Interruptio.UI.UpdateKickCooldown, Interruptio.UI)
                    
                    -- Broadcast to party
                    Interruptio.Net:SendGroupMessage("V1|CD|" .. cdDur, "CD")
                    
                    if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFF00FF00OWN KICK|r " .. spellName .. " cd=" .. cdDur .. "s") end
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
            spellName = Interruptio.Taint:SafeResolveSpell(spellID)
        end

        if spellName and Interruptio.Data.INTERRUPT_NAME_TO_CD[spellName] then
            -- Clean spell name resolved → push signal for correlation
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
                local rosterData = Interruptio.RosterList[matchedPlayer]
                if rosterData then
                    local isOnCD = rosterData.cdEnd and rosterData.cdEnd > GetTime()
                    if not isOnCD then
                        local sid = Interruptio.Data.CLASS_INTERRUPT_SPELLID[rosterData.class]
                        if sid then
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
        if not Interruptio._active then return end

        -- Get player info from CLEAN sources
        local playerName = UnitName("player")
        local _, playerClass = UnitClass("player")
        if not playerName or not playerClass then return end
        
        -- Get the interrupt spell ID from STATIC table (clean data)
        local interruptSpellID = Interruptio.Data.CLASS_INTERRUPT_SPELLID[playerClass]
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
            -- Is this a NEW cooldown start or a CD reduction shift?
            if math.abs(cleanStart - _cleanLastCDStart) > 0.5 then
                _cleanLastCDStart = cleanStart
                
                local now = GetTime()
                local exactCDEnd = cleanStart + cleanDur
                local remaining = exactCDEnd - now
                
                -- Si ya expiró, no re-transmitir
                if remaining > 0 then
                    if now - _cleanLastBroadcastTime < 0.5 then return end
                    _cleanLastBroadcastTime = now
                    
                    -- === UPDATE LOCAL UI ===
                    if Interruptio.RosterList then
                        for rName, rData in pairs(Interruptio.RosterList) do
                            local short = strsplit("-", rName) or rName
                            if short == playerName or rName == playerName then
                                rData.cdEnd = exactCDEnd
                                rData.cdTotal = cleanDur
                                break
                            end
                        end
                    end
                    Interruptio.UI:UpdatePanel()
                    Interruptio.StartPanelTicker()
                    pcall(Interruptio.UI.UpdateKickCooldown, Interruptio.UI)
                    
                    -- === BROADCAST ===
                    -- Enviamos el TIEMPO RESTANTE real para que el cliente sincronice su cdEnd = now + remaining
                    Interruptio.Net:SendGroupMessage("V1|CD|" .. string.format("%.2f", remaining), "CD")
                    
                    if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFF00FF00CLEAN INTERRUPT|r rem=" .. remaining) end
                end
            end
        end
    end)
end)

-- RegisterPartyInterruptWatchers: no-op (Signal Correlation handles everything)
function Interruptio.RegisterPartyInterruptWatchers() end


-- Smart panel ticker: only runs when CDs are active
Interruptio.PanelTicker = nil

function Interruptio.StartPanelTicker()
    if Interruptio.PanelTicker then return end
    -- Aumentamos el tick rate drásticamente (30 actualizaciones por segundo) 
    -- para asegurar que la bajada de las barras sea completamente fluida y suave.
    Interruptio.PanelTicker = C_Timer.NewTicker(0.033, function()
        if Interruptio.UI.Panel and Interruptio.UI.Panel:IsShown() then
            -- Llamar UpdatePanel() a 30fps es muy barato al ser solo para 5 mienbros de party.
            Interruptio.UI:UpdatePanel()
        end
        Interruptio.UI:UpdateAllNameplates()
        
        local hasWork = false
        local now = GetTime()
        for _, data in pairs(Interruptio.RosterList) do
            if data.cdEnd and data.cdEnd > now then
                hasWork = true
                break
            end
        end
        if not hasWork then
            for _ in pairs(Interruptio.UI.ActiveNameplates) do
                hasWork = true
                break
            end
        end
        if not hasWork and not (Interruptio.UI.Panel and Interruptio.UI.Panel:IsShown()) then
            Interruptio.PanelTicker:Cancel()
            Interruptio.PanelTicker = nil
        end
    end)
end

hooksecurefunc(Interruptio.UI, "UpdatePanel", function()
    local now = GetTime()
    for _, data in pairs(Interruptio.RosterList) do
        if data.cdEnd and data.cdEnd > now then
            Interruptio.StartPanelTicker()
            return
        end
    end
end)

print("|cFF00FFFF[Interruptio]|r Cargado. Asigna la tecla en: ESC -> Atajos -> AddOns -> Interruptio")
