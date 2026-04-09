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

local function FindRosterPlayer(sender)
    if Cortio.RosterList[sender] then return sender end
    local ambig = Ambiguate(sender, "short")
    if Cortio.RosterList[ambig] then return ambig end
    for k in pairs(Cortio.RosterList) do
        if Ambiguate(k, "short") == ambig then return k end
    end
    return nil
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
        Cortio.UI:UpdatePanel()
        if not InCombatLockdown() then
            Cortio.Marks:QueueSecureBtnUpdate()
        end
        C_Timer.After(1, function()
            Cortio.Roster:RegisterPartyWatchers()
            Cortio.Roster:AutoRegisterByClass()
            Cortio.UI:UpdatePanel()
            Cortio.Net:SendGroupMessage("V1|SYNCREQ", "SyncReq")
        end)
        C_Timer.After(3, function()
            Cortio.Roster:RegisterPartyWatchers()
            Cortio.Roster:AutoRegisterByClass()
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

local combatLogFrame = CreateFrame("Frame")
combatLogFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatLogFrame:SetScript("OnEvent", function(self, event)
    local _, subevent, _, sourceGUID, sourceName, _, _, _, _, _, _, spellId = CombatLogGetCurrentEventInfo()
    if not sourceName or not subevent or not spellId then return end
    
    local interruptData = Cortio.Data.ALL_INTERRUPTS[spellId]
    if interruptData then
        if subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_INTERRUPT" or subevent == "SPELL_MISSED" then
            local shortName = Cortio.Data:ShortName(sourceName)
            local matchedPlayer = nil
            
            for pName, pData in pairs(Cortio.RosterList) do
                if Cortio.Data:ShortName(pName) == shortName then
                    matchedPlayer = pName
                    break
                end
            end
            
            if matchedPlayer then
                local now = GetTime()
                local cdTotal = Cortio.RosterList[matchedPlayer].cdTotal or interruptData.cd
                
                if subevent == "SPELL_CAST_SUCCESS" then
                    Cortio.RosterList[matchedPlayer].cdEnd = now + cdTotal
                    Cortio.RosterList[matchedPlayer].lastResult = "USED"
                    if Cortio.UI then Cortio.UI:UpdatePanel() end
                elseif subevent == "SPELL_INTERRUPT" then
                    Cortio.RosterList[matchedPlayer].lastResult = "SUCCESS"
                    if Cortio.UI then Cortio.UI:UpdatePanel() end
                elseif subevent == "SPELL_MISSED" then
                    Cortio.RosterList[matchedPlayer].lastResult = "MISSED"
                    if Cortio.UI then Cortio.UI:UpdatePanel() end
                end
            end
        end
    end
end)

-- Smart panel ticker: only runs when CDs are active
Cortio.PanelTicker = nil

function Cortio.StartPanelTicker()
    if Cortio.PanelTicker then return end
    Cortio.PanelTicker = C_Timer.NewTicker(0.25, function()
        if Cortio.UI.Panel and Cortio.UI.Panel:IsShown() then
            Cortio.UI:UpdatePanel()
        end
        Cortio.UI:UpdateAllNameplates()
        
        -- Auto-stop when no active CDs and no visible nameplates
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

-- Auto-start ticker when UpdatePanel detects active CDs
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
