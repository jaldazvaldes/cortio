--------------------------------------------------------------
-- INTERRUPTIO - Taint Buster
-- Utilidades para resolver valores "secret" tainted en WoW 12.0
--
-- Técnicas basadas en BliZzi_Interrupts v3.3.4:
--   1. issecretvalue() — detecta si un valor es "secret/tainted"
--   2. rawset({}, key, true) — verifica que un string NO está tainted
--   3. pcall wrappers — catch-all para operaciones con tainted data
--------------------------------------------------------------
Interruptio = Interruptio or {}
Interruptio.Taint = {}

-- ============================================================
-- issecretvalue helper
-- WoW 12.0 provides issecretvalue() to detect tainted values.
-- We wrap it so older clients don't error.
-- ============================================================
function Interruptio.Taint:IsSecret(value)
    if issecretvalue then
        local ok, result = pcall(issecretvalue, value)
        return ok and result
    end
    return false
end

-- ============================================================
-- ResolveNumber: simplified stub WITHOUT Slider (no taint source)
-- Only works for clean values; returns nil for tainted/secret values
-- ============================================================
function Interruptio.Taint:ResolveNumber(rawID)
    if Interruptio.Taint:IsSecret(rawID) then return nil end
    local ok, result = pcall(tonumber, rawID)
    if ok and result then return result end
    return nil
end

-- ============================================================
-- SafeUnitName: BliZzi-style double verification
-- 1. pcall(string.format, "%s", raw) — attempt to detaint
-- 2. pcall(rawset, {}, clean, true) — verify the string is usable
-- ============================================================
function Interruptio.Taint:SafeUnitName(unit)
    if not unit then return nil end
    local raw = UnitName(unit)
    if not raw then return nil end
    local ok1, clean = pcall(string.format, "%s", raw)
    if not ok1 or not clean then return nil end
    local ok2 = pcall(rawset, {}, clean, true)
    return ok2 and clean or nil
end

-- ============================================================
-- SafeUnitFullName: Safe unit name with realm
-- ============================================================
function Interruptio.Taint:SafeUnitFullName(unit)
    if not unit then return nil end
    local ok, name, realm = pcall(UnitFullName, unit)
    if not ok or not name then return nil end
    local okN, cleanName = pcall(string.format, "%s", name)
    if not okN or not cleanName then return nil end
    local ok2 = pcall(rawset, {}, cleanName, true)
    if not ok2 then return nil end
    if realm and realm ~= "" then
        local okR, cleanRealm = pcall(string.format, "%s", realm)
        if okR and cleanRealm then
            local ok3 = pcall(rawset, {}, cleanRealm, true)
            if ok3 then return cleanName .. "-" .. cleanRealm end
        end
    end
    return cleanName
end

-- ============================================================
-- SafeIsMatch: UnitIsUnit with full taint protection
-- ============================================================
function Interruptio.Taint:SafeIsMatch(token, npUnit)
    if not token or not npUnit then return false end
    local ok, match = pcall(UnitIsUnit, token, npUnit)
    if not ok then return false end
    local evalOk, evalResult = pcall(function() return match == true end)
    if not evalOk then return false end
    return evalResult
end

-- ============================================================
-- SafeResolveSpell: Try to identify a spell safely
-- Returns: spellName (clean string) or nil
-- ============================================================
function Interruptio.Taint:SafeResolveSpell(spellID)
    if not spellID then return nil end
    if Interruptio.Taint:IsSecret(spellID) then return nil end

    local ok, spellName = pcall(C_Spell.GetSpellName, spellID)
    if not ok or not spellName then return nil end
    if Interruptio.Taint:IsSecret(spellName) then return nil end

    -- Verify the name is usable as a table key
    local ok2 = pcall(rawset, {}, spellName, true)
    return ok2 and spellName or nil
end
