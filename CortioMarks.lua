--------------------------------------------------------------
-- CORTIO - Marks Management
--------------------------------------------------------------
Cortio = Cortio or {}
Cortio.Marks = {}

Cortio.Marks.Active = {}

local secureBtnNeedsUpdate = false
local secureBtnFrame = CreateFrame("Frame")
secureBtnFrame:SetScript("OnUpdate", function(self, elapsed)
    if secureBtnNeedsUpdate and not InCombatLockdown() then
        secureBtnNeedsUpdate = false
        Cortio.Marks:UpdateSecureBtnMacro()
    end
end)

local CortioMarkSABT = CreateFrame("Button", "CortioMarkSABT", UIParent, "SecureActionButtonTemplate")
CortioMarkSABT:RegisterForClicks("AnyDown")
CortioMarkSABT:SetAttribute("type", "macro")
CortioMarkSABT:SetAttribute("macrotext", "/targetmarker 1")
CortioMarkSABT:SetAttribute("markerSlot", 1)
CortioMarkSABT:SetSize(1, 1)
Cortio.Marks.SABT = CortioMarkSABT

function Cortio.Marks:QueueSecureBtnUpdate()
    secureBtnNeedsUpdate = true
end

function Cortio.Marks:ClearPlayerMark(who)
    for i = #Cortio.Marks.Active, 1, -1 do
        if Cortio.Marks.Active[i].playerName == who then
            table.remove(Cortio.Marks.Active, i)
        end
    end
end

