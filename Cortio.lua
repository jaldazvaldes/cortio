--------------------------------------------------------------
-- CORTIO - Asistente de cortes para WoW 12.0
-- UnitIsUnit + nameplate tokens para identificación de NPCs.
-- Los nombres de NPCs son "secret values" en instancias (WoW 12.0);
-- la identificación remota se hace via UnitTarget(partyN) + UnitIsUnit.
--------------------------------------------------------------

local COMM_PREFIX = "CORTIO"
C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)

-- { npcName, playerName, playerClass, specIcon, remoteCDEnd, remoteCDDuration, nameplateUnit, markId, markerSlot }
local activeMarks = {}
local playerName, playerClass

local CortioRoster = {}      -- { [playerName] = { class, specIcon, cdEnd, cdTotal } }
local inspectQueue = {}
local inspectPending = false
local specCache = {}

local defaultDB = {
    announce = true,
    testMode = false,
}

--------------------------------------------------------------
-- ICONOS DE RAID MARKER (sprite sheet)
-- Slot 1=Estrella, 2=Circulo, 3=Diamante, 4=Triangulo,
--      5=Luna, 6=Cuadrado, 7=Cruz/X, 8=Calavera
--------------------------------------------------------------
local RAID_ICON_COORDS = {
    [1]={0,16,0,16},  -- Estrella
    [2]={16,32,0,16}, -- Circulo
    [3]={32,48,0,16}, -- Diamante
    [4]={48,64,0,16}, -- Triangulo
    [5]={0,16,16,32}, -- Luna
    [6]={16,32,16,32},-- Cuadrado
    [7]={32,48,16,32},-- Cruz/X
    [8]={48,64,16,32},-- Calavera
}
local RAID_ICON_NAMES = {"Estrella","Circulo","Diamante","Triangulo","Luna","Cuadrado","Cruz","Calavera"}
local RAID_ICON_TEX  = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local function GetRaidIconString(slot, size)
    size = size or 14
    local c = RAID_ICON_COORDS[slot]
    if not c then return "" end
    return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t",
        RAID_ICON_TEX, size, size, c[1], c[2], c[3], c[4])
end

--------------------------------------------------------------
-- LOG
--------------------------------------------------------------
local MAX_ERRORS = 50
local function LogError(ctx, err)
    if not CortioDB then CortioDB = {} end
    if not CortioDB.errors then CortioDB.errors = {} end
    table.insert(CortioDB.errors, date("%H:%M:%S") .. " [" .. tostring(ctx) .. "] " .. tostring(err))
    while #CortioDB.errors > MAX_ERRORS do table.remove(CortioDB.errors, 1) end
end
local function SafeCall(ctx, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then LogError(ctx, err) end
    return ok
end

--------------------------------------------------------------
-- INIT
--------------------------------------------------------------
local function EnsurePlayerInfo()
    if not playerName then
        local n, r = securecallfunction(UnitName, "player")
        if n then
            playerName = (r and r ~= "") and (n .. "-" .. r) or n
            local _, cls = securecallfunction(UnitClass, "player")
            playerClass = cls
        end
    end
end

--------------------------------------------------------------
-- PANEL FLOTANTE
--------------------------------------------------------------
local panel = CreateFrame("Frame", "CortioPanelFrame", UIParent, "BackdropTemplate")
panel:SetSize(250, 30)
panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)
panel:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
panel:SetBackdropColor(0.03, 0.03, 0.08, 0.93)
panel:SetBackdropBorderColor(0.0, 0.75, 1.0, 0.85)

-- Franja de color detras del titulo
local titleBg = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
titleBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
titleBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
titleBg:SetHeight(17)
titleBg:SetColorTexture(0.0, 0.45, 0.75, 0.30)

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOP", panel, "TOP", 0, -6)
title:SetText("|cFF00D4FF--|r |cFFFFFFFFCORTIO|r |cFF00D4FF--|r")


-- Linea separadora bajo el titulo
local separator = panel:CreateTexture(nil, "ARTWORK")
separator:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -21)
separator:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -21)
separator:SetHeight(1)
separator:SetColorTexture(0.0, 0.75, 1.0, 0.45)

local panelRows = {}

local function GetOrCreatePanelRow(i)
    if panelRows[i] then return panelRows[i] end
    
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(238, 15)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -24 - (i - 1) * 15)
    
    row.raidIcon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.raidIcon:SetSize(14, 14)
    row.raidIcon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.raidIcon:SetJustifyH("CENTER")
    
    row.classIcon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.classIcon:SetSize(16, 16)
    row.classIcon:SetPoint("LEFT", row.raidIcon, "RIGHT", 4, 0)
    row.classIcon:SetJustifyH("CENTER")
    
    row.playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.playerText:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)
    row.playerText:SetPoint("RIGHT", row, "RIGHT", -40, 0)
    row.playerText:SetJustifyH("LEFT")
    row.playerText:SetWordWrap(false)
    
    row.cdText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cdText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.cdText:SetJustifyH("RIGHT")
    
    row:Hide()
    panelRows[i] = row
    return row
end

local function HidePanelRow(i)
    if panelRows[i] then panelRows[i]:Hide() end
end

