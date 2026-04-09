--------------------------------------------------------------
-- CORTIO - Data
-- Constantes y bases de datos estáticas
--------------------------------------------------------------
Cortio = Cortio or {}
Cortio.Data = {}

Cortio.Data.COMM_PREFIX = "CORTIO"
Cortio.Data.MAX_ERRORS = 50

function Cortio.Data:LogError(ctx, err)
    if not CortioDB then CortioDB = {} end
    if not CortioDB.errors then CortioDB.errors = {} end
    table.insert(CortioDB.errors, date("%H:%M:%S") .. " [" .. tostring(ctx) .. "] " .. tostring(err))
    while #CortioDB.errors > Cortio.Data.MAX_ERRORS do table.remove(CortioDB.errors, 1) end
end

function Cortio.Data:SafeCall(ctx, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Cortio.Data:LogError(ctx, err) end
    return ok
end

Cortio.Data.RAID_ICON_COORDS = {
    [1]={0,16,0,16},  -- Estrella
    [2]={16,32,0,16}, -- Circulo
    [3]={32,48,0,16}, -- Diamante
    [4]={48,64,0,16}, -- Triangulo
    [5]={0,16,16,32}, -- Luna
    [6]={16,32,16,32},-- Cuadrado
    [7]={32,48,16,32},-- Cruz/X
    [8]={48,64,16,32},-- Calavera
}
Cortio.Data.RAID_ICON_NAMES = {"Estrella","Circulo","Diamante","Triangulo","Luna","Cuadrado","Cruz","Calavera"}
Cortio.Data.RAID_ICON_TEX  = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

Cortio.Data.CLASS_COLORS = {
    WARRIOR="FFC79C6E", PALADIN="FFF58CBA", HUNTER="FFABD473",
    ROGUE="FFFFF569", PRIEST="FFFFFFFF", DEATHKNIGHT="FFC41F3B",
    SHAMAN="FF0070DE", MAGE="FF40C7EB", WARLOCK="FF8787ED",
    MONK="FF00FF96", DRUID="FFFF7D0A", DEMONHUNTER="FFA330C9",
    EVOKER="FF33937F",
}

Cortio.Data.CLASS_INTERRUPT_ICONS = {
    WARRIOR     = "132938",
    PALADIN     = "523893",
    HUNTER      = "249170",
    ROGUE       = "132219",
    PRIEST      = "458230",
    DEATHKNIGHT = "237527",
    SHAMAN      = "136018",
    MAGE        = "135856",
    WARLOCK     = "136174",
    MONK        = "608940",
    DRUID       = "133732",
    DEMONHUNTER = "1305153",
    EVOKER      = "4622469",
}

Cortio.Data.ALL_INTERRUPTS = {
    [6552] = { cd = 15, class = "WARRIOR" },        -- Pummel
    [96231] = { cd = 15, class = "PALADIN" },       -- Rebuke
    [147362] = { cd = 24, class = "HUNTER" },       -- Counter Shot
    [187707] = { cd = 15, class = "HUNTER" },       -- Muzzle
    [1766] = { cd = 15, class = "ROGUE" },          -- Kick
    [15487] = { cd = 30, class = "PRIEST" },        -- Silence
    [47528] = { cd = 15, class = "DEATHKNIGHT" },   -- Mind Freeze
    [57994] = { cd = 12, class = "SHAMAN" },        -- Wind Shear
    [2139] = { cd = 20, class = "MAGE" },           -- Counterspell
    [19647] = { cd = 24, class = "WARLOCK" },       -- Spell Lock
    [119914]= { cd = 30, class = "WARLOCK" },       -- Axe Toss
    [116705]= { cd = 15, class = "MONK" },          -- Spear Hand Strike
    [106839]= { cd = 15, class = "DRUID" },         -- Skull Bash
    [78675] = { cd = 60, class = "DRUID" },         -- Solar Beam
    [183752]= { cd = 15, class = "DEMONHUNTER" },   -- Disrupt
    [351338]= { cd = 20, class = "EVOKER" },        -- Quell
}

Cortio.Data.CLASS_INTERRUPT_SPELLID = {
    WARRIOR     = 6552,
    PALADIN     = 96231,
    HUNTER      = 147362,
    ROGUE       = 1766,
    PRIEST      = 15487,
    DEATHKNIGHT = 47528,
    SHAMAN      = 57994,
    MAGE        = 2139,
    WARLOCK     = 19647,
    MONK        = 116705,
    DRUID       = 106839,
    DEMONHUNTER = 183752,
    EVOKER      = 351338,
}

Cortio.Data.INTERRUPT_NAME_TO_CD = {}
Cortio.Data.INTERRUPT_NAME_TO_CLASS = {}

for sid, data in pairs(Cortio.Data.ALL_INTERRUPTS) do
    local ok, sName = pcall(C_Spell.GetSpellName, sid)
    if ok and sName and sName ~= "" then
        Cortio.Data.INTERRUPT_NAME_TO_CD[sName]    = data.cd
        Cortio.Data.INTERRUPT_NAME_TO_CLASS[sName] = data.class
    end
end


-- Spec-specific interrupt overrides (specId -> interrupt data)
-- Only specs where the interrupt differs from the class default
Cortio.Data.SPEC_INTERRUPTS = {
    -- Hunter: BM & MM use Counter Shot (24s), Survival uses Muzzle (15s)
    [253] = { spellId = 147362, baseCD = 24 },  -- Beast Mastery
    [254] = { spellId = 147362, baseCD = 24 },  -- Marksmanship
    [255] = { spellId = 187707, baseCD = 15 },  -- Survival
    -- Druid: Balance uses Solar Beam (60s), others use Skull Bash (15s)
    [102] = { spellId = 78675,  baseCD = 60 },  -- Balance
    [103] = { spellId = 106839, baseCD = 15 },  -- Feral
    [104] = { spellId = 106839, baseCD = 15 },  -- Guardian
    [105] = { spellId = 106839, baseCD = 15 },  -- Restoration
    -- Warlock: Demonology uses Axe Toss (30s), others use Spell Lock (24s)
    [265] = { spellId = 19647,  baseCD = 24 },  -- Affliction
    [266] = { spellId = 119914, baseCD = 30 },  -- Demonology
    [267] = { spellId = 19647,  baseCD = 24 },  -- Destruction
}

function Cortio.Data:GetRaidIconString(slot, size)
    size = size or 14
    local c = Cortio.Data.RAID_ICON_COORDS[slot]
    if not c then return "" end
    return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t",
        Cortio.Data.RAID_ICON_TEX, size, size, c[1], c[2], c[3], c[4])
