--------------------------------------------------------------
-- CORTIO - UI (Modern Display)
--------------------------------------------------------------
Cortio = Cortio or {}
Cortio.UI = {}

Cortio.UI.ActiveNameplates = {}
local nameplateFrames = {}
local MAX_ICONS_PER_PLATE = 8

-- ============================================================
-- Design Constants
-- ============================================================
local FRAME_WIDTH       = 260
local HEADER_HEIGHT     = 28
local BAR_HEIGHT        = 26
local ICON_SIZE         = 20
local PADDING           = 6
local BAR_GAP           = 2
local HEADER_GAP        = 2

-- Color Palette (Cortio: deep blue + cyan accent)
local C_BG        = { 8/255, 12/255, 24/255 }         -- #080c18
local C_HEADER_BG = { 10/255, 16/255, 30/255 }        -- #0a101e
local C_BAR_BG    = { 14/255, 20/255, 36/255 }        -- #0e1424
local C_ACCENT    = { 0, 212/255, 255/255 }            -- #00d4ff
local C_READY     = { 68/255, 255/255, 136/255 }      -- #44ff88
local C_CD_HIGH   = { 255/255, 68/255, 68/255 }       -- #ff4444 (just used)
local C_CD_MID    = { 255/255, 170/255, 0 }            -- #ffaa00 (mid cd)
local C_BORDER    = { 0, 140/255, 200/255 }            -- #008cc8

-- Hex strings (avoid allocations)
local HEX_READY   = "44FF88"
local HEX_CD_HIGH = "FF4444"
local HEX_CD_MID  = "FFAA00"
local HEX_CD_LOW  = "FFFF66"

local STRIP_HEIGHT = 2  -- progress strip at bottom of each row

local function getCooldownColor(ratio)
    -- ratio = remaining / total (1.0 = just used, 0.0 = almost ready)
    if ratio > 0.6 then
        return C_CD_HIGH[1], C_CD_HIGH[2], C_CD_HIGH[3], HEX_CD_HIGH
    elseif ratio > 0.3 then
        return C_CD_MID[1], C_CD_MID[2], C_CD_MID[3], HEX_CD_MID
    else
        return C_READY[1], C_READY[2], C_READY[3], HEX_CD_LOW
    end
end

-- ============================================================
-- Panel Frame
-- ============================================================
local panel = CreateFrame("Frame", "CortioPanelFrame", UIParent, "BackdropTemplate")
panel:SetSize(FRAME_WIDTH, HEADER_HEIGHT + 10)
panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if CortioDB then
        local point, _, relPoint, x, y = self:GetPoint()
        CortioDB.framePoint = { point, nil, relPoint, x, y }
    end
end)
panel:SetFrameStrata("HIGH")
panel:SetClampedToScreen(true)

-- Dark background
local panelBg = panel:CreateTexture(nil, "BACKGROUND")
panelBg:SetAllPoints()
panelBg:SetColorTexture(C_BG[1], C_BG[2], C_BG[3], 0.95)

-- Subtle edge
panel:SetBackdrop({ edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
panel:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 0.35)

-- Header
local headerFrame = CreateFrame("Frame", nil, panel)
headerFrame:SetHeight(HEADER_HEIGHT)
headerFrame:SetPoint("TOPLEFT")
headerFrame:SetPoint("TOPRIGHT")

local headerBg = headerFrame:CreateTexture(nil, "BACKGROUND")
headerBg:SetAllPoints()
headerBg:SetColorTexture(C_HEADER_BG[1], C_HEADER_BG[2], C_HEADER_BG[3], 0.98)

-- Cyan accent line below header
local accentLine = headerFrame:CreateTexture(nil, "ARTWORK")
accentLine:SetHeight(2)
accentLine:SetPoint("BOTTOMLEFT")
accentLine:SetPoint("BOTTOMRIGHT")
accentLine:SetColorTexture(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.8)

-- Title
local titleText = headerFrame:CreateFontString(nil, "OVERLAY")
titleText:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
titleText:SetShadowOffset(1, -1)
titleText:SetPoint("LEFT", 10, 0)
titleText:SetText("|cff00d4ffCORTIO|r")

-- Badge pill (ready/total counter)
local badgeFrame = CreateFrame("Frame", nil, headerFrame)
badgeFrame:SetHeight(16)
badgeFrame:SetPoint("LEFT", titleText, "RIGHT", 8, 0)

local badgeBg = badgeFrame:CreateTexture(nil, "BACKGROUND")
badgeBg:SetAllPoints()
badgeBg:SetColorTexture(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.12)

local badgeText = badgeFrame:CreateFontString(nil, "OVERLAY")
badgeText:SetFont("Fonts\\ARIALN.TTF", 9, "")
badgeText:SetShadowOffset(1, -1)
badgeText:SetPoint("CENTER", 0, 0)
badgeText:SetTextColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3])

