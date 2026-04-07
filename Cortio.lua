--------------------------------------------------------------
-- CORTIO - Asistente de cortes para WoW 12.0
-- UnitIsUnit + nameplate tokens para identificación de NPCs.
-- Los nombres de NPCs son "secret values" en instancias (WoW 12.0);
-- la identificación remota se hace via UnitTarget(partyN) + UnitIsUnit.
--------------------------------------------------------------

local COMM_PREFIX = "CORTIO"

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
        -- Eliminamos securecallfunction porque TODO lo que retorna se contamina automáticamente con Taint.
        -- Eso provocaba que "playerName" y "playerClass" envenenaran cada mensaje de la red (Fallo 11).
        local n, r = UnitName("player")
        if n then
            playerName = (r and r ~= "") and (n .. "-" .. r) or n
            local _, cls = UnitClass("player")
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

-- Iconos de corte de cada clase (FileDataID verificado en wago.tools para parche 12.0)
local CLASS_INTERRUPT_ICONS = {
    WARRIOR     = "132938",   -- Pummel          (inv_gauntlets_04)
    PALADIN     = "523893",   -- Rebuke           (spell_holy_rebuke)
    HUNTER      = "249170",   -- Counter Shot     (inv_ammo_arrow_03)
    ROGUE       = "132219",   -- Kick             (ability_kick)             ✓
    PRIEST      = "458230",   -- Silence          (ability_priest_silence)
    DEATHKNIGHT = "237527",   -- Mind Freeze      (spell_deathknight_mindfreeze)
    SHAMAN      = "136018",   -- Wind Shear       (spell_nature_cyclone)     ✓
    MAGE        = "135856",   -- Counterspell     (spell_frost_iceshock)     ✓
    WARLOCK     = "136174",   -- Spell Lock       (spell_shadow_mindrot)     ✓
    MONK        = "608940",   -- Spear Hand Strike(ability_monk_spearhand)
    DRUID       = "133732",   -- Skull Bash       (inv_misc_bone_taurenskull_01)
    DEMONHUNTER = "1305153",  -- Disrupt          (ability_demonhunter_consumemagic)
    EVOKER      = "4622469",  -- Quell            (ability_evoker_quell)
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
    WARRIOR     = 15,   -- Pummel
    PALADIN     = 15,   -- Rebuke
    HUNTER      = 24,   -- Counter Shot / Muzzle (Survival)
    ROGUE       = 15,   -- Kick
    PRIEST      = 45,   -- Silence
    DEATHKNIGHT = 15,   -- Mind Freeze
    SHAMAN      = 12,   -- Wind Shear
    MAGE        = 24,   -- Counterspell base (talentos pueden reducir a 20s)
    WARLOCK     = 24,   -- Spell Lock
    MONK        = 15,   -- Spear Hand Strike
    DRUID       = 15,   -- Skull Bash
    DEMONHUNTER = 15,   -- Disrupt
    EVOKER      = 40,   -- Quell
}
-- NOTA: estos valores son CDs BASE sin talentos. Para el jugador LOCAL, Cortio
-- lee el CD real de C_Spell.GetSpellCooldown() al hacer el corte (incluye talentos).

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
-- Bypass Tainted Secret Booleans (WoW 12.0 API Crash)
-- UnitIsUnit(partyNtarget, nameplateX) devuelve un 'secret boolean'.
-- Evaluarlo en un 'if' directo crashea Lua. Usamos doble-pcall.
--------------------------------------------------------------
local function SafeIsMatch(token, npUnit)
    if not token or not npUnit then return false end
    local ok, match = pcall(UnitIsUnit, token, npUnit)
    if not ok then return false end
    local evalOk, evalResult = pcall(function() return match == true end)
    if not evalOk then return false end
    return evalResult
end

--------------------------------------------------------------
-- HELPER: buscar qué nameplateN corresponde a un unit token
--------------------------------------------------------------
local function FindNameplateUnit(unit)
    for i = 1, 40 do
        local npUnit = "nameplate" .. i
        if UnitExists(npUnit) and SafeIsMatch(npUnit, unit) then
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