local CLASS_COLORS = {
    WARRIOR="FFC79C6E", PALADIN="FFF58CBA", HUNTER="FFABD473",
    ROGUE="FFFFF569", PRIEST="FFFFFFFF", DEATHKNIGHT="FFC41F3B",
    SHAMAN="FF0070DE", MAGE="FF40C7EB", WARLOCK="FF8787ED",
    MONK="FF00FF96", DRUID="FFFF7D0A", DEMONHUNTER="FFA330C9",
    EVOKER="FF33937F",
}

-- Iconos de corte de cada clase (FileDataID para evitar problemas de compatibilidad)
local CLASS_INTERRUPT_ICONS = {
    WARRIOR = "132344",       -- Zurrar
    PALADIN = "135966",       -- Reprimenda
    HUNTER = "135250",        -- Disparo contrarrestante
    ROGUE = "132219",         -- Patada
    PRIEST = "136154",        -- Silencio
    DEATHKNIGHT = "136173",   -- Helada mental
    SHAMAN = "136018",        -- Corte de viento
    MAGE = "135856",          -- Contrahechizo
    WARLOCK = "136174",       -- Bloqueo de hechizo
    MONK = "606547",          -- Golpe de mano de lanza
    DRUID = "132114",         -- Testarazo
    DEMONHUNTER = "1323326",  -- Interrumpir
    EVOKER = "4623131",       -- Sofocar
}

-- Spell IDs de interrupt por clase (necesario antes de ApplyLocalCooldown)
local CLASS_INTERRUPT_SPELLID = {
    WARRIOR     = 6552,    -- Pummel / Zurrar
    PALADIN     = 96231,   -- Rebuke / Reprimenda
    HUNTER      = 147362,  -- Counter Shot / Disparo contrarrestante
    ROGUE       = 1766,    -- Kick / Patada
    PRIEST      = 15487,   -- Silence / Silencio
    DEATHKNIGHT = 47528,   -- Mind Freeze / Helada mental
    SHAMAN      = 57994,   -- Wind Shear / Corte de viento
    MAGE        = 2139,    -- Counterspell / Contrahechizo
    WARLOCK     = 19647,   -- Spell Lock / Bloqueo de hechizo
    MONK        = 116705,  -- Spear Hand Strike / Golpe de mano de lanza
    DRUID       = 106839,  -- Skull Bash / Testarazo
    DEMONHUNTER = 183752,  -- Disrupt / Interrumpir
    EVOKER      = 351338,  -- Quell / Sofocar
}

-- Cooldown base (segundos) de cada interrupt — para compartir con otros jugadores
-- (valores base sin talentos; suficiente para feedback visual)
local CLASS_INTERRUPT_CD = {
    WARRIOR     = 15,
    PALADIN     = 15,
    HUNTER      = 24,
    ROGUE       = 15,
    PRIEST      = 45,
    DEATHKNIGHT = 15,
    SHAMAN      = 12,
    MAGE        = 24,
    WARLOCK     = 24,
    MONK        = 15,
    DRUID       = 15,
    DEMONHUNTER = 15,
    EVOKER      = 40,
}

-- Lookup inverso: spellID → true (para detectar casts rápido)
local INTERRUPT_SPELLID_SET = {}
for _, sid in pairs(CLASS_INTERRUPT_SPELLID) do
    INTERRUPT_SPELLID_SET[sid] = true
end
local function ShortName(fullName)
    if not fullName then return "?" end
    local name = strsplit("-", fullName)
    return name or fullName
end



--------------------------------------------------------------
-- HELPER: buscar qué nameplateN corresponde a un unit token
--------------------------------------------------------------
local function FindNameplateUnit(unit)
    for i = 1, 40 do
        local npUnit = "nameplate" .. i
        if UnitExists(npUnit) and UnitIsUnit(npUnit, unit) then
            return npUnit
        end
    end
    return nil
end


--------------------------------------------------------------
-- NAMEPLATES POOL & ANCHORING
-- Usa frames de icono reales (no FontStrings) para poder
-- mostrar CooldownFrame encima del icono del jugador local.
--------------------------------------------------------------
local MAX_ICONS_PER_PLATE = 8  -- hasta 4 jugadores x 2 iconos (clase+spec)
local nameplateFrames = {}
local activeNameplates = {} -- unitID "nameplateX" => frame

local function CreateIconSubFrame(parent, index)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(24, 24)
    -- Apilar iconos de derecha a izquierda
    if index == 1 then
        icon:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    else
        icon:SetPoint("RIGHT", parent.icons[index - 1], "LEFT", -2, 0)
    end
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    -- CooldownFrame para el swipe visual (solo se activará en el icono local)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawSwipe(true)
    icon.cooldown:SetDrawEdge(true)
    icon.cooldown:SetDrawBling(true)
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.65)
    icon.isLocal = false   -- flag: icono del jugador local
    icon.ownerName = nil   -- nombre del jugador dueño del icono
    icon:Hide()
    return icon
end

local function GetNameplateFrame()
    for _, f in ipairs(nameplateFrames) do
        if not f:IsShown() and not f.inUse then
            -- Resetear todos los iconos
            for _, ic in ipairs(f.icons) do
                ic:Hide()
                ic.cooldown:Clear()
                ic.isLocal = false
                ic.ownerName = nil
            end
            f.inUse = true
            return f
        end
    end
    
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(MAX_ICONS_PER_PLATE * 26, 24)
    f:SetFrameStrata("HIGH")
    f.icons = {}
    for i = 1, MAX_ICONS_PER_PLATE do
        f.icons[i] = CreateIconSubFrame(f, i)
    end
    f.inUse = true
    table.insert(nameplateFrames, f)
    return f
