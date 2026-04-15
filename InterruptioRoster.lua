--------------------------------------------------------------
-- INTERRUPTIO - Roster & Inspect
--------------------------------------------------------------
Interruptio = Interruptio or {}
Interruptio.Roster = {}

Interruptio.PlayerName = nil
Interruptio.PlayerClass = nil
Interruptio.RosterList = {}
Interruptio.InspectQueue = {}
local inspectPending = false
local specCache = {}
local specIdCache = {}

function Interruptio.Roster:EnsurePlayerInfo()
    if not Interruptio.PlayerName then
        local raw = UnitName("player")
        if raw then
            local ok, cleanN = pcall(string.format, "%s", raw)
            local n = ok and cleanN or raw
            local _, r = UnitName("player")
            local cleanR = nil
            if r and r ~= "" then
                local okR, cr = pcall(string.format, "%s", r)
                cleanR = okR and cr or r
            end
            Interruptio.PlayerName = cleanR and (n .. "-" .. cleanR) or n
            local _, cls = UnitClass("player")
            Interruptio.PlayerClass = cls
        end
    end
end

function Interruptio.Roster:ProcessInspectQueue()
    if inspectPending or #Interruptio.InspectQueue == 0 then return end
    local unit = table.remove(Interruptio.InspectQueue, 1)
    if UnitExists(unit) and CanInspect(unit) then
        inspectPending = true
        C_Timer.After(0, function()
            if UnitExists(unit) and CanInspect(unit) then
                NotifyInspect(unit)
            else
                inspectPending = false
                C_Timer.After(0.5, function() Interruptio.Roster:ProcessInspectQueue() end)
            end
        end)
    else
        if UnitExists(unit) then
            C_Timer.After(2, function()
                table.insert(Interruptio.InspectQueue, unit)
                Interruptio.Roster:ProcessInspectQueue()
            end)
        end
        C_Timer.After(0.1, function() Interruptio.Roster:ProcessInspectQueue() end)
    end
end

