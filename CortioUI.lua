--------------------------------------------------------------
-- CORTIO - UI
--------------------------------------------------------------
Cortio = Cortio or {}
Cortio.UI = {}

Cortio.UI.ActiveNameplates = {}
local nameplateFrames = {}
local MAX_ICONS_PER_PLATE = 8

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

local titleBg = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
titleBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
titleBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
titleBg:SetHeight(17)
titleBg:SetColorTexture(0.0, 0.45, 0.75, 0.30)

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOP", panel, "TOP", 0, -6)
title:SetText("|cFF00D4FF--|r |cFFFFFFFFCORTIO|r |cFF00D4FF--|r")

local separator = panel:CreateTexture(nil, "ARTWORK")
separator:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -21)
separator:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -21)
separator:SetHeight(1)
separator:SetColorTexture(0.0, 0.75, 1.0, 0.45)

Cortio.UI.Panel = panel

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

function Cortio.UI:UpdatePanel()
    for i = 1, #panelRows do HidePanelRow(i) end
    
    local entries = {}
    local now = GetTime()
    
    for rPlayerName, data in pairs(Cortio.RosterList) do
        local rClass = data.class
        local rSpec = data.specIcon
        
        local assignedMark = nil
        local rShort = Cortio.Data:ShortName(rPlayerName)
        for _, m in ipairs(Cortio.Marks.Active) do
            if m.playerName == rPlayerName or Cortio.Data:ShortName(m.playerName) == rShort then
                assignedMark = m
                break
            end
        end
        
        local color = Cortio.Data.CLASS_COLORS[rClass] or "FFFFFFFF"
        local playerStr = "|c" .. color .. Cortio.Data:ShortName(rPlayerName) .. "|r"
        
        if rSpec and rSpec ~= "0" and rSpec ~= "" then
            playerStr = "|T" .. rSpec .. ":14:14:0:0|t " .. playerStr
        end
        
        local iconID = Cortio.Data.CLASS_INTERRUPT_ICONS[rClass]
        local iconsStr = iconID and ("|T" .. iconID .. ":16:16:0:0|t ") or ""
        
        local raidStr = ""
        local markerSlot = 0
        if assignedMark and assignedMark.markerSlot and assignedMark.markerSlot > 0 then
            raidStr = Cortio.Data:GetRaidIconString(assignedMark.markerSlot, 14)
            markerSlot = assignedMark.markerSlot
        end
        
        local cdText = ""
        local sLeft = data.cdEnd - now
        
        if sLeft > 0 then
            local ratio = sLeft / data.cdTotal
            local cdCol = "FFFF66"
            if ratio > 0.6 then cdCol = "FF4444" elseif ratio > 0.3 then cdCol = "FFAA00" end
            
            local resultIcon = ""
            if data.lastResult == "SUCCESS" then resultIcon = " |cFF55FF55[✓]|r"
            elseif data.lastResult == "MISSED" then resultIcon = " |cFFFF5555[X]|r"
            elseif data.lastResult == "USED" then resultIcon = " |cFFFFFF55[-]|r" end
            
            cdText = string.format("|cff%s%.1fs|r%s", cdCol, sLeft, resultIcon)
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
        row.raidIcon:SetText(entry.raidIcon)
        row.classIcon:SetText(entry.icons)
        row.playerText:SetText(entry.cuttersText)
        row.cdText:SetText(entry.cdText)
        row:Show()
    end
    
    for i = idx + 1, #panelRows do HidePanelRow(i) end
    
    panel:SetHeight(28 + idx * 15)
    panel:Show()
    
    Cortio.Data:SafeCall("Nameplates", function() Cortio.UI:UpdateAllNameplates() end)
end

-- Nameplates
local function CreateIconSubFrame(parent, index)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(24, 24)
    if index == 1 then
        icon:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    else
        icon:SetPoint("RIGHT", parent.icons[index - 1], "LEFT", -2, 0)
    end
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawSwipe(true)
    icon.cooldown:SetDrawEdge(true)
    icon.cooldown:SetDrawBling(true)
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.65)
    icon.isLocal = false
    icon.ownerName = nil
    icon:Hide()
    return icon
end

local function GetNameplateFrame()
    for _, f in ipairs(nameplateFrames) do
        if not f:IsShown() and not f.inUse then
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

function Cortio.UI:ReleaseNameplateFrame(unit)
    local f = Cortio.UI.ActiveNameplates[unit]
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
        Cortio.UI.ActiveNameplates[unit] = nil
    end
end