end

local function ReleaseNameplateFrame(unit)
    local f = activeNameplates[unit]
    if f then
        for _, ic in ipairs(f.icons) do
            ic:Hide()
            ic.cooldown:Clear()
            ic.isLocal = false
            ic.ownerName = nil
        end
        f:Hide()
        f:ClearAllPoints()
        f.inUse = false
        activeNameplates[unit] = nil
    end
end



-- ApplyLocalCooldown se elimina porque todo se unifica en UpdateNameplate

-- Bypass Tainted Secret Booleans (WoW 12.0 API Crash)
-- La API 'UnitIsUnit(partyNtarget, nameplateX)' ahora devuelve un 'secret boolean' si no es tu objetivo directo.
-- Si intentamos leer este boolean en un 'if', el motor Lua colapsa de inmediato por Execution Taint.
-- Solucion: Evaluamos la igualdad boolean dentro de un 'pcall' secundario. Si explota, lo absorbemos y retornamos falso.
local function SafeIsMatch(token, npUnit)
    if not token or not npUnit then return false end
    local ok, match = pcall(UnitIsUnit, token, npUnit)
    if not ok then return false end
    
    local evalOk, evalResult = pcall(function() return match == true end)
    if not evalOk then return false end
    return evalResult
end

local function UpdateNameplate(unit)
    local marks = {}

    for _, mark in ipairs(activeMarks) do
        -- Si esta marca ya está anclada permanentemente a este Nameplate, se queda.
        if mark.nameplateUnit == unit then
            table.insert(marks, mark)
        -- Si la marca aún no tiene ancla, y el jugador tiene al objetivo en la mira (target/partyNtarget)
        elseif not mark.nameplateUnit then
            if mark.unitToken and UnitExists(mark.unitToken) then
                -- Intentamos cazar el Nameplate activo de forma segura evadiendo el Taint
                if SafeIsMatch(mark.unitToken, unit) then
                    mark.nameplateUnit = unit
                    table.insert(marks, mark)
                end
            end
        end
    end
    
    local f = activeNameplates[unit]
    
    if #marks == 0 then 
        if f then ReleaseNameplateFrame(unit) end
        return 
    end
    
    local np = C_NamePlate.GetNamePlateForUnit(unit)
    if not np then 
        if f then ReleaseNameplateFrame(unit) end
        return 
    end
    
    local anchorFrame = np.UnitFrame or np

    if not f then
        f = GetNameplateFrame()
        activeNameplates[unit] = f
    end
    
    if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
    f:ClearAllPoints()
    f:SetPoint("RIGHT", anchorFrame, "LEFT", -6, 0)
    f:Show()
    
    local iconIdx = 0
    for _, mark in ipairs(marks) do
        -- Icono de clase (interrupción)
        local classIcon = CLASS_INTERRUPT_ICONS[mark.playerClass]
        if classIcon then
            iconIdx = iconIdx + 1
            if iconIdx <= MAX_ICONS_PER_PLATE then
                local ic = f.icons[iconIdx]
                ic.texture:SetTexture(tonumber(classIcon))
                ic.ownerName = mark.playerName
                if mark.playerName == playerName then
                    ic.isLocal = true
                else
                    ic.isLocal = false
                end
                
                local pData = CortioRoster[mark.playerName]
                if pData and pData.cdEnd and pData.cdEnd > GetTime() then
                    ic.cooldown:SetCooldown(pData.cdEnd - pData.cdTotal, pData.cdTotal)
                else
                    ic.cooldown:SetCooldown(0, 0)
                end
                ic:Show()
            end
        end
        -- Icono de especialización
        if mark.specIcon and mark.specIcon ~= "0" and mark.specIcon ~= "" then
            iconIdx = iconIdx + 1
            if iconIdx <= MAX_ICONS_PER_PLATE then
                local ic = f.icons[iconIdx]
                ic.texture:SetTexture(tonumber(mark.specIcon))
                ic.isLocal = false
                ic.ownerName = nil
                ic.cooldown:Clear()
                ic:Show()
            end
        end
    end
    
    -- Ocultar iconos sobrantes
    for i = iconIdx + 1, MAX_ICONS_PER_PLATE do
        if f.icons[i]:IsShown() then
            f.icons[i]:Hide()
            f.icons[i].cooldown:Clear()
        end
    end
    
    f:Show()
end

-- UpdateNameplateCooldowns y SPELL_UPDATE_COOLDOWN eliminados (usamos tracking local seguro)

local function UpdateAllNameplates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            UpdateNameplate(unit)
        end
    end
end

--------------------------------------------------------------
-- Roster & Inspect
--------------------------------------------------------------
local function ProcessInspectQueue()
    if inspectPending or #inspectQueue == 0 then return end
    local unit = table.remove(inspectQueue, 1)
    if UnitExists(unit) and CanInspect(unit) then
        inspectPending = true
        NotifyInspect(unit)
    else
        if UnitExists(unit) then
            C_Timer.After(2, function()
                table.insert(inspectQueue, unit)
                ProcessInspectQueue()
            end)
        end
        C_Timer.After(0.1, ProcessInspectQueue)
    end
end