-- Ya no intentamos leer GetRaidTargetIndex ni propiedades visuales de nameplates directamente, Blizzard lo marca como secret properties y revienta Lua incluso dentro de pcall.
local function UpdateNameplate(unit)
    local marks = {}

    for _, mark in ipairs(activeMarks) do
        local isMatch = false
        
        -- Cache permanente: si ya sabemos el nameplateUnit, match directo.
        if mark.nameplateUnit == unit then
            isMatch = true
        elseif not mark.nameplateUnit and mark.unitToken then
            -- GetNamePlateForUnit YA NO acepta "target" en 12.0 (tira error "bad argument #1").
            -- En su lugar, comparamos con UnitIsUnit explícitamente solo si es "target" (que sí es seguro comparar).
            -- Tokens compuestos ("party1target") detonan la alarma de Addon bloqueado de Blizzard incluso en pcall, se purgan.
            if mark.unitToken == "target" and UnitExists("target") then
                if SafeIsMatch("target", unit) then
                    isMatch = true
                    mark.unitToken = nil  -- ancla fijada al nameplate, minimizamos futuras llamadas al motor
                end
            else
                -- Token remoto compuesto: imposible anclar el icono de placa en WoW 12.0 instanciado sin target local.
                -- El seguimiento de los compañeros seguirá mostrándose puramente a través del Panel Grande.
                mark.unitToken = nil
            end
        end

        if isMatch then
            mark.nameplateUnit = unit
            table.insert(marks, mark)
        -- Si esta placa antes era nuestra pero ya no cumple (ej. perdió la marca de banda o cambió el objetivo)
        elseif mark.nameplateUnit == unit then
            mark.nameplateUnit = nil
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
        -- C_Timer.After: NotifyInspect desde frame limpio para evitar el diálogo
        -- de "acción bloqueada" cuando se llama desde event handlers taintados (M+).
        C_Timer.After(0, function()
            if UnitExists(unit) and CanInspect(unit) then
                NotifyInspect(unit)
            else
                inspectPending = false
                C_Timer.After(0.5, ProcessInspectQueue)
            end
        end)
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
    else
        -- TAINT-SAFE: IsInGroup() sin argumento = LE_PARTY_CATEGORY_HOME.
        -- En M+ formado manualmente (premade) IsInGroup() = true.
        -- En M+ via LFG/instancia, IsInGroup(LE_PARTY_CATEGORY_INSTANCE) = true.
        -- Comprobamos ambos para cubrir todos los casos.
        local inHomeGroup     = IsInGroup()
        local inInstanceGroup = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        if inHomeGroup or inInstanceGroup then
            -- party1..party4 funcionan siempre para grupos de 5; los tokens son iguales
            -- tanto para HOME como para INSTANCE party en WoW 12.0.
            for i = 1, 4 do
                if UnitExists("party"..i) then AddUnit("party"..i) end
            end
        end
    end
    
    CortioRoster = newRoster
end

-- Re‑intento de roster: al entrar al mundo los party members pueden tardar
-- unos segundos en estar disponibles (especialmente tras una pantalla de carga larga).
local function RebuildRosterWithRetry()
    RebuildRoster()
    -- Si sólo tenemos al jugador local pero deberíamos tener grupo, reintentamos.
    C_Timer.After(3, function()
        local count = 0
        for _ in pairs(CortioRoster) do count = count + 1 end
        if count <= 1 and (IsInGroup() or IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or IsInRaid()) then
            RebuildRoster()
            UpdatePanel()
        end
    end)
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
-- Frame dedicado para actualizar el macro del botón seguro.
-- OnUpdate corre siempre en un hilo limpio, sin taint de eventos previos.
-- Cuando necesitamos actualizar SetAttribute, encendemos la flag y este frame lo ejecuta.
local secureBtnNeedsUpdate = false
local secureBtnFrame = CreateFrame("Frame")
secureBtnFrame:SetScript("OnUpdate", function(self, elapsed)
    if secureBtnNeedsUpdate and not InCombatLockdown() then
        secureBtnNeedsUpdate = false
        Cortio_UpdateSecureBtnMacro()
    end
end)

