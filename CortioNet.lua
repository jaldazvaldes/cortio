--------------------------------------------------------------
-- CORTIO - Network Queue
-- Rate-limited addon message system with backoff/retry
--------------------------------------------------------------
Cortio = Cortio or {}
Cortio.Net = {}

Cortio.Net.Queue = {}
Cortio.Net.Stats = {
    sent = 0,
    received = 0,
    lastResult = nil,
    lastResultTime = 0,
    recentMessages = {},
    sentThisMinute = 0,
    receivedThisMinute = 0,
}

local MAX_RECENT_MSGS = 10
local SEND_INTERVAL = 0.1   -- max 10 msgs/sec
local MAX_RETRIES = 3
local netTicker = nil

function Cortio.Net:LogReceived(prefix, msg, sender)
    local entry = {
        time = date("%H:%M:%S"),
        msg = msg,
        sender = sender,
    }
    table.insert(Cortio.Net.Stats.recentMessages, entry)
    while #Cortio.Net.Stats.recentMessages > MAX_RECENT_MSGS do
        table.remove(Cortio.Net.Stats.recentMessages, 1)
    end
    Cortio.Net.Stats.received = Cortio.Net.Stats.received + 1
    Cortio.Net.Stats.receivedThisMinute = Cortio.Net.Stats.receivedThisMinute + 1
end

local function ProcessQueue()
    if #Cortio.Net.Queue == 0 then
        if netTicker then
            netTicker:Cancel()
            netTicker = nil
        end
        return
    end

    local job = table.remove(Cortio.Net.Queue, 1)

    local ok, result
    if job.target then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, job.prefix, job.msg, job.channel, job.target)
    else
        ok, result = pcall(C_ChatInfo.SendAddonMessage, job.prefix, job.msg, job.channel)
    end

    Cortio.Net.Stats.lastResult = ok and result or ("ERROR: " .. tostring(result))
    Cortio.Net.Stats.lastResultTime = GetTime()

    if ok and (result == nil or result == 0) then
        -- Success
        Cortio.Net.Stats.sent = Cortio.Net.Stats.sent + 1
        Cortio.Net.Stats.sentThisMinute = Cortio.Net.Stats.sentThisMinute + 1
    elseif ok and result then
        local retries = job.retries or 0

        if (result == 5 or result == 11) and retries < MAX_RETRIES then
            -- Throttle (5) or Lockdown (11): retry with exponential backoff
            local delay = 0.5 * (2 ^ retries)
            job.retries = retries + 1
            if result == 11 and job.channel == "INSTANCE_CHAT" then
                job.channel = "PARTY"
            end
            C_Timer.After(delay, function()
                table.insert(Cortio.Net.Queue, job)
                Cortio.Net:EnsureTicker()
            end)
        elseif result == 11 and job.channel == "PARTY" and not job.fallbackP2P then
            -- Last resort: whisper each party member directly
            for i = 1, 4 do
                local targetUnit = "party"..i
                if UnitExists(targetUnit) and UnitIsPlayer(targetUnit) then
                    local cleanTarget = Cortio.Taint:SafeUnitFullName(targetUnit)
                    if cleanTarget then
                        table.insert(Cortio.Net.Queue, {
                            prefix = job.prefix,
                            msg = job.msg,
                            channel = "WHISPER",
                            target = cleanTarget,
                            fallbackP2P = true,
                            tag = "P2P",
                            retries = 0,
                        })
                    end
                end
            end
            Cortio.Net:EnsureTicker()
        else
            Cortio.Data:LogError(job.tag or "Send",
                "AddonMsg fail (" .. tostring(job.channel) .. "): code=" .. tostring(result))
        end
    elseif not ok then
        Cortio.Data:LogError(job.tag or "Send",
            "AddonMsg error: " .. tostring(result))
    end
end

function Cortio.Net:EnsureTicker()
    if not netTicker and #Cortio.Net.Queue > 0 then
        netTicker = C_Timer.NewTicker(SEND_INTERVAL, ProcessQueue)
    end
end

function Cortio.Net:SendGroupMessage(msg, tag)
    local ch
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
    elseif IsInRaid() then ch = "RAID"
    elseif IsInGroup() then ch = "PARTY"
    end
    if ch then
        table.insert(Cortio.Net.Queue, {
            prefix = Cortio.Data.COMM_PREFIX,
            msg = msg,
            channel = ch,
            tag = tag or "Send",
            retries = 0,
        })
        Cortio.Net:EnsureTicker()
    end
end

-- Reset per-minute counters every 60s
C_Timer.NewTicker(60, function()
    Cortio.Net.Stats.sentThisMinute = 0
    Cortio.Net.Stats.receivedThisMinute = 0
end)
