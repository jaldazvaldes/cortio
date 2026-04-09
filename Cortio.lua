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
            if not sender then return end
            local ambigSender = Ambiguate(sender, "short")
            local ambigPlayer = Cortio.PlayerName and Ambiguate(Cortio.PlayerName, "short") or ""
            if sender == Cortio.PlayerName or ambigSender == ambigPlayer then return end
            
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
                        end
                        for _, f in pairs(Cortio.UI.ActiveNameplates) do
                            if f and f.icons then
                                for _, ic in ipairs(f.icons) do
                                    if ic:IsShown() and ic.ownerName == rPlayer and not ic.isLocal then
                                        ic.cooldown:SetCooldown(now, cdDuration)
                                    end
                                end
                            end
                        end
                        Cortio.UI:UpdatePanel()
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
-- LOCAL PLAYER: interrupt detection with precise CD (proven working)
-- ============================================================
local lastInterruptBroadcastTime = 0
local castDetectFrame = CreateFrame("Frame")
castDetectFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
castDetectFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    if not spellID then return end
    local cleanSpell = Cortio.Taint:ResolveNumber(spellID)
    if not cleanSpell then return end
    
    local okSpell, spellName = pcall(C_Spell.GetSpellName, cleanSpell)
    if not okSpell or not spellName then return end
    if not Cortio.Data.INTERRUPT_NAME_TO_CD[spellName] then return end
    if not Cortio.PlayerClass then return end

    local now = GetTime()
    if now - lastInterruptBroadcastTime < 1 then return end
    lastInterruptBroadcastTime = now

    local cdDuration = Cortio.Data:GetClassInterruptCD(Cortio.PlayerClass)
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and info and info.duration then
        local cleanDuration = Cortio.Taint:ResolveNumber(info.duration)
        if cleanDuration and cleanDuration > 1.5 then
            cdDuration = math.floor(cleanDuration + 0.5)
        end
    end

    if Cortio.RosterList[Cortio.PlayerName] then
        Cortio.RosterList[Cortio.PlayerName].cdEnd   = now + cdDuration
        Cortio.RosterList[Cortio.PlayerName].cdTotal = cdDuration
    end

    Cortio.UI:UpdatePanel()
    Cortio.UI:UpdateKickCooldown()
    Cortio.Net:SendGroupMessage("V1|CD|"..cdDuration, "CD")
end)

-- ============================================================
-- REMOTE PARTY: detect party member interrupts via UNIT_SPELLCAST_SUCCEEDED
-- (Confirmed working in WoW 12.0 - events DO fire for party members)
-- ============================================================
local partyInterruptFrame = CreateFrame("Frame")

