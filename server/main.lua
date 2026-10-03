--- Garage Level System
local tempVehicle = {}
local vehicleSpawnCooldown = {} -- Moved to top for better organization

-- Cache de veículos para reduzir queries repetitivas (TTL: 30s)
local vehicleCache = {}
local CACHE_TTL = 30 -- 30 segundos

-- Mutex para controle de spawn concorrente por placa
local plateLocks = {}
local function isPlateLocked(plate)
    if not plate then return false end
    local lock = plateLocks[plate]
    if not lock then return false end
    if os.time() - lock.time > 15 then
        plateLocks[plate] = nil
        return false
    end
    return true
end

local function lockPlate(plate, src)
    if not plate then return end
    plateLocks[plate] = { time = os.time(), src = src }
end

local function unlockPlate(plate)
    if not plate then return end
    plateLocks[plate] = nil
end

-- Registro de veículos ativos por placa (Placa -> Entidade)
SpawnedVehicleEntities = SpawnedVehicleEntities or {}

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
        and 'SELECT state, last_out, engine, body, fuel, mods, deformation, vehicle_name, citizenid FROM player_vehicles WHERE plate = ? OR fakeplate = ? OR TRIM(plate) = ?'
        or 'SELECT state, last_out, engine, body, fuel, mods, deformation, vehicle_name FROM player_vehicles WHERE plate = ? OR fakeplate = ? OR TRIM(plate) = ?'
    
    local vehData = MySQL.single.await(query, {plate, plate, plate})
    
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
    return fw.gvobp(src, plate, {
        onlyOwner = not shared
    }, pleaseUpdate)
end)

lib.callback.register('vanguard_garage:cb_server:getvehiclePropByPlate', function (_, plate)
    return fw.gpvbp(plate)
end)

local function HasGaragePermission(source, player, perm)
    if not perm or perm == "" or perm == "nil" or perm == "false" then return true end
    if exports.qbx_core:HasPermission(source, "admin") or exports.qbx_core:HasPermission(source, "god") then
        return true
    end

    local permLower = string.lower(tostring(perm))
    if exports.qbx_core:HasPermission(source, perm) or exports.qbx_core:HasGroup(source, perm) or exports.qbx_core:HasGroup(source, permLower) then
        return true
    end

    local job = (player.PlayerData and player.PlayerData.job) or player.job
    if job then
        local jName = string.lower(tostring(job.name or ""))
        local jType = string.lower(tostring(job.type or ""))
        if jName == permLower or jType == permLower then
            return true
        end

        -- Mapeamentos de permissão de polícia / hospital
        if permLower == "paramedico" or permLower == "paramedic" or permLower == "hp" or permLower == "hpheli" or permLower == "paramedicoheli" then
            if jName == "paramedic" or jName == "paramedico" or jName == "ambulance" or exports.qbx_core:HasGroup(source, "ambulance") or exports.qbx_core:HasGroup(source, "paramedic") then
                return true
            end
        elseif permLower == "pm" or permLower == "pc" or permLower == "pf" or permLower == "prf" or permLower == "gcm" or permLower == "police" or permLower == "helipm" or permLower == "helipf" or permLower == "heliprf" or permLower == "bprv" or permLower == "bprv1" or permLower == "qcg" then
            if jName == "police" or jName == "pmesp" or jName == "policia" or jName == permLower or jType == "leo" or exports.qbx_core:HasGroup(source, "police") or exports.qbx_core:HasGroup(source, "pm") or exports.qbx_core:HasGroup(source, "pmesp") then
                return true
            end
        elseif permLower == "bombeiro" or permLower == "bm" or permLower == "heli bm" or permLower == "boats bm" then
            if jName == "fire" or jName == "bombeiro" or exports.qbx_core:HasGroup(source, "fire") or exports.qbx_core:HasGroup(source, "bombeiro") then
                return true
            end
        elseif permLower == "mechanic" or permLower == "mecanico" or permLower == "mec" or permLower == "mec1" or permLower == "mec2" or permLower == "mec3" then
            if jName == "mechanic" or jName == "mecanico" or jType == "mechanic" or exports.qbx_core:HasGroup(source, "mechanic") then
                return true
            end
        end
    end

    local gang = (player.PlayerData and player.PlayerData.gang) or player.gang
    if gang and string.lower(tostring(gang.name or "")) == permLower then
        return true
    end

    return false
end

