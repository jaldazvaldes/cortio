--------------------------------------------------------------
-- INTERRUPTIO - UI (Modern Display)
--------------------------------------------------------------
Interruptio = Interruptio or {}
Interruptio.UI = {}

Interruptio.UI.ActiveNameplates = {}
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

-- Color Palette (Interruptio: deep blue + cyan accent)
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
local panel = CreateFrame("Frame", "InterruptioPanelFrame", UIParent, "BackdropTemplate")
panel:SetSize(FRAME_WIDTH, HEADER_HEIGHT + 10)
panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if InterruptioDB then
        local point, _, relPoint, x, y = self:GetPoint()
        InterruptioDB.framePoint = { point, nil, relPoint, x, y }
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
titleText:SetText("|cff00d4ffINTERRUPTIO|r")

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

Interruptio.UI.Panel = panel

function Interruptio.UI:ApplyTheme()
    local modern = (not InterruptioDB or InterruptioDB.modernUI == nil) and true or InterruptioDB.modernUI
    if modern then
        panelBg:SetColorTexture(0, 0, 0, 0.4)
        panel:SetBackdropBorderColor(0, 0, 0, 0.9)
        headerBg:SetColorTexture(0, 0, 0, 0.7)
    else
        panelBg:SetColorTexture(C_BG[1], C_BG[2], C_BG[3], 0.95)
        panel:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 0.35)
        headerBg:SetColorTexture(C_HEADER_BG[1], C_HEADER_BG[2], C_HEADER_BG[3], 0.98)
    end
end
Interruptio.UI:ApplyTheme()

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

    -- Class-color left stripe (3px accent — Interruptio signature)
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

    bar._targetStripW = 1
    bar.strip:SetWidth(1)
    bar:SetScript("OnUpdate", function(self, elapsed)
        local currW = self.strip:GetWidth()
        if self._targetStripW and math.abs(currW - self._targetStripW) > 0.5 then
            self.strip:SetWidth(currW + (self._targetStripW - currW) * 15 * elapsed)
        end
    end)
    
    -- Flash glow overlay for ready state
    bar.flashGlow = bar:CreateTexture(nil, "OVERLAY")
    bar.flashGlow:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 2, 0)
    bar.flashGlow:SetPoint("BOTTOMRIGHT", 0, 0)
    bar.flashGlow:SetColorTexture(1, 1, 1, 1)
    bar.flashGlow:SetBlendMode("ADD")
    bar.flashGlow:SetAlpha(0)
    
    bar.flashAG = bar.flashGlow:CreateAnimationGroup()
    bar.flashAG:SetLooping("BOUNCE")
    local flashAlpha = bar.flashAG:CreateAnimation("Alpha")
    flashAlpha:SetFromAlpha(0.1)
    flashAlpha:SetToAlpha(0.4)
    flashAlpha:SetDuration(1.2)
    flashAlpha:SetSmoothing("IN_OUT")

    bar:Hide()
    barPool[index] = bar
    return bar
end