local function RebuildRoster()
    local newRoster = {}
    local function AddUnit(unit)
        local name, realm = UnitName(unit)
        local fullName = (realm and realm ~= "") and (name .. "-" .. realm) or name
        local _, class = UnitClass(unit)
        if fullName and class then
            local specIcon = "0"
            if UnitIsUnit(unit, "player") then
                local specIndex = GetSpecialization()
                if specIndex then
                    local si = select(4, GetSpecializationInfo(specIndex))
                    if si then specIcon = tostring(si) end
                end
            elseif specCache[fullName] then
                specIcon = specCache[fullName]
            else
                local inQueue = false
                for _, u in ipairs(inspectQueue) do
                    if UnitIsUnit(u, unit) then inQueue = true break end
                end
                if not inQueue then
                    table.insert(inspectQueue, unit)
                    ProcessInspectQueue()
                end
            end
            
            local old = CortioRoster[fullName]
            newRoster[fullName] = {
                unit = unit,
                class = class,
                specIcon = specIcon,
                cdEnd = old and old.cdEnd or 0,
                cdTotal = old and old.cdTotal or (CLASS_INTERRUPT_CD[class] or 15)
            }
        end
    end
    
    if CortioDB and CortioDB.testMode then
        CortioRoster = {
            [playerName or "Jugador"] = { unit="player", class=playerClass or "HUNTER", specIcon="132111", cdEnd=0, cdTotal=15 },
            ["Aliado1"] = { unit="party1", class="WARRIOR", specIcon="132344", cdEnd=GetTime()+5, cdTotal=15 },
            ["Aliado2"] = { unit="party2", class="MAGE", specIcon="135856", cdEnd=0, cdTotal=24 },
        }
        return
    end

    AddUnit("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do AddUnit("raid"..i) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() do
            if UnitExists("party"..i) then AddUnit("party"..i) end
        end
    end
    
    CortioRoster = newRoster
end

local function UpdatePanel()
    for i = 1, #panelRows do
        HidePanelRow(i)
    end
    
    local entries = {}
    local now = GetTime()
    
    for rPlayerName, data in pairs(CortioRoster) do
        local rClass = data.class
        local rSpec = data.specIcon
        
        -- Buscar si este jugador tiene una marca activa asignada
        local assignedMark = nil
        for _, m in ipairs(activeMarks) do
            if m.playerName == rPlayerName then
                assignedMark = m
                break
            end
        end
        
        local color = CLASS_COLORS[rClass] or "FFFFFFFF"
        local playerStr = "|c" .. color .. ShortName(rPlayerName) .. "|r"
        
        if rSpec and rSpec ~= "0" and rSpec ~= "" then
            playerStr = "|T" .. rSpec .. ":14:14:0:0|t " .. playerStr
        end
        
        local iconID = CLASS_INTERRUPT_ICONS[rClass]
        local iconsStr = iconID and ("|T" .. iconID .. ":16:16:0:0|t ") or ""
        
        local raidStr = ""
        local markerSlot = 0
        if assignedMark and assignedMark.markerSlot and assignedMark.markerSlot > 0 then
            raidStr = GetRaidIconString(assignedMark.markerSlot, 14)
            markerSlot = assignedMark.markerSlot
        end
        
        -- Calcular Cooldown
        local cdText = ""
        local now = GetTime()
        
        -- Bypass Secret Value Taint: Todos usan sincronización por variables numéricas locales en vez de API
        local sLeft = data.cdEnd - now
        
        if sLeft > 0 then
            local ratio = sLeft / data.cdTotal
            local cdCol = "FFFF66"
            if ratio > 0.6 then cdCol = "FF4444" elseif ratio > 0.3 then cdCol = "FFAA00" end
            cdText = string.format("|cff%s%.1fs|r", cdCol, sLeft)
        else
            cdText = "|cff44FF88Ready|r"
        end
        
        table.insert(entries, { 
            icons = iconsStr, 
            raidIcon = raidStr, 
            cuttersText = playerStr, 
            playerName = rPlayerName, 
            markerSlot = markerSlot,
            cdText = cdText
        })
    end
    if #entries == 0 then
        panel:Hide()
        return
    end
    
    -- Ordenar primero por si tienen marca (y luego por markerSlot), si no tienen marca por nombre
    table.sort(entries, function(a, b)
        if a.markerSlot > 0 and b.markerSlot == 0 then return true end
        if b.markerSlot > 0 and a.markerSlot == 0 then return false end
        if a.markerSlot > 0 and b.markerSlot > 0 and a.markerSlot ~= b.markerSlot then 
            return a.markerSlot < b.markerSlot 
        end
        return a.playerName < b.playerName
    end)
    
    local idx = 0
    for _, entry in ipairs(entries) do
        idx = idx + 1
        local row = GetOrCreatePanelRow(idx)
        -- Column elements alignment
        row.raidIcon:SetText(entry.raidIcon)
        row.classIcon:SetText(entry.icons)
        row.playerText:SetText(entry.cuttersText)
        row.cdText:SetText(entry.cdText)
        row:Show()
    end
    
    -- Ocultar filas extras generadas previamente
    for i = idx + 1, #panelRows do HidePanelRow(i) end
    
    -- Altura: 25px titulo+separador + 15px por linea + 5px padding inferior
    panel:SetHeight(28 + idx * 15)
    panel:Show()
    
    -- Actualizar Nameplates por separado para evitar que errores UI oculten el panel
    SafeCall("Nameplates", UpdateAllNameplates)
end

--------------------------------------------------------------
-- LÓGICA DE MARCAS 
--------------------------------------------------------------
local function ClearPlayerMark(who)
    for i = #activeMarks, 1, -1 do
        if activeMarks[i].playerName == who then
            table.remove(activeMarks, i)
        end
    end
end

--------------------------------------------------------------
-- KEYBINDING VARIABLES
--------------------------------------------------------------
BINDING_HEADER_CORTIO_HEADER = "Cortio - Asignacion de Cortes"
BINDING_NAME_CLICK_CortioMarkSABT_LeftButton = "Poner/Quitar Marca de Corte"

--------------------------------------------------------------
-- SECURE ACTION BUTTONS para raid markers (WoW 12.0)
--------------------------------------------------------------
local CortioMarkSABT = CreateFrame("Button", "CortioMarkSABT", UIParent, "SecureActionButtonTemplate")
CortioMarkSABT:RegisterForClicks("AnyDown")
CortioMarkSABT:SetAttribute("type", "macro")
CortioMarkSABT:SetAttribute("macrotext", "/targetmarker 1")
CortioMarkSABT:SetAttribute("markerSlot", 1)
CortioMarkSABT:SetSize(1, 1)

-- Asigna un icono automaticamente del 8 (Calavera) hacia abajo segun el grupo
local function AutoAssignMarkerSlot()
    if not IsInGroup() then return 8 end
    local members = {}
    if playerName then table.insert(members, playerName) end
    
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        local u = prefix .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") then
            local n, r = UnitName(u)
            if n then
                table.insert(members, (r and r ~= "") and (n.."-"..r) or n)
            end
        end
    end
    table.sort(members)
    for i, name in ipairs(members) do
        if name == playerName then
            -- Por ejemplo: 1º=8(Calavera), 2º=7(Cruz), etc.
            return math.max(1, 9 - i)
        end
    end
    return 8
end

-- Función pura y rápida sin loops para no manchar (taint)
local function GetPlayerMarkerSlotSafe()
    if CortioDB and CortioDB.markerSlot and CortioDB.markerSlot > 0 then
        return CortioDB.markerSlot
    end
    return AutoAssignMarkerSlot()
end

function Cortio_UpdateSecureBtnMacro()
    if InCombatLockdown() then return end
    local slot = GetPlayerMarkerSlotSafe()
    CortioMarkSABT:SetAttribute("macrotext", "/targetmarker " .. tostring(slot))
    CortioMarkSABT:SetAttribute("markerSlot", slot)
end

--------------------------------------------------------------
-- ACCIÓN POST-MARCA: Sync AddonMessage y UI
--------------------------------------------------------------
local function HandlePostClick(self, button, down)
    -- Evitamos ejecuciones duplicadas de teclados
    if not down then return end

    -- Retraso de 50ms para que GetRaidTargetIndex(target) reciba la info
    C_Timer.After(0.05, function()
        EnsurePlayerInfo()
        if not playerName then return end

        local sourceUnit = "target"
        
        if not UnitExists(sourceUnit) then
            ClearPlayerMark(playerName)
            UpdatePanel()
            local ch
            if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
            elseif IsInRaid() then ch = "RAID"
            elseif IsInGroup() then ch = "PARTY"
            end
            if ch then
                local msg = "UNMARK:"..(playerClass or "UNKNOWN")..":0:0:0:0"
                local result = C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, ch)
            end
            print("|cFF00FFFF[Cortio]|r Corte retirado (sin objetivo).")
            return
        end

        local slot = CortioMarkSABT:GetAttribute("markerSlot") or GetPlayerMarkerSlotSafe()

        local targetName = UnitName(sourceUnit)
        if not targetName then return end

        local npUnit = FindNameplateUnit(sourceUnit)
        local specIndex = GetSpecialization()
        local specIcon = "0"
        if specIndex then
            local si = select(4, GetSpecializationInfo(specIndex))
            if si then specIcon = tostring(si) end
        end

        local markId = math.random(10000, 99999)

        ClearPlayerMark(playerName)

        table.insert(activeMarks, {
            playerName = playerName,
            playerClass = playerClass,
            specIcon = specIcon,
            remoteCDEnd = 0,
            remoteCDDuration = 0,
            nameplateUnit = nil,
            unitToken = "target",
            markId = markId,
            markerSlot = slot
        })
        
        local iconStr = GetRaidIconString(slot, 14)
        print("|cFF00FFFF[Cortio]|r Corte asignado" .. (slot > 0 and (" " .. iconStr) or "") .. " |cFFFFDD00" .. tostring(targetName) .. "|r")
        
        if CortioDB and CortioDB.announce then
            local ch
            if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
            elseif IsInRaid() then ch = "RAID"
            elseif IsInGroup() then ch = "PARTY"
            end
            if ch and slot > 0 then
                local iconName = "{" .. (RAID_ICON_NAMES[slot] or "") .. "}"
                SendChatMessage("[Cortio] Corte: " .. iconName .. " ➔ " .. ShortName(playerName), ch)
            end
        end

        UpdatePanel()
        UpdateAllNameplates()

        local channel
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel = "INSTANCE_CHAT"
        elseif IsInRaid() then channel = "RAID"
        elseif IsInGroup() then channel = "PARTY"
        end

        if channel then
            local msg = "MARK:"..(playerClass or "UNKNOWN")..":"..(specIcon or "0")..":"..(markId or "0")..":"..(slot or "0")..":0"
            local result = C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, channel)
            if result and Enum and Enum.SendAddonMessageResult and result ~= Enum.SendAddonMessageResult.Success then
                LogError("Send", "AddonMsg fallo: " .. tostring(result))
            end
        end
    end)
