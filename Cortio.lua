--------------------------------------------------------------
-- CORTIO - Asistente de cortes para WoW 12.0
-- ARQUITECTURA "ZERO GUID":
-- En WoW 12.0, UnitGUID devuelve "secret strings" intocables.
-- Usamos ÚNICAMENTE UnitName como identificador.
--------------------------------------------------------------
local addonName, _ = ...

local COMM_PREFIX = "CORTIO"
C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)

-- Array simple: { { npcName = "...", playerName = "...", playerClass = "..." }, ... }
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

local function ShortName(fullName)
    if not fullName then return "?" end
    local name = strsplit("-", fullName)
    return name or fullName
end

local function UpdatePanel()
    for _, line in ipairs(textLines) do
        line:SetText("")
        line:Hide()
    end
    
    -- Agrupar por nombre del NPC para mostrar juntos
    local grouped = {}
    for _, mark in ipairs(activeMarks) do
        local npc = mark.npcName
        if not grouped[npc] then
            grouped[npc] = {}
        end
        local color = CLASS_COLORS[mark.playerClass] or "FFFFFFFF"
        table.insert(grouped[npc], "|c" .. color .. ShortName(mark.playerName) .. "|r")
    end
    
    local entries = {}
    for npc, cutters in pairs(grouped) do
        table.sort(cutters)
        table.insert(entries, { npc = npc, cuttersText = table.concat(cutters, ", ") })
    end
    
    if #entries == 0 then
        panel:Hide()
        return
    end
    
    table.sort(entries, function(a, b) return a.npc < b.npc end)
    
    local idx = 0
    for _, entry in ipairs(entries) do
        idx = idx + 1
        if idx > MAX_LINES then break end
        textLines[idx]:SetText("|cFFFFDD00" .. entry.npc .. "|r ← " .. entry.cuttersText)
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
    local targetName = UnitName("mouseover") or UnitName("target")
    if not targetName then
        print("|cFF00FFFF[Cortio]|r Selecciona un objetivo primero.")
        return
    end
    
    local isMarked = false
    for _, mark in ipairs(activeMarks) do
        if mark.npcName == targetName and mark.playerName == playerName then
            isMarked = true
            break
        end
    end
    
    local action = isMarked and "UNMARK" or "MARK"
    
    if action == "MARK" then
        ClearPlayerMark(playerName)
        table.insert(activeMarks, { 
            npcName = targetName, 
            playerName = playerName, 
            playerClass = playerClass 
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
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, action..":"..playerClass..":"..targetName, channel)
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
    elseif cmd == "clearerrors" then
        if CortioDB then CortioDB.errors = {} end
        print("|cFF00FFFF[Cortio]|r Errores borrados.")
    else
        print("|cFF00FFFF[Cortio]|r Opciones: /ct show|hide | /cortio errors")
        print("|cFF00FFFF[Cortio]|r Atajos: ESC -> Opciones -> Atajos (Keybindings).")
    end
end

--------------------------------------------------------------
-- EVENTOS
--------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        EnsurePlayerInfo()
        if not CortioDB then CortioDB = {} end
        if not CortioDB.errors then CortioDB.errors = {} end
        
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == COMM_PREFIX then
            local sender = select(2, ...)
            if sender == playerName then return end
            
            local action, cls, npcName = strsplit(":", arg2)
            if action and cls and npcName then
                if action == "MARK" then
                    ClearPlayerMark(sender)
                    table.insert(activeMarks, { 
                        npcName = npcName, 
                        playerName = sender, 
                        playerClass = cls 
                    })
                elseif action == "UNMARK" then
                    ClearPlayerMark(sender)
                end
                UpdatePanel()
            end
        end
    end
end)

panel:Hide()
print("|cFF00FFFF[Cortio]|r Cargado. Macro: /ct m")