end

function Cortio.Data:GetClassInterruptCD(class)
    local sid = Cortio.Data.CLASS_INTERRUPT_SPELLID[class]
    if sid and Cortio.Data.ALL_INTERRUPTS[sid] then
        return Cortio.Data.ALL_INTERRUPTS[sid].cd
    end
    return 15
end

function Cortio.Data:GetInterruptSpellForUnit(playerName)
    local data = Cortio.RosterList and Cortio.RosterList[playerName]
    if not data then return nil, 15 end
    -- Try spec-specific first
    if data.specId and data.specId > 0 then
        local specData = Cortio.Data.SPEC_INTERRUPTS[data.specId]
        if specData then
            return specData.spellId, specData.baseCD
        end
    end
    -- Fall back to class default
    local sid = Cortio.Data.CLASS_INTERRUPT_SPELLID[data.class]
    local cd = Cortio.Data:GetClassInterruptCD(data.class)
    return sid, cd
end

function Cortio.Data:GetExpectedCooldownForUnit(playerName)
    local _, cd = Cortio.Data:GetInterruptSpellForUnit(playerName)
    return cd or 15
end

function Cortio.Data:UpdateCooldownState(playerName, cdEnd, cdTotal)
    if not Cortio.RosterList or not Cortio.RosterList[playerName] then return end
    Cortio.RosterList[playerName].cdEnd = cdEnd
    Cortio.RosterList[playerName].cdTotal = cdTotal
end

function Cortio.Data:ShortName(fullName)
    if not fullName then return "?" end
    local name = strsplit("-", fullName)
    return name or fullName
end
