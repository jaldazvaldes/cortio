--------------------------------------------------------------
-- INTERRUPTIO - Marks Management
--------------------------------------------------------------
Interruptio = Interruptio or {}
Interruptio.Marks = {}

Interruptio.Marks.Active = {}

local secureBtnNeedsUpdate = false
local secureBtnFrame = CreateFrame("Frame")
secureBtnFrame:SetScript("OnUpdate", function(self, elapsed)
    if secureBtnNeedsUpdate and not InCombatLockdown() then
        secureBtnNeedsUpdate = false
        Interruptio.Marks:UpdateSecureBtnMacro()
    end
end)

local InterruptioMarkSABT = CreateFrame("Button", "InterruptioMarkSABT", UIParent, "SecureActionButtonTemplate")
InterruptioMarkSABT:RegisterForClicks("AnyDown")
InterruptioMarkSABT:SetAttribute("type", "macro")
InterruptioMarkSABT:SetAttribute("macrotext", "/targetmarker 1")
InterruptioMarkSABT:SetAttribute("markerSlot", 1)
InterruptioMarkSABT:SetSize(1, 1)
Interruptio.Marks.SABT = InterruptioMarkSABT

function Interruptio.Marks:QueueSecureBtnUpdate()
    secureBtnNeedsUpdate = true
end

function Interruptio.Marks:ClearPlayerMark(who)
    for i = #Interruptio.Marks.Active, 1, -1 do
        if Interruptio.Marks.Active[i].playerName == who then
            table.remove(Interruptio.Marks.Active, i)
        end
    end
end