-- ============================================================
-- UpdatePanel (Cooldown spiral + progress strip rendering)
-- ============================================================
function Interruptio.UI:UpdatePanel()
    -- Hide all existing bars
    for i = 1, activeBarCount do
        if barPool[i] then barPool[i]:Hide() end
    end

    local entries = {}
    local now = GetTime()
    local readyCount = 0
    local totalCount = 0

    for rPlayerName, data in pairs(Interruptio.RosterList) do
        local rClass = data.class
        local sLeft = (data.cdEnd or 0) - now
        local isReady = sLeft <= 0

        -- Clear lastResult when CD has fully expired (prevents stale "–" icon next to "READY")
        if isReady and data.lastResult then
            data.lastResult = nil
        end

        -- Find assigned mark
        local assignedMark = nil
        local rShort = Interruptio.Data:ShortName(rPlayerName)
        for _, m in ipairs(Interruptio.Marks.Active) do
            if m.playerName == rPlayerName or Interruptio.Data:ShortName(m.playerName) == rShort then
                assignedMark = m
                break
            end
        end

        totalCount = totalCount + 1
        if isReady then readyCount = readyCount + 1 end

        local staticSlot = Interruptio.Marks:GetMarkerSlotForPlayer(rPlayerName)
        
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
        local colorHex = Interruptio.Data.CLASS_COLORS[entry.class] or "FFFFFFFF"
        local classR = tonumber(colorHex:sub(3, 4), 16) / 255
        local classG = tonumber(colorHex:sub(5, 6), 16) / 255
        local classB = tonumber(colorHex:sub(7, 8), 16) / 255

        -- Class stripe
        bar.classStripe:SetColorTexture(classR, classG, classB, 0.8)

        local modern = (not InterruptioDB or InterruptioDB.modernUI == nil) and true or InterruptioDB.modernUI
        local emphasize = (not InterruptioDB or InterruptioDB.emphasizeReady == nil) and true or InterruptioDB.emphasizeReady
        local isClassBars = InterruptioDB and InterruptioDB.classBars
        local showIcon = (not InterruptioDB or InterruptioDB.showSpellIcon == nil) and true or InterruptioDB.showSpellIcon
        local maxStripW

        bar.strip:ClearAllPoints()

        if isClassBars then
            bar.classStripe:Hide()
            if showIcon then
                bar.icon:SetPoint("LEFT", 4, 0)
                bar.iconBg:ClearAllPoints()
                bar.iconBg:SetPoint("CENTER", bar.icon, "CENTER", 0, 0)
                bar.strip:SetPoint("LEFT", bar.iconBg, "RIGHT", 0, 0)
                maxStripW = barWidth - 25
            else
                bar.strip:SetPoint("LEFT", bar, "LEFT", 0, 0)
                maxStripW = barWidth
            end
            bar.strip:SetHeight(BAR_HEIGHT)
            bar.strip:SetDrawLayer("BORDER")
        else
            bar.classStripe:Show()
            if showIcon then
                bar.icon:SetPoint("LEFT", 7, 0)
                bar.iconBg:ClearAllPoints()
                bar.iconBg:SetPoint("CENTER", bar.icon, "CENTER", 0, 0)
                bar.strip:SetPoint("BOTTOMLEFT", 3, 0)
                maxStripW = barWidth - 6
            else
                bar.strip:SetPoint("BOTTOMLEFT", 3, 0)
                maxStripW = barWidth - 6
            end
            bar.strip:SetHeight(STRIP_HEIGHT)
            bar.strip:SetDrawLayer("ARTWORK", 4)
        end

        -- State-dependent visuals
        if entry.isReady then
            if not bar._wasReady then
                bar._wasReady = true
                if modern and emphasize and barWidth > 10 and not isClassBars then bar.flashAG:Play() end
            end
            if isClassBars and bar.flashAG:IsPlaying() then bar.flashAG:Stop() end
            
            if emphasize then 
                bar:SetAlpha(1.0)
                bar.icon:SetDesaturated(false)
            end
            
            -- Ready: subtle bright tint on background, green border
            local bgA = modern and 0.4 or 0.92
            if isClassBars then
                bar.bg:SetColorTexture(0, 0, 0, modern and 0.4 or 0.7)
                bar.border:SetBackdropBorderColor(0, 0, 0, 0)
            else
                bar.bg:SetColorTexture(
                    C_BAR_BG[1] + C_READY[1] * 0.04,
                    C_BAR_BG[2] + C_READY[2] * 0.04,
                    C_BAR_BG[3] + C_READY[3] * 0.04, bgA)
                bar.border:SetBackdropBorderColor(C_READY[1], C_READY[2], C_READY[3], modern and 0.6 or 0.25)
            end
            
            bar.statusText:SetText("|cff" .. HEX_READY .. "READY|r")
            -- Icon cooldown: clear
            bar.iconCD:SetCooldown(0, 0)
            -- Progress strip: full width, green
            if modern then
                bar._targetStripW = maxStripW
            else
                bar.strip:SetWidth(maxStripW)
            end
            
            if isClassBars then
                bar.strip:SetColorTexture(classR, classG, classB, 0.85)
            else
                bar.strip:SetColorTexture(C_READY[1], C_READY[2], C_READY[3], modern and 0.9 or 0.45)
            end
        else
            bar._wasReady = false
            if modern then bar.flashAG:Stop() end
            if emphasize then 
                bar:SetAlpha(0.45)
                bar.icon:SetDesaturated(true)
            else
                bar:SetAlpha(1.0)
                bar.icon:SetDesaturated(false)
            end
            
            -- On CD: default dark background, colored border
            local ratio = entry.remaining / entry.cdTotal
            local r, g, b, hex = getCooldownColor(ratio)
            local baseBg = modern and {0, 0, 0} or C_BAR_BG
            local bgA = modern and 0.4 or 0.9
            
            if isClassBars then
                bar.bg:SetColorTexture(0, 0, 0, modern and 0.4 or 0.7)
                bar.border:SetBackdropBorderColor(0, 0, 0, 0)
            else
                bar.bg:SetColorTexture(baseBg[1], baseBg[2], baseBg[3], bgA)
                bar.border:SetBackdropBorderColor(r, g, b, modern and 0.2 or 0.15)
            end

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
            local stripW = math.max(1, maxStripW * progress)
            if modern then
                bar._targetStripW = stripW
                if math.abs(bar.strip:GetWidth() - stripW) > barWidth / 2 then
                    bar.strip:SetWidth(stripW)
                end
            else
                bar.strip:SetWidth(stripW)
            end
            
            if isClassBars then
                bar.strip:SetColorTexture(classR, classG, classB, 0.85)
            else
                bar.strip:SetColorTexture(r, g, b, modern and 0.8 or 0.5)
            end
        end

        -- Spell icon (spec-aware)
        local spellId = nil
        if entry.specId > 0 and Interruptio.Data.SPEC_INTERRUPTS[entry.specId] then
            spellId = Interruptio.Data.SPEC_INTERRUPTS[entry.specId].spellId
        end
        if not spellId then
            spellId = Interruptio.Data.CLASS_INTERRUPT_SPELLID[entry.class]
        end

        bar.iconHit._spellID = spellId

        local iconID = Interruptio.Data.CLASS_INTERRUPT_ICONS[entry.class]
        if iconID and showIcon then
            bar.icon:SetTexture(tonumber(iconID))
            bar.icon:Show()
            bar.iconBg:Show()
            bar.iconHit:Show()
        else
            bar.icon:Hide()
            bar.iconBg:Hide()
            bar.iconHit:Hide()
            bar.iconCD:SetCooldown(0, 0)
        end

        -- Class-tinted icon background
        bar.iconBg:SetColorTexture(classR * 0.25, classG * 0.25, classB * 0.25, 0.8)

        -- Raid marker
        bar.nameText:ClearAllPoints()
        bar.marker:ClearAllPoints()
        bar.flashGlow:ClearAllPoints()
        
        if entry.markerSlot and entry.markerSlot > 0 then
            bar.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. entry.markerSlot)
            bar.marker:Show()
        else
            bar.marker:Hide()
        end
        
        local textBasePad = 6
        if showIcon then
            bar.flashGlow:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 2, 0)
            if entry.markerSlot and entry.markerSlot > 0 then
                bar.marker:SetPoint("LEFT", bar.icon, "RIGHT", 4, 0)
                bar.nameText:SetPoint("LEFT", bar.marker, "RIGHT", 4, 0)
            else
                bar.nameText:SetPoint("LEFT", bar.icon, "RIGHT", textBasePad, 0)
            end
        else
            local baseRef = isClassBars and bar or bar.classStripe
            local anchorPoint = isClassBars and "TOPLEFT" or "TOPRIGHT"
            local leftAnchorPoint = isClassBars and "LEFT" or "RIGHT"
            
            bar.flashGlow:SetPoint("TOPLEFT", baseRef, anchorPoint, 0, 0)
            
            if entry.markerSlot and entry.markerSlot > 0 then
                bar.marker:SetPoint("LEFT", baseRef, leftAnchorPoint, textBasePad, 0)
                bar.nameText:SetPoint("LEFT", bar.marker, "RIGHT", 4, 0)
            else
                bar.nameText:SetPoint("LEFT", baseRef, leftAnchorPoint, textBasePad, 0)
            end
        end
        bar.flashGlow:SetPoint("BOTTOMRIGHT", 0, 0)
        
        bar.nameText:SetPoint("RIGHT", bar.statusText, "LEFT", -4, 0)

        -- Player name (class colored)
        if isClassBars then
            bar.nameText:SetText("|cFFFFFFFF" .. Interruptio.Data:ShortName(entry.playerName) .. "|r")
        else
            bar.nameText:SetText("|c" .. colorHex .. Interruptio.Data:ShortName(entry.playerName) .. "|r")
        end

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
    if InterruptioDB and InterruptioDB.framePoint and not panel._posRestored then
        local p = InterruptioDB.framePoint
        if p[1] then
            panel:ClearAllPoints()
            panel:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        end
        panel._posRestored = true
    end

    panel:Show()

    Interruptio.Data:SafeCall("Nameplates", function() Interruptio.UI:UpdateAllNameplates() end)
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

