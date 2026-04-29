local usedBuckets = {}
local playerBuckets = {}

-- Generate a unique routing bucket
local function generateBucket()
    for i = 1, 7000 do
        local bucket = math.random(1, 7000)
        if not usedBuckets[bucket] then
            return bucket
        end
    end
    return nil
end

-- Cleanup function for player bucket
local function cleanupPlayerBucket(src)
    local bucket = playerBuckets[src]
    if bucket then
        usedBuckets[bucket] = nil
        playerBuckets[src] = nil
    end
    SetPlayerRoutingBucket(src, 0)
end

-- Event: Player enters solo session
RegisterNetEvent("vanguard_garage:server:soloSession", function()
    local src = source
    local bucket = generateBucket()
    if bucket then
        usedBuckets[bucket] = true
        playerBuckets[src] = bucket
        SetPlayerRoutingBucket(src, bucket)
    else
        print("^1[vanguard_garage] Erro: Nenhum routing bucket disponível!^7")
    end
end)

-- Event: Player leaves solo session
RegisterNetEvent("vanguard_garage:server:soloSessionLeave", function()
    local src = source
    cleanupPlayerBucket(src)
end)

-- Cleanup on disconnect
AddEventHandler("playerDropped", function()
    local src = source
    cleanupPlayerBucket(src)
end)
