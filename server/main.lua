--- Garage Level System
local tempVehicle = {}

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

lib.callback.register('rhd_garage:server:getGarageLevel', function(src)
    return getPlayerGarageLevel(src)
end)

lib.callback.register('rhd_garage:server:getCurrentTime', function(src)
    return os.time()
end)

lib.callback.register('rhd_garage:server:checkRecovery', function(src, plate)
    local vehData = MySQL.single.await('SELECT state, last_out FROM player_vehicles WHERE plate = ? OR fakeplate = ?', {plate, plate})
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
lib.callback.register('rhd_garage:cb_server:removeMoney', function(src, type, amount)
    return fw.rm(src, type, amount)
end)

lib.callback.register('rhd_garage:cb_server:getvehowner', function (src, plate, shared, pleaseUpdate)
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

lib.callback.register('rhd_garage:cb_server:getvehiclePropByPlate', function (_, plate)
    return fw.gpvbp(plate)
end)

lib.callback.register('rhd_garage:cb_server:getVehicleList', function(src, garage, impound, shared)
    print("^3[rhd_garage:DEBUG] Servidor recebeu pedido de lista: Player=" .. src .. " | Garagem=" .. tostring(garage) .. " | Impound=" .. tostring(impound) .. "^7")
    
    local list = fw.gpvbg(src, garage, {
        impound = impound,
        shared = shared
    })
    
    print("^2[rhd_garage:DEBUG] Servidor processou a lista. Veículos encontrados: " .. (list and #list or 0) .. "^7")
    return list
end)

lib.callback.register("rhd_garage:cb_server:swapGarage", function (source, clientData)
    return fw.svg(clientData.newgarage, clientData.plate)
end)

lib.callback.register("rhd_garage:cb_server:transferVehicle", function (src, clientData)
    if src == clientData.targetSrc then
        return false, locale("notify.error.cannot_transfer_to_myself")
    end

    local tid = clientData.targetSrc

    if not fw.rm(src, "cash", clientData.price) then
        return false, locale("notify.error.need_money", lib.math.groupdigits(clientData.price, '.'))
    end

    print("Transfer vehicle from " .. fw.gn(src) .. " to " .. fw.gn(tid))
    print("Plate: " .. clientData.plate)
    local success = fw.uvo(src, tid, clientData.plate)
    if success then utils.notify(tid, locale("notify.success.transferveh.target", fw.gn(src), clientData.garage), "success") end
    return success, locale("notify.success.transferveh.source", fw.gn(tid))
end)

lib.callback.register('rhd_garage:cb_server:getVehicleInfoByPlate', function (_, plate)
    return fw.gpvbp(plate)
end)

--- Event
RegisterNetEvent("rhd_garage:server:removeTemp", function ( data )
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

RegisterNetEvent("rhd_garage:server:updateState", function ( data )
    if GetInvokingResource() then return end
    fw.uvs(data.plate, data.state, data.garage, data.engine, data.body)
end)

RegisterNetEvent("rhd_garage:server:destroyVehicle", function(plate)
    if GetInvokingResource() then return end
    print("^1[rhd_garage] Sincronizando destruição no banco de dados para a placa: " .. plate .. "^7")
    MySQL.update('UPDATE player_vehicles SET engine = 0, body = 0, state = 3 WHERE plate = ? OR fakeplate = ?', {plate, plate})
end)

RegisterNetEvent("rhd_garage:server:saveGarageZone", function(fileData)
    if GetInvokingResource() then return end
    if type(fileData) ~= "table" or type(fileData) == "nil" then return end
    return storage.SaveGarage(fileData)
end)

RegisterNetEvent("rhd_garage:server:saveCustomVehicleName", function (fileData)
    if GetInvokingResource() then return end
    if type(fileData) ~= "table" or type(fileData) == "nil" then return end
    return storage.SaveVehicleName(fileData)
end)

local vehicleSpawnCooldown = {}

lib.callback.register('rhd_garage:server:spawnVehicle', function(source, model, coords, props)
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

    -- Verificação de Cooldown (Anti-Abuso Detran)
    if plate then
        local vehData = MySQL.single.await('SELECT state, last_out FROM player_vehicles WHERE plate = ? OR fakeplate = ?', {plate, plate})
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
        return false, false
    end

    vehicleSpawnCooldown[playerId] = true

    local netid, veh = qbx.spawnVehicle({
        model = model,
        spawnSource = coords,
        warp = false,
        props = props
    })

    SetTimeout(3000, function()
        vehicleSpawnCooldown[playerId] = nil
    end)

    return netid, veh
end)

--- exports
exports("Garage", function ()
    return GarageZone
end)