lib.callback.register('vanguard_garage:cb_server:getVehicleList', function(src, garage, impound, shared)
    local player = exports.qbx_core:GetPlayer(src) or (QBCore and QBCore.Functions.GetPlayer(src))
    if not player then return {} end

    local gz = GarageZone[tostring(garage)]
    local gName = gz and (gz.name or gz.label) or "Garage"
    local perm = gz and (gz.permission or gz.job)

    -- 1. Verificação de Permissão se houver
    if perm and not HasGaragePermission(src, player, perm) then
        return { error = "Você não possui permissão para acessar esta garagem." }
    end

    -- 2. GARAGEM DE TRABALHO / EMPREGO (Viaturas, Serviços, Facções)
    local workKey = gz and gz.workName
    if not workKey and Config.Works then
        if Config.Works[gName] then
            workKey = gName
        elseif gz and gz.job and Config.Works[gz.job] and gName ~= "Garage" then
            workKey = gz.job
        elseif perm and perm ~= "" and Config.Works[perm] and gName ~= "Garage" then
            workKey = perm
        elseif gName ~= "Garage" then
            local pLower = string.lower(tostring(perm or gName or ""))
            if (pLower == "paramedic" or pLower == "paramedico" or pLower == "hp" or pLower == "hpheli" or pLower == "paramedicoheli") and Config.Works["Paramedico"] then
                workKey = "Paramedico"
            elseif (pLower == "bombeiro" or pLower == "bm" or pLower == "heli bm" or pLower == "boats bm") and Config.Works["BM"] then
                workKey = "BM"
            elseif (pLower == "mechanic" or pLower == "mecanico" or pLower == "mec" or pLower == "mec1" or pLower == "mec2" or pLower == "mec3") and Config.Works["Mechanic"] then
                workKey = "Mechanic"
            elseif (pLower:find("pm") or pLower == "qcg" or pLower == "bprv" or pLower == "bprv1") and Config.Works["PM"] then
                workKey = "PM"
            elseif pLower:find("pc") and Config.Works["PC"] then
                workKey = "PC"
            elseif pLower:find("prf") and Config.Works["PRF"] then
                workKey = "PRF"
            elseif pLower:find("pf") and Config.Works["PF"] then
                workKey = "PF"
            elseif pLower:find("gcm") and Config.Works["GCM"] then
                workKey = "GCM"
            end
        end
    end

    if workKey and Config.Works and Config.Works[workKey] then
        local prefix = "SRV"
        local wkUpper = tostring(workKey):upper()
        if wkUpper == "PM" or wkUpper:find("PM") or wkUpper == "ROCAM" or wkUpper == "FT" or wkUpper == "COE" or wkUpper == "QCG" then
            prefix = "PM"
        elseif wkUpper == "PC" or wkUpper:find("PC") then
            prefix = "PC"
        elseif wkUpper == "PF" or wkUpper:find("PF") then
            prefix = "PF"
        elseif wkUpper == "PRF" or wkUpper:find("PRF") or wkUpper:find("BPRV") then
            prefix = "PRF"
        elseif wkUpper:find("PARAMEDICO") or wkUpper == "HP" or wkUpper:find("HELI") then
            prefix = "SAMU"
        elseif wkUpper:find("BM") or wkUpper:find("BOMBEIRO") then
            prefix = "BM"
        elseif wkUpper:find("MEC") then
            prefix = "MEC"
        elseif wkUpper:find("GCM") then
            prefix = "GCM"
        end

        local list = {}
        for idx, rawItem in ipairs(Config.Works[workKey]) do
            local model = type(rawItem) == "table" and rawItem.model or rawItem
            local ok, name = pcall(fw.gvn, model)
            local vehName = (type(rawItem) == "table" and rawItem.name) or ((ok and name and name ~= "") and name or string.upper(tostring(model)))

            list[#list + 1] = {
                name = vehName,
                model = model,
                plate = string.format("%s-%03d", prefix, idx),
                fuel = 100,
                engine = 1000,
                body = 1000,
                state = 1,
                state_text = "Disponível para Serviço",
                garage = garage,
                price = 0,
                isWork = true,
                isNearby = false,
                canStore = false
            }
        end
        return list
    end

    -- 3. GARAGENS PÚBLICAS OU PRIVADAS PESSOAIS (Veículos civis do jogador)
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
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player or not data or not data.plate then return end
    local p = utils.string.trim(data.plate)
    local vehData = getVehicleFromDB(p, false, true)
    if vehData and vehData.citizenid == player.PlayerData.citizenid then
        fw.uvs(p, data.state, data.garage, data.engine, data.body)
        vehicleCache[p] = nil
        vehicleCache[p .. "_owner"] = nil
    end
end)

-- Mapa de rastreamento de veículos ativos no servidor (Entity -> Plate)
ActiveVehiclePlates = ActiveVehiclePlates or {}

-- Thread de sincronização contínua para mapear placas de todos os veículos existentes
CreateThread(function()
    while true do
        Wait(5000)
        local allVehicles = GetAllVehicles()
        for i = 1, #allVehicles do
            local entity = allVehicles[i]
            if DoesEntityExist(entity) and not ActiveVehiclePlates[entity] then
                pcall(function()
                    local statePlate = Entity(entity).state.trackedPlate or Entity(entity).state.plate
                    local rawPlate = GetVehicleNumberPlateText(entity)
                    local cp = statePlate and utils.string.trim(tostring(statePlate)) or (rawPlate and utils.string.trim(rawPlate))
                    if cp and cp ~= "" then
                        local np = cp:gsub("%s+", ""):upper()
                        ActiveVehiclePlates[entity] = cp
                        SpawnedVehicleEntities[cp] = entity
                        SpawnedVehicleEntities[np] = entity
                    end
                end)
            end
        end
    end
end)

