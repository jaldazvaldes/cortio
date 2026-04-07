--------------------------------------------------------------
-- CORTIO - Taint Buster
-- Utilidades para resolver valores "secret" tainted en WoW 12.0
--------------------------------------------------------------
Cortio = Cortio or {}
Cortio.Taint = {}

local _taintSlider = CreateFrame("Slider", nil, UIParent)
_taintSlider:SetMinMaxValues(0, 9999999)
_taintSlider:SetSize(1, 1)
_taintSlider:Hide()
local _taintResult = nil
_taintSlider:SetScript("OnValueChanged", function(_, v) _taintResult = v end)

local _dummyTable = {}
function Cortio.Taint:ResolveNumber(rawID)
    local ok = pcall(function() return _dummyTable[rawID] end)
    if ok then
        local directOk, directHit = pcall(tonumber, rawID)
        if directOk and directHit then return directHit end
    end
    
    pcall(_taintSlider.SetValue, _taintSlider, 0)
    _taintResult = nil
    local sliderOk = pcall(_taintSlider.SetValue, _taintSlider, rawID)
    if sliderOk and _taintResult and _taintResult ~= 0 then
        local strOk, str = pcall(tostring, _taintResult)
        if strOk and str then
            local numOk, num = pcall(tonumber, str)
            if numOk and num then return num end
        end
        return _taintResult
    end
    return nil
end

function Cortio.Taint:SafeUnitName(unit)
    if not unit then return nil end
    local raw = UnitName(unit)
    if not raw then return nil end
    local ok, clean = pcall(string.format, "%s", raw)
    return ok and clean or nil
end

function Cortio.Taint:SafeUnitFullName(unit)
    if not unit then return nil end
    local ok, name, realm = pcall(UnitFullName, unit)
    if not ok or not name then return nil end
    local okN, cleanName = pcall(string.format, "%s", name)
    if not okN or not cleanName then return nil end
    if realm and realm ~= "" then
        local okR, cleanRealm = pcall(string.format, "%s", realm)
        if okR and cleanRealm then return cleanName .. "-" .. cleanRealm end
    end
    return cleanName
end

function Cortio.Taint:SafeIsMatch(token, npUnit)
    if not token or not npUnit then return false end
    local ok, match = pcall(UnitIsUnit, token, npUnit)
    if not ok then return false end
    local evalOk, evalResult = pcall(function() return match == true end)
    if not evalOk then return false end
    return evalResult
end
