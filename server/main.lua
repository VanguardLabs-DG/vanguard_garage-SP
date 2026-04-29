--- Garage Level System
local tempVehicle = {}
local vehicleSpawnCooldown = {} -- Moved to top for better organization

-- Cache de veículos para reduzir queries repetitivas (TTL: 30s)
local vehicleCache = {}
local CACHE_TTL = 30 -- 30 segundos

local function getPlayerGarageLevel(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return 1 end
    return player.PlayerData.metadata['garage_level'] or 1
end

local function setPlayerGarageLevel(src, level)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false end
    level = tonumber(level)
    if not Config.GarageLevels[level] then return false end
    player.Functions.SetMetaData('garage_level', level)
    return true
end

-- Função auxiliar para cache de queries de veículos
local function getVehicleFromDB(plate, useCache, includeOwner)
    -- Cache key deve incluir includeOwner para evitar inconsistências
    local cacheKey = includeOwner and (plate .. "_owner") or plate
    
    if useCache and vehicleCache[cacheKey] then
        local cached = vehicleCache[cacheKey]
        if os.time() - cached.time < CACHE_TTL then
            return cached.data
        end
    end
    
    local query = includeOwner 
        and 'SELECT state, last_out, engine, body, fuel, mods, deformation, vehicle_name, citizenid FROM player_vehicles WHERE plate = ? OR fakeplate = ?'
        or 'SELECT state, last_out, engine, body, fuel, mods, deformation, vehicle_name FROM player_vehicles WHERE plate = ? OR fakeplate = ?'
    
    local vehData = MySQL.single.await(query, {plate, plate})
    
    if useCache and vehData then
        vehicleCache[cacheKey] = {
            data = vehData,
            time = os.time()
        }
    end
    
    return vehData
end

exports('GetGarageLevel', getPlayerGarageLevel)
exports('SetGarageLevel', setPlayerGarageLevel)

lib.addCommand('setgaragelevel', {
    help = 'Definir nível de garagem do player',
    restricted = 'group.admin',
    params = {
        { name = 'id', help = 'ID do player', type = 'number' },
        { name = 'level', help = 'Nível (1-3)', type = 'number' }
    }
}, function(source, args)
    if setPlayerGarageLevel(args.id, args.level) then
        utils.notify(source, ("Nível de garagem do ID %s definido para %s"):format(args.id, args.level), "success")
        utils.notify(args.id, ("Seu nível de garagem foi alterado para %s"):format(args.level), "info")
    else
        utils.notify(source, "ID ou Nível inválido", "error")
    end
end)

lib.callback.register('vanguard_garage:server:getGarageLevel', function(src)
    return getPlayerGarageLevel(src)
end)

lib.callback.register('vanguard_garage:server:getCurrentTime', function(src)
    return os.time()
end)

lib.callback.register('vanguard_garage:server:checkRecovery', function(src, plate)
    local vehData = getVehicleFromDB(plate, true)
    if not vehData then return { allowed = true } end

    if vehData.state == 0 or vehData.state == 3 then
        local currentTime = os.time()
        local lastOut = vehData.last_out or 0
        local waitTime = (vehData.state == 0) and Config.RecoveryCooldown or Config.DestroyedCooldown
        
        if (currentTime - lastOut) < waitTime then
            return { 
                allowed = false, 
                reason = "cooldown", 
                remaining = waitTime - (currentTime - lastOut) 
            }
        end
    end

    return { allowed = true }
end)

--- callback
lib.callback.register('vanguard_garage:cb_server:removeMoney', function(src, type, amount)
    return fw.rm(src, type, amount)
end)

lib.callback.register('vanguard_garage:cb_server:getvehowner', function (src, plate, shared, pleaseUpdate)
    -- Check Garage Capacity
    local level = getPlayerGarageLevel(src)
    local maxSlots = Config.GarageLevels[level].slots
    
    local vehicles = fw.gpvbg(src, nil, { shared = false, impound = false }) -- Use Config.VehiclesInAllGarages logic
    if #vehicles >= maxSlots then
        return { error = "Sua garagem está cheia! (Nível " .. level .. ": " .. maxSlots .. " slots)" }
    end

    return fw.gvobp(src, plate, {
        owner = shared
    }, pleaseUpdate)
end)

lib.callback.register('vanguard_garage:cb_server:getvehiclePropByPlate', function (_, plate)
    return fw.gpvbp(plate)
end)

lib.callback.register('vanguard_garage:cb_server:getVehicleList', function(src, garage, impound, shared)
    local list = fw.gpvbg(src, garage, {
        impound = impound,
        shared = shared
    })
    
    return list
end)

lib.callback.register("vanguard_garage:cb_server:swapGarage", function (source, clientData)
    return fw.svg(clientData.newgarage, clientData.plate)
end)

lib.callback.register("vanguard_garage:cb_server:transferVehicle", function (src, clientData)
    -- Validação server-side rigorosa
    if src == clientData.targetSrc then
        return false, locale("notify.error.cannot_transfer_to_myself")
    end

    local targetPlayer = exports.qbx_core:GetPlayer(clientData.targetSrc)
    if not targetPlayer then
        return false, locale("notify.error.player_offline", clientData.targetSrc)
    end

    local sourcePlayer = exports.qbx_core:GetPlayer(src)
    if not sourcePlayer then
        return false, "Erro: jogador não encontrado"
    end

    -- Verifica se o veículo realmente pertence ao jogador
    local vehData = getVehicleFromDB(clientData.plate, false, true) -- includeOwner = true
    if not vehData or vehData.citizenid ~= sourcePlayer.PlayerData.citizenid then
        return false, "Você não é proprietário deste veículo"
    end

    -- Executa a transferência PRIMEIRO (antes de remover dinheiro)
    local success = fw.uvo(src, clientData.targetSrc, clientData.plate)
    if not success then
        return false, "Erro ao transferir veículo. Tente novamente."
    end

    -- Só remove o dinheiro após sucesso na transferência
    if not fw.rm(src, "cash", clientData.price) then
        -- Reverte a transferência se falhar ao remover dinheiro (edge case)
        fw.uvo(clientData.targetSrc, src, clientData.plate)
        return false, locale("notify.error.need_money", lib.math.groupdigits(clientData.price, '.'))
    end

    -- Notifica ambos os jogadores
    utils.notify(clientData.targetSrc, locale("notify.success.transferveh.target", fw.gn(src), clientData.garage), "success")
    
    return success, locale("notify.success.transferveh.source", fw.gn(clientData.targetSrc))
end)

lib.callback.register('vanguard_garage:cb_server:getVehicleInfoByPlate', function (_, plate)
    return fw.gpvbp(plate)
end)

--- Event
RegisterNetEvent("vanguard_garage:server:removeTemp", function ( data )
    if GetInvokingResource() then return end
    local player = exports.qbx_core:GetPlayer(source)
    local citizenid = player.PlayerData.citizenid
    if tempVehicle[citizenid] == data.model then
        tempVehicle[citizenid] = nil
    end
end)

lib.addCommand('removeTemp', {
    help = 'Recuperar garagem de player',
    restricted = 'group.admin',
    params = {
        { name = 'id', help = 'ID do player', type = 'number' }
    }
}, function(source, args)
    if args.id then
        local player = exports.qbx_core:GetPlayer(tonumber(args.id))
        local citizenid = player.PlayerData.citizenid
        tempVehicle[citizenid] = nil
        lib.notify(tonumber(args.id), {description = "Seus veículos de aluguel foram recuperados.", type = "success", duration = 10000})
        lib.notify(source, {description = "Garagem recuperada do id: " .. args.id .. " cidadão: " .. citizenid .. " de nome " .. player.PlayerData.name .. ".", type = "success", duration = 10000})
    else
        lib.notify(source, {description = "ID inválido.", type = "error", duration = 10000})
    end
end)

RegisterNetEvent("vanguard_garage:server:updateState", function ( data )
    if GetInvokingResource() then return end
    fw.uvs(data.plate, data.state, data.garage, data.engine, data.body)
end)

RegisterNetEvent("vanguard_garage:server:destroyVehicle", function(plate)
    if GetInvokingResource() then return end
    
    -- Validação server-side: só marca como destruído se não estiver já com state 3
    local currentData = MySQL.single.await('SELECT state FROM player_vehicles WHERE plate = ? OR fakeplate = ?', {plate, plate})
    
    if currentData and currentData.state ~= 3 then
        MySQL.update('UPDATE player_vehicles SET engine = 0, body = 0, state = 3 WHERE plate = ? OR fakeplate = ?', {plate, plate})
        
        -- Limpa AMBOS os caches (com e sem owner) para forçar refresh
        vehicleCache[plate] = nil
        vehicleCache[plate .. "_owner"] = nil
    end
end)

RegisterNetEvent("vanguard_garage:server:saveGarageZone", function(fileData)
    if GetInvokingResource() then return end
    if type(fileData) ~= "table" or type(fileData) == "nil" then return end
    return storage.SaveGarage(fileData)
end)

RegisterNetEvent("vanguard_garage:server:saveCustomVehicleName", function (fileData)
    if GetInvokingResource() then return end
    if type(fileData) ~= "table" or type(fileData) == "nil" then return end
    return storage.SaveVehicleName(fileData)
end)

local function cleanupCooldowns(playerId)
    SetTimeout(3000, function()
        vehicleSpawnCooldown[playerId] = nil
    end)
end

lib.callback.register('vanguard_garage:server:spawnVehicle', function(source, model, coords, props)
    local playerId = source
    local plate = props and props.plate

    -- Prevenção de Duplicação: Deleta veículo antigo se existir no mapa
    if Config.DeleteOldVehicleOnSpawn and plate then
        local allVehicles = GetAllVehicles()
        for _, veh in ipairs(allVehicles) do
            if DoesEntityExist(veh) then
                local vehPlate = GetVehicleNumberPlateText(veh)
                if vehPlate and vehPlate:gsub("%s+", "") == plate:gsub("%s+", "") then
                    DeleteEntity(veh)
                end
            end
        end
    end

    -- Verificação de Cooldown (Anti-Abuso Detran) com cache
    if plate then
        local vehData = getVehicleFromDB(plate, true)
        if vehData and (vehData.state == 0 or vehData.state == 3) then
            local currentTime = os.time()
            local lastOut = vehData.last_out or 0
            local waitTime = (vehData.state == 0) and Config.RecoveryCooldown or Config.DestroyedCooldown
            
            if (currentTime - lastOut) < waitTime then
                local remaining = waitTime - (currentTime - lastOut)
                local minutes = math.ceil(remaining / 60)
                utils.notify(playerId, "O seguro está investigando o desaparecimento. Volte em " .. minutes .. " minutos.", "error")
                return false, false
            end
        end
    end

    if vehicleSpawnCooldown[playerId] then
        utils.notify(playerId, "Aguarde antes de retirar outro veículo.", "error")
        return false, false
    end

    vehicleSpawnCooldown[playerId] = true
    cleanupCooldowns(playerId)

    local netid, veh = qbx.spawnVehicle({
        model = model,
        spawnSource = coords,
        warp = false,
        props = props
    })

    return netid, veh
end)

--- exports
exports("Garage", function ()
    return GarageZone
end)