Cortio.UI.Panel = panel

-- Content area (holds bars)
local contentFrame = CreateFrame("Frame", nil, panel)
contentFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -HEADER_GAP)
contentFrame:SetPoint("RIGHT", panel, "RIGHT", 0, 0)

-- ============================================================
-- Row Pool (Frame + Cooldown spiral + progress strip)
-- ============================================================
local barPool = {}
local activeBarCount = 0

local function getBar(index)
    local bar = barPool[index]
    if bar then return bar end

    bar = CreateFrame("Frame", nil, contentFrame)
    bar:SetHeight(BAR_HEIGHT)

    -- Dark row background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(C_BAR_BG[1], C_BAR_BG[2], C_BAR_BG[3], 0.9)

    -- Thin border (state-colored)
    bar.border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.border:SetAllPoints()
    bar.border:SetBackdrop({ edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })

    -- Class-color left stripe (3px accent — Cortio signature)
    bar.classStripe = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    bar.classStripe:SetWidth(3)
    bar.classStripe:SetPoint("TOPLEFT", 0, 0)
    bar.classStripe:SetPoint("BOTTOMLEFT", 0, 0)

    -- Icon background (class-tinted)
    bar.iconBg = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.iconBg:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
    bar.iconBg:SetPoint("LEFT", 7, 0)
    bar.iconBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Interrupt spell icon
    bar.icon = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.icon:SetSize(ICON_SIZE, ICON_SIZE)
    bar.icon:SetPoint("LEFT", 7, 0)
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Cooldown spiral on icon (WoW-native swipe)
    bar.iconCD = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
    bar.iconCD:SetAllPoints(bar.icon)
    bar.iconCD:SetDrawSwipe(true)
    bar.iconCD:SetDrawEdge(true)
    bar.iconCD:SetDrawBling(false)
    bar.iconCD:SetSwipeColor(0, 0, 0, 0.6)
    bar.iconCD:SetHideCountdownNumbers(true)

    -- Tooltip on icon hover
    bar.iconHit = CreateFrame("Frame", nil, bar)
    bar.iconHit:SetAllPoints(bar.icon)
    bar.iconHit:EnableMouse(true)
    bar.iconHit:SetScript("OnEnter", function(self)
        local id = self._spellID
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(id)
        GameTooltip:Show()
    end)
    bar.iconHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Raid marker
    bar.marker = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    bar.marker:SetSize(14, 14)
    bar.marker:SetPoint("LEFT", bar.icon, "RIGHT", 4, 0)

    -- Player name
    bar.nameText = bar:CreateFontString(nil, "OVERLAY")
    bar.nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    bar.nameText:SetShadowOffset(1, -1)
    bar.nameText:SetJustifyH("LEFT")
    bar.nameText:SetWordWrap(false)

    -- Status text (READY / 4.2s)
    bar.statusText = bar:CreateFontString(nil, "OVERLAY")
    bar.statusText:SetFont("Fonts\\ARIALN.TTF", 10, "")
    bar.statusText:SetShadowOffset(1, -1)
    bar.statusText:SetPoint("RIGHT", -PADDING, 0)
    bar.statusText:SetJustifyH("RIGHT")

    -- Result indicator (✓/✗)
    bar.resultText = bar:CreateFontString(nil, "OVERLAY")
    bar.resultText:SetFont("Fonts\\ARIALN.TTF", 8, "")
    bar.resultText:SetShadowOffset(1, -1)
    bar.resultText:SetPoint("RIGHT", bar.statusText, "LEFT", -3, 0)
    bar.resultText:SetJustifyH("RIGHT")

    -- Progress strip (thin bar at bottom of row)
    bar.strip = bar:CreateTexture(nil, "ARTWORK", nil, 4)
    bar.strip:SetHeight(STRIP_HEIGHT)
    bar.strip:SetPoint("BOTTOMLEFT", 3, 0)

    bar:Hide()
    barPool[index] = bar
    return bar
end