-- Listener para sincronizar veículos deletados no servidor (via /dv, script de limpeza, etc.)
AddEventHandler('entityRemoved', function(entity)
    if GetEntityType(entity) ~= 2 then return end -- 2 = veículo
    
    local plate = ActiveVehiclePlates[entity]
    if not plate then
        local stateBag = Entity(entity).state
        plate = stateBag and stateBag.trackedPlate
    end
    if not plate then
        pcall(function()
            local raw = GetVehicleNumberPlateText(entity)
            if raw and raw ~= "" then plate = utils.string.trim(raw) end
        end)
    end
    
    local eng = (DoesEntityExist(entity) and GetVehicleEngineHealth(entity)) or nil
    local bdy = (DoesEntityExist(entity) and GetVehicleBodyHealth(entity)) or nil
    local stFuel = Entity(entity).state and Entity(entity).state.fuel

    ActiveVehiclePlates[entity] = nil
    if plate and plate ~= "" then
        local np = plate:gsub("%s+", ""):upper()
        if SpawnedVehicleEntities[plate] == entity then
            SpawnedVehicleEntities[plate] = nil
        end
        if SpawnedVehicleEntities[np] == entity then
            SpawnedVehicleEntities[np] = nil
        end
        vehicleCache[plate] = nil
        vehicleCache[np] = nil
        vehicleCache[plate .. "_owner"] = nil
        vehicleCache[np .. "_owner"] = nil
        unlockPlate(plate)
        unlockPlate(np)

        -- Se for veículo de trabalho/serviço, não precisa atualizar player_vehicles
        local isWork = false
        if np:sub(1,3) == "WRK" or np:sub(1,4) == "WORK" or np == "SERVIÇO" or np:sub(1,3) == "SRV" or np:sub(1,2) == "PM" or np:sub(1,2) == "PC" or np:sub(1,3) == "PRF" or np:sub(1,2) == "PF" or np:sub(1,2) == "BM" then
            isWork = true
        end

        if not isWork then
            CreateThread(function()
                -- Atualiza no banco para state = 1 (disponível na garagem) caso estivesse fora (state = 0)
                local row = MySQL.single.await([[
                    SELECT id, plate, state, fuel, engine, body, garage FROM player_vehicles 
                    WHERE REPLACE(plate, ' ', '') = ? LIMIT 1
                ]], { np })

                if row and row.state == 0 then
                    local engineVal = (eng and eng > 0) and eng or (row.engine or 1000)
                    local bodyVal = (bdy and bdy > 0) and bdy or (row.body or 1000)
                    local fuelVal = stFuel or row.fuel or 100
                    local targetGarage = (row.garage and row.garage ~= "") and row.garage or "100002"

                    MySQL.update.await([[
                        UPDATE player_vehicles 
                        SET state = 1, engine = ?, body = ?, fuel = ?, garage = ? 
                        WHERE id = ?
                    ]], { engineVal, bodyVal, fuelVal, targetGarage, row.id })

                    if row.plate then
                        vehicleCache[row.plate] = nil
                        vehicleCache[row.plate .. "_owner"] = nil
                        unlockPlate(row.plate)
                    end
                end
            end)
        end
    end
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
    local src = source
    if not exports.qbx_core:HasPermission(src, "admin") and not exports.qbx_core:HasPermission(src, "god") then
        print(("[vanguard_garage] AVISO: Jogador %s (%s) tentou salvar zonas de garagem sem permissão!"):format(GetPlayerName(src), src))
        return
    end
    if type(fileData) ~= "table" or type(fileData) == "nil" then return end
    storage.SaveGarage(fileData)
    refreshGaragesFromDB(-1)
end)

RegisterNetEvent("vanguard_garage:server:saveCustomVehicleName", function (fileData)
    if GetInvokingResource() then return end
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    if type(fileData) ~= "table" or type(fileData) == "nil" then return end
    return storage.SaveVehicleName(fileData)
end)

local function cleanupCooldowns(playerId)
    SetTimeout(3000, function()
        vehicleSpawnCooldown[playerId] = nil
    end)
end

local function givePlayerVehicleKeys(src, plate)
    if not src or not plate or plate == "" then return false end
    local cleanPlate = (tostring(plate):gsub("%W", "")):upper()

    local success = false
    if GetResourceState('mri_Qcarkeys') == 'started' then
        local ok = pcall(function()
            if exports.mri_Qcarkeys.GiveKeyItem then
                exports.mri_Qcarkeys:GiveKeyItem(src, cleanPlate)
                success = true
            end
            if exports.mri_Qcarkeys.GiveTempKeys then
                exports.mri_Qcarkeys:GiveTempKeys(src, cleanPlate)
            end
        end)
        if not ok then
            print(("[vanguard_garage] AVISO: Erro ao chamar exports.mri_Qcarkeys:GiveKeyItem para o jogador %s (placa %s)"):format(src, cleanPlate))
        end
    end

    if not success and GetResourceState('ox_inventory') == 'started' then
        pcall(function()
            exports.ox_inventory:AddItem(src, 'vehiclekey', 1, {
                label = 'CHAVE-' .. cleanPlate,
                plate = cleanPlate
            })
            success = true
        end)
    end

    return success
end