-- Encola una actualización del macro de forma segura (puede llamarse desde cualquier contexto)
local function QueueSecureBtnUpdate()
    secureBtnNeedsUpdate = true
end

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

-- Asigna un icono automaticamente sin colisionar con slots ya usados por otros
local function AutoAssignMarkerSlot()
    if not IsInGroup() and not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInRaid() then return 8 end
    if IsInRaid() then
        -- En raid podemos identificar nuestra posicion con UnitIsUnit (sin taint)
        for i = 1, GetNumGroupMembers() do
            if UnitIsUnit("raid"..i, "player") then
                return math.max(1, 9 - i)  -- 1º=8, 2º=7, etc.
            end
        end
    end
    -- PARTY (M+): asignar el slot libre más alto que no use ningún otro jugador.
    -- Leemos activeMarks para saber qué slots ya han sido reclamados.
    -- Si nadie ha marcado aún, tomamos el 8 (Calavera) por defecto.
    local usedSlots = {}
    for _, mark in ipairs(activeMarks) do
        if mark.playerName ~= playerName and mark.markerSlot and mark.markerSlot > 0 then
            usedSlots[mark.markerSlot] = true
        end
    end
    for slot = 8, 1, -1 do
        if not usedSlots[slot] then return slot end
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
    local lines = {"/targetmarker " .. tostring(slot)}
    if CortioDB and CortioDB.announce then
        local sName = playerName and ShortName(playerName) or "?"
        if #sName > 12 then sName = sName:sub(1, 12) end
        local chatIcon = slot > 0 and ("{rt" .. slot .. "}") or ""
        -- SIN %t: el nombre del objetivo NPC es un "secret value" en instancias M+.
        -- Usarlo en el macro contamina el chat frame y causa crash en UpdateHeader.
        local txt = chatIcon .. " [Cortio] " .. sName .. " corta!"
        table.insert(lines, "/i [group:instance] " .. txt)
        table.insert(lines, "/p [nogroup:instance,group] " .. txt)
    end
    CortioMarkSABT:SetAttribute("macrotext", table.concat(lines, "\n"))
    CortioMarkSABT:SetAttribute("markerSlot", slot)
end

--------------------------------------------------------------
-- ACCIÓN POST-MARCA: Sync AddonMessage y UI
--------------------------------------------------------------

-- Búfer de Red (Bypass Hardware Event Taint / Fallo 11)
-- Blizzard (v10+) ensucia con Taint cualquier C_ChatInfo que derive de un hardware click
-- o de un C_Timer anidado en él. El frame OnUpdate es 100% puro e independiente.
local netQueue = {}
local netFrame = CreateFrame("Frame")
netFrame:SetScript("OnUpdate", function(self, elapsed)
    if #netQueue > 0 then
        local job = table.remove(netQueue, 1)
        local result = C_ChatInfo.SendAddonMessage(job.prefix, job.msg, job.channel)
        if result and result ~= 0 then 
            LogError(job.tag, "AddonMsg fallo ("..job.channel.."): " .. tostring(result)) 
        end
    end
end)