function Interruptio.UI:ReleaseNameplateFrame(unit)
    local f = Interruptio.UI.ActiveNameplates[unit]
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
            if uFrame._interruptioScaleBoosted then
                pcall(function() uFrame:SetScale(uFrame._interruptioOrigScale or 1) end)
                uFrame._interruptioScaleBoosted = nil
                uFrame._interruptioOrigScale = nil
            end
            -- Restore reparenting (elevation) sin ser destructivos
            if uFrame._interruptioReparented then
                pcall(function()
                    if uFrame._interruptioOrigStrata then uFrame:SetFrameStrata(uFrame._interruptioOrigStrata) end
                    if uFrame._interruptioOrigLevel then uFrame:SetFrameLevel(uFrame._interruptioOrigLevel) end
                end)
                uFrame._interruptioReparented = nil
                uFrame._interruptioOrigStrata = nil
                uFrame._interruptioOrigLevel = nil
            end
        end
        f:Hide()
        f:ClearAllPoints()
        f.inUse = false
        Interruptio.UI.ActiveNameplates[unit] = nil
    end
end

function Interruptio.UI:UpdateNameplate(unit)
    local marks = {}

    -- Read raid marker on this nameplate (taint-safe)
    local raidIndex = nil
    if UnitExists(unit) then
        local okRT, idx = pcall(GetRaidTargetIndex, unit)
        -- Extra security: drop it immediately if it's flagged as secret by the client
        if okRT and idx and not Interruptio.Taint:IsSecret(idx) then
            raidIndex = idx 
        end
    end

    for _, mark in ipairs(Interruptio.Marks.Active) do
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
                if Interruptio.Taint:SafeIsMatch("target", unit) then
                    isMatch = true
                    mark.unitToken = nil
                end
            else
                mark.unitToken = nil
            end
        end

        if isMatch then
            mark.nameplateUnit = unit
            mark.isLocal = (mark.playerName == Interruptio.PlayerName)
            table.insert(marks, mark)
        elseif mark.nameplateUnit == unit then
            mark.nameplateUnit = nil
        end
    end
    
    local f = Interruptio.UI.ActiveNameplates[unit]
    
    if #marks == 0 then 
        if f then Interruptio.UI:ReleaseNameplateFrame(unit) end
        return 
    end
    
    local np = C_NamePlate.GetNamePlateForUnit(unit)
    if not np then 
        if f then Interruptio.UI:ReleaseNameplateFrame(unit) end
        return 
    end
    
    -- Try to find the actual health bar for the glow
    local uiFrame = np.UnitFrame or np
    local barFrame = uiFrame.healthBar or uiFrame.HealthBar or uiFrame.Health or uiFrame.healthbar or uiFrame

    if not f then
        f = GetNameplateFrame()
        Interruptio.UI.ActiveNameplates[unit] = f
    end
    
    if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
    f:ClearAllPoints()
    
    -- Anclar iconos a la barra de vida con offset configurable por el usuario
    local iconSide = (InterruptioDB and InterruptioDB.iconSide) or 1
    local iconOffset = (not InterruptioDB or InterruptioDB.iconOffset == nil) and 30 or InterruptioDB.iconOffset
    local iconOffsetY = (InterruptioDB and InterruptioDB.iconOffsetY) or 0
    if iconSide == 2 then
        f:SetPoint("LEFT", barFrame, "RIGHT", iconOffset, iconOffsetY)
    elseif iconSide == 3 then
        f:SetPoint("BOTTOMRIGHT", barFrame, "TOPRIGHT", iconOffset, 2 + iconOffsetY)
    elseif iconSide == 4 then
        f:SetPoint("TOPRIGHT", barFrame, "BOTTOMRIGHT", iconOffset, -2 + iconOffsetY)
    else
        f:SetPoint("RIGHT", barFrame, "LEFT", -iconOffset, iconOffsetY)
    end
    f:Show()
    
    local glowMark = PickPrimaryMark(marks)
    local isMyMark = glowMark and glowMark.isLocal

    -- === NAMEPLATE BOOST: scale + strata ===
    local showGlow = (not InterruptioDB or InterruptioDB.nameplateGlow == nil) and true or InterruptioDB.nameplateGlow
    local scaleBoost = (InterruptioDB and InterruptioDB.nameplateScaleBoost) or 1.15
    
    if np then
        -- Scale boost: solo para el mob que TÚ tienes marcado (isMyMark)
        if isMyMark and showGlow and scaleBoost ~= 1.0 then
            if not uiFrame._interruptioOrigScale then
                pcall(function() uiFrame._interruptioOrigScale = uiFrame:GetScale() end)
            end
            local desiredScale = (uiFrame._interruptioOrigScale or 1) * scaleBoost
            pcall(function()
                local currentScale = uiFrame:GetScale()
                if math.abs(currentScale - desiredScale) > 0.01 then
                    uiFrame:SetScale(desiredScale)
                end
            end)
            uiFrame._interruptioScaleBoosted = true
        else
            -- Restaurar escala si ya no es tu marca o se desactiva
            if uiFrame._interruptioScaleBoosted then
                pcall(function() uiFrame:SetScale(uiFrame._interruptioOrigScale or 1) end)
                uiFrame._interruptioScaleBoosted = nil
                uiFrame._interruptioOrigScale = nil
            end
        end
        
        -- ============================================================
        -- Bring to Front: Safe Strata Elevation
        -- ============================================================
        local bringToFront = (not InterruptioDB or InterruptioDB.bringToFront == nil) and true or InterruptioDB.bringToFront
        if isMyMark and bringToFront then
            if not uiFrame._interruptioReparented then
                -- Guardar strata y level originales sin arrancar la barra de su padre
                pcall(function()
                    uiFrame._interruptioOrigStrata = uiFrame:GetFrameStrata()
                    uiFrame._interruptioOrigLevel = uiFrame:GetFrameLevel()
                end)
                -- Elevar
                pcall(function()
                    uiFrame:SetFrameStrata("TOOLTIP")
                    uiFrame:SetFrameLevel(9000)
                end)
                uiFrame._interruptioReparented = true
            end
        else
            -- Restaurar strata y level originales
            if uiFrame._interruptioReparented then
                pcall(function()
                    if uiFrame._interruptioOrigStrata then uiFrame:SetFrameStrata(uiFrame._interruptioOrigStrata) end
                    if uiFrame._interruptioOrigLevel then uiFrame:SetFrameLevel(uiFrame._interruptioOrigLevel) end
                end)
                uiFrame._interruptioReparented = nil
                uiFrame._interruptioOrigStrata = nil
                uiFrame._interruptioOrigLevel = nil
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
        local bringToFront = (not InterruptioDB or InterruptioDB.bringToFront == nil) and true or InterruptioDB.bringToFront
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
            local colorHex = Interruptio.Data.CLASS_COLORS[glowMark.playerClass] or "FFFFFFFF"
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
        if np and np._interruptioScaled then
            np:SetScale(np._interruptioOrigScale or 1)
            np._interruptioScaled = false
        end
    end
    
    local iconIdx = 0
    for _, mark in ipairs(marks) do
        local classIcon = Interruptio.Data.CLASS_INTERRUPT_ICONS[mark.playerClass]
        if classIcon then
            iconIdx = iconIdx + 1
            if iconIdx <= MAX_ICONS_PER_PLATE then
                local ic = f.icons[iconIdx]
                ic.texture:SetTexture(tonumber(classIcon))
                ic.ownerName = mark.playerName
                ic.isLocal = (mark.playerName == Interruptio.PlayerName)
                
                local pData = Interruptio.RosterList[mark.playerName]
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