local function removePlayerVehicleKeys(src, plate)
    if not src or not plate or plate == "" then return false end
    local cleanPlate = (tostring(plate):gsub("%W", "")):upper()

    -- 1. Remove via mri_Qcarkeys oficial (remove o item físico e a autorização temporária)
    if GetResourceState('mri_Qcarkeys') == 'started' then
        pcall(function()
            if exports.mri_Qcarkeys.RemoveKeyItem then
                exports.mri_Qcarkeys:RemoveKeyItem(src, cleanPlate)
            end
            if exports.mri_Qcarkeys.RemoveTempKeys then
                exports.mri_Qcarkeys:RemoveTempKeys(src, cleanPlate)
            end
        end)
    end

    -- 2. Fallback direto no ox_inventory garantindo limpeza completa de qualquer chave física com essa placa
    if GetResourceState('ox_inventory') == 'started' then
        pcall(function()
            local items = exports.ox_inventory:GetSlotsWithItem(src, 'vehiclekey')
            if items and type(items) == 'table' then
                for _, item in pairs(items) do
                    local meta = item.metadata or item.info
                    if meta then
                        local itemPlate = meta.plate and (tostring(meta.plate):gsub("%W", "")):upper()
                        local itemLabel = meta.label and (tostring(meta.label):gsub("%W", "")):upper()
                        if itemPlate == cleanPlate or (itemLabel and itemLabel:find(cleanPlate, 1, true)) then
                            exports.ox_inventory:RemoveItem(src, 'vehiclekey', 1, false, item.slot)
                        end
                    end
                end
            end
        end)
    end

    return true
end

-- Callback Autoritativo para Guardar Veículo
lib.callback.register('vanguard_garage:server:storeVehicle', function(source, netId, garageId, deformationData, clientProps, clientHealth)
    local playerId = source
    local player = exports.qbx_core:GetPlayer(playerId) or (QBCore and QBCore.Functions.GetPlayer(playerId))
    if not player then return false, "Jogador não encontrado." end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
        return false, "Veículo não encontrado ou inválido."
    end

    local ped = GetPlayerPed(playerId)
    local pCoords = GetEntityCoords(ped)
    local vCoords = GetEntityCoords(entity)

    -- Validação de distância entre jogador e veículo
    if #(pCoords - vCoords) > 60.0 then
        return false, "Você está muito longe deste veículo."
    end

    -- Validação de distância da garagem
    local gz = garageId and GarageZone[tostring(garageId)]
    if gz then
        local gCoords = gz.marker or (gz.marker_x and vec3(gz.marker_x, gz.marker_y, gz.marker_z)) or gz.coords
        if gCoords and #(pCoords - gCoords) > 120.0 then
            return false, "Você está muito longe do ponto da garagem."
        end
    end

    -- Validação de velocidade do veículo (Server-safe)
    if type(GetEntityVelocity) == "function" then
        local vel = GetEntityVelocity(entity)
        if vel and #(vel) > 5.0 then
            return false, "O veículo precisa estar parado para ser guardado."
        end
    end

    -- Validação de condutor: se outro jogador real estiver no volante
    local driver = GetPedInVehicleSeat(entity, -1)
    if driver ~= 0 and DoesEntityExist(driver) and driver ~= ped and IsPedAPlayer(driver) then
        return false, "Há outro jogador conduzindo o veículo."
    end

    -- Validação de passageiros algemados ou desacordados (Server-safe via StateBags)
    for seat = -1, 6 do
        local occ = GetPedInVehicleSeat(entity, seat)
        if occ ~= 0 and DoesEntityExist(occ) and occ ~= ped then
            local st = Entity(occ).state
            if st and (st.isHandcuffed or st.isDead or st.inLastStand) then
                return false, "Não é possível guardar o veículo com passageiros algemados ou desacordados."
            end
        end
    end

    local isWork = Entity(entity).state.isWorkVehicle or (gz and gz.isWork)
    local entityPlate = utils.getPlate(entity)
    local plate = entityPlate or ActiveVehiclePlates[entity] or (DoesEntityExist(entity) and Entity(entity).state.trackedPlate)
    local cleanPlate = plate and utils.string.trim(plate)

    if not isWork and cleanPlate then
        local prefix = cleanPlate:sub(1, 4):upper()
        if cleanPlate == "SERVIÇO" or prefix:sub(1,3) == "SRV" or prefix:sub(1,2) == "PM" or prefix:sub(1,2) == "PC" or prefix:sub(1,3) == "PRF" or prefix:sub(1,2) == "PF" or prefix:sub(1,2) == "BM" or prefix == "SAMU" or prefix:sub(1,3) == "MEC" or prefix:sub(1,3) == "GCM" or prefix == "ROTE" or prefix:sub(1,2) == "CB" then
            isWork = true
        end
    end

    -- 1. Veículo de Trabalho / Serviço
    if isWork then
        if cleanPlate then
            removePlayerVehicleKeys(playerId, cleanPlate)
            -- Limpeza em eventuais parceiros/oficiais próximos da viatura
            local nearbyPeds = GetAllPeds()
            local entCoords = GetEntityCoords(entity)
            for _, p in ipairs(nearbyPeds) do
                if IsPedAPlayer(p) then
                    local dist = #(GetEntityCoords(p) - entCoords)
                    if dist <= 15.0 then
                        local pSrc = NetworkGetEntityOwner(p)
                        if pSrc and pSrc ~= playerId and pSrc > 0 then
                            removePlayerVehicleKeys(pSrc, cleanPlate)
                        end
                    end
                end
            end
            SpawnedVehicleEntities[cleanPlate] = nil
        end
        ActiveVehiclePlates[entity] = nil
        DeleteEntity(entity)
        return true, "Viatura / Veículo de serviço guardado com sucesso!"
    end

    -- 2. Veículo Civil Pessoal
    if not cleanPlate or cleanPlate == "" then
        return false, "Placa inválida."
    end

    local vehData = getVehicleFromDB(cleanPlate, false, true)
    if not vehData then
        return false, "Veículo não registrado no sistema."
    end

    if vehData.citizenid ~= player.PlayerData.citizenid then
        return false, "Você não é o proprietário deste veículo."
    end

    -- Prioriza o dano físico real capturado no cliente (bodyHealth, engineHealth e fuelLevel)
    -- No servidor, GetVehicleBodyHealth(entity) não reflete colisões do cliente no OneSync e retorna 1000.
    local clientBody = (clientHealth and clientHealth.body)
                    or (clientProps and (clientProps.bodyHealth or clientProps.body))
    local clientEngine = (clientHealth and clientHealth.engine)
                    or (clientProps and (clientProps.engineHealth or clientProps.engine))
    local clientFuel = (clientHealth and clientHealth.fuel)
                    or (clientProps and (clientProps.fuelLevel or clientProps.fuel))

    local body = tonumber(clientBody) or 1000.0
    local engine = tonumber(clientEngine) or (DoesEntityExist(entity) and GetVehicleEngineHealth(entity)) or 1000.0
    local fuel = tonumber(clientFuel) or utils.getFuel(entity) or 100

    -- Limites de segurança (0 a 1000 para health, 0 a 100 para fuel)
    body = math.floor(math.max(0.0, math.min(1000.0, body)) + 0.5)
    engine = math.floor(math.max(0.0, math.min(1000.0, engine)) + 0.5)
    fuel = math.floor(math.max(0.0, math.min(100.0, tonumber(fuel) or 100)) + 0.5)

    fw.uvs(cleanPlate, 1, garageId or vehData.garage or "100002", engine, body)

    local modsToSave = nil
    if type(clientProps) == 'table' and next(clientProps) then
        clientProps.bodyHealth = body
        clientProps.engineHealth = engine
        clientProps.fuelLevel = fuel
        modsToSave = json.encode(clientProps)
    elseif vehData and vehData.mods then
        modsToSave = type(vehData.mods) == 'string' and vehData.mods or json.encode(vehData.mods)
    else
        modsToSave = "{}"
    end

    local np = cleanPlate:gsub("%s+", ""):upper()
    MySQL.update([[
        UPDATE player_vehicles
        SET mods = ?, fuel = ?, deformation = ?, engine = ?, body = ?
        WHERE plate = ? OR fakeplate = ? OR TRIM(plate) = ? OR REPLACE(plate, ' ', '') = ?
    ]], {
        modsToSave,
        fuel,
        json.encode(deformationData or {}),
        engine,
        body,
        cleanPlate,
        cleanPlate,
        cleanPlate,
        np
    })

    if cleanPlate and (Config.GiveKeys.onspawn or Config.GiveKeys.enable) then
        removePlayerVehicleKeys(playerId, cleanPlate)
    end

    SpawnedVehicleEntities[cleanPlate] = nil
    ActiveVehiclePlates[entity] = nil
    vehicleCache[cleanPlate] = nil
    vehicleCache[cleanPlate .. "_owner"] = nil

    DeleteEntity(entity)
    return true, "Veículo guardado na garagem com sucesso!"
end)

