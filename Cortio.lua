--------------------------------------------------------------
-- CORTIO - Asistente de cortes para WoW 12.0
--------------------------------------------------------------
-- CORTIO - Asistente de cortes para WoW 12.0
-- ARQUITECTURA "ZERO GUID + NAMEPLATE TOKEN":
-- En WoW 12.0, UnitGUID en nameplates devuelve "secret strings" intocables.
-- Usamos UnitName + nameplate unit token para asegurar que solo una instancia se marque.
--------------------------------------------------------------
local addonName, _ = ...

local COMM_PREFIX = "CORTIO"
C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)

-- { { npcName, playerName, playerClass, specIcon, remoteCDEnd, remoteCDDuration, nameplateUnit }, ... }
local activeMarks = {}   
local playerName, playerClass

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
        local n = securecallfunction(UnitName, "player")
        local r = securecallfunction(GetNormalizedRealmName)
        if n and r then
            playerName = n .. "-" .. r
            local _, cls = securecallfunction(UnitClass, "player")
            playerClass = cls
        end
    end
end

--------------------------------------------------------------
-- PANEL FLOTANTE
--------------------------------------------------------------
local panel = CreateFrame("Frame", "CortioPanelFrame", UIParent, "BackdropTemplate")
panel:SetSize(220, 30)
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
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
panel:SetBackdropColor(0.05, 0.05, 0.1, 0.85)
panel:SetBackdropBorderColor(0, 0.8, 0.8, 0.7)

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOP", panel, "TOP", 0, -6)
title:SetText("|cFF00FFFF⚔ CORTIO|r")

local textLines = {}
local MAX_LINES = 8
for i = 1, MAX_LINES do
    local line = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -18 - (i - 1) * 14)
    line:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    line:SetJustifyH("LEFT")
    line:SetWordWrap(false)
    line:Hide()
    textLines[i] = line
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



-- Aplicar cooldown del interrupt del jugador local a un icono
local function ApplyLocalCooldown(iconFrame)
    if C_Spell and C_Spell.GetSpellCooldown then
        local spellID = CLASS_INTERRUPT_SPELLID and CLASS_INTERRUPT_SPELLID[playerClass]
        if spellID then
            local info = C_Spell.GetSpellCooldown(spellID)
            if info then
                iconFrame.cooldown:SetCooldown(info.startTime, info.duration)
                return
            end
        end
    elseif GetSpellCooldown then
        local spellID = CLASS_INTERRUPT_SPELLID and CLASS_INTERRUPT_SPELLID[playerClass]
        if spellID then
            iconFrame.cooldown:SetCooldown(GetSpellCooldown(spellID))
            return
        end
    end
    iconFrame.cooldown:Clear()
end

local function UpdateNameplate(unit)
    local npcName = UnitName(unit)
    if not npcName then return end
    
    local marks = {}
    for _, mark in ipairs(activeMarks) do
        -- Si ya está asignada a ESTE nameplate en concreto
        if mark.nameplateUnit == unit then
            table.insert(marks, mark)
        -- Si no está asignada a nadie, INTENTAR asignarla mediante el nombre
        elseif not mark.nameplateUnit then
            -- Pcall vital: Blizzard devuelve secret strings tintados desde UnitName("nameplateN") en las mazmorras
            -- Si se intenta comparar "==" se produce un error fatal. pcall lo previene silenciosamente.
            local ok, match = pcall(function() return mark.npcName == npcName end)
            if ok and match then
                mark.nameplateUnit = unit
                table.insert(marks, mark)
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
    
    if not f then
        f = GetNameplateFrame()
        activeNameplates[unit] = f
    end
    
    f:SetParent(UIParent)
    f:ClearAllPoints()
    f:SetPoint("RIGHT", np, "LEFT", -2, 0)
    
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
                    ApplyLocalCooldown(ic)
                else
                    ic.isLocal = false
                    if mark.remoteCDEnd and mark.remoteCDDuration and mark.remoteCDEnd > GetTime() then
                        ic.cooldown:SetCooldown(mark.remoteCDEnd - mark.remoteCDDuration, mark.remoteCDDuration)
                    else
                        ic.cooldown:Clear()
                    end
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

-- Actualizar SOLO los cooldowns de los iconos locales en nameplates activos
-- (sin reconstruir frames — llamada ligera para SPELL_UPDATE_COOLDOWN)
local function UpdateNameplateCooldowns()
    for _, f in pairs(activeNameplates) do
        if f and f.icons then
            for _, ic in ipairs(f.icons) do
                if ic:IsShown() and ic.isLocal then
                    ApplyLocalCooldown(ic)
                end
            end
        end
    end
end