function Cortio.RegisterPartyInterruptWatchers()
    partyInterruptFrame:UnregisterAllEvents()
    if Cortio._partyFrame2 then Cortio._partyFrame2:UnregisterAllEvents() end
    if not IsInGroup() then return end
    
    local units = {}
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            table.insert(units, u)
        end
    end
    
    if #units == 0 then return end
    
    -- RegisterUnitEvent takes up to 2 unit args per call
    if #units <= 2 then
        partyInterruptFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", units[1], units[2])
    else
        partyInterruptFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", units[1], units[2])
        if not Cortio._partyFrame2 then
            Cortio._partyFrame2 = CreateFrame("Frame")
            Cortio._partyFrame2:SetScript("OnEvent", function(self, ev, unit, castGUID, spellID)
                Cortio.HandleRemoteInterrupt(unit, castGUID, spellID)
            end)
        end
        if #units == 3 then
            Cortio._partyFrame2:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", units[3])
        else
            Cortio._partyFrame2:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", units[3], units[4])
        end
    end
    
    local regOk = partyInterruptFrame:IsEventRegistered("UNIT_SPELLCAST_SUCCEEDED")
    print("|cFF00FFFF[Cortio]|r Party watchers: " .. #units .. " units | reg=" .. tostring(regOk) .. " | units=" .. table.concat(units, ","))
end

local _remoteEventCount = 0
local _remoteInterruptHits = 0
function Cortio.HandleRemoteInterrupt(unit, castGUID, spellID)
    if not spellID or not unit then return end
    -- WoW 12.0: party spellIDs are tainted. Use string.match to create untainted copy
    local cleanSpell
    pcall(function()
        local rawStr = tostring(spellID)
        local numStr = rawStr and rawStr:match("(%d+)")
        if numStr then cleanSpell = tonumber(numStr) end
    end)
    if not cleanSpell then return end
    
    -- Check if this spell is a known interrupt
    local interruptData = Cortio.Data.ALL_INTERRUPTS[cleanSpell]
    if not interruptData then
        local okSpell, spellName = pcall(C_Spell.GetSpellName, cleanSpell)
        if not (okSpell and spellName and Cortio.Data.INTERRUPT_NAME_TO_CD[spellName]) then
            return
        end
    end

    -- === INTERRUPT DETECTED ===
    _remoteInterruptHits = _remoteInterruptHits + 1
    
    -- Identify the player
    local okName, uName, uRealm = pcall(UnitName, unit)
    if not okName or not uName then
        if _remoteInterruptHits <= 5 then print("|cFFFF0000[Cortio] FAIL: UnitName(" .. unit .. ") failed|r") end
        return
    end
    local fullName = (uRealm and uRealm ~= "") and (uName .. "-" .. uRealm) or uName
    
    local okGuid, unitGUID = pcall(UnitGUID, unit)
    local guid = (okGuid and unitGUID) or nil
    local matchedPlayer = FindRosterPlayerByGUIDOrName(guid, fullName)
    
    if _remoteInterruptHits <= 5 then
        print("|cFF00FFFF[Cortio]|r INTERRUPT HIT #" .. _remoteInterruptHits .. ": unit=" .. unit .. " spell=" .. cleanSpell .. " name=" .. fullName .. " matched=" .. tostring(matchedPlayer))
    end
    
    if not matchedPlayer then
        local cls = interruptData and interruptData.class or nil
        if not cls then
            local okCls, _, engClass = pcall(UnitClass, unit)
            if okCls and engClass then cls = engClass end
        end
        if cls then
            Cortio.RosterList[fullName] = {
                unit = unit, guid = guid, class = cls,
                specIcon = "0", specId = 0, cdEnd = 0, cdTotal = 0, lastResult = nil,
            }
            matchedPlayer = fullName
            if _remoteInterruptHits <= 5 then
                print("|cFF00FFFF[Cortio]|r Auto-registered: " .. fullName .. " class=" .. cls)
            end
        end
    end
    
    if not matchedPlayer then
        if _remoteInterruptHits <= 5 then print("|cFFFF0000[Cortio] FAIL: no matchedPlayer for " .. fullName .. "|r") end
        return
    end
    
    local rosterData = Cortio.RosterList[matchedPlayer]
    if guid and not rosterData.guid then rosterData.guid = guid end
    
    -- Compute cooldown: spec > spellId > class default
    local cdTotal
    if rosterData.specId and rosterData.specId > 0 and Cortio.Data.SPEC_INTERRUPTS then
        local specData = Cortio.Data.SPEC_INTERRUPTS[rosterData.specId]
        if specData then cdTotal = specData.baseCD end
    end
    if not cdTotal and interruptData then cdTotal = interruptData.cd end
    if not cdTotal then cdTotal = Cortio.Data:GetClassInterruptCD(rosterData.class) or 15 end
    
    local now = GetTime()
    rosterData.cdEnd = now + cdTotal
    rosterData.cdTotal = cdTotal
    rosterData.lastResult = "USED"
    
    if _remoteInterruptHits <= 5 then
        print("|cFF00FFFF[Cortio]|r CD SET: " .. matchedPlayer .. " cd=" .. cdTotal .. " cdEnd=" .. string.format("%.1f", rosterData.cdEnd))
    end
    
    if Cortio.UI then Cortio.UI:UpdatePanel() end
    Cortio.StartPanelTicker()
end




local _frameEventCount = 0
partyInterruptFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    _frameEventCount = _frameEventCount + 1
    if _frameEventCount <= 5 then
        print("|cFF00FFFF[Cortio]|r |cFF00FF00FRAME EVENT #" .. _frameEventCount .. ": " .. tostring(unit) .. " spell=" .. tostring(spellID) .. "|r")
    end

    -- Dump interrupt name table once
    if _frameEventCount == 1 then
        local n = 0
        for _ in pairs(Cortio.Data.INTERRUPT_NAME_TO_CD) do n = n + 1 end
        local names = {}
        for name in pairs(Cortio.Data.INTERRUPT_NAME_TO_CD) do table.insert(names, name) end
        print("|cFF00FFFF[Cortio]|r INT_TABLE (" .. n .. "): " .. table.concat(names, ", "))
    end

    if not spellID then return end

    -- ================================================================
    -- METHOD 1: Resolve spellID to a clean number via Slider trick
    -- This is the same approach that works for local player detection.
    -- The Slider trick strips WoW 12.0 taint from "secret" numbers.
    -- ================================================================
    local cleanSpell = Cortio.Taint:ResolveNumber(spellID)

    -- METHOD 2: If Slider fails, try tostring extraction (numbers print OK)
    if not cleanSpell then
        pcall(function()
            local rawStr = tostring(spellID)
            if rawStr then
                local numStr = rawStr:match("(%d+)")
                if numStr then cleanSpell = tonumber(numStr) end
            end
        end)
    end

    if not cleanSpell then return end

    -- Direct numeric lookup in ALL_INTERRUPTS (no tainted keys involved)
    local interruptData = Cortio.Data.ALL_INTERRUPTS[cleanSpell]
    if interruptData then
        if _frameEventCount <= 10 then
            print("|cFF00FFFF[Cortio]|r |cFFFFFF00INTERRUPT (ID match): " .. tostring(unit) .. " spellId=" .. cleanSpell .. "|r")
        end
        Cortio.HandleRemoteInterrupt(unit, castGUID, cleanSpell)
        return
    end

    -- ================================================================
    -- METHOD 3: Fallback — spell name comparison with pcall protection.
    -- For spells not in ALL_INTERRUPTS by ID (unlikely but safe).
    -- ================================================================
    local nameOk, spellName = pcall(C_Spell.GetSpellName, spellID)
    if not nameOk or not spellName then return end

    for knownID, data in pairs(Cortio.Data.ALL_INTERRUPTS) do
        local knOk, knName = pcall(C_Spell.GetSpellName, knownID)
        if knOk and knName then
            -- pcall the comparison: tainted == untainted may produce a "secret boolean"
            local matchOk, isMatch = pcall(function() return spellName == knName end)
            if matchOk and isMatch then
                if _frameEventCount <= 10 then
                    print("|cFF00FFFF[Cortio]|r |cFFFFFF00INTERRUPT (Name match): " .. tostring(unit) .. " " .. tostring(knName) .. " (id=" .. knownID .. ")|r")
                end
                Cortio.HandleRemoteInterrupt(unit, castGUID, knownID)
                return
            end
        end
    end
end)

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