-- Callback Autoritativo para Spawn de Veículo (Prevenção Absoluta de Duplicação)
lib.callback.register('vanguard_garage:server:spawnVehicle', function(source, model, coords, props, extra)
    local playerId = source
    local player = exports.qbx_core:GetPlayer(playerId) or (QBCore and QBCore.Functions.GetPlayer(playerId))
    if not player then return false, false end

    local plate = (extra and extra.plate) or (props and props.plate)
    local cleanPlate = plate and utils.string.trim(plate)
    local garage = extra and extra.garage
    local isWork = (extra and extra.isWork) or (cleanPlate and (cleanPlate == "SERVIÇO" or cleanPlate:sub(1,3) == "SRV" or cleanPlate:sub(1,2) == "PM" or cleanPlate:sub(1,2) == "PC" or cleanPlate:sub(1,3) == "PRF" or cleanPlate:sub(1,2) == "PF" or cleanPlate:sub(1,2) == "BM" or cleanPlate:sub(1,4) == "SAMU" or cleanPlate:sub(1,3) == "MEC" or cleanPlate:sub(1,3) == "GCM" or cleanPlate:sub(1,4) == "ROTE" or cleanPlate:sub(1,2) == "CB"))

    -- Se for viatura de serviço e a placa for genérica, contiver hífen (preview) ou vazia, gera uma placa única
    if isWork and (not cleanPlate or cleanPlate == "" or cleanPlate == "SERVIÇO" or cleanPlate:find("-")) then
        local pPrefix = "SRV"
        if cleanPlate and cleanPlate:sub(1, 2) == "PM" then pPrefix = "PM"
        elseif cleanPlate and cleanPlate:sub(1, 2) == "PC" then pPrefix = "PC"
        elseif cleanPlate and cleanPlate:sub(1, 2) == "PF" then pPrefix = "PF"
        elseif cleanPlate and cleanPlate:sub(1, 3) == "PRF" then pPrefix = "PRF"
        elseif cleanPlate and cleanPlate:sub(1, 4) == "SAMU" then pPrefix = "SAMU"
        elseif cleanPlate and (cleanPlate:sub(1, 2) == "BM" or cleanPlate:sub(1, 2) == "CB") then pPrefix = "BM"
        elseif cleanPlate and cleanPlate:sub(1, 3) == "GCM" then pPrefix = "GCM"
        elseif cleanPlate and cleanPlate:sub(1, 4) == "ROTE" then pPrefix = "ROTE"
        end
        cleanPlate = ("%s%04d"):format(pPrefix, math.random(1000, 9999)):sub(1, 8)
    end

    -- Validação de Cooldown por jogador
    if vehicleSpawnCooldown[playerId] then
        utils.notify(playerId, "Aguarde antes de retirar outro veículo.", "error")
        return false, false
    end

    local ped = GetPlayerPed(playerId)
    local pCoords = GetEntityCoords(ped)
    if coords and (coords.x or coords[1]) then
        local spPos = vec3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
        if #(pCoords - spPos) > 120.0 then
            return false, false
        end
    end

    local vehData = nil

    -- Se for veículo civil pessoal (não isWork)
    if not isWork then
        if not cleanPlate or cleanPlate == "" then
            return false, false
        end

        -- MUTEX / LOCK ATÔMICO POR PLACA
        if isPlateLocked(cleanPlate) then
            utils.notify(playerId, "Este veículo já está em processo de retirada. Aguarde.", "error")
            return false, false
        end

        vehData = getVehicleFromDB(cleanPlate, false, true)
        if not vehData then
            utils.notify(playerId, "Veículo não encontrado.", "error")
            return false, false
        end

        if vehData.citizenid ~= player.PlayerData.citizenid then
            utils.notify(playerId, "Você não é o proprietário deste veículo.", "error")
            return false, false
        end

        local gz = garage and GarageZone[tostring(garage)]
        local isImpoundGarage = gz and gz.impound

        if vehData.state == 2 and not isImpoundGarage then
            utils.notify(playerId, "Este veículo está apreendido no pátio policial.", "error")
            return false, false
        end

        if (vehData.state == 0 or vehData.state == 3) and not isImpoundGarage then
            utils.notify(playerId, "Este veículo já está fora da garagem!", "error")
            return false, false
        end

        if isImpoundGarage and (vehData.state == 0 or vehData.state == 3) then
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

        -- Ativa o lock atômico da placa
        lockPlate(cleanPlate, playerId)

        -- ATUALIZAÇÃO IMEDIATA NO BANCO DE DADOS (STATE = 0)
        fw.uvs(cleanPlate, 0, garage or vehData.garage or "100002")
        vehicleCache[cleanPlate] = nil
        vehicleCache[cleanPlate .. "_owner"] = nil
    end

    -- Prevenção de Duplicação: Deleta cópia antiga existente no mapa
    if Config.DeleteOldVehicleOnSpawn and cleanPlate then
        local oldEntity = SpawnedVehicleEntities[cleanPlate]
        if oldEntity and DoesEntityExist(oldEntity) then
            DeleteEntity(oldEntity)
            SpawnedVehicleEntities[cleanPlate] = nil
        else
            local allVehicles = GetAllVehicles()
            for _, veh in ipairs(allVehicles) do
                if DoesEntityExist(veh) then
                    local vehPlate = GetVehicleNumberPlateText(veh)
                    if vehPlate and vehPlate:gsub("%s+", "") == cleanPlate:gsub("%s+", "") then
                        DeleteEntity(veh)
                        break
                    end
                end
            end
        end
    end

    vehicleSpawnCooldown[playerId] = true
    cleanupCooldowns(playerId)

    -- Instancia a entidade via CreateVehicle nativo do servidor (idêntico ao script garages)
    local spawnX = coords.x or coords[1]
    local spawnY = coords.y or coords[2]
    local spawnZ = coords.z or coords[3]
    local spawnH = coords.w or coords.h or coords[4] or 0.0

    local modelHash = type(model) == 'number' and model or joaat(model)
    local veh = CreateVehicle(modelHash, spawnX, spawnY, spawnZ, spawnH, true, true)

    local timeout = 0
    while not DoesEntityExist(veh) and timeout < 100 do
        timeout = timeout + 1
        Wait(20)
    end

    -- Rollback caso a criação falhe
    if not veh or not DoesEntityExist(veh) then
        if not isWork and cleanPlate then
            fw.uvs(cleanPlate, 1, garage or (vehData and vehData.garage) or "100002")
            vehicleCache[cleanPlate] = nil
            vehicleCache[cleanPlate .. "_owner"] = nil
            unlockPlate(cleanPlate)
        end
        utils.notify(playerId, "Falha ao instanciar o veículo no mapa.", "error")
        return false, false
    end

    if cleanPlate and cleanPlate ~= "" then
        SetVehicleNumberPlateText(veh, cleanPlate)
    end

    -- Garante que mods salvos sejam carregados caso props esteja vazio
    if (not props or not next(props)) and cleanPlate then
        local rawMods = vehData and vehData.mods
        if not rawMods then
            local dbRow = MySQL.single.await("SELECT mods FROM player_vehicles WHERE REPLACE(plate, ' ', '') = ? LIMIT 1", { cleanPlate:gsub("%s+", "") })
            if dbRow and dbRow.mods then
                rawMods = dbRow.mods
            end
        end
        if rawMods then
            if type(rawMods) == "string" and rawMods ~= "" and rawMods ~= "{}" then
                local ok, p = pcall(json.decode, rawMods)
                if ok and type(p) == "table" then
                    props = p
                end
            elseif type(rawMods) == "table" then
                props = rawMods
            end
        end
    end

    -- Seta propriedades via ox_lib no servidor (state bag) antes de replicar aos clientes (idêntico a garages)
    if props and type(props) == "table" and next(props) then
        pcall(function() lib.setVehicleProperties(veh, props) end)
    end

    local fuelLevel = tonumber(vehData and vehData.fuel) or (extra and tonumber(extra.fuel)) or 100
    Entity(veh).state:set('fuel', fuelLevel, true)

    local netid = NetworkGetNetworkIdFromEntity(veh)

    if Config.SpawnLocked then
        SetVehicleDoorsLocked(veh, 2)
    end

    if cleanPlate and cleanPlate ~= "" then
        local np = cleanPlate:gsub("%s+", ""):upper()
        ActiveVehiclePlates[veh] = cleanPlate
        SpawnedVehicleEntities[cleanPlate] = veh
        SpawnedVehicleEntities[np] = veh
        Entity(veh).state:set('trackedPlate', cleanPlate, true)
    end

    if isWork then
        Entity(veh).state:set('isWorkVehicle', true, true)
    else
        unlockPlate(cleanPlate)
    end

    -- Entrega autoritativa da chave física no inventário e registro de chave temporária
    if cleanPlate and cleanPlate ~= "" and (isWork or Config.GiveKeys.onspawn) then
        givePlayerVehicleKeys(playerId, cleanPlate)
    end

    return netid, veh, cleanPlate
end)