function Cortio.UI:UpdateNameplate(unit)
    local marks = {}

    for _, mark in ipairs(Cortio.Marks.Active) do
        local isMatch = false
        
        if mark.nameplateUnit == unit then
            isMatch = true
        elseif not mark.nameplateUnit and mark.unitToken then
            if mark.unitToken == "target" and UnitExists("target") then
                if Cortio.Taint:SafeIsMatch("target", unit) then
                    isMatch = true
                    mark.unitToken = nil
                end
            else
                mark.unitToken = nil
            end
        end

        if isMatch then
            mark.nameplateUnit = unit
            table.insert(marks, mark)
        elseif mark.nameplateUnit == unit then
            mark.nameplateUnit = nil
        end
    end
    
    local f = Cortio.UI.ActiveNameplates[unit]
    
    if #marks == 0 then 
        if f then Cortio.UI:ReleaseNameplateFrame(unit) end
        return 
    end
    
    local np = C_NamePlate.GetNamePlateForUnit(unit)
    if not np then 
        if f then Cortio.UI:ReleaseNameplateFrame(unit) end
        return 
    end
    
    local anchorFrame = np.UnitFrame or np

    if not f then
        f = GetNameplateFrame()
        Cortio.UI.ActiveNameplates[unit] = f
    end
    
    if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
    f:ClearAllPoints()
    f:SetPoint("RIGHT", anchorFrame, "LEFT", -6, 0)
    f:Show()
    
    local iconIdx = 0
    for _, mark in ipairs(marks) do
        local classIcon = Cortio.Data.CLASS_INTERRUPT_ICONS[mark.playerClass]
        if classIcon then
            iconIdx = iconIdx + 1
            if iconIdx <= MAX_ICONS_PER_PLATE then
                local ic = f.icons[iconIdx]
                ic.texture:SetTexture(tonumber(classIcon))
                ic.ownerName = mark.playerName
                ic.isLocal = (mark.playerName == Cortio.PlayerName)
                
                local pData = Cortio.RosterList[mark.playerName]
                if pData and pData.cdEnd and pData.cdEnd > GetTime() then
                    ic.cooldown:SetCooldown(pData.cdEnd - pData.cdTotal, pData.cdTotal)
                else
                    ic.cooldown:SetCooldown(0, 0)
                end
                ic:Show()
            end
        end
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
    
    for i = iconIdx + 1, MAX_ICONS_PER_PLATE do
        if f.icons[i]:IsShown() then
            f.icons[i]:Hide()
            f.icons[i].cooldown:Clear()
        end
    end
    
    f:Show()
end

function Cortio.UI:UpdateAllNameplates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            Cortio.UI:UpdateNameplate(unit)
        end
    end
end

local kickIconFrame = CreateFrame("Frame", "CortioKickIconFrame", panel)
kickIconFrame:SetSize(32, 32)
kickIconFrame:SetPoint("RIGHT", panel, "LEFT", -6, 0)
local kickIconTexture = kickIconFrame:CreateTexture(nil, "ARTWORK")
kickIconTexture:SetAllPoints(kickIconFrame)
local kickIconBorder = kickIconFrame:CreateTexture(nil, "OVERLAY")
kickIconBorder:SetAllPoints(kickIconFrame)
kickIconBorder:SetAtlas("UI-HUD-ActionBar-IconFrame")
if not kickIconBorder:GetAtlas() then
    kickIconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    kickIconBorder:SetAllPoints(kickIconFrame)
end

local kickCooldown = CreateFrame("Cooldown", "CortioKickCooldown", kickIconFrame, "CooldownFrameTemplate")
kickCooldown:SetAllPoints(kickIconFrame)
kickCooldown:SetDrawSwipe(true)
kickCooldown:SetDrawEdge(true)
kickCooldown:SetDrawBling(true)
kickCooldown:SetSwipeColor(0, 0, 0, 0.65)
kickCooldown:SetHideCountdownNumbers(false)

function Cortio.UI:UpdateKickCooldown()
    local myInterruptSpellID = Cortio.Data.CLASS_INTERRUPT_SPELLID[Cortio.PlayerClass]
    if not myInterruptSpellID or not Cortio.RosterList[Cortio.PlayerName] then return end
    local cdEnd = Cortio.RosterList[Cortio.PlayerName].cdEnd
    local cdTotal = Cortio.RosterList[Cortio.PlayerName].cdTotal
    if cdEnd and cdTotal and cdEnd > GetTime() then
        kickCooldown:SetCooldown(cdEnd - cdTotal, cdTotal)
    else
        kickCooldown:SetCooldown(0, 0)
    end
end