local function UpdateAllNameplates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            UpdateNameplate(unit)
        end
    end
end

local function UpdatePanel()
    for _, line in ipairs(textLines) do
        line:SetText("")
        line:Hide()
    end
    
    local entries = {}
    for _, mark in ipairs(activeMarks) do
        -- No podemos usar mark.npcName como llave de un diccionario (grouped[npc]) porque
        -- mark.npcName puede ser un Secret String de WoW 12.0. Las variables taint desaparecen de pairs().
        local color = CLASS_COLORS[mark.playerClass] or "FFFFFFFF"
        local playerStr = "|c" .. color .. ShortName(mark.playerName) .. "|r"
        
        if mark.specIcon and mark.specIcon ~= "0" and mark.specIcon ~= "" then
            playerStr = "|T" .. mark.specIcon .. ":14:14:0:0|t " .. playerStr
        end
        
        local iconID = CLASS_INTERRUPT_ICONS[mark.playerClass]
        local iconsStr = iconID and ("|T" .. iconID .. ":16:16:0:0|t ") or ""
        
        table.insert(entries, { npc = mark.npcName, icons = iconsStr, cuttersText = playerStr, playerName = mark.playerName })
    end
    
    SafeCall("Upd_Nameplates", UpdateAllNameplates) -- Actualizar placas de mundo 3D aislándolo del panel
    
    if #entries == 0 then
        panel:Hide()
        return
    end
    
    -- Ordenamos por el nombre del jugador porque hacer (a.npc < b.npc) crashearía la ejecución si npc es Secret String
    table.sort(entries, function(a, b) return a.playerName < b.playerName end)
    
    local idx = 0
    for _, entry in ipairs(entries) do
        idx = idx + 1
        if idx > MAX_LINES then break end
        
        -- tostring() previene crashes infrecuentes al pintar variables secretas directamente
        textLines[idx]:SetText(entry.icons .. "|cFFFFDD00" .. tostring(entry.npc) .. "|r <- " .. entry.cuttersText)
        textLines[idx]:Show()
    end
    panel:SetHeight(24 + idx * 14)
    panel:Show()
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
BINDING_HEADER_CORTIO_HEADER = "⚔ Cortio (Asignación de Cortes)"
BINDING_NAME_CORTIO_TOGGLE_MARK = "Marcar/Desmarcar Objetivo"

--------------------------------------------------------------
-- ACCIÓN DE MARCAR Pura (Secure Path a través de Keybinding)
--------------------------------------------------------------
-- Esta función DEBE ser global para que Bindings.xml pueda llamarla
function Cortio_ToggleMark()
    EnsurePlayerInfo()
    if not playerName then return end
    
    -- Al dispararse desde un Hardware Event (Hardware Keybinding), el entorno
    -- de ejecución es nativamente seguro, así que UnitName devuelve strings limpios.
    -- Detectar qué unit token se está usando (mouseover tiene prioridad)
    local sourceUnit = UnitExists("mouseover") and "mouseover" or (UnitExists("target") and "target" or nil)
    if not sourceUnit then
        print("|cFF00FFFF[Cortio]|r Selecciona un objetivo primero.")
        return
    end
    
    local targetName = UnitName(sourceUnit)
    if not targetName then
        print("|cFF00FFFF[Cortio]|r Selecciona un objetivo primero.")
        return
    end
    
    local npUnit = FindNameplateUnit(sourceUnit)
    local specIndex = GetSpecialization()
    local specIcon = specIndex and select(4, GetSpecializationInfo(specIndex)) or "0"
    
    local isMarked = false
    for _, mark in ipairs(activeMarks) do
        if mark.playerName == playerName then
            if npUnit and mark.nameplateUnit == npUnit then
                isMarked = true
                break
            elseif not npUnit and mark.npcName == targetName then
                isMarked = true
                break
            end
        end
    end
    
    local action = isMarked and "UNMARK" or "MARK"
    
    if action == "MARK" then
        ClearPlayerMark(playerName)
        table.insert(activeMarks, { 
            npcName = targetName, 
            playerName = playerName, 
            playerClass = playerClass,
            specIcon = tostring(specIcon),
            remoteCDEnd = 0,
            remoteCDDuration = 0,
            nameplateUnit = npUnit
        })
        print("|cFF00FFFF[Cortio]|r Corte asignado a |cFFFFDD00" .. targetName .. "|r")
    else
        ClearPlayerMark(playerName)
        print("|cFF00FFFF[Cortio]|r Corte retirado de |cFFFFDD00" .. targetName .. "|r")
    end
    
    UpdatePanel()
    
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        channel = "RAID"
    elseif IsInGroup() then
        channel = "PARTY"
    end
    
    if channel then
        -- Formato: ACTION:CLASS:SPECICON:NPCNAME
        -- (el nameplate token es local, no se envía por comms)
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, action..":"..playerClass..":"..tostring(specIcon)..":"..targetName, channel)
    end