end
CortioMarkSABT:HookScript("PostClick", HandlePostClick)



--------------------------------------------------------------
-- SLASH COMMANDS (Bloqueado por Blizzard en 12.0)
--------------------------------------------------------------
SLASH_CORTIO1 = "/cortio"
SLASH_CORTIO2 = "/ct"
SlashCmdList["CORTIO"] = function(msg)
    local cmd = strsplit(" ", msg, 2)
    cmd = (cmd or ""):lower()
    
    if cmd == "mark" or cmd == "m" then
        print("|cFF00FFFF[Cortio]|r |cFFFF0000ERROR CRITICO:|r Usa un Atajo de Teclado nativo (ESC > Opciones > Atajos > AddOns > Cortio).")
    elseif cmd:match("^slot") then
        local n = tonumber(cmd:match("%d+"))
        if not CortioDB then CortioDB = {} end
        if n and n >= 1 and n <= 8 then
            CortioDB.markerSlot = n
            print(string.format("|cFF00FFFF[Cortio]|r Slot asignado: %s %s",
                GetRaidIconString(n, 14), RAID_ICON_NAMES[n] or tostring(n)))
            Cortio_UpdateSecureBtnMacro()
        elseif n == 0 then
            CortioDB.markerSlot = 0
            print("|cFF00FFFF[Cortio]|r Slot en modo automatico.")
            Cortio_UpdateSecureBtnMacro()
        else
            local curr = (CortioDB and CortioDB.markerSlot or 0)
            local currStr = curr > 0 and (GetRaidIconString(curr, 14) .. " slot " .. curr) or "automatico"
            print("|cFF00FFFF[Cortio]|r Uso: /ct slot [1-8] | /ct slot 0 (auto) | actual: " .. currStr)
            print("|cFF00FFFF[Cortio]|r Slots: 1=Estrella 2=Circulo 3=Diamante 4=Triangulo 5=Luna 6=Cuadrado 7=Cruz 8=Calavera")
        end
    elseif cmd == "show" then
        panel:SetAlpha(1)
        panel:Show()
    elseif cmd == "hide" then
        panel:Hide()
    elseif cmd == "reset" then
        if not CortioDB then CortioDB = {} end
        CortioDB.scale = 1.0
        panel:SetScale(1.0)
        panel:ClearAllPoints()
        panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
        panel:SetAlpha(1)
        panel:Show()
        print("|cFF00FFFF[Cortio]|r Panel reiniciado y forzado en pantalla.")
    elseif cmd == "errors" then
        if CortioDB and CortioDB.errors and #CortioDB.errors > 0 then
            print("|cFF00FFFF[Cortio]|r Errores (" .. #CortioDB.errors .. "):")
            for _, e in ipairs(CortioDB.errors) do
                print("|cFFFF6666  " .. e .. "|r")
            end
        else
            print("|cFF00FFFF[Cortio]|r Sin errores.")
        end
    elseif cmd == "clearerrors" or cmd == "clear" then
        if CortioDB then CortioDB.errors = {} end
        print("|cFF00FFFF[Cortio]|r Errores borrados.")
    else
        print("|cFF00FFFF[Cortio]|r Opciones: /ct show|hide | /ct errors | /ct clear")
        print("|cFF00FFFF[Cortio]|r Atajos: ESC -> Opciones -> Atajos (Keybindings).")
    end
end

--------------------------------------------------------------
-- EVENTOS
--------------------------------------------------------------
local function FindRosterPlayer(sender)
    if CortioRoster[sender] then return sender end
    local simpleName = strsplit("-", sender)
    for k in pairs(CortioRoster) do
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
        EnsurePlayerInfo()
        if not CortioDB then CortioDB = {} end
        if not CortioDB.errors then CortioDB.errors = {} end
        Cortio_UpdateSecureBtnMacro()
        RebuildRoster()
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        Cortio_UpdateSecureBtnMacro()
        
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then
        UpdateNameplate(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" or event == "FORBIDDEN_NAME_PLATE_UNIT_REMOVED" then
        for _, mark in ipairs(activeMarks) do
            if mark.nameplateUnit == arg1 then
                mark.nameplateUnit = nil
            end
        end
        ReleaseNameplateFrame(arg1)
        
    elseif event == "GROUP_ROSTER_UPDATE" then
        RebuildRoster()
        UpdatePanel()
        if not InCombatLockdown() then
            Cortio_UpdateSecureBtnMacro()
        end
        
    elseif event == "INSPECT_READY" then
        inspectPending = false
        for _, unit in pairs({"party1", "party2", "party3", "party4"}) do
            if UnitExists(unit) and UnitGUID(unit) == arg1 then
                local specId = GetInspectSpecialization(unit)
                if specId and specId > 0 then
                    local name, realm = UnitName(unit)
                    local fullName = (realm and realm ~= "") and (name .. "-" .. realm) or name
                    local specIcon = "0"
                    local si = select(4, GetSpecializationInfoByID(specId))
                    if si then specIcon = tostring(si) end
                    specCache[fullName] = specIcon
                    RebuildRoster()
                    UpdatePanel()
                end
                break
            end
        end
        C_Timer.After(0.3, ProcessInspectQueue)

    elseif event == "UNIT_DIED" then
        -- arg1 = token de la unidad que murio (puede ser "nameplateN", "target", etc.)
        -- Compara con UnitIsUnit para detectar si el NPC marcado acabo de morir.
        local cleared = false
        for i = #activeMarks, 1, -1 do
            local mark = activeMarks[i]
            if mark.nameplateUnit then
                local ok, isMatch = pcall(UnitIsUnit, mark.nameplateUnit, arg1)
                if ok and isMatch then
                    -- Si era nuestra propia marca, propagar UNMARK al grupo
                    if mark.playerName == playerName then
                        local ch
                        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
                        elseif IsInRaid() then ch = "RAID"
                        elseif IsInGroup() then ch = "PARTY"
                        end
                        if ch then
                            pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX,
                                "UNMARK:" .. (playerClass or "UNKNOWN") .. ":0:0", ch)
                        end
                    end
                    table.remove(activeMarks, i)
                    cleared = true
                end
            end
        end
        if cleared then UpdatePanel() end
        
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == COMM_PREFIX then
            local sender = select(2, ...)
            local sName = strsplit("-", sender)
            local pName = strsplit("-", playerName)
            if sender == playerName or sName == pName then return end
            
            local action, p2, p3, p4, p5, p6 = strsplit(":", arg2, 7)
            local rPlayer = FindRosterPlayer(sender) or sender
            
            if action == "CD" then
                local cdDuration = tonumber(p2)
                if cdDuration and cdDuration > 0 then
                    SafeCall("Remote_CD", function()
                        local now = GetTime()
                        for _, mark in ipairs(activeMarks) do
                            if mark.playerName == rPlayer then
                                mark.remoteCDEnd = now + cdDuration
                                mark.remoteCDDuration = cdDuration
                            end
                        end
                        if CortioRoster[rPlayer] then
                            CortioRoster[rPlayer].cdEnd = now + cdDuration
                            CortioRoster[rPlayer].cdTotal = cdDuration
                        end
                        for _, f in pairs(activeNameplates) do
                            if f and f.icons then
                                for _, ic in ipairs(f.icons) do
                                    if ic:IsShown() and ic.ownerName == rPlayer and not ic.isLocal then
                                        ic.cooldown:SetCooldown(now, cdDuration)
                                    end
                                end
                            end
                        end
                    end)
                end
            elseif action and p2 and p3 then
                local cls, specIcon, markIdStr, markerSlotStr = p2, p3, p4, p5
                local tGUID = (p6 and p6 ~= "") and p6 or nil
                local mId = markIdStr and tonumber(markIdStr) or nil
                local markerSlot = markerSlotStr and tonumber(markerSlotStr) or 0
                if action == "MARK" then
                    ClearPlayerMark(rPlayer)
                    local uToken = nil
                    if GetNumGroupMembers() > 0 then
                        local prefix = IsInRaid() and "raid" or "party"
                        for i = 1, GetNumGroupMembers() do
                            local u = prefix .. i
                            if UnitExists(u) then
                                local n, r = UnitName(u)
                                if n then
                                    local fN = (r and r ~= "") and (n.."-"..r) or n
                                    local sN = strsplit("-", rPlayer)
                                    if fN == rPlayer or n == sN then
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
                    table.insert(activeMarks, newMark)
                elseif action == "UNMARK" then
                    ClearPlayerMark(rPlayer)
                end
                UpdatePanel()
                UpdateAllNameplates()
            end
        end
    end
end)