function Interruptio.Marks:GetMarkerSlotForPlayer(targetName)
    if not targetName then return 8 end
    if targetName == Interruptio.PlayerName and InterruptioDB and InterruptioDB.markerSlot and InterruptioDB.markerSlot > 0 then
        return InterruptioDB.markerSlot
    end
    
    if not IsInGroup() and not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInRaid() then return 8 end

    local allPlayers = {}
    if Interruptio.PlayerName then allPlayers[#allPlayers+1] = Interruptio.PlayerName end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid"..i
            if UnitExists(u) then
                local ok, name, realm = pcall(UnitName, u)
                if ok and name then
                    allPlayers[#allPlayers+1] = (realm and realm ~= "") and (name.."-"..realm) or name
                end
            end
        end
    else
        for i = 1, 4 do
            local u = "party"..i
            if UnitExists(u) then
                local ok, name, realm = pcall(UnitName, u)
                if ok and name then
                    allPlayers[#allPlayers+1] = (realm and realm ~= "") and (name.."-"..realm) or name
                end
            end
        end
    end

    -- Add the target if not already in roster (e.g. test mode instances)
    local found = false
    local tShort = Interruptio.Data:ShortName(targetName)
    for _, n in ipairs(allPlayers) do
        if n == targetName or Interruptio.Data:ShortName(n) == tShort then
            found = true
            break
        end
    end
    if not found then allPlayers[#allPlayers+1] = targetName end

    table.sort(allPlayers)

    for idx, name in ipairs(allPlayers) do
        local nameShort = Interruptio.Data:ShortName(name)
        if name == targetName or nameShort == tShort then
            return math.max(1, 9 - idx)
        end
    end
    return 8
end

function Interruptio.Marks:AutoAssignMarkerSlot()
    return Interruptio.Marks:GetMarkerSlotForPlayer(Interruptio.PlayerName)
end

function Interruptio.Marks:GetPlayerMarkerSlotSafe()
    if InterruptioDB and InterruptioDB.markerSlot and InterruptioDB.markerSlot > 0 then
        return InterruptioDB.markerSlot
    end
    return Interruptio.Marks:AutoAssignMarkerSlot()
end

function Interruptio.Marks:UpdateSecureBtnMacro()
    if InCombatLockdown() then return end
    local slot = Interruptio.Marks:GetPlayerMarkerSlotSafe()
    local lines = {"/targetmarker " .. tostring(slot)}
    table.insert(lines, "/stopmacro [noexists]")
    
    if not InterruptioDB or InterruptioDB.announce ~= false then
        local chatIcon = slot > 0 and ("{rt" .. slot .. "}") or ""
        local sName = Interruptio.PlayerName and Interruptio.Data:ShortName(Interruptio.PlayerName) or "?"
        local txt = string.format(Interruptio.L["MSG_ASSIGNED_SELF"] or "[Interruptio] Assigned %s (%s)", chatIcon, sName)
        
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            table.insert(lines, "/i " .. txt)
        elseif IsInRaid() then
            table.insert(lines, "/ra " .. txt)
        elseif IsInGroup() then
            table.insert(lines, "/p " .. txt)
        else
            table.insert(lines, "/p " .. txt)
        end
    end
    
    InterruptioMarkSABT:SetAttribute("macrotext", table.concat(lines, "\n"))
    InterruptioMarkSABT:SetAttribute("markerSlot", slot)
end

function Interruptio.Marks:HandlePostClick(self, button, down)
    if not down then return end

    C_Timer.After(0.05, function()
        Interruptio.Roster:EnsurePlayerInfo()
        if not Interruptio.PlayerName then return end
        
        -- Warn about raid marker permissions
        if IsInRaid() and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
            print("|cFF00FFFF[Interruptio]|r |cFFFF9900Aviso: en raid necesitas ser líder/asistente para que el raid marker sea visible.|r")
        end

        local ch
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
        elseif IsInRaid() then ch = "RAID"
        elseif IsInGroup() then ch = "PARTY"
        end

        local slot = Interruptio.Marks:GetPlayerMarkerSlotSafe()
        local specIndex = GetSpecialization()
        local specIcon = "0"
        if specIndex then
            local si = select(4, GetSpecializationInfo(specIndex))
            if si then
                local cleanSi = Interruptio.Taint:ResolveNumber(si)
                specIcon = cleanSi and tostring(cleanSi) or "0"
            end
        end
        local rawId = math.floor(GetTime() * 1000) % 100000
        local okT, markId = pcall(math.floor, rawId)
        if not okT then markId = 0 end

        local msgMark = "V1|MARK|"..(Interruptio.PlayerClass or "UNKNOWN").."|"..(specIcon).."|"..(markId or "0").."|"..(slot or "0").."|"..("0")
        local msgUnmark = "V1|UNMARK"

        local sourceUnit = "target"
        
        if not UnitExists(sourceUnit) then
            Interruptio.Marks:ClearPlayerMark(Interruptio.PlayerName)
            if Interruptio.UI then Interruptio.UI:UpdatePanel() Interruptio.UI:UpdateAllNameplates() end

            print("|cFF00FFFF[Interruptio]|r Corte retirado (sin objetivo).")
            return
        end

        Interruptio.Marks:ClearPlayerMark(Interruptio.PlayerName)

        table.insert(Interruptio.Marks.Active, {
            playerName = Interruptio.PlayerName,
            playerClass = Interruptio.PlayerClass,
            specIcon = specIcon,
            remoteCDEnd = 0,
            remoteCDDuration = 0,
            nameplateUnit = nil,
            unitToken = "target",
            markId = markId,
            markerSlot = slot
        })



        if Interruptio.UI then
            Interruptio.UI:UpdatePanel()
            Interruptio.UI:UpdateAllNameplates()
        end

        local targetName = Interruptio.Taint:SafeUnitName(sourceUnit)
        if not targetName then return end
        
        local iconStr = Interruptio.Data:GetRaidIconString(slot, 14)
        print("|cFF00FFFF[Interruptio]|r " .. string.format(Interruptio.L["MSG_ASSIGNED_PARTY"], (slot > 0 and iconStr or ""), "|cFFFFDD00" .. tostring(targetName) .. "|r"))
    end)
end
InterruptioMarkSABT:HookScript("PostClick", function(self, button, down) Interruptio.Marks:HandlePostClick(self, button, down) end)

function Interruptio.Marks:BroadcastCurrentMark()
    -- Eliminado (sin AddonMessages)
end