function Interruptio.UI:UpdateAllNameplates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            Interruptio.UI:UpdateNameplate(unit)
        end
    end
end

-- ============================================================
-- Kick Icon (Removed by user request)
-- ============================================================
function Interruptio.UI:UpdateKickCooldown() end
function Interruptio.UI:SetupKickIcon() end

panel:Hide()

-- ============================================================
-- Settings (unchanged)
-- ============================================================
local settingsCreated = false
function Interruptio.UI:CreateSettingsMenu()
    if settingsCreated then return end
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end
    settingsCreated = true
    
    local category = Settings.RegisterVerticalLayoutCategory("Interruptio")
    
    local scaleSetting = Settings.RegisterProxySetting(
        category, "Interruptio_Scale", Settings.VarType.Number, "Tamaño de la Ventana", 
        (InterruptioDB and InterruptioDB.scale) or 1.0, 
        function() return (InterruptioDB and InterruptioDB.scale) or 1.0 end,
        function(val) 
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.scale = val 
            Interruptio.UI.Panel:SetScale(val) 
        end
    )
    local scaleOpts = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
    scaleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.2fx", v) end)
    Settings.CreateSlider(category, scaleSetting, scaleOpts, "Ajusta la escala del panel flotante.")
    
    local announceSetting = Settings.RegisterProxySetting(
        category, "Interruptio_Announce", Settings.VarType.Boolean, "Anunciar asignaciones en grupo", 
        (not InterruptioDB or InterruptioDB.announce == nil) and true or InterruptioDB.announce, 
        function() return (not InterruptioDB or InterruptioDB.announce == nil) and true or InterruptioDB.announce end,
        function(val) 
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.announce = val 
        end
    )
    Settings.CreateCheckbox(category, announceSetting, "Enviar mensaje al chat de grupo /p cada vez que cambias tu marca.")

    local announceCDSetting = Settings.RegisterProxySetting(
        category, "Interruptio_AnnounceCD", Settings.VarType.Boolean, "Anunciar tu CD al marcar", 
        (not InterruptioDB or InterruptioDB.announceCD == nil) and true or InterruptioDB.announceCD, 
        function() return (not InterruptioDB or InterruptioDB.announceCD == nil) and true or InterruptioDB.announceCD end,
        function(val)  
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.announceCD = val 
        end
    )
    Settings.CreateCheckbox(category, announceCDSetting, "Añade el tiempo de recarga (CD) que le queda a tu corte en el mensaje de chat al asignar una marca.")
    
    local modernSetting = Settings.RegisterProxySetting(
        category, "Interruptio_ModernUI", Settings.VarType.Boolean, "UI Moderna (Translúcida & Fluida)", 
        (not InterruptioDB or InterruptioDB.modernUI == nil) and true or InterruptioDB.modernUI, 
        function() return (not InterruptioDB or InterruptioDB.modernUI == nil) and true or InterruptioDB.modernUI end,
        function(val) 
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.modernUI = val
            Interruptio.UI:ApplyTheme()
            Interruptio.UI:UpdatePanel()
        end
    )
    Settings.CreateCheckbox(category, modernSetting, "Activa fondos estilo 'cristal' translúcidos y barras con movimiento y destellos brillantes suaves.")
    
    local emphasizeSetting = Settings.RegisterProxySetting(
        category, "Interruptio_EmphasizeReady", Settings.VarType.Boolean, "Resaltar Disp. (Atenuación + Latido)", 
        (InterruptioDB and InterruptioDB.emphasizeReady) or false, 
        function() return (InterruptioDB and InterruptioDB.emphasizeReady) or false end,
        function(val) 
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.emphasizeReady = val
            Interruptio.UI:UpdatePanel()
        end
    )
    Settings.CreateCheckbox(category, emphasizeSetting, "Las barras de cortes en enfriamiento se oscurecen al 60% y sus iconos se vuelven grises. Los disponibles laten al 100%.")

    local classBarsSetting = Settings.RegisterProxySetting(
        category, "Interruptio_ClassBars", Settings.VarType.Boolean, "Barras Progeso Clásicas (Color Clase)", 
        (not InterruptioDB or InterruptioDB.classBars == nil) and true or InterruptioDB.classBars, 
        function() return (not InterruptioDB or InterruptioDB.classBars == nil) and true or InterruptioDB.classBars end,
        function(val) 
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.classBars = val
            Interruptio.UI:UpdatePanel()
        end
    )
    Settings.CreateCheckbox(category, classBarsSetting, "Las barras de enfriamiento rellenarán toda su altura con el color de clase estilo clásico, sustituyendo la línea de color dinámico.")

    local showSpellIconSetting = Settings.RegisterProxySetting(
        category, "Interruptio_ShowSpellIcon", Settings.VarType.Boolean, "Mostrar Icono del Hechizo", 
        (not InterruptioDB or InterruptioDB.showSpellIcon == nil) and true or InterruptioDB.showSpellIcon, 
        function() return (not InterruptioDB or InterruptioDB.showSpellIcon == nil) and true or InterruptioDB.showSpellIcon end,
        function(val) 
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.showSpellIcon = val
            Interruptio.UI:UpdatePanel()
        end
    )
    Settings.CreateCheckbox(category, showSpellIconSetting, "Muestra el icono del hechizo de interrupción a la izquierda del nombre del jugador.")

    local testSetting = Settings.RegisterProxySetting(
        category, "Interruptio_TestMode", Settings.VarType.Boolean, "Modo de Prueba (Test Mode)", 
        (InterruptioDB and InterruptioDB.testMode) or false, 
        function() return (InterruptioDB and InterruptioDB.testMode) or false end,
        function(val) 
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.testMode = val
            Interruptio.Roster:Rebuild()
            if val then Interruptio.UI.Panel:Show() else Interruptio.UI.Panel:Hide() end
        end
    )
    Settings.CreateCheckbox(category, testSetting, "Genera un grupo falso para probar la interfaz de cortes.")
    
    -- Nameplate Glow
    local glowSetting = Settings.RegisterProxySetting(
        category, "Interruptio_NameplateGlow", Settings.VarType.Boolean, "Brillo en Nameplate",
        (not InterruptioDB or InterruptioDB.nameplateGlow == nil) and true or InterruptioDB.nameplateGlow,
        function() return (not InterruptioDB or InterruptioDB.nameplateGlow == nil) and true or InterruptioDB.nameplateGlow end,
        function(val)
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.nameplateGlow = val
            Interruptio.UI:UpdateAllNameplates()
        end
    )
    Settings.CreateCheckbox(category, glowSetting, "Muestra un borde brillante alrededor de la nameplate del mob asignado para cortarte.")
    
    -- Bring to Front Option
    local frontSetting = Settings.RegisterProxySetting(
        category, "Interruptio_BringToFront", Settings.VarType.Boolean, "Traer barra al Frente (Top Layer)",
        (not InterruptioDB or InterruptioDB.bringToFront == nil) and true or InterruptioDB.bringToFront,
        function() return (not InterruptioDB or InterruptioDB.bringToFront == nil) and true or InterruptioDB.bringToFront end,
        function(val)
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.bringToFront = val
            Interruptio.UI:UpdateAllNameplates()
        end
    )
    Settings.CreateCheckbox(category, frontSetting, "Fuerza a la barra de vida de tu objetivo asignado a renderizarse por encima del resto (FrameStrata: DIALOG) cuando tienes la patada asignada.")
    
    -- Nameplate Scale Boost
    local npScaleSetting = Settings.RegisterProxySetting(
        category, "Interruptio_NPScale", Settings.VarType.Number, "Tamaño de la Barra del Objetivo",
        (InterruptioDB and InterruptioDB.nameplateScaleBoost) or 1.15,
        function() return (InterruptioDB and InterruptioDB.nameplateScaleBoost) or 1.15 end,
        function(val)
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.nameplateScaleBoost = val
            Interruptio.UI:UpdateAllNameplates()
        end
    )
    local npScaleOpts = Settings.CreateSliderOptions(0.8, 2.0, 0.05)
    npScaleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format("%.2fx", v) end)
    Settings.CreateSlider(category, npScaleSetting, npScaleOpts, "Escala de la barra de vida del mob asignado.")
    
    -- ============================================================
    -- Icon Position (LEFT / RIGHT of nameplate)
    local iconSideSetting = Settings.RegisterProxySetting(
        category, "Interruptio_IconSide", Settings.VarType.Number, "Lado de los iconos de corte",
        (InterruptioDB and InterruptioDB.iconSide) or 1,
        function() return (InterruptioDB and InterruptioDB.iconSide) or 1 end,
        function(val)
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.iconSide = val
            Interruptio.UI:UpdateAllNameplates()
        end
    )
    local sideOptions = Settings.CreateSliderOptions(1, 4, 1)
    sideOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
        if v == 1 then return "Izquierda"
        elseif v == 2 then return "Derecha"
        elseif v == 3 then return "Arriba"
        elseif v == 4 then return "Abajo"
        end
    end)
    Settings.CreateSlider(category, iconSideSetting, sideOptions, "Punto de anclaje de los iconos respecto a la barra de vida.")
    
    -- Icon Offset (horizontal distance from health bar edge)
    local iconOffsetSetting = Settings.RegisterProxySetting(
        category, "Interruptio_IconOffset", Settings.VarType.Number, "Separación horizontal de iconos",
        (not InterruptioDB or InterruptioDB.iconOffset == nil) and 30 or InterruptioDB.iconOffset,
        function() return (not InterruptioDB or InterruptioDB.iconOffset == nil) and 30 or InterruptioDB.iconOffset end,
        function(val)
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.iconOffset = val
            Interruptio.UI:UpdateAllNameplates()
        end
    )
    local offsetOpts = Settings.CreateSliderOptions(-50, 50, 1)
    offsetOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return v .. "px" end)
    Settings.CreateSlider(category, iconOffsetSetting, offsetOpts, "Ajusta la distancia horizontal de los iconos respecto al borde de la barra de vida.")

    -- Icon Y Offset (vertical distance)
    local iconOffsetYSetting = Settings.RegisterProxySetting(
        category, "Interruptio_IconOffsetY", Settings.VarType.Number, "Alineación vertical de iconos",
        (InterruptioDB and InterruptioDB.iconOffsetY) or 0,
        function() return (InterruptioDB and InterruptioDB.iconOffsetY) or 0 end,
        function(val)
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.iconOffsetY = val
            Interruptio.UI:UpdateAllNameplates()
        end
    )
    local offsetOptsY = Settings.CreateSliderOptions(-50, 50, 1)
    offsetOptsY:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return v .. "px" end)
    Settings.CreateSlider(category, iconOffsetYSetting, offsetOptsY, "Ajusta la distancia vertical de los iconos respecto a la barra de vida.")
    
    -- Debug Logs
    local debugSetting = Settings.RegisterProxySetting(
        category, "Interruptio_DebugLogs", Settings.VarType.Boolean, "Logs de Debug",
        (InterruptioDB and InterruptioDB.debugLogs) or false,
        function() return (InterruptioDB and InterruptioDB.debugLogs) or false end,
        function(val)
            if not InterruptioDB then InterruptioDB = {} end
            InterruptioDB.debugLogs = val
        end
    )
    Settings.CreateCheckbox(category, debugSetting, "Muestra mensajes de debug en el chat (correlación de señales, red, etc).")
    
    Settings.RegisterAddOnCategory(category)