--------------------------------------------------------------
-- DETECCIÓN DE CAST DE INTERRUPCIÓN → BROADCAST CD
--------------------------------------------------------------
local castDetectFrame = CreateFrame("Frame")
castDetectFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castDetectFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" then return end
    if not INTERRUPT_SPELLID_SET[spellID] then return end
    if not playerClass then return end
    
    -- Nuestro interrupt se ha lanzado con éxito → broadcast CD al grupo
    local cdDuration = CLASS_INTERRUPT_CD[playerClass]
    if not cdDuration then return end
    
    -- Aplicar localmente también
    if CortioRoster[playerName] then
        CortioRoster[playerName].cdEnd = GetTime() + cdDuration
        CortioRoster[playerName].cdTotal = cdDuration
    end
    
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        channel = "RAID"
    elseif IsInGroup() then
        channel = "PARTY"
    end
    
    if channel then
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, "CD:" .. cdDuration, channel)
    end
end)

--------------------------------------------------------------
-- COOLDOWN OVERLAY para el icono de corte del JUGADOR
--------------------------------------------------------------

-- Crear frame contenedor del icono (32x32) anclado a la izquierda del panel
local kickIconFrame = CreateFrame("Frame", "CortioKickIconFrame", panel)
kickIconFrame:SetSize(32, 32)
kickIconFrame:SetPoint("RIGHT", panel, "LEFT", -6, 0)