function Cortio.UI:SetupKickIcon()
    Cortio.Roster:EnsurePlayerInfo()
    if not Cortio.PlayerClass then return end

    local iconID = Cortio.Data.CLASS_INTERRUPT_ICONS[Cortio.PlayerClass]
    if iconID then
        kickIconTexture:SetTexture(tonumber(iconID))
        kickIconFrame:Show()
    else
        kickIconFrame:Hide()
    end
    Cortio.UI:UpdateKickCooldown()
end

panel:HookScript("OnShow", function()
    if Cortio.Data.CLASS_INTERRUPT_SPELLID[Cortio.PlayerClass] then
        kickIconFrame:Show()
        Cortio.UI:UpdateKickCooldown()
    end
end)
panel:HookScript("OnHide", function()
    kickIconFrame:Hide()
end)

kickIconFrame:Hide()
panel:Hide()

local settingsCreated = false
function Cortio.UI:CreateSettingsMenu()
    if settingsCreated then return end
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end
    settingsCreated = true
    
    local category = Settings.RegisterVerticalLayoutCategory("Cortio")
    
    local scaleSetting = Settings.RegisterProxySetting(
        category, "Cortio_Scale", Settings.VarType.Number, "Tamaño de la Ventana", 
        (CortioDB and CortioDB.scale) or 1.0, 
        function() return (CortioDB and CortioDB.scale) or 1.0 end,
        function(val) 
            if not CortioDB then CortioDB = {} end
            CortioDB.scale = val 
            Cortio.UI.Panel:SetScale(val) 
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
            Cortio.Roster:Rebuild()
            if val then Cortio.UI.Panel:Show() else Cortio.UI.Panel:Hide() end
        end
    )
    Settings.CreateCheckbox(category, testSetting, "Genera un grupo falso para probar la interfaz de cortes.")
    
    Settings.RegisterAddOnCategory(category)
end

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
                Cortio.Data:GetRaidIconString(n, 14), Cortio.Data.RAID_ICON_NAMES[n] or tostring(n)))
            Cortio.Marks:UpdateSecureBtnMacro()
        elseif n == 0 then
            CortioDB.markerSlot = 0
            print("|cFF00FFFF[Cortio]|r Slot en modo automatico.")
            Cortio.Marks:UpdateSecureBtnMacro()
        else
            local curr = (CortioDB and CortioDB.markerSlot or 0)
            local currStr = curr > 0 and (Cortio.Data:GetRaidIconString(curr, 14) .. " slot " .. curr) or "automatico"
            print("|cFF00FFFF[Cortio]|r Uso: /ct slot [1-8] | /ct slot 0 (auto) | actual: " .. currStr)
            print("|cFF00FFFF[Cortio]|r Slots: 1=Estrella 2=Circulo 3=Diamante 4=Triangulo 5=Luna 6=Cuadrado 7=Cruz 8=Calavera")
        end
    elseif cmd == "show" then
        Cortio.UI.Panel:SetAlpha(1)
        Cortio.UI.Panel:Show()
    elseif cmd == "hide" then
        Cortio.UI.Panel:Hide()
    elseif cmd == "reset" then
        if not CortioDB then CortioDB = {} end
        CortioDB.scale = 1.0
        Cortio.UI.Panel:SetScale(1.0)
        Cortio.UI.Panel:ClearAllPoints()
        Cortio.UI.Panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
        Cortio.UI.Panel:SetAlpha(1)
        Cortio.UI.Panel:Show()
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
    elseif cmd == "debug" then
        print("|cFF00FFFF[Cortio]|r === DEBUG ===")
        print("  playerName = " .. tostring(Cortio.PlayerName))
        print("  activeMarks (" .. #Cortio.Marks.Active .. "):")
        for i, m in ipairs(Cortio.Marks.Active) do
            print(string.format("    [%d] player=%s slot=%s class=%s",
                i, tostring(m.playerName), tostring(m.markerSlot), tostring(m.playerClass)))
        end
        print("  CortioRoster:")
        for k, v in pairs(Cortio.RosterList) do
            print(string.format("    [%s] unit=%s class=%s cdEnd=%.1f",
                tostring(k), tostring(v.unit), tostring(v.class), (v.cdEnd or 0) - GetTime()))
        end
        print("|cFF00FFFF[Cortio]|r === FIN ===")
    else
        print("|cFF00FFFF[Cortio]|r Opciones: /ct show|hide | /ct debug | /ct errors | /ct clear")
        print("|cFF00FFFF[Cortio]|r Atajos: ESC -> Opciones -> Atajos (Keybindings).")
    end
end
