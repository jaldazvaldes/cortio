--------------------------------------------------------------
-- CORTIO - Network Queue
-- Sistema para evitar taint de hardware events (Bug 11)
--------------------------------------------------------------
Cortio = Cortio or {}
Cortio.Net = {}

Cortio.Net.Queue = {}
local netFrame = CreateFrame("Frame")
netFrame:SetScript("OnUpdate", function(self, elapsed)
    if #Cortio.Net.Queue > 0 then
        local job = table.remove(Cortio.Net.Queue, 1)
        local ok, result
        if job.target then
            ok, result = pcall(C_ChatInfo.SendAddonMessage, job.prefix, job.msg, job.channel, job.target)
        else
            ok, result = pcall(C_ChatInfo.SendAddonMessage, job.prefix, job.msg, job.channel)
        end
        if ok and result and result ~= 0 then
            if result == 11 and job.channel == "INSTANCE_CHAT" then
                table.insert(Cortio.Net.Queue, {prefix=job.prefix, msg=job.msg, channel="PARTY", tag=job.tag})
            elseif result == 11 and job.channel == "PARTY" and not job.fallbackP2P then
                for i = 1, 4 do
                    local targetUnit = "party"..i
                    if UnitExists(targetUnit) and UnitIsPlayer(targetUnit) then
                        local cleanTarget = Cortio.Taint:SafeUnitFullName(targetUnit)
                        if cleanTarget then
                            table.insert(Cortio.Net.Queue, {prefix=job.prefix, msg=job.msg, channel="WHISPER", target=cleanTarget, fallbackP2P=true, tag="P2P_WHISPER"})
                        end
                    end
                end
            else
                Cortio.Data:LogError(job.tag, "AddonMsg fallo ("..tostring(job.channel).."): " .. tostring(result)) 
            end
        elseif not ok then
            Cortio.Data:LogError(job.tag, "AddonMsg error interno: " .. tostring(result))
        end
    end
end)

function Cortio.Net:SendGroupMessage(msg, tag)
    local ch
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then ch = "INSTANCE_CHAT"
    elseif IsInRaid() then ch = "RAID"
    elseif IsInGroup() then ch = "PARTY"
    end
    if ch then
        table.insert(Cortio.Net.Queue, {prefix=Cortio.Data.COMM_PREFIX, msg=msg, channel=ch, tag=tag or "Send"})
    end
end