local function HandlePostClick(self, button, down)
    -- Evitamos ejecuciones duplicadas de teclados
    if not down then return end

    -- Retraso de 50ms para que el motor procese /targetmarker antes de que leamos el estado.
    -- NOTA: el announce en chat YA fue enviado por el macrotext del botón seguro (corre antes
    -- de PostClick). Aquí solo sincronizamos el addon (AddonMessage) y la UI local.
    C_Timer.After(0.05, function()
        EnsurePlayerInfo()
        if not playerName then return end

        local ch
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
        elseif IsInRaid() then ch = "RAID"
        elseif IsInGroup() then ch = "PARTY"
        end

        local slot = GetPlayerMarkerSlotSafe()
        local specIndex = GetSpecialization()
        local specIcon = "0"
        if specIndex then
            local si = select(4, GetSpecializationInfo(specIndex))
            if si then specIcon = tostring(si) end
        end
        local markId = math.floor(GetTime() * 1000) % 100000

        -- Aislamos la creación de strings del entorno antes de interactuar con el motor (UnitName)
        local msgMark = "MARK:"..(playerClass or "UNKNOWN")..":"..(specIcon or "0")..":"..(markId or "0")..":"..(slot or "0")..":0"
        local msgUnmark = "UNMARK:"..(playerClass or "UNKNOWN")..":0:0:0:0"

        local sourceUnit = "target"
        
        if not UnitExists(sourceUnit) then
            ClearPlayerMark(playerName)
            UpdatePanel()
            if ch then
                table.insert(netQueue, {prefix=COMM_PREFIX, msg=msgUnmark, channel=ch, tag="Send"})
            end
            print("|cFF00FFFF[Cortio]|r Corte retirado (sin objetivo).")
            return
        end

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

        if ch then
            table.insert(netQueue, {prefix=COMM_PREFIX, msg=msgMark, channel=ch, tag="Send"})
        end

        -- ¡CRÍTICO! Validamos TODA la UI y C++ Frame APIs ANTES de tocar UnitName()
        UpdatePanel()
        UpdateAllNameplates()

        -- *************** ZONA DE PELIGRO DE TAINT ****************
        -- CUALQUIER COSA DEBAJO DE ESTA LÍNEA ENVENENARÁ EL HILO EN 12.0
        local targetName = UnitName(sourceUnit)
        if not targetName then return end
        
        local iconStr = GetRaidIconString(slot, 14)
        -- El mensaje de chat ya lo enviamos desde el macro del botón seguro (sin taint).
        -- Aquí solo mostramos confirmación LOCAL en el chat del jugador.
        print("|cFF00FFFF[Cortio]|r Corte asignado" .. (slot > 0 and (" " .. iconStr) or "") .. " |cFFFFDD00" .. tostring(targetName) .. "|r")
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
        
        -- Limpiar marks activos al entrar al mundo.
        activeMarks = {}
        for unit, _ in pairs(activeNameplates) do
            ReleaseNameplateFrame(unit)
        end
        
        -- Registrar prefijo addon.
        local function SafeRegisterPrefix()
            if not C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX) then
                C_Timer.After(2, SafeRegisterPrefix)
            end
        end
        SafeRegisterPrefix()
        
        if not CortioDB then CortioDB = {} end
        if not CortioDB.errors then CortioDB.errors = {} end
        
        -- TAINT-SAFE: RebuildRoster toca UnitName/UnitIsUnit y mancha el hilo.
        -- Cortio_UpdateSecureBtnMacro llama SetAttribute que necesita hilo LIMPIO.
        -- Solución: RebuildRoster PRIMERO, luego SetAttribute con delay 2s en frame dedicado.
        -- El frame secureBtnUpdateFrame nunca registra eventos que puedan taintarlo.
        RebuildRosterWithRetry()
        -- Encolar actualización del macro via OnUpdate: garantiza hilo limpio.
        QueueSecureBtnUpdate()
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Encolar actualización del macro via OnUpdate (hilo limpio, fuera de combate)
        QueueSecureBtnUpdate()
        
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
            QueueSecureBtnUpdate()
        end
        
    elseif event == "INSPECT_READY" then
        inspectPending = false
        -- Construir lista de unidades a revisar (party en dungeon, raid en raid)
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
                -- UnitGUID en instancias puede devolver un "secret value" que explota en comparaciones
                -- directas (==). Envolvemos en pcall para blindar contra el crash de taint.
                local okGuid, guid = pcall(UnitGUID, unit)
                if okGuid and guid and guid == arg1 then
                    local specId = GetInspectSpecialization(unit)
                    if specId and specId > 0 then
                        -- UnitName en instancias también puede ser secret; pcall defensivo
                        local okName, name, realm = pcall(UnitName, unit)
                        if okName and name then
                            local fullName = (realm and realm ~= "") and (name .. "-" .. realm) or name
                            local specIcon = "0"
                            local si = select(4, GetSpecializationInfoByID(specId))
                            if si then specIcon = tostring(si) end
                            specCache[fullName] = specIcon
                            RebuildRoster()
                            UpdatePanel()
                        end
                    end
                    break
                end
            end
        end
        C_Timer.After(0.3, ProcessInspectQueue)

    elseif event == "UNIT_DIED" then
        -- arg1 = token de la unidad que murio (puede ser "nameplateN", "target", etc.)
        -- Compara con UnitIsUnit para detectar si el NPC marcado acabo de morir.
        local cleared = false
        
        -- Bypass Secret String: si arg1 es un nameplate en mazmorras, comparar con "==" destruye la ejecución.
        local ok, isTargetStr = pcall(function() return arg1 == "target" end)
        isTargetStr = ok and isTargetStr
        
        for i = #activeMarks, 1, -1 do
            local mark = activeMarks[i]
            local shouldClear = false

            if mark.nameplateUnit then
                -- Omitimos la comparación "==" directa porque mark.nameplateUnit y arg1 pueden tener Taints mezclados
                -- Usamos exclusivamente SafeIsMatch que envuelve la lectura de C++ en pcalls blindados
                if SafeIsMatch(mark.nameplateUnit, arg1) then
                    shouldClear = true
                end
            end

            -- Si es nuestra marca, todavía no tenía ancla 3D, y se muere nuestro "target" explícito
            if not shouldClear and mark.playerName == playerName and not mark.nameplateUnit then
                if isTargetStr or SafeIsMatch(arg1, "target") then
                    shouldClear = true
                end
            end

            if shouldClear then
                -- Si era nuestra propia marca, propagar UNMARK al grupo
                if mark.playerName == playerName then
                    local ch
                    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
                    elseif IsInRaid() then ch = "RAID"
                    elseif IsInGroup() then ch = "PARTY"
                    end
                    if ch then
                        local msg = "UNMARK:" .. (playerClass or "UNKNOWN") .. ":0:0"
                        table.insert(netQueue, {prefix=COMM_PREFIX, msg=msg, channel=ch, tag="Send"})
                    end
                end
                table.remove(activeMarks, i)
                cleared = true
            end
        end
        if cleared then UpdatePanel() end
        
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == COMM_PREFIX then
            -- CHAT_MSG_ADDON args: prefix(arg1), text(arg2), channel, sender, target, ...
            -- '...' aqui = channel, sender, target, ... => sender es select(2, ...)
            -- PERO en el handler (self, event, arg1, arg2, ...) el '...' empieza en arg3
            -- arg3=channel, arg4=sender => sender = select(2, ...) es CORRECTO solo si
            -- los args extra incluyen channel como 1er elemento.
            -- Verificado: CHAT_MSG_ADDON payload: prefix, text, channelType, sender, ...
            -- Con arg1=prefix, arg2=text, el vararg '...' = channelType, sender, target, ...
            -- Por tanto sender = select(2, ...) apunta al 2do elemento de '...' = SENDER ✓
            local _, sender = ...   -- _ = channelType, sender = sender
            if not sender then return end
            local sName = strsplit("-", sender)
            local pName = playerName and strsplit("-", playerName) or ""
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
                        -- Fix 5: refrescar panel inmediatamente al recibir CD remoto
                        UpdatePanel()
                    end)
                end
            elseif action and p2 and p3 then
                local cls, specIcon, markIdStr, markerSlotStr = p2, p3, p4, p5
                local tGUID = (p6 and p6 ~= "") and p6 or nil
                local mId = markIdStr and tonumber(markIdStr) or nil
                local markerSlot = markerSlotStr and tonumber(markerSlotStr) or 0
                if action == "MARK" then
                    ClearPlayerMark(rPlayer)

                    -- Calcular nuestro slot ANTES de registrar el mark del otro
                    -- (para saber si hay colisión después)
                    local ourSlotBefore = GetPlayerMarkerSlotSafe()

                    -- Buscar el token de la unidad del remoto (party1target, etc.)
                    local uToken = nil
                    for i = 1, 4 do
                        local u = "party" .. i
                        if UnitExists(u) then
                            if CortioRoster[rPlayer] and CortioRoster[rPlayer].unit == u then
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
                    table.insert(activeMarks, newMark)

                    -- Detección de colisión: tras insertar el mark del otro,
                    -- si AutoAssignMarkerSlot ahora devuelve un slot distinto al que
                    -- teníamos antes, significa que nos pisó el slot → reasignamos.
                    -- Solo aplica en modo automático (CortioDB.markerSlot == 0 o nil).
                    local ourSlotFixed = not CortioDB or (CortioDB.markerSlot or 0) == 0
                    if ourSlotFixed and markerSlot > 0 and markerSlot == ourSlotBefore then
                        -- El otro tomó exactamente nuestro slot auto-asignado → pedir reasignación
                        -- AutoAssignMarkerSlot ahora excluirá el slot del otro y devolverá el siguiente
                        QueueSecureBtnUpdate()
                    end
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
-- Fix: forward declaration para que el closure del handler vea UpdateKickCooldown
-- (se define más abajo junto a kickCooldown, pero la referencia en el closure
-- se resuelve en tiempo de ejecución gracias a la upvalue capturada aquí).
local UpdateKickCooldown  -- forward declaration
local lastInterruptBroadcastTime = 0

