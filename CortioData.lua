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

Cortio.Data.CLASS_INTERRUPT_CD = {
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

Cortio.Data.INTERRUPT_SPELLID_SET = {}
for _, sid in pairs(Cortio.Data.CLASS_INTERRUPT_SPELLID) do
    Cortio.Data.INTERRUPT_SPELLID_SET[sid] = true
end

Cortio.Data.INTERRUPT_NAME_TO_CD = {}
Cortio.Data.INTERRUPT_NAME_TO_CLASS = {}
for cls, sid in pairs(Cortio.Data.CLASS_INTERRUPT_SPELLID) do
    local ok, sName = pcall(C_Spell.GetSpellName, sid)
    if ok and sName and sName ~= "" then
        Cortio.Data.INTERRUPT_NAME_TO_CD[sName]    = Cortio.Data.CLASS_INTERRUPT_CD[cls] or 15
        Cortio.Data.INTERRUPT_NAME_TO_CLASS[sName] = cls
    end
end

function Cortio.Data:GetRaidIconString(slot, size)
    size = size or 14
    local c = Cortio.Data.RAID_ICON_COORDS[slot]
    if not c then return "" end
    return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t",
        Cortio.Data.RAID_ICON_TEX, size, size, c[1], c[2], c[3], c[4])
end

function Cortio.Data:ShortName(fullName)
    if not fullName then return "?" end
    local name = strsplit("-", fullName)
    return name or fullName
end