function Cortio.Marks:AutoAssignMarkerSlot()
    if not IsInGroup() and not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInRaid() then return 8 end

    local allPlayers = {}
    if Cortio.PlayerName then allPlayers[#allPlayers+1] = Cortio.PlayerName end

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

    table.sort(allPlayers)

    local myShort = Cortio.PlayerName and Cortio.Data:ShortName(Cortio.PlayerName) or ""
    for idx, name in ipairs(allPlayers) do
        local nameShort = Cortio.Data:ShortName(name)
        if name == Cortio.PlayerName or nameShort == myShort then
            return math.max(1, 9 - idx)
        end
    end
    return 8
end

function Cortio.Marks:GetPlayerMarkerSlotSafe()
    if CortioDB and CortioDB.markerSlot and CortioDB.markerSlot > 0 then
        return CortioDB.markerSlot
    end
    return Cortio.Marks:AutoAssignMarkerSlot()
end

function Cortio.Marks:UpdateSecureBtnMacro()
    if InCombatLockdown() then return end
    local slot = Cortio.Marks:GetPlayerMarkerSlotSafe()
    local lines = {"/targetmarker " .. tostring(slot)}
    -- Always include the announce: when SendAddonMessage fails (result=11 in M+),
    -- this is the ONLY way to sync markers. The CHAT_MSG parser on the other end
    -- reads this message to update the marker UI.
    local sName = Cortio.PlayerName and Cortio.Data:ShortName(Cortio.PlayerName) or "?"
    if #sName > 12 then sName = sName:sub(1, 12) end
    local chatIcon = slot > 0 and ("{rt" .. slot .. "}") or ""
    
    table.insert(lines, "/stopmacro [noexists]")
    local txt = "[Cortio] Assigned " .. chatIcon .. " (" .. sName .. ")"
    
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        table.insert(lines, "/i " .. txt)
    elseif IsInRaid() then
        table.insert(lines, "/ra " .. txt)
    elseif IsInGroup() then
        table.insert(lines, "/p " .. txt)
    end
    CortioMarkSABT:SetAttribute("macrotext", table.concat(lines, "\n"))
    CortioMarkSABT:SetAttribute("markerSlot", slot)
end

function Cortio.Marks:HandlePostClick(self, button, down)
    if not down then return end

    C_Timer.After(0.05, function()
        Cortio.Roster:EnsurePlayerInfo()
        if not Cortio.PlayerName then return end
        
        -- Warn about raid marker permissions
        if IsInRaid() and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
            print("|cFF00FFFF[Cortio]|r |cFFFF9900Aviso: en raid necesitas ser líder/asistente para que el raid marker sea visible.|r")
        end

        local ch
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
        elseif IsInRaid() then ch = "RAID"
        elseif IsInGroup() then ch = "PARTY"
        end

        local slot = Cortio.Marks:GetPlayerMarkerSlotSafe()
        local specIndex = GetSpecialization()
        local specIcon = "0"
        if specIndex then
            local si = select(4, GetSpecializationInfo(specIndex))
            if si then
                local cleanSi = Cortio.Taint:ResolveNumber(si)
                specIcon = cleanSi and tostring(cleanSi) or "0"
            end
        end
        local rawId = math.floor(GetTime() * 1000) % 100000
        local okT, markId = pcall(math.floor, rawId)
        if not okT then markId = 0 end

        local msgMark = "V1|MARK|"..(Cortio.PlayerClass or "UNKNOWN").."|"..(specIcon).."|"..(markId or "0").."|"..(slot or "0").."|"..("0")
        local msgUnmark = "V1|UNMARK"

        local sourceUnit = "target"
        
        if not UnitExists(sourceUnit) then
            Cortio.Marks:ClearPlayerMark(Cortio.PlayerName)
            if Cortio.UI then Cortio.UI:UpdatePanel() end
            if ch then
                table.insert(Cortio.Net.Queue, {prefix=Cortio.Data.COMM_PREFIX, msg=msgUnmark, channel=ch, tag="Send"})
            end
            print("|cFF00FFFF[Cortio]|r Corte retirado (sin objetivo).")
            return
        end

        Cortio.Marks:ClearPlayerMark(Cortio.PlayerName)

        table.insert(Cortio.Marks.Active, {
            playerName = Cortio.PlayerName,
            playerClass = Cortio.PlayerClass,
            specIcon = specIcon,
            remoteCDEnd = 0,
            remoteCDDuration = 0,
            nameplateUnit = nil,
            unitToken = "target",
            markId = markId,
            markerSlot = slot
        })

        if ch then
            table.insert(Cortio.Net.Queue, {prefix=Cortio.Data.COMM_PREFIX, msg=msgMark, channel=ch, tag="Send"})
        end

        if Cortio.UI then
            Cortio.UI:UpdatePanel()
            Cortio.UI:UpdateAllNameplates()
        end

        local targetName = UnitName(sourceUnit)
        if not targetName then return end
        
        local iconStr = Cortio.Data:GetRaidIconString(slot, 14)
        print("|cFF00FFFF[Cortio]|r Corte asignado" .. (slot > 0 and (" " .. iconStr) or "") .. " |cFFFFDD00" .. tostring(targetName) .. "|r")
    end)
end
CortioMarkSABT:HookScript("PostClick", function(self, button, down) Cortio.Marks:HandlePostClick(self, button, down) end)

function Cortio.Marks:BroadcastCurrentMark()
    if not Cortio.PlayerName or not Cortio.PlayerClass then return end
    local ch
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
    elseif IsInRaid() then ch = "RAID"
    elseif IsInGroup() then ch = "PARTY"
    end
    if not ch then return end
    for _, m in ipairs(Cortio.Marks.Active) do
        if m.playerName == Cortio.PlayerName or Cortio.Data:ShortName(m.playerName) == Cortio.Data:ShortName(Cortio.PlayerName) then
            local rawSI = m.specIcon
            local cleanSI = "0"
            if rawSI and rawSI ~= "0" then
                local n = tonumber(rawSI)
                if n then
                    local c = Cortio.Taint:ResolveNumber(n)
                    cleanSI = c and tostring(c) or "0"
                end
            end
            local msg = "V1|MARK|"..Cortio.PlayerClass.."|"..cleanSI.."|"..(m.markId or "0").."|"..(m.markerSlot or "0").."|0"
            table.insert(Cortio.Net.Queue, {prefix=Cortio.Data.COMM_PREFIX, msg=msg, channel=ch, tag="BroadcastMark"})
            return
        end
    end
end