--- exports
exports("Garage", function ()
    return GarageZone
end)

local CustomGarageIds = {}

local function refreshGaragesFromDB(target)
    local ok, rows = pcall(function()
        return MySQL.query.await("SELECT * FROM custom_garages ORDER BY id ASC")
    end)
    if not ok or not rows then
        print("^1[vanguard_garage] Falha ao consultar custom_garages: " .. tostring(rows))
        return false, tostring(rows)
    end

    local newCustomIds = {}
    for _, g in ipairs(rows) do
        local gid = tostring(g.garage_id or g.id)
        newCustomIds[gid] = true

        local markerCoord = vec3(g.marker_x, g.marker_y, g.marker_z)
        local spawns = {}
        if g.spawns and g.spawns ~= "" and g.spawns ~= "null" then
            local okDec, decoded = pcall(json.decode, g.spawns)
            if okDec and type(decoded) == "table" and #decoded > 0 then
                for _, sp in ipairs(decoded) do
                    if sp and sp.x and sp.y and sp.z then
                        spawns[#spawns + 1] = vec4(sp.x, sp.y, sp.z, sp.heading or sp.h or 0.0)
                    end
                end
            end
        end
        if #spawns == 0 then
            spawns = { vec4(g.spawn_x, g.spawn_y, g.spawn_z, g.spawn_h) }
        end

        local isWork = (Config.Works and Config.Works[g.name] ~= nil) or false
        local perm = g.permission or ""
        if perm == "nil" or perm == "false" then perm = "" end

        local isPublic = (perm == "") and not isWork
        local blipConf = nil
        if isPublic then
            local bLabel = "Garagem Pública"
            local sprite = 357
            if g.name == "Concessionária" then sprite = 225
            elseif g.name == "Aeronaves" then sprite = 359
            elseif g.name and g.name ~= "Garage" and g.name ~= "" then bLabel = "Garagem " .. g.name end
            blipConf = { type = sprite, color = 3, label = bLabel }
        end

        GarageZone[gid] = {
            garage_id = gid,
            name = g.name or "Garage",
            label = g.name or "Garage",
            marker = markerCoord,
            marker_x = g.marker_x,
            marker_y = g.marker_y,
            marker_z = g.marker_z,
            spawnPoint = spawns,
            spawnpoint = spawns,
            type = {"car", "motorcycle", "cycles"},
            job = perm ~= "" and perm or (isWork and g.name or nil),
            permission = perm ~= "" and perm or (isWork and g.name or nil),
            isWork = isWork,
            workName = isWork and g.name or nil,
            payment = (g.payment == true or g.payment == "true" or g.payment == 1) or false,
            blip = blipConf,
            interaction = "keypressed",
            impound = false
        }
    end

    -- Remove garagens deletadas do banco que estavam no cache
    for oldGid in pairs(CustomGarageIds) do
        if not newCustomIds[oldGid] then
            GarageZone[oldGid] = nil
        end
    end
    CustomGarageIds = newCustomIds

    TriggerClientEvent('vanguard_garage:client:syncConfig', target or -1, GarageZone)
    return true
end

exports("ReloadCustomGarages", refreshGaragesFromDB)

RegisterNetEvent('vanguard_garage:server:requestGarages', function()
    local src = source
    TriggerClientEvent('vanguard_garage:client:syncConfig', src, GarageZone)
end)

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(100)
    end
    Wait(500)
    refreshGaragesFromDB(-1)
    print('^2[vanguard_garage]^7 Garagens customizadas carregadas do banco de dados.')
end)