end

-- ============================================================
-- Slash Commands (unchanged)
-- ============================================================
SLASH_INTERRUPTIO1 = "/interruptio"
SLASH_INTERRUPTIO2 = "/it"
SlashCmdList["INTERRUPTIO"] = function(msg)
    local cmd = strsplit(" ", msg, 2)
    cmd = (cmd or ""):lower()
    
    if cmd == "mark" or cmd == "m" then
        print("|cFF00FFFF[Interruptio]|r |cFFFF0000ERROR CRITICO:|r Usa un Atajo de Teclado nativo (ESC > Opciones > Atajos > AddOns > Interruptio).")
    elseif cmd:match("^slot") then
        local n = tonumber(cmd:match("%d+"))
        if not InterruptioDB then InterruptioDB = {} end
        if n and n >= 1 and n <= 8 then
            InterruptioDB.markerSlot = n
            print(string.format("|cFF00FFFF[Interruptio]|r Slot asignado: %s %s",
                Interruptio.Data:GetRaidIconString(n, 14), Interruptio.Data.RAID_ICON_NAMES[n] or tostring(n)))
            Interruptio.Marks:UpdateSecureBtnMacro()
        elseif n == 0 then
            InterruptioDB.markerSlot = 0
            print("|cFF00FFFF[Interruptio]|r Slot en modo automatico.")
            Interruptio.Marks:UpdateSecureBtnMacro()
        else
            local curr = (InterruptioDB and InterruptioDB.markerSlot or 0)
            local currStr = curr > 0 and (Interruptio.Data:GetRaidIconString(curr, 14) .. " slot " .. curr) or "automatico"
            print("|cFF00FFFF[Interruptio]|r Uso: /it slot [1-8] | /it slot 0 (auto) | actual: " .. currStr)
            print("|cFF00FFFF[Interruptio]|r Slots: 1=Estrella 2=Circulo 3=Diamante 4=Triangulo 5=Luna 6=Cuadrado 7=Cruz 8=Calavera")
        end
    elseif cmd == "show" then
        Interruptio.UI.Panel:SetAlpha(1)
        Interruptio.UI.Panel:Show()
    elseif cmd == "hide" then
        Interruptio.UI.Panel:Hide()
    elseif cmd == "reset" then
        if not InterruptioDB then InterruptioDB = {} end
        InterruptioDB.scale = 1.0
        InterruptioDB.framePoint = nil
        Interruptio.UI.Panel:SetScale(1.0)
        Interruptio.UI.Panel:ClearAllPoints()
        Interruptio.UI.Panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
        Interruptio.UI.Panel:SetAlpha(1)
        Interruptio.UI.Panel:Show()
        print("|cFF00FFFF[Interruptio]|r Panel reiniciado y forzado en pantalla.")
    elseif cmd == "errors" then
        if InterruptioDB and InterruptioDB.errors and #InterruptioDB.errors > 0 then
            print("|cFF00FFFF[Interruptio]|r Errores (" .. #InterruptioDB.errors .. "):")
            for _, e in ipairs(InterruptioDB.errors) do
                print("|cFFFF6666  " .. e .. "|r")
            end
        else
            print("|cFF00FFFF[Interruptio]|r Sin errores.")
        end
    elseif cmd == "clearerrors" or cmd == "clear" then
        if InterruptioDB then InterruptioDB.errors = {} end
        print("|cFF00FFFF[Interruptio]|r Errores borrados.")
    elseif cmd == "test" then
        if not InterruptioDB then InterruptioDB = {} end
        InterruptioDB.testMode = not InterruptioDB.testMode
        Interruptio.Roster:Rebuild()
        if InterruptioDB.testMode then 
            Interruptio.UI.Panel:Show()
            print("|cFF00FFFF[Interruptio]|r Modo Prueba ACTIVADO.")
        else 
            Interruptio.UI.Panel:Hide()
            print("|cFF00FFFF[Interruptio]|r Modo Prueba DESACTIVADO.")
        end
    elseif cmd == "debug" then
        print("|cFF00FFFF[Interruptio]|r === DEBUG ===")
        print("  playerName = " .. tostring(Interruptio.PlayerName))
        
        -- Prefix status
        local prefixOk = C_ChatInfo.IsAddonMessagePrefixRegistered and
            C_ChatInfo.IsAddonMessagePrefixRegistered(Interruptio.Data.COMM_PREFIX)
        print("  prefix '" .. Interruptio.Data.COMM_PREFIX .. "' registered = " .. tostring(prefixOk))
        
        -- Network stats
        local stats = Interruptio.Net.Stats
        print(string.format("  net: sent=%d recv=%d | this min: sent=%d recv=%d",
            stats.sent, stats.received, stats.sentThisMinute, stats.receivedThisMinute))
        print("  lastSendResult = " .. tostring(stats.lastResult)
            .. " (" .. string.format("%.1fs ago", GetTime() - (stats.lastResultTime or 0)) .. ")")
        print("  queue length = " .. #Interruptio.Net.Queue)
        
        -- Panel ticker status
        print("  panelTicker active = " .. tostring(Interruptio.PanelTicker ~= nil))
        
        -- Active marks
        print("  activeMarks (" .. #Interruptio.Marks.Active .. "):")
        for i, m in ipairs(Interruptio.Marks.Active) do
            print(string.format("    [%d] player=%s slot=%s class=%s",
                i, tostring(m.playerName), tostring(m.markerSlot), tostring(m.playerClass)))
        end
        
        -- Roster
        print("  InterruptioRoster:")
        for k, v in pairs(Interruptio.RosterList) do
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
        
        print("|cFF00FFFF[Interruptio]|r === FIN ===")
    elseif cmd == "debugcl" then
        if not InterruptioDB then InterruptioDB = {} end
        InterruptioDB.debugCombatLog = not InterruptioDB.debugCombatLog
        if InterruptioDB.debugCombatLog then
            print("|cFF00FFFF[Interruptio]|r Combat Log debug: |cFF44FF88ON|r (interrupt events will be printed)")
        else
            print("|cFF00FFFF[Interruptio]|r Combat Log debug: |cFFFF4444OFF|r")
        end
    elseif cmd == "logs" then
        if not InterruptioDB then InterruptioDB = {} end
        InterruptioDB.debugLogs = not InterruptioDB.debugLogs
        if InterruptioDB.debugLogs then
            print("|cFF00FFFF[Interruptio]|r Developer logs: |cFF44FF88ON|r")
        else
            print("|cFF00FFFF[Interruptio]|r Developer logs: |cFFFF4444OFF|r")
        end
    else
        print("|cFF00FFFF[Interruptio]|r Opciones: /it test | /it show|hide | /it debug | /it debugcl | /it logs | /it errors | /it clear")
        print("|cFF00FFFF[Interruptio]|r Atajos: ESC -> Opciones -> Atajos (Keybindings).")
    end
end