-- ============================================================
-- UpdatePanel (Cooldown spiral + progress strip rendering)
-- ============================================================
function Cortio.UI:UpdatePanel()
    -- Hide all existing bars
    for i = 1, activeBarCount do
        if barPool[i] then barPool[i]:Hide() end
    end

    local entries = {}
    local now = GetTime()
    local readyCount = 0
    local totalCount = 0

    for rPlayerName, data in pairs(Cortio.RosterList) do
        local rClass = data.class
        local sLeft = (data.cdEnd or 0) - now
        local isReady = sLeft <= 0

        -- Clear lastResult when CD has fully expired (prevents stale "–" icon next to "READY")
        if isReady and data.lastResult then
            data.lastResult = nil
        end

        -- Find assigned mark
        local assignedMark = nil
        local rShort = Cortio.Data:ShortName(rPlayerName)
        for _, m in ipairs(Cortio.Marks.Active) do
            if m.playerName == rPlayerName or Cortio.Data:ShortName(m.playerName) == rShort then
                assignedMark = m
                break
            end
        end

        totalCount = totalCount + 1
        if isReady then readyCount = readyCount + 1 end

        local staticSlot = Cortio.Marks:GetMarkerSlotForPlayer(rPlayerName)
        
        table.insert(entries, {
            playerName = rPlayerName,
            class = rClass,
            specId = data.specId or 0,
            mark = assignedMark,
            markerSlot = staticSlot,
            cdEnd = data.cdEnd or 0,
            cdTotal = data.cdTotal or 15,
            remaining = isReady and 0 or sLeft,
            isReady = isReady,
            lastResult = data.lastResult,
        })
    end

    if #entries == 0 then
        panel:Hide()
        return
    end

    -- Sort: marked first, then ready, then by remaining
    table.sort(entries, function(a, b)
        if a.markerSlot > 0 and b.markerSlot == 0 then return true end
        if b.markerSlot > 0 and a.markerSlot == 0 then return false end
        if a.markerSlot > 0 and b.markerSlot > 0 and a.markerSlot ~= b.markerSlot then
            return a.markerSlot < b.markerSlot
        end
        if a.isReady ~= b.isReady then return a.isReady end
        if not a.isReady and not b.isReady then return a.remaining < b.remaining end
        return a.playerName < b.playerName
    end)

    local barWidth = FRAME_WIDTH - PADDING * 2

    for i, entry in ipairs(entries) do
        local bar = getBar(i)

        bar:SetWidth(barWidth)
        bar:SetPoint("TOPLEFT", contentFrame, "TOPLEFT",
            PADDING, -(BAR_GAP + (i - 1) * (BAR_HEIGHT + BAR_GAP)))

        -- Parse class color
        local colorHex = Cortio.Data.CLASS_COLORS[entry.class] or "FFFFFFFF"
        local classR = tonumber(colorHex:sub(3, 4), 16) / 255
        local classG = tonumber(colorHex:sub(5, 6), 16) / 255
        local classB = tonumber(colorHex:sub(7, 8), 16) / 255

        -- Class stripe
        bar.classStripe:SetColorTexture(classR, classG, classB, 0.8)

        -- State-dependent visuals
        if entry.isReady then
            -- Ready: subtle bright tint on background, green border
            bar.bg:SetColorTexture(
                C_BAR_BG[1] + C_READY[1] * 0.04,
                C_BAR_BG[2] + C_READY[2] * 0.04,
                C_BAR_BG[3] + C_READY[3] * 0.04, 0.92)
            bar.border:SetBackdropBorderColor(C_READY[1], C_READY[2], C_READY[3], 0.25)
            bar.statusText:SetText("|cff" .. HEX_READY .. "READY|r")
            -- Icon cooldown: clear
            bar.iconCD:SetCooldown(0, 0)
            -- Progress strip: full width, green
            bar.strip:SetWidth(barWidth - 6)
            bar.strip:SetColorTexture(C_READY[1], C_READY[2], C_READY[3], 0.45)
        else
            -- On CD: default dark background, colored border
            local ratio = entry.remaining / entry.cdTotal
            local r, g, b, hex = getCooldownColor(ratio)
            bar.bg:SetColorTexture(C_BAR_BG[1], C_BAR_BG[2], C_BAR_BG[3], 0.9)
            bar.border:SetBackdropBorderColor(r, g, b, 0.15)

            local text
            if entry.remaining >= 10 then
                text = math.floor(entry.remaining) .. "s"
            else
                text = string.format("%.1fs", entry.remaining)
            end
            bar.statusText:SetText("|cff" .. hex .. text .. "|r")

            -- Icon cooldown: spiral swipe
            bar.iconCD:SetCooldown(entry.cdEnd - entry.cdTotal, entry.cdTotal)

            -- Progress strip: width proportional to elapsed time
            local progress = (entry.cdTotal - entry.remaining) / entry.cdTotal
            if progress < 0 then progress = 0 end
            if progress > 1 then progress = 1 end
            local stripW = math.max(1, (barWidth - 6) * progress)
            bar.strip:SetWidth(stripW)
            bar.strip:SetColorTexture(r, g, b, 0.5)
        end

        -- Spell icon (spec-aware)
        local spellId = nil
        if entry.specId > 0 and Cortio.Data.SPEC_INTERRUPTS[entry.specId] then
            spellId = Cortio.Data.SPEC_INTERRUPTS[entry.specId].spellId
        end
        if not spellId then
            spellId = Cortio.Data.CLASS_INTERRUPT_SPELLID[entry.class]
        end

        bar.iconHit._spellID = spellId

        local iconID = Cortio.Data.CLASS_INTERRUPT_ICONS[entry.class]
        if iconID then
            bar.icon:SetTexture(tonumber(iconID))
            bar.icon:Show()
        else
            bar.icon:Hide()
        end

        -- Class-tinted icon background
        bar.iconBg:SetColorTexture(classR * 0.25, classG * 0.25, classB * 0.25, 0.8)

        -- Raid marker
        bar.nameText:ClearAllPoints()
        if entry.markerSlot and entry.markerSlot > 0 then
            bar.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. entry.markerSlot)
            bar.marker:Show()
            bar.nameText:SetPoint("LEFT", bar.marker, "RIGHT", 4, 0)
        else
            bar.marker:Hide()
            bar.nameText:SetPoint("LEFT", bar.icon, "RIGHT", 6, 0)
        end
        bar.nameText:SetPoint("RIGHT", bar.statusText, "LEFT", -4, 0)

        -- Player name (class colored)
        bar.nameText:SetText("|c" .. colorHex .. Cortio.Data:ShortName(entry.playerName) .. "|r")

        -- Result indicator
        local resultIcon = ""
        if entry.lastResult == "SUCCESS" then resultIcon = "|cFF55FF55✓|r"
        elseif entry.lastResult == "MISSED" then resultIcon = "|cFFFF5555✗|r"
        elseif entry.lastResult == "USED" then resultIcon = "|cFFFFFF55–|r"
        end
        bar.resultText:SetText(resultIcon)

        bar:Show()
    end

    activeBarCount = #entries

    -- Update badge
    badgeText:SetText(readyCount .. "/" .. totalCount)
    badgeFrame:SetWidth(badgeText:GetStringWidth() + 12)

    -- Resize panel to fit content
    local contentHeight = #entries * (BAR_HEIGHT + BAR_GAP) + BAR_GAP
    panel:SetHeight(HEADER_HEIGHT + HEADER_GAP + contentHeight + 4)

    -- Restore saved position on first show
    if CortioDB and CortioDB.framePoint and not panel._posRestored then
        local p = CortioDB.framePoint
        if p[1] then
            panel:ClearAllPoints()
            panel:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        end
        panel._posRestored = true
    end

    panel:Show()

    Cortio.Data:SafeCall("Nameplates", function() Cortio.UI:UpdateAllNameplates() end)