exports("GetGarageTypes", function()
    local types = {}
    types[#types + 1] = {
        value = "Garage",
        label = "Garage (Pública / Pessoal)",
        vehicles = {},
        count = 0
    }
    if Config.Works then
        for catName, models in pairs(Config.Works) do
            local vehList = {}
            for _, m in ipairs(models) do
                local ok, name = pcall(fw.gvn, m)
                local nameLabel = (ok and name and name ~= "" and name ~= "NULL") and name or string.upper(tostring(m))
                vehList[#vehList + 1] = {
                    model = m,
                    label = nameLabel
                }
            end
            table.sort(vehList, function(a, b) return tostring(a.label or a.model):lower() < tostring(b.label or b.model):lower() end)
            types[#types + 1] = {
                value = catName,
                label = catName,
                vehicles = vehList,
                count = #vehList
            }
        end
    end
    table.sort(types, function(a, b) return a.value:lower() < b.value:lower() end)
    return types
end)

exports("ApplyCustomGarageMutation", function(action, row)
    action = tostring(action or "")
    row = type(row) == "table" and row or {}
    local gid = tostring(row.garage_id or row.id or "")

    if action == "remove" and gid ~= "" then
        if GarageZone[gid] then
            GarageZone[gid] = nil
        end
        CustomGarageIds[gid] = nil
        TriggerClientEvent('vanguard_garage:client:syncConfig', -1, GarageZone)
        return true
    end

    if action == "upsert" and gid ~= "" then
        local markerCoord = vec3(tonumber(row.marker_x or 0.0), tonumber(row.marker_y or 0.0), tonumber(row.marker_z or 0.0))
        local spawns = {}
        if row.spawns and row.spawns ~= "" and row.spawns ~= "null" then
            local okDec, decoded = pcall(json.decode, row.spawns)
            if okDec and type(decoded) == "table" and #decoded > 0 then
                for _, sp in ipairs(decoded) do
                    if sp and sp.x and sp.y and sp.z then
                        spawns[#spawns + 1] = vec4(tonumber(sp.x), tonumber(sp.y), tonumber(sp.z), tonumber(sp.heading or sp.h or 0.0))
                    end
                end
            end
        end
        if #spawns == 0 and row.spawn_x and row.spawn_y and row.spawn_z then
            spawns = { vec4(tonumber(row.spawn_x), tonumber(row.spawn_y), tonumber(row.spawn_z), tonumber(row.spawn_h or 0.0)) }
        end

        local isWork = (Config.Works and Config.Works[row.name] ~= nil) or false
        local perm = row.permission or ""
        if perm == "nil" or perm == "false" then perm = "" end

        local isPublic = (perm == "") and not isWork
        local blipConf = nil
        if isPublic then
            local bLabel = "Garagem Pública"
            local sprite = 357
            if row.name == "Concessionária" then sprite = 225
            elseif row.name == "Aeronaves" then sprite = 359
            elseif row.name and row.name ~= "Garage" and row.name ~= "" then bLabel = "Garagem " .. row.name end
            blipConf = { type = sprite, color = 3, label = bLabel }
        end

        GarageZone[gid] = {
            garage_id = gid,
            name = row.name or "Garage",
            label = row.name or "Garage",
            marker = markerCoord,
            marker_x = tonumber(row.marker_x or 0.0),
            marker_y = tonumber(row.marker_y or 0.0),
            marker_z = tonumber(row.marker_z or 0.0),
            spawnPoint = spawns,
            spawnpoint = spawns,
            type = {"car", "motorcycle", "cycles"},
            job = perm ~= "" and perm or (isWork and row.name or nil),
            permission = perm ~= "" and perm or (isWork and row.name or nil),
            isWork = isWork,
            workName = isWork and row.name or nil,
            payment = (row.payment == true or row.payment == "true" or row.payment == 1) or false,
            blip = blipConf,
            interaction = "keypressed",
            impound = false
        }
        CustomGarageIds[gid] = true
        TriggerClientEvent('vanguard_garage:client:syncConfig', -1, GarageZone)
        return true
    end

    return refreshGaragesFromDB(-1)
end)

-- Evento de compatibilidade para scripts legados (trucker, desmanche, etc.)
RegisterNetEvent("garages:deleteVehicle", function(netId, plate)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
    if plate then
        local p = utils.string.trim(plate)
        fw.uvs(p, 1, "100002", 1000, 1000)
        vehicleCache[p] = nil
        vehicleCache[p .. "_owner"] = nil
    end
end)
