BINDING_HEADER_CORTIO_HEADER = "Cortio - Asignacion de Cortes"
BINDING_NAME_CLICK_CortioMarkSABT_LeftButton = "Poner/Quitar Marca de Corte"

Cortio = Cortio or {}

local function SafeRegisterPrefix()
    if not C_ChatInfo.RegisterAddonMessagePrefix(Cortio.Data.COMM_PREFIX) then
        C_Timer.After(2, SafeRegisterPrefix)
    end
end
SafeRegisterPrefix()

local function FindRosterPlayer(sender)
    if Cortio.RosterList[sender] then return sender end
    local simpleName = strsplit("-", sender)
    for k in pairs(Cortio.RosterList) do
        local kb = strsplit("-", k)
        if kb == simpleName then return k end
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

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        Cortio.Roster:EnsurePlayerInfo()
        
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
        C_Timer.After(2, function() Cortio.Net:SendGroupMessage("SYNCREQ", "SyncReq") end)
        C_Timer.After(3, function() Cortio.Roster:AutoRegisterByClass(); Cortio.Roster:RegisterPartyWatchers(); Cortio.UI:UpdatePanel() end)
        C_Timer.After(5, function() Cortio.Net:SendGroupMessage("SYNCREQ", "SyncReq") end)
        
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
            Cortio.Net:SendGroupMessage("SYNCREQ", "SyncReq")
        end)
        C_Timer.After(3, function()
            Cortio.Roster:RegisterPartyWatchers()
            Cortio.Roster:AutoRegisterByClass()
        end)
        
    elseif event == "INSPECT_READY" then
        Cortio.Roster:OnInspectReady(arg1)

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
                    Cortio.Net:SendGroupMessage("UNMARK:" .. (Cortio.PlayerClass or "UNKNOWN") .. ":0:0", "Send")
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
            local sName = strsplit("-", sender)
            local pName = Cortio.PlayerName and strsplit("-", Cortio.PlayerName) or ""
            if sender == Cortio.PlayerName or sName == pName then return end
            
            local action, p2, p3, p4, p5, p6 = strsplit(":", arg2, 7)
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
    if not Cortio.Data.INTERRUPT_SPELLID_SET[spellID] then return end
    if not Cortio.PlayerClass then return end

    local now = GetTime()
    if now - lastInterruptBroadcastTime < 1 then return end
    lastInterruptBroadcastTime = now

    local cdDuration = Cortio.Data.CLASS_INTERRUPT_CD[Cortio.PlayerClass] or 15
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

    Cortio.Net:SendGroupMessage("CD:"..cdDuration, "CD")
end)

local ticker = 0
local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function(self, elapsed)
    ticker = ticker + elapsed
    if ticker >= 0.25 then
        ticker = 0
        if Cortio.UI.Panel and Cortio.UI.Panel:IsShown() then
            Cortio.UI:UpdatePanel()
        end
        Cortio.UI:UpdateAllNameplates()
    end
end)

print("|cFF00FFFF[Cortio]|r Cargado. Asigna la tecla en: ESC -> Atajos -> AddOns -> Cortio")