end

-- ============================================================
-- Nameplates
-- ============================================================

-- Pick which mark "owns" the glow (color/animation) when multiple
-- marks exist on the same nameplate. Prefer local player's mark;
-- if none, pick the lowest markerSlot (= highest raid priority).
local function PickPrimaryMark(marks)
    if not marks or #marks == 0 then return nil end
    for _, m in ipairs(marks) do
        if m.isLocal then return m end
    end
    -- Stable fallback: lowest markerSlot
    local best = marks[1]
    for i = 2, #marks do
        if (marks[i].markerSlot or 99) < (best.markerSlot or 99) then
            best = marks[i]
        end
    end
    return best
end
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
        if f.glow then
            f.glow:Hide()
            if f.glowAG then f.glowAG:Stop() end
        end
        -- Restore nameplate strata, level and scale
        local np = C_NamePlate.GetNamePlateForUnit(unit)
        if np then
            local uFrame = np.UnitFrame or np
            -- Restore scale
            if uFrame._cortioScaleBoosted then
                pcall(function() uFrame:SetScale(uFrame._cortioOrigScale or 1) end)
                uFrame._cortioScaleBoosted = nil
                uFrame._cortioOrigScale = nil
            end
            -- Restore strata+level de cada sub-frame (Plater-style)
            if uFrame._cortioStrataBoosted and uFrame._cortioOrigFrames then
                for _, fr in ipairs(uFrame._cortioOrigFrames) do
                    pcall(function()
                        fr:SetFrameStrata(fr._cortioOrigStrata or "BACKGROUND")
                        fr:SetFrameLevel(fr._cortioOrigLevel or 1)
                    end)
                end
                uFrame._cortioOrigFrames = nil
                uFrame._cortioStrataBoosted = nil
            end
        end
        f:Hide()
        f:ClearAllPoints()
        f.inUse = false
        Cortio.UI.ActiveNameplates[unit] = nil
    end
end