-- Textura del icono (se rellenará al cargar según la clase del jugador)
local kickIconTexture = kickIconFrame:CreateTexture(nil, "ARTWORK")
kickIconTexture:SetAllPoints(kickIconFrame)

-- Borde fino para que se vea más limpio
local kickIconBorder = kickIconFrame:CreateTexture(nil, "OVERLAY")
kickIconBorder:SetAllPoints(kickIconFrame)
kickIconBorder:SetAtlas("UI-HUD-ActionBar-IconFrame")  -- borde nativo de action bar
-- Fallback si el atlas no existe (Classic/viejas):
if not kickIconBorder:GetAtlas() then
    kickIconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    kickIconBorder:SetAllPoints(kickIconFrame)
end

-- CooldownFrame nativo (el swipe visual)
local kickCooldown = CreateFrame("Cooldown", "CortioKickCooldown", kickIconFrame, "CooldownFrameTemplate")
kickCooldown:SetAllPoints(kickIconFrame)
kickCooldown:SetDrawSwipe(true)     -- animación de barrido oscuro
kickCooldown:SetDrawEdge(true)      -- línea brillante en el borde del barrido
kickCooldown:SetDrawBling(true)     -- destello al terminar el CD
kickCooldown:SetSwipeColor(0, 0, 0, 0.65)  -- negro semitransparente
kickCooldown:SetHideCountdownNumbers(false) -- mostrar números de CD si el usuario los tiene activados