function Interruptio.Roster:Rebuild()
    Interruptio.Roster:EnsurePlayerInfo()
    local newRoster = {}
    local function AddUnit(unit)
        local rawName, realm = UnitName(unit)
        if not rawName then return end
        local okN, cleanName = pcall(string.format, "%s", rawName)
        cleanName = okN and cleanName or rawName
        local cleanRealm = nil
        if realm and realm ~= "" then
            local okR, cr = pcall(string.format, "%s", realm)
            cleanRealm = okR and cr or nil
        end
        local fullName = cleanRealm and (cleanName .. "-" .. cleanRealm) or cleanName
        local okGuid, unitGUID = pcall(UnitGUID, unit)
        local guid = (okGuid and unitGUID) or nil
        local _, class = UnitClass(unit)
        if fullName and class then
            local specIcon = "0"
            local specId = 0
            if UnitIsUnit(unit, "player") then
                local specIndex = GetSpecialization()
                if specIndex then
                    local id, _, _, icon = GetSpecializationInfo(specIndex)
                    if icon then specIcon = tostring(icon) end
                    if id then specId = id end
                end
            elseif specCache[fullName] then
                specIcon = specCache[fullName]
                specId = specIdCache[fullName] or 0
            else
                local inQueue = false
                for _, u in ipairs(Interruptio.InspectQueue) do
                    if UnitIsUnit(u, unit) then inQueue = true break end
                end
                if not inQueue then
                    table.insert(Interruptio.InspectQueue, unit)
                    Interruptio.Roster:ProcessInspectQueue()
                end
            end
            
            -- Use spec-aware CD when available
            local old = Interruptio.RosterList[fullName]
            local baseCd = Interruptio.Data:GetClassInterruptCD(class)
            if specId > 0 and Interruptio.Data.SPEC_INTERRUPTS then
                local specData = Interruptio.Data.SPEC_INTERRUPTS[specId]
                if specData then baseCd = specData.baseCD end
            end
            newRoster[fullName] = {
                unit = unit,
                guid = guid,
                class = class,
                specIcon = specIcon,
                specId = specId,
                cdEnd = old and old.cdEnd or 0,
                cdTotal = old and old.cdTotal or baseCd,
                lastResult = old and old.lastResult or nil,
            }
            if UnitIsUnit(unit, "player") then
                Interruptio.PlayerName = fullName
            end
        end
    end
    
    if InterruptioDB and InterruptioDB.testMode then
        Interruptio.RosterList = {
            [Interruptio.PlayerName or "Jugador"] = { unit="player", class=Interruptio.PlayerClass or "HUNTER", specIcon="132111", cdEnd=0, cdTotal=15 },
            ["Aliado1"] = { unit="party1", class="WARRIOR", specIcon="132344", cdEnd=GetTime()+5, cdTotal=15 },
            ["Aliado2"] = { unit="party2", class="MAGE", specIcon="135856", cdEnd=0, cdTotal=20 },
        }
        return
    end

    AddUnit("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do AddUnit("raid"..i) end
    else
        local inHomeGroup     = IsInGroup()
        local inInstanceGroup = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        if inHomeGroup or inInstanceGroup then
            for i = 1, 4 do
                if UnitExists("party"..i) then AddUnit("party"..i) end
            end
        end
    end
    
    Interruptio.RosterList = newRoster
end

function Interruptio.Roster:RebuildWithRetry()
    Interruptio.Roster:Rebuild()
    C_Timer.After(3, function()
        local count = 0
        for _ in pairs(Interruptio.RosterList) do count = count + 1 end
        if count <= 1 and (IsInGroup() or IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid()) then
            Interruptio.Roster:Rebuild()
            if Interruptio.UI then Interruptio.UI:UpdatePanel() end
        end
    end)
end

function Interruptio.Roster:AutoRegisterByClass()
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local fullName = Interruptio.Taint:SafeUnitFullName(u)
            if fullName then
                local _, cls = UnitClass(u)
                if cls and Interruptio.Data.CLASS_INTERRUPT_SPELLID[cls] and not Interruptio.RosterList[fullName] then
                    local sid = specIdCache[fullName] or 0
                    local baseCd = Interruptio.Data:GetClassInterruptCD(cls)
                    if sid > 0 and Interruptio.Data.SPEC_INTERRUPTS and Interruptio.Data.SPEC_INTERRUPTS[sid] then
                        baseCd = Interruptio.Data.SPEC_INTERRUPTS[sid].baseCD
                    end
                    local okG, uGuid = pcall(UnitGUID, u)
                    Interruptio.RosterList[fullName] = {
                        unit     = u,
                        guid     = (okG and uGuid) or nil,
                        class    = cls,
                        specIcon = specCache[fullName] or "0",
                        specId   = sid,
                        cdEnd    = 0,
                        cdTotal  = baseCd,
                    }
                end
            end
        end
    end
end

function Interruptio.Roster:RegisterPartyWatchers()
    -- Vaciado: Ahora el Combat Log (en Interruptio.lua) hace todo este trabajo sin taint.
end

function Interruptio.Roster:OnInspectReady(guid)
    inspectPending = false
    local unitsToCheck = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            unitsToCheck[#unitsToCheck+1] = "raid"..i
        end
    else
        for i = 1, 4 do
            unitsToCheck[#unitsToCheck+1] = "party"..i
        end
    end
    for _, unit in ipairs(unitsToCheck) do
        if UnitExists(unit) then
            local okGuid, uGuid = pcall(UnitGUID, unit)
            if okGuid and uGuid and uGuid == guid then
                local specId = GetInspectSpecialization(unit)
                if specId and specId > 0 then
                    local okName, name, realm = pcall(UnitName, unit)
                    if okName and name then
                        local fullName = (realm and realm ~= "") and (name .. "-" .. realm) or name
                        local specIcon = "0"
                        local si = select(4, GetSpecializationInfoByID(specId))
                        if si then specIcon = tostring(si) end
                        specCache[fullName] = specIcon
                        specIdCache[fullName] = specId
                        Interruptio.Roster:Rebuild()
                        if Interruptio.UI then Interruptio.UI:UpdatePanel() end
                    end
                end
                break
            end
        end
    end
    C_Timer.After(0.3, function() Interruptio.Roster:ProcessInspectQueue() end)
end