function Cortio.UI:UpdateNameplate(unit)
    local marks = {}

    -- Read raid marker on this nameplate (taint-safe)
    local raidIndex = nil
    if UnitExists(unit) then
        local okRT, idx = pcall(GetRaidTargetIndex, unit)
        -- Extra security: drop it immediately if it's flagged as secret by the client
        if okRT and idx and not Cortio.Taint:IsSecret(idx) then
            raidIndex = idx 
        end
    end

    for _, mark in ipairs(Cortio.Marks.Active) do
        local isMatch = false
        
        -- 1) Cached from a previous frame
        if mark.nameplateUnit == unit then
            isMatch = true
        end

        -- 2) Match by raid marker index (stable, works for remote marks)
        -- We wrap in pcall because comparing a tainted number throws a hard Lua error in 12.0
        if not isMatch and raidIndex and mark.markerSlot and mark.markerSlot > 0 then
            local okCmp, isEq = pcall(function() return raidIndex == mark.markerSlot end)
            if okCmp and isEq then
                isMatch = true
            end
        end

        -- 3) Fallback: local UnitIsUnit("target", nameplateX)
        if not isMatch and not mark.nameplateUnit and mark.unitToken then
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
            mark.isLocal = (mark.playerName == Cortio.PlayerName)
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
    
    -- Try to find the actual health bar for the glow
    local uiFrame = np.UnitFrame or np
    local barFrame = uiFrame.healthBar or uiFrame.HealthBar or uiFrame.Health or uiFrame.healthbar or uiFrame

    if not f then
        f = GetNameplateFrame()
        Cortio.UI.ActiveNameplates[unit] = f
    end
    
    if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
    f:ClearAllPoints()
    
    -- Anclar iconos a la barra de vida con offset configurable por el usuario
    local iconSide = (CortioDB and CortioDB.iconSide) or 1
    local iconOffset = (CortioDB and CortioDB.iconOffset) or 0
    if iconSide == 2 then
        f:SetPoint("LEFT", barFrame, "RIGHT", iconOffset, 0)
    else
        f:SetPoint("RIGHT", barFrame, "LEFT", -iconOffset, 0)
    end
    f:Show()
    
    local glowMark = PickPrimaryMark(marks)
    local isMyMark = glowMark and glowMark.isLocal

    -- === NAMEPLATE BOOST: scale + strata ===
    local showGlow = (not CortioDB or CortioDB.nameplateGlow == nil) and true or CortioDB.nameplateGlow
    local scaleBoost = (CortioDB and CortioDB.nameplateScaleBoost) or 1.15
    
    if np then
        -- Scale boost: escalar directamente el UnitFrame de la nameplate
        if showGlow and scaleBoost ~= 1.0 then
            if not uiFrame._cortioOrigScale then
                pcall(function() uiFrame._cortioOrigScale = uiFrame:GetScale() end)
            end
            local desiredScale = (uiFrame._cortioOrigScale or 1) * scaleBoost
            pcall(function()
                local currentScale = uiFrame:GetScale()
                if math.abs(currentScale - desiredScale) > 0.01 then
                    uiFrame:SetScale(desiredScale)
                end
            end)
            uiFrame._cortioScaleBoosted = true
        else
            if uiFrame._cortioScaleBoosted then
                pcall(function() uiFrame:SetScale(uiFrame._cortioOrigScale or 1) end)
                uiFrame._cortioScaleBoosted = nil
                uiFrame._cortioOrigScale = nil
            end
        end
        
        -- Raise FrameStrata + FrameLevel al estilo Plater:
        -- Se cambia strata y nivel de CADA sub-frame individual
        -- (healthBar, castBar, nombre, etc.) porque los hijos no heredan strata del padre
        local bringToFront = (not CortioDB or CortioDB.bringToFront == nil) and true or CortioDB.bringToFront
        if isMyMark and bringToFront then
            -- Recopilar todos los sub-frames que debemos subir
            if not uiFrame._cortioStrataBoosted then
                uiFrame._cortioOrigFrames = {}
                -- Guardar strata+level originales de np, uiFrame y todos sus hijos
                -- np es el contenedor WorldFrame - subirlo es clave para la profundidad visual
                local frames = { np, uiFrame }
                -- Añadir sub-frames conocidos de barras nativas de WoW
                if uiFrame.healthBar then frames[#frames+1] = uiFrame.healthBar end
                if uiFrame.HealthBarsContainer then frames[#frames+1] = uiFrame.HealthBarsContainer end
                if uiFrame.castBar then frames[#frames+1] = uiFrame.castBar end
                if uiFrame.CastBar then frames[#frames+1] = uiFrame.CastBar end
                if uiFrame.BuffFrame then frames[#frames+1] = uiFrame.BuffFrame end
                if uiFrame.selectionHighlight then frames[#frames+1] = uiFrame.selectionHighlight end
                if uiFrame.aggroHighlight then frames[#frames+1] = uiFrame.aggroHighlight end
                if uiFrame.ClassificationFrame then frames[#frames+1] = uiFrame.ClassificationFrame end
                if uiFrame.RaidTargetFrame then frames[#frames+1] = uiFrame.RaidTargetFrame end
                -- Enumerar TODOS los hijos de np y uiFrame
                for _, parentFrame in ipairs({ np, uiFrame }) do
                    pcall(function()
                        local children = { parentFrame:GetChildren() }
                        for _, child in ipairs(children) do
                            if child and child.GetFrameStrata then
                                local found = false
                                for _, f2 in ipairs(frames) do if f2 == child then found = true break end end
                                if not found then frames[#frames+1] = child end
                            end
                        end
                    end)
                end
                
                for _, fr in ipairs(frames) do
                    pcall(function()
                        fr._cortioOrigStrata = fr:GetFrameStrata()
                        fr._cortioOrigLevel = fr:GetFrameLevel()
                    end)
                end
                uiFrame._cortioOrigFrames = frames
                uiFrame._cortioStrataBoosted = true
            end
            
            -- Re-imponer en cada tick (Plater style: strata DIALOG + level 5000+)
            pcall(function()
                for _, fr in ipairs(uiFrame._cortioOrigFrames) do
                    pcall(function()
                        fr:SetFrameStrata("DIALOG")
                        local origLvl = fr._cortioOrigLevel or 1
                        fr:SetFrameLevel(origLvl + 5000)
                    end)
                end
            end)
        else
            if uiFrame._cortioStrataBoosted and uiFrame._cortioOrigFrames then
                for _, fr in ipairs(uiFrame._cortioOrigFrames) do
                    pcall(function()
                        fr:SetFrameStrata(fr._cortioOrigStrata or "BACKGROUND")
                        fr:SetFrameLevel(fr._cortioOrigLevel or 1)
                    end)
                end
                uiFrame._cortioOrigFrames = nil
                uiFrame._cortioStrataBoosted = nil
            end
        end
    end
    
    -- === ANIMATED GLOW (configurable via Settings) ===
    if showGlow then
        if not f.glow then
            -- Main glow container
            f.glow = CreateFrame("Frame", nil, UIParent)
            f.glow:SetFrameStrata("BACKGROUND")
            f.glow:SetFrameLevel(0)
            
            -- Layer 1: outermost soft glow (solid texture)
            f.glowOuter = f.glow:CreateTexture(nil, "BACKGROUND", nil, -2)
            f.glowOuter:SetTexture("Interface\\Buttons\\WHITE8x8")
            
            -- Layer 2: middle glow (solid texture)
            f.glowMid = f.glow:CreateTexture(nil, "BACKGROUND", nil, -1)
            f.glowMid:SetTexture("Interface\\Buttons\\WHITE8x8")
            
            -- Layer 3: inner bright border
            f.glowInner = CreateFrame("Frame", nil, f.glow, "BackdropTemplate")
            f.glowInner:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            
            -- Pulse animation: breathing effect
            f.glowAG = f.glow:CreateAnimationGroup()
            f.glowAG:SetLooping("BOUNCE")
            local pulse = f.glowAG:CreateAnimation("Alpha")
            pulse:SetFromAlpha(0.35)
            pulse:SetToAlpha(1.0)
            pulse:SetDuration(0.8)
            pulse:SetSmoothing("IN_OUT")
            f.glowAG:Play()
        end
        
        -- Levantar el brillo por encima del fondo con cuidado para evitar errores de Lua
        local strata = "LOW"
        local lvl = 1
        pcall(function() strata = uiFrame:GetFrameStrata() or "LOW" end)
        pcall(function() lvl = (uiFrame:GetFrameLevel() or 1) + 4 end)
        
        -- Si el Bring to Front está activado, blindamos el brillo a capa DIALOG independientemente de la placa
        local bringToFront = (not CortioDB or CortioDB.bringToFront == nil) and true or CortioDB.bringToFront
        if isMyMark and bringToFront then 
            strata = "DIALOG" 
        end
        
        f.glow:SetFrameStrata(strata)
        f.glow:SetFrameLevel(lvl)

        -- Expandir el brillo para generar el marco translúcido de fondo (estilo original)
        f.glow:ClearAllPoints()
        f.glow:SetPoint("TOPLEFT", barFrame, "TOPLEFT", -8, 8)
        f.glow:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 8, -8)
        f.glow:Show()
        
        f.glowOuter:ClearAllPoints()
        f.glowOuter:SetPoint("TOPLEFT", barFrame, "TOPLEFT", -6, 6)
        f.glowOuter:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 6, -6)
        
        f.glowMid:ClearAllPoints()
        f.glowMid:SetPoint("TOPLEFT", barFrame, "TOPLEFT", -3, 3)
        f.glowMid:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 3, -3)
        
        f.glowInner:ClearAllPoints()
        f.glowInner:SetPoint("TOPLEFT", barFrame, "TOPLEFT", -1, 1)
        f.glowInner:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 1, -1)
        
        -- Color by class
        if glowMark then
            local colorHex = Cortio.Data.CLASS_COLORS[glowMark.playerClass] or "FFFFFFFF"
            local gR = tonumber(colorHex:sub(3, 4), 16) / 255
            local gG = tonumber(colorHex:sub(5, 6), 16) / 255
            local gB = tonumber(colorHex:sub(7, 8), 16) / 255
            
            f.glowOuter:SetColorTexture(gR, gG, gB, 0.15)
            f.glowMid:SetColorTexture(gR, gG, gB, 0.3)
            f.glowInner:SetBackdropBorderColor(gR, gG, gB, 0.95)
        end
        
        if not f.glowAG:IsPlaying() then f.glowAG:Play() end
    else
        if f.glow then
            f.glow:Hide()
            if f.glowAG then f.glowAG:Stop() end
        end
        -- Restore nameplate scale
        if np and np._cortioScaled then
            np:SetScale(np._cortioOrigScale or 1)
            np._cortioScaled = false
        end
    end
    
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

-- ============================================================
-- Kick Icon (unchanged)
-- ============================================================
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

-- ============================================================
-- Settings (unchanged)
-- ============================================================
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
    
    -- Nameplate Glow
    local glowSetting = Settings.RegisterProxySetting(
        category, "Cortio_NameplateGlow", Settings.VarType.Boolean, "Brillo en Nameplate",
        (not CortioDB or CortioDB.nameplateGlow == nil) and true or CortioDB.nameplateGlow,
        function() return (not CortioDB or CortioDB.nameplateGlow == nil) and true or CortioDB.nameplateGlow end,
        function(val)
            if not CortioDB then CortioDB = {} end
            CortioDB.nameplateGlow = val
            Cortio.UI:UpdateAllNameplates()
        end
    )
    Settings.CreateCheckbox(category, glowSetting, "Muestra un borde brillante alrededor de la nameplate del mob asignado para cortarte.")
    
    -- Bring to Front Option
    local frontSetting = Settings.RegisterProxySetting(
        category, "Cortio_BringToFront", Settings.VarType.Boolean, "Traer barra al Frente (Top Layer)",
        (not CortioDB or CortioDB.bringToFront == nil) and true or CortioDB.bringToFront,
        function() return (not CortioDB or CortioDB.bringToFront == nil) and true or CortioDB.bringToFront end,
        function(val)
            if not CortioDB then CortioDB = {} end
            CortioDB.bringToFront = val
            Cortio.UI:UpdateAllNameplates()
        end
    )
    Settings.CreateCheckbox(category, frontSetting, "Fuerza a la barra de vida de tu objetivo asignado a renderizarse por encima del resto (FrameStrata: DIALOG) cuando tienes la patada asignada.")
    
    -- Nameplate Scale Boost
    local npScaleSetting = Settings.RegisterProxySetting(
        category, "Cortio_NPScale", Settings.VarType.Number, "Tamaño de la Barra del Objetivo",
        (CortioDB and CortioDB.nameplateScaleBoost) or 1.15,
        function() return (CortioDB and CortioDB.nameplateScaleBoost) or 1.15 end,
        function(val)
            if not CortioDB then CortioDB = {} end
            CortioDB.nameplateScaleBoost = val
            Cortio.UI:UpdateAllNameplates()
        end
    )
    local npScaleOpts = Settings.CreateSliderOptions(0.8, 2.0, 0.05)
    npScaleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.2fx", v) end)
    Settings.CreateSlider(category, npScaleSetting, npScaleOpts, "Escala de la barra de vida del mob asignado.")
    
    -- ============================================================
    -- Icon Position (LEFT / RIGHT of nameplate)
    local iconSideSetting = Settings.RegisterProxySetting(
        category, "Cortio_IconSide", Settings.VarType.Number, "Lado de los iconos de corte",
        (CortioDB and CortioDB.iconSide) or 1,
        function() return (CortioDB and CortioDB.iconSide) or 1 end,
        function(val)
            if not CortioDB then CortioDB = {} end
            CortioDB.iconSide = val
            Cortio.UI:UpdateAllNameplates()
        end
    )
    local sideOptions = Settings.CreateSliderOptions(1, 2, 1)
    sideOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
        return v == 1 and "Izquierda" or "Derecha"
    end)
    Settings.CreateSlider(category, iconSideSetting, sideOptions, "En qué lado de la barra de vida del mob aparecen los iconos de interrupción.")
    
    -- Icon Offset (horizontal distance from health bar edge)
    local iconOffsetSetting = Settings.RegisterProxySetting(
        category, "Cortio_IconOffset", Settings.VarType.Number, "Separación horizontal de iconos",
        (CortioDB and CortioDB.iconOffset) or 0,
        function() return (CortioDB and CortioDB.iconOffset) or 0 end,
        function(val)
            if not CortioDB then CortioDB = {} end
            CortioDB.iconOffset = val
            Cortio.UI:UpdateAllNameplates()
        end
    )
    local offsetOpts = Settings.CreateSliderOptions(-50, 50, 1)
    offsetOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return v .. "px" end)
    Settings.CreateSlider(category, iconOffsetSetting, offsetOpts, "Ajusta la distancia horizontal de los iconos respecto al borde de la barra de vida.")
    
    -- Debug Logs
    local debugSetting = Settings.RegisterProxySetting(
        category, "Cortio_DebugLogs", Settings.VarType.Boolean, "Logs de Debug",
        (CortioDB and CortioDB.debugLogs) or false,
        function() return (CortioDB and CortioDB.debugLogs) or false end,
        function(val)
            if not CortioDB then CortioDB = {} end
            CortioDB.debugLogs = val
        end
    )
    Settings.CreateCheckbox(category, debugSetting, "Muestra mensajes de debug en el chat (correlación de señales, red, etc).")
    
    Settings.RegisterAddOnCategory(category)
end

-- ============================================================
-- Slash Commands (unchanged)
-- ============================================================
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
        CortioDB.framePoint = nil
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
        
        -- Prefix status
        local prefixOk = C_ChatInfo.IsAddonMessagePrefixRegistered and
            C_ChatInfo.IsAddonMessagePrefixRegistered(Cortio.Data.COMM_PREFIX)
        print("  prefix '" .. Cortio.Data.COMM_PREFIX .. "' registered = " .. tostring(prefixOk))
        
        -- Network stats
        local stats = Cortio.Net.Stats
        print(string.format("  net: sent=%d recv=%d | this min: sent=%d recv=%d",
            stats.sent, stats.received, stats.sentThisMinute, stats.receivedThisMinute))
        print("  lastSendResult = " .. tostring(stats.lastResult)
            .. " (" .. string.format("%.1fs ago", GetTime() - (stats.lastResultTime or 0)) .. ")")
        print("  queue length = " .. #Cortio.Net.Queue)
        
        -- Panel ticker status
        print("  panelTicker active = " .. tostring(Cortio.PanelTicker ~= nil))
        
        -- Active marks
        print("  activeMarks (" .. #Cortio.Marks.Active .. "):")
        for i, m in ipairs(Cortio.Marks.Active) do
            print(string.format("    [%d] player=%s slot=%s class=%s",
                i, tostring(m.playerName), tostring(m.markerSlot), tostring(m.playerClass)))
        end
        
        -- Roster
        print("  CortioRoster:")
        for k, v in pairs(Cortio.RosterList) do
            print(string.format("    [%s] unit=%s class=%s spec=%s specId=%s guid=%s cdEnd=%.1f",
                tostring(k), tostring(v.unit), tostring(v.class),
                tostring(v.specIcon), tostring(v.specId or 0),
                tostring(v.guid or "?"), (v.cdEnd or 0) - GetTime()))
        end
        
        -- Recent messages
        if #stats.recentMessages > 0 then
            print("  Last " .. #stats.recentMessages .. " received messages:")
            for _, msg in ipairs(stats.recentMessages) do
                print(string.format("    [%s] from=%s: %s",
                    msg.time, tostring(msg.sender), tostring(msg.msg)))
            end
        else
            print("  No messages received yet.")
        end
        
        print("|cFF00FFFF[Cortio]|r === FIN ===")
    elseif cmd == "debugcl" then
        if not CortioDB then CortioDB = {} end
        CortioDB.debugCombatLog = not CortioDB.debugCombatLog
        if CortioDB.debugCombatLog then
            print("|cFF00FFFF[Cortio]|r Combat Log debug: |cFF44FF88ON|r (interrupt events will be printed)")
        else
            print("|cFF00FFFF[Cortio]|r Combat Log debug: |cFFFF4444OFF|r")
        end
    elseif cmd == "logs" then
        if not CortioDB then CortioDB = {} end
        CortioDB.debugLogs = not CortioDB.debugLogs
        if CortioDB.debugLogs then
            print("|cFF00FFFF[Cortio]|r Developer logs: |cFF44FF88ON|r")
        else
            print("|cFF00FFFF[Cortio]|r Developer logs: |cFFFF4444OFF|r")
        end
    else
        print("|cFF00FFFF[Cortio]|r Opciones: /ct show|hide | /ct debug | /ct debugcl | /ct logs | /ct errors | /ct clear")
        print("|cFF00FFFF[Cortio]|r Atajos: ESC -> Opciones -> Atajos (Keybindings).")
    end
end
