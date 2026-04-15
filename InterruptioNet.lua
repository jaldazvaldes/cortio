--------------------------------------------------------------
-- INTERRUPTIO - Network Queue
-- Rate-limited addon message system with backoff/retry
--------------------------------------------------------------
Interruptio = Interruptio or {}
Interruptio.Net = {}

Interruptio.Net.Queue = {}
Interruptio.Net.Stats = {
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

function Interruptio.Net:LogReceived(prefix, msg, sender)
    local entry = {
        time = date("%H:%M:%S"),
        msg = msg,
        sender = sender,
    }
    table.insert(Interruptio.Net.Stats.recentMessages, entry)
    while #Interruptio.Net.Stats.recentMessages > MAX_RECENT_MSGS do
        table.remove(Interruptio.Net.Stats.recentMessages, 1)
    end
    Interruptio.Net.Stats.received = Interruptio.Net.Stats.received + 1
    Interruptio.Net.Stats.receivedThisMinute = Interruptio.Net.Stats.receivedThisMinute + 1
end

local function ProcessQueue()
    if #Interruptio.Net.Queue == 0 then
        if netTicker then
            netTicker:Cancel()
            netTicker = nil
        end
        return
    end

    local job = table.remove(Interruptio.Net.Queue, 1)

    local ok, result
    if job.target then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, job.prefix, job.msg, job.channel, job.target)
    else
        ok, result = pcall(C_ChatInfo.SendAddonMessage, job.prefix, job.msg, job.channel)
    end

    if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFFAAAAAA[NET]|r SEND ch=" .. tostring(job.channel) .. " msg=" .. tostring(job.msg) .. " ok=" .. tostring(ok) .. " result=" .. tostring(result)) end

    Interruptio.Net.Stats.lastResult = ok and result or ("ERROR: " .. tostring(result))
    Interruptio.Net.Stats.lastResultTime = GetTime()

    if ok and (result == nil or result == 0) then
        -- Success
        Interruptio.Net.addonMsgBlocked = false
        Interruptio.Net.Stats.sent = Interruptio.Net.Stats.sent + 1
        Interruptio.Net.Stats.sentThisMinute = Interruptio.Net.Stats.sentThisMinute + 1
    elseif ok and result then
        local retries = job.retries or 0

        if result == 11 then
            -- Addon Message Lockdown (M+ instances block ALL channels).
            -- This is EXPECTED — do NOT retry, do NOT fallback to WHISPER.
            -- Marker sync works via /p chat macro instead.
            Interruptio.Net.addonMsgBlocked = true
            -- Silent: no error log, no retry
        elseif result == 5 and retries < MAX_RETRIES then
            -- Throttle: retry with exponential backoff
            local delay = 0.5 * (2 ^ retries)
            job.retries = retries + 1
            C_Timer.After(delay, function()
                table.insert(Interruptio.Net.Queue, job)
                Interruptio.Net:EnsureTicker()
            end)
        else
            Interruptio.Data:LogError(job.tag or "Send",
                "AddonMsg fail (" .. tostring(job.channel) .. "): code=" .. tostring(result))
        end
    elseif not ok then
        Interruptio.Data:LogError(job.tag or "Send",
            "AddonMsg error: " .. tostring(result))
    end
end

function Interruptio.Net:EnsureTicker()
    if not netTicker and #Interruptio.Net.Queue > 0 then
        netTicker = C_Timer.NewTicker(SEND_INTERVAL, ProcessQueue)
    end
end

function Interruptio.Net:SendGroupMessage(msg, tag)
    local ch
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
    elseif IsInRaid() then ch = "RAID"
    elseif IsInGroup() then ch = "PARTY"
    end
    if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFFAAAAAA[NET]|r QUEUE msg=" .. tostring(msg) .. " ch=" .. tostring(ch) .. " inGroup=" .. tostring(IsInGroup()) .. " inInst=" .. tostring(IsInGroup(LE_PARTY_CATEGORY_INSTANCE))) end
    if ch then
        table.insert(Interruptio.Net.Queue, {
            prefix = Interruptio.Data.COMM_PREFIX,
            msg = msg,
            channel = ch,
            tag = tag or "Send",
            retries = 0,
        })
        Interruptio.Net:EnsureTicker()
    else
        if InterruptioDB and InterruptioDB.debugLogs then print("|cFF00FFFF[Interruptio]|r |cFFFF0000[NET] NO CHANNEL — not in group!|r") end
    end
end

-- Reset per-minute counters every 60s
C_Timer.NewTicker(60, function()
    Interruptio.Net.Stats.sentThisMinute = 0
    Interruptio.Net.Stats.receivedThisMinute = 0
end)