end

--------------------------------------------------------------
-- SLASH COMMANDS (Bloqueado por Blizzard en 12.0)
--------------------------------------------------------------
SLASH_CORTIO1 = "/cortio"
SLASH_CORTIO2 = "/ct"
SlashCmdList["CORTIO"] = function(msg)
    local cmd = strsplit(" ", msg, 2)
    cmd = (cmd or ""):lower()
    
    if cmd == "mark" or cmd == "m" then
        print("|cFF00FFFF[Cortio]|r |cFFFF0000ERROR CRÍTICO:|r Blizzard v12.0 prohibe leer enemigos usando macros (/ct m).")
        print("|cFF00FFFF[Cortio]|r |cFFFFFFFFPara que funcione, debes usar un Atajo de Teclado nativo.|r")
        print("|cFF00FFFF[Cortio]|r |cFFFFDD00Instrucciones: Pulsa ESC -> Opciones -> Atajos de Teclado -> AddOns -> Cortio -> Asigna tu tecla ahí.|r")
    elseif cmd == "show" then
        panel:Show()
    elseif cmd == "hide" then
        panel:Hide()
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
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        EnsurePlayerInfo()
        if not CortioDB then CortioDB = {} end
        if not CortioDB.errors then CortioDB.errors = {} end
        
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        SafeCall("Nameplate_Add", UpdateNameplate, arg1)
        
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        for _, mark in ipairs(activeMarks) do
            if mark.nameplateUnit == arg1 then
                mark.nameplateUnit = nil  -- liberar token perdido
            end
        end
        SafeCall("Nameplate_Remove", ReleaseNameplateFrame, arg1)
        
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == COMM_PREFIX then
            local sender = select(2, ...)
            if sender == playerName then return end
            
            local action, p2, p3, p4 = strsplit(":", arg2, 4)
            
            if action == "CD" then
                local cdDuration = tonumber(p2)
                if cdDuration and cdDuration > 0 then
                    SafeCall("Remote_CD", function()
                        local now = GetTime()
                        for _, mark in ipairs(activeMarks) do
                            if mark.playerName == sender then
                                mark.remoteCDEnd = now + cdDuration
                                mark.remoteCDDuration = cdDuration
                            end
                        end
                        for _, f in pairs(activeNameplates) do
                            if f and f.icons then
                                for _, ic in ipairs(f.icons) do
                                    if ic:IsShown() and ic.ownerName == sender and not ic.isLocal then
                                        ic.cooldown:SetCooldown(now, cdDuration)
                                    end
                                end
                            end
                        end
                    end)
                end
            elseif action and p2 and p4 then
                local cls, specIcon, npcName = p2, p3, p4
                if action == "MARK" then
                    ClearPlayerMark(sender)
                    table.insert(activeMarks, { 
                        npcName = npcName, 
                        playerName = sender, 
                        playerClass = cls,
                        specIcon = specIcon,
                        remoteCDEnd = 0,
                        remoteCDDuration = 0,
                        nameplateUnit = nil
                    })
                elseif action == "UNMARK" then
                    ClearPlayerMark(sender)
                end
                UpdatePanel()
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

-- Actualizar el cooldown del icono
local myInterruptSpellID = nil

local function UpdateKickCooldown()
    if not myInterruptSpellID then return end
    -- WoW 12.0: start y duration son "secret numbers" (tainted).
    -- NO se pueden comparar en Lua (>, <, ==, ~= dan error de taint).
    -- SetCooldown ES un widget seguro que acepta valores tainted directamente.
    -- Si duration=0, el CooldownFrame simplemente no muestra nada.
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(myInterruptSpellID)
        if info then
            kickCooldown:SetCooldown(info.startTime, info.duration)
        end
    elseif GetSpellCooldown then
        kickCooldown:SetCooldown(GetSpellCooldown(myInterruptSpellID))
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

-- Frame de eventos dedicado al cooldown
local cdEventFrame = CreateFrame("Frame")
cdEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
cdEventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
cdEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

cdEventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        SafeCall("KickIcon_Setup", SetupKickIcon)
    else
        SafeCall("KickIcon_CD", UpdateKickCooldown)
        -- También refrescar cooldowns en los iconos de nameplate
        SafeCall("KickIcon_NP", UpdateNameplateCooldowns)
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
print("|cFF00FFFF[Cortio]|r Cargado. Macro: /ct m")