-- Actualizar el cooldown del icono local
local myInterruptSpellID = nil

local function UpdateKickCooldown()
    if not myInterruptSpellID or not CortioRoster[playerName] then return end
    local cdEnd = CortioRoster[playerName].cdEnd
    local cdTotal = CortioRoster[playerName].cdTotal
    if cdEnd and cdTotal and cdEnd > GetTime() then
        kickCooldown:SetCooldown(cdEnd - cdTotal, cdTotal)
    else
        kickCooldown:SetCooldown(0, 0)
    end
end

-- Configurar el icono según la clase del jugador
local function SetupKickIcon()
    EnsurePlayerInfo()
    if not playerClass then return end

    myInterruptSpellID = CLASS_INTERRUPT_SPELLID[playerClass]
    local iconID = CLASS_INTERRUPT_ICONS[playerClass]

    if iconID then
        kickIconTexture:SetTexture(tonumber(iconID))
        kickIconFrame:Show()
    else
        kickIconFrame:Hide()
    end

    UpdateKickCooldown()
end

local cdEventFrame = CreateFrame("Frame")
cdEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
cdEventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        SetupKickIcon()
    end
end)

-- Vincular visibilidad del icono al panel
panel:HookScript("OnShow", function()
    if myInterruptSpellID then
        kickIconFrame:Show()
        UpdateKickCooldown()
    end
end)
panel:HookScript("OnHide", function()
    kickIconFrame:Hide()
end)

-- Inicialmente oculto (el panel empieza oculto)
kickIconFrame:Hide()

panel:Hide()

local ticker = 0
panel:SetScript("OnUpdate", function(self, elapsed)
    ticker = ticker + elapsed
    if ticker >= 0.25 then
        ticker = 0
        if self:IsShown() then
            UpdatePanel()
        end
        -- El Nameplate scanner debe correr SIEMPRE en background para enlazar
        -- instantaneamente las nuevas marcas de grupo que puedan entrar en pantalla.
        UpdateAllNameplates()
    end
end)

--------------------------------------------------------------
-- SETTINGS PANEL
--------------------------------------------------------------
local function CreateSettingsMenu()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end
    
    local category = Settings.RegisterVerticalLayoutCategory("Cortio")
    
    local scaleSetting = Settings.RegisterProxySetting(
        category, "Cortio_Scale", Settings.VarType.Number, "Tamaño de la Ventana", 
        (CortioDB and CortioDB.scale) or 1.0, 
        function() return (CortioDB and CortioDB.scale) or 1.0 end,
        function(val) 
            if not CortioDB then CortioDB = {} end
            CortioDB.scale = val 
            panel:SetScale(val) 
        end
    )
    local scaleOpts = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
    scaleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.2fx", v) end)
    Settings.CreateSlider(category, scaleSetting, scaleOpts, "Ajusta la escala del panel flotante.")
    
    local announceSetting = Settings.RegisterProxySetting(
        category, "Cortio_Announce", Settings.VarType.Boolean, "Anunciar asignaciones en grupo", 
        (not CortioDB or CortioDB.announce == nil) and true or CortioDB.announce, 
        function() return (not CortioDB or CortioDB.announce == nil) and true or CortioDB.announce end,
        function(val) 
            if not CortioDB then CortioDB = {} end
            CortioDB.announce = val 
        end
    )
    Settings.CreateCheckbox(category, announceSetting, "Enviar mensaje al chat de grupo /p cada vez que cambias tu marca.")
    
    local testSetting = Settings.RegisterProxySetting(
        category, "Cortio_TestMode", Settings.VarType.Boolean, "Modo de Prueba (Test Mode)", 
        (CortioDB and CortioDB.testMode) or false, 
        function() return (CortioDB and CortioDB.testMode) or false end,
        function(val) 
            if not CortioDB then CortioDB = {} end
            CortioDB.testMode = val
            RebuildRoster()
            if val then panel:Show() else panel:Hide() end
        end
    )
    Settings.CreateCheckbox(category, testSetting, "Genera un grupo falso para probar la interfaz de cortes.")
    
    Settings.RegisterAddOnCategory(category)
end

-- Aplicar escala guardada
C_Timer.After(0.5, function()
    if CortioDB and CortioDB.scale then panel:SetScale(CortioDB.scale) end
    CreateSettingsMenu()
end)

print("|cFF00FFFF[Cortio]|r Cargado. Asigna la tecla en: ESC -> Atajos -> AddOns -> Cortio")