local castDetectFrame = CreateFrame("Frame")
-- TAINT-SAFE: Solo usamos UNIT_SPELLCAST_SUCCEEDED.
-- COMBAT_LOG_EVENT_UNFILTERED devuelve secret values en instancias M+ (sourceName de NPCs,
-- spellIds de boss abilities, etc.) que contaminan el hilo y hacen fallar SendAddonMessage.
castDetectFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castDetectFrame:SetScript("OnEvent", function(self, event, ...)
    local isInterrupt = false
    local cdDuration = 15

    -- UNIT_SPELLCAST_SUCCEEDED dispara para "player", "party1".."party4", "raid1"..etc.
    -- spellID aqui es siempre un numero limpio (es un spell de jugador, nunca secret).
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
        if not INTERRUPT_SPELLID_SET[spellID] then return end  -- salida rapida

        if unit == "player" and playerClass then
            -- *** Jugador LOCAL: broadcast CD al grupo ***
            isInterrupt = true
            cdDuration = CLASS_INTERRUPT_CD[playerClass] or 15

        elseif unit ~= "player" then
            -- *** Jugador REMOTO: buscar en roster por unit token (sin UnitName) ***
            -- CortioRoster guarda pData.unit = "party1" etc. desde RebuildRoster.
            -- Comparar unit tokens es 100% seguro, no genera taint.
            local now = GetTime()
            for pName, pData in pairs(CortioRoster) do
                if pData.unit == unit then
                    local rCD = CLASS_INTERRUPT_CD[pData.class] or 15
                    CortioRoster[pName].cdEnd   = now + rCD
                    CortioRoster[pName].cdTotal  = rCD
                    UpdatePanel()
                    break
                end
            end
        end
    end
    
    if isInterrupt then
        -- Fix 3: guard anti-doble-disparo (1 segundo de ventana)
        local now = GetTime()
        if now - lastInterruptBroadcastTime < 1 then return end
        lastInterruptBroadcastTime = now
        
        -- Aplicar localmente
        if CortioRoster[playerName] then
            CortioRoster[playerName].cdEnd = now + cdDuration
            CortioRoster[playerName].cdTotal = cdDuration
        end
        
        -- Fix 2: refrescar UI local inmediatamente sin esperar el ticker
        UpdatePanel()
        UpdateKickCooldown()
        
        local channel
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel = "INSTANCE_CHAT"
        elseif IsInRaid() then channel = "RAID"
        elseif IsInGroup() then channel = "PARTY"
        end
        
        if channel then
            local msg = "CD:" .. cdDuration
            table.insert(netQueue, {prefix=COMM_PREFIX, msg=msg, channel=channel, tag="CD"})
        end
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

UpdateKickCooldown = function()  -- asigna la forward declaration de arriba
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
