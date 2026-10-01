local VehicleShow = nil
local Deformation = require 'modules.deformation'

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        LocalPlayer.state:set('garageBusy', false, true)
    end
end)

local function destroyPreview(keepCam)
    if VehicleShow and DoesEntityExist(VehicleShow) then
        if not keepCam then
            utils.destroyPreviewCam(VehicleShow)
        end
        local entity = VehicleShow
        VehicleShow = nil
        DeleteVehicle(entity)
        
        local timeout = 0
        while DoesEntityExist(entity) and timeout < 50 do
            Wait(10)
            timeout = timeout + 1
        end
    end
    return true
end

local function swapEnabled(from)
    if GarageZone[from] then
        local fromJob = GarageZone[from]['job']
        local fromGang = GarageZone[from]['gang']
        
        if GarageZone[from]['vehicles'] and #GarageZone[from]['vehicles'] > 0 then
            return false
        end
        return not (fromJob or fromGang)
    else
        return false
    end

end

local function canSwapVehicle(to)
    local toJob = GarageZone[to]['job']
    local toGang = GarageZone[to]['gang']
    
    if GarageZone[to]['vehicles'] and #GarageZone[to]['vehicles'] > 0 then
        return false
    end
    
    return not (toJob or toGang)
end

local isSpawning = false

--- Spawn Vehicle
---@param data GarageVehicleData
--- Spawn Vehicle
---@param data GarageVehicleData
local function spawnvehicle(data)
    LocalPlayer.state:set('garageBusy', true)
    if isSpawning then
        utils.notify('Aguarde enquanto o veículo está sendo retirado.', 'error')
        return
    end

    isSpawning = true

    local success, errorMsg = pcall(function()
        local vehData = {
            model = data.model,
            plate = data.plate,
        }
        
        local isWork = data.isWork or (data.plate == "SERVIÇO") or (data.plate and data.plate:sub(1,3) == "SRV")
        if isWork then
            local pPrefix = "SRV"
            local gData = GarageZone[data.garage]
            if gData and gData.name then
                if gData.name == "PM" or gData.name == "ROCAM" or gData.name == "FT" or gData.name == "COE" then
                    pPrefix = "PM"
                elseif gData.name == "PC" then
                    pPrefix = "PC"
                elseif gData.name == "PF" or gData.name == "PFHELI" then
                    pPrefix = "PF"
                elseif gData.name == "PRF" or gData.name == "BPRV" or gData.name == "BPRV1" then
                    pPrefix = "PRF"
                elseif gData.name == "Paramedico" or gData.name == "HP" then
                    pPrefix = "SAMU"
                elseif gData.name == "BM" then
                    pPrefix = "BOMBEIRO"
                end
            end
            vehData.plate = ("%s%04d"):format(pPrefix, math.random(1000, 9999)):sub(1, 8)
            vehData.vehicle_name = data.name or string.upper(data.model)
        elseif data.plate then
            local callbackData = lib.callback.await('vanguard_garage:cb_server:getvehiclePropByPlate', false, data.plate)
            if callbackData then
                for key, value in pairs(callbackData) do
                    vehData[key] = value
                end
            end
        end

        local vehEntity
        if not vehData.mods then vehData.mods = {} end
        vehData.mods.plate = vehData.plate or data.plate

        utils.createPlyVeh(vehData.model, data.coords, function(veh) vehEntity = veh end, true, vehData.mods, {
            plate = vehData.plate or data.plate,
            garage = data.garage,
            isWork = isWork
        })
        
        local timeout = 500 -- 5 segundos de timeout
        while vehEntity == nil and timeout > 0 do 
            Wait(10) 
            timeout = timeout - 1
        end

        if not vehEntity then 
            error('Falha ao criar entidade do veículo ou spawn cancelado.')
        end

        SetVehicleOnGroundProperly(vehEntity)

        if vehData.plate then
            SetVehicleNumberPlateText(vehEntity, vehData.plate)
        end

        local engineHealth = vehData.engine or 1000
        local bodyHealth = vehData.body or 1000
        local deformationData = vehData.deformation or data.deformation

        -- Regra de Conserto Automático ao pagar Franquia de Seguro
        local garageData = GarageZone[data.garage]
        if Config.RepairOnInsurance and garageData and garageData.impound and (engineHealth <= 0 and bodyHealth <= 0) then
            engineHealth = 1000
            bodyHealth = 1000
            deformationData = nil
        end

        if deformationData then
            if type(deformationData) == "string" then
                deformationData = json.decode(deformationData)
            end
            if type(deformationData) == "table" and next(deformationData) then
                Deformation.set(vehEntity, deformationData)
            end
        end

        SetVehicleEngineHealth(vehEntity, (engineHealth) + 0.0)
        SetVehicleBodyHealth(vehEntity, (bodyHealth) + 0.0)
        utils.setFuel(vehEntity, vehData.fuel or 100)

        Entity(vehEntity).state:set('vehlabel', vehData.vehicle_name or data.vehicle_name)
        
        if isWork then
            Entity(vehEntity).state:set('isWorkVehicle', true)
        end

        local plate = vehData.plate or data.plate or GetVehicleNumberPlateText(vehEntity)
        local cleanPlate = utils.string.trim(plate)

        local inventoryFull = false
        if isWork then
            if GetResourceState('mri_Qcarkeys') == 'started' then
                TriggerEvent('mm_carkeys:client:addtempkeys', cleanPlate)
                TriggerServerEvent('mm_carkeys:server:acquiretempvehiclekeys', cleanPlate)
            end
        else
            if GetResourceState('mri_Qcarkeys') == 'started' and Config.GiveKeys.onspawn then
                if not exports.mri_Qcarkeys:HavePermanentKey(cleanPlate) then
                    local keySuccess = exports.mri_Qcarkeys:GiveKeyItem(cleanPlate)
                    if keySuccess == false then
                        inventoryFull = true
                        utils.notify("Seu inventário está cheio para receber a chave física. O veículo foi deixado destrancado.", "warning", 8000)
                    end
                end
            end
        end

        if Config.SpawnInVehicle then
            TaskWarpPedIntoVehicle(cache.ped, vehEntity, -1)
            SetVehicleNeedsToBeHotwired(vehEntity, false)
            SetVehicleEngineOn(vehEntity, true, true, false)
            SetVehicleLights(vehEntity, 2)
            SetVehicleFullbeam(vehEntity, true)
            if GetResourceState('mri_Qcarkeys') == 'started' then
                Entity(vehEntity).state:set('keysIn', true, true)
            end
        else
            if Config.SpawnLocked and not inventoryFull then
                SetVehicleDoorsLocked(vehEntity, 2)
                local netId = NetworkGetNetworkIdFromEntity(vehEntity)
                if netId and netId ~= 0 then
                    TriggerServerEvent('mm_carkeys:server:setVehLockState', netId, 2)
                end
            else
                SetVehicleDoorsLocked(vehEntity, 1)
            end
            SetVehicleNeedsToBeHotwired(vehEntity, false)
            SetVehicleEngineOn(vehEntity, false, false, true)
            SetVehicleLights(vehEntity, 0)
            if GetResourceState('mri_Qcarkeys') == 'started' then
                Entity(vehEntity).state:set('keysIn', false, true)
            end
        end

        -- Criar a câmera cinematográfica (ela mesma cuidará do primeiro FadeIn)
        utils.createPreviewCam(vehEntity, true)

        -- Barra de progresso customizada Vanguard (7 segundos total)
        utils.vanguardProgress('Retirando veículo...', 7000)

        -- Finaliza a câmera e volta para o jogador
        utils.destroyPreviewCam(vehEntity, Config.SpawnInVehicle)
        if IsScreenFadedOut() or IsScreenFadingOut() then
            DoScreenFadeIn(500)
        end
    end)

    isSpawning = false
    LocalPlayer.state:set('garageBusy', false)
    if not success then
        utils.notify('Erro ao spawnar veículo: ' .. (errorMsg or 'desconhecido'), 'error')
    end
end

local function getVehMetadata(data)
    local fuel = data.fuel
    local body = data.body
    local engine = data.engine
    return {
        {label = '⛽ Combustível', value = math.floor(fuel) .. '%', progress = math.floor(fuel), colorScheme = utils.getColorLevel(math.floor(fuel))},
        {label = '🧰 Lataria', value = math.floor(body / 10) .. '%', progress = math.floor(body / 10), colorScheme = utils.getColorLevel(math.floor(body / 10))},
        {label = '🔧 Motor', value = math.floor(engine / 10) .. '%', progress = math.floor(engine / 10), colorScheme = utils.getColorLevel(math.floor(engine / 10))}
    }
end
--- Garage Action
---@param data GarageVehicleData
local function actionMenu(data)
    local actionData = {
        id = 'garage_action',
        title = data.plate or data.vehName,
        description = data.vehicle_name,
        menu = 'garage_menu',
        onBack = destroyPreview,
        onExit = destroyPreview,
        options = {
            {
                title = data.vehName,
                icon = data.icon --[[@as string]],
                readOnly = true,
                iconAnimation = Config.IconAnimation,
                metadata = getVehMetadata(data),
            },
            {
                title = data.impound and locale('garage.pay_impound') or locale('garage.take_out_veh'),
                icon = data.impound and 'hand-holding-dollar' or 'sign-out-alt',
                iconAnimation = Config.IconAnimation,
                onSelect = function()
                    if data.impound then
                        utils.createMenu({
                            id = 'pay_methode',
                            title = locale('context.insurance.pay_methode_header'):upper(),
                            onExit = destroyPreview,
                            menu = 'garage_action',
                            options = {
                                {
                                    title = locale('context.insurance.pay_methode_cash_title'):upper(),
                                    icon = 'dollar-sign',
                                    description = locale('context.insurance.pay_methode_cash_desc'),
                                    iconAnimation = Config.IconAnimation,
                                    onSelect = function()
                                        DoScreenFadeOut(0)
                                        destroyPreview(true)
                                        if fw.gm('cash') < data.depotprice then return utils.notify(locale('notify.error.not_enough_cash'), 'error') end
                                        local success = lib.callback.await('vanguard_garage:cb_server:removeMoney', false, 'cash', data.depotprice)
                                        if success then
                                            utils.notify(locale('garage.success_pay_impound'), 'success')
                                            return spawnvehicle(data)
                                        end
                                    end
                                },
                                {
                                    title = locale('context.insurance.pay_methode_bank_title'):upper(),
                                    icon = 'fab fa-cc-mastercard',
                                    description = locale('context.insurance.pay_methode_bank_desc'),
                                    iconAnimation = Config.IconAnimation,
                                    onSelect = function()
                                        DoScreenFadeOut(0)
                                        destroyPreview(true)
                                        if fw.gm('bank') < data.depotprice then return utils.notify(locale('notify.error.not_enough_bank'), 'error') end
                                        local success = lib.callback.await('vanguard_garage:cb_server:removeMoney', false, 'bank', data.depotprice)
                                        if success then
                                            utils.notify(locale('garage.success_pay_impound'), 'success')
                                            return spawnvehicle(data)
                                        end
                                    end
                                }
                            }
                        })
                        return
                    end
                    DoScreenFadeOut(0)
                    destroyPreview(true)
                    spawnvehicle(data)
                end
            },
        
        }
    }
    
    if not data.impound and data.plate then
        if Config.TransferVehicle.enable and not Config.VehiclesInAllGarages then
            actionData.options[#actionData.options + 1] = {
                title = locale("context.garage.transferveh_title"),
                icon = "exchange-alt",
                iconAnimation = Config.IconAnimation,
                metadata = {
                    ["Preço"] = 'R$ ' .. lib.math.groupdigits(Config.TransferVehicle.price, '.')
                },
                onSelect = function()
                    destroyPreview()
                    local transferInput = lib.inputDialog(data.vehName, {
                        {type = 'number', label = 'Player Id', required = true},
                    })
                    
                    if transferInput then
                        local clData = {
                            targetSrc = transferInput[1],
                            plate = data.plate,
                            price = Config.TransferVehicle.price,
                            garage = data.garage
                        }
                        lib.callback('vanguard_garage:cb_server:transferVehicle', false, function(success, information)
                            if not success then return
                                utils.notify(information, "error")
                            end
                            
                            utils.notify(information, "success")
                        end, clData)
                    end
                end
            }
        end
        
        if Config.SwapGarage.enable and swapEnabled(data.garage) and not Config.VehiclesInAllGarages then
            actionData.options[#actionData.options + 1] = {
                title = locale('context.garage.swapgarage'),
                icon = "retweet",
                iconAnimation = Config.IconAnimation,
                metadata = {
                    ["Preço"] = 'R$ ' .. lib.math.groupdigits(Config.SwapGarage.price, '.')
                },
                onSelect = function()
                    destroyPreview()
                    
                    local garageTable = function()
                        local result = {}
                        for k, v in pairs(GarageZone) do
                            if k ~= data.garage and not v.impound and canSwapVehicle(k) then
                                result[#result + 1] = {value = k}
                            end
                        end
                        return result
                    end
                    
                    local garageInput = lib.inputDialog(data.garage:upper(), {
                        {type = 'select', label = locale('input.garage.swapgarage'), options = garageTable(), required = true},
                    })
                    
                    if garageInput then
                        local vehdata = {
                            plate = data.plate,
                            newgarage = garageInput[1]
                        }
                        
                        if fw.gm('cash') < Config.SwapGarage.price then return utils.notify(locale("notify.error.need_money", lib.math.groupdigits(Config.SwapGarage.price, '.')), 'error') end
                        local success = lib.callback.await('vanguard_garage:cb_server:removeMoney', false, 'cash', Config.SwapGarage.price)
                        if not success then return end
                        
                        lib.callback('vanguard_garage:cb_server:swapGarage', false, function(success)
                            if not success then return
                                utils.notify(locale("notify.error.swapgarage"), "error")
                            end
                            
                            utils.notify(locale('notify.success.swapgarage', vehdata.newgarage), "success")
                        end, vehdata)
                    end
                end
            }
        end
        
        actionData.options[#actionData.options + 1] = {
            title = locale('context.garage.change_veh_name'),
            icon = 'pencil',
            iconAnimation = Config.IconAnimation,
            metadata = {
                ["Preço"] = 'R$ ' .. lib.math.groupdigits(Config.changeNamePrice, '.')
            },
            onSelect = function()
                destroyPreview()
                
                local input = lib.inputDialog(data.vehName, {
                    {type = 'input', label = '', placeholder = locale('input.garage.change_veh_name'), required = true, max = 20},
                })
                
                if input then
                    if fw.gm('cash') < Config.changeNamePrice then return utils.notify(locale('notify.error.not_enough_cash'), 'error') end
                    
                    local success = lib.callback.await('vanguard_garage:cb_server:removeMoney', false, 'cash', Config.changeNamePrice)
                    if success then
                        CNV[data.plate] = {
                            name = input[1]
                        }
                        TriggerServerEvent('vanguard_garage:server:saveCustomVehicleName', CNV)
                    end
                end
            end
        }
        
        actionData.options[#actionData.options + 1] = {
            title = locale('context.garage.vehicle_keys'),
            icon = 'key',
            iconAnimation = Config.IconAnimation,
            metadata = {
                ["Preço"] = 'R$ ' .. lib.math.groupdigits(Config.GiveKeys.price, '.')
            },
            onSelect = function()
                
                
                local input = lib.alertDialog({
                    header = 'Criar cópia de chave',
                    content = 'Você deseja copiar a chave do seu veículo por R$' .. Config.GiveKeys.price .. '?',
                    centered = true,
                    cancel = true
                }) == "confirm"
                
                if input then
                    if fw.gm('cash') < Config.GiveKeys.price then destroyPreview() return utils.notify('Você não possui dinheiro suficiente na carteira.', 'error') end
                    
                    local success = lib.callback.await('vanguard_garage:cb_server:removeMoney', false, 'cash', Config.GiveKeys.price)
                    if success then
                        exports.mri_Qcarkeys:GiveKeyItem(data.plate, data.entity)
                    end
                end
                destroyPreview()
            end
        }
    end
    
    utils.createMenu(actionData)
end

--- Get available spawn point
---@param points table
---@param ignoreDist boolean?
---@param defaultCoords vector4?
---@return vector4?
local function getAvailableSP(points, ignoreDist, defaultCoords)
    if not points then return defaultCoords end
    if type(points) == "vector4" then return points end
    if type(points) ~= "table" then return points end
    if not points[1] and points.x then
        return vec4(points.x, points.y, points.z, points.w or points.h or 0.0)
    end

    for i = 1, #points do
        local v = points[i]
        local sp = vec4(v.x, v.y, v.z, v.w or v.h or 0.0)
        local vehEntity = lib.getClosestVehicle(sp.xyz, 2.5, true)
        if not vehEntity then
            return sp
        end
    end

    -- Se todas as vagas configuradas estiverem ocupadas, retorna nil para impedir colisão
    return nil
end

local function listAddedVehicles(data, menuData)
    for i = 1, #data.vehicles do
        local v = data.vehicles[i]
        local vehModel = v
        local vehName = GetLabelText(GetDisplayNameFromVehicleModel(v))
        
        
        menuData.options[#menuData.options + 1] = {
            title = vehName,
            icon = 'car',
            iconColor = 'white',
            onSelect = function()
                local defaultcoords = vec(GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.0, 0.5), GetEntityHeading(cache.ped) + 90)
                
                if data.spawnpoint then
                    defaultcoords = getAvailableSP(data.spawnpoint, data.ignoreDist, defaultcoords)
                end
                
                if not defaultcoords then
                    return utils.notify(locale('notify.error.no_parking_spot'), 'error', 8000)
                end
                
                local vehInArea = lib.getClosestVehicle(defaultcoords.xyz)
                if DoesEntityExist(vehInArea) then return utils.notify(locale('notify.error.no_parking_spot'), 'error') end
                
                VehicleShow = utils.createPreviewVeh(vehModel, defaultcoords)
                FreezeEntityPosition(VehicleShow, true)
                SetVehicleDoorsLocked(VehicleShow, 2)
                utils.createPreviewCam(VehicleShow)
                
                -- Barra de progresso customizada Vanguard (7 segundos total)
                utils.vanguardProgress('Retirando veículo...', 7000)
                actionMenu({
                    prop = nil,
                    engine = 1000,
                    fuel = 100,
                    body = 1000,
                    model = vehModel,
                    plate = nil,
                    coords = defaultcoords,
                    garage = data.garage,
                    vehName = vehName,
                    vehicle_name = nil,
                    impound = data.impound,
                    shared = data.shared,
                    deformation = nil,
                    depotprice = nil,
                    entity = VehicleShow
                })
            end,
        }
    end
    
    return menuData
end

--- Open Garage Otimizado
---@param data GarageVehicleData
local function openMenu(data)
    if LocalPlayer.state.garageBusy then 
        return utils.notify('A garagem está em uso. Aguarde.', 'error')
    end
    
    if type(data.type) == "string" then
        data.type = { data.type }
    elseif type(data.type) ~= "table" then
        data.type = { "car", "motorcycle", "cycles" }
    end
    
    local vehData = lib.callback.await('vanguard_garage:cb_server:getVehicleList', false, data.garage, data.impound, data.shared)
    
    if type(vehData) == "table" and vehData.error then
        return utils.notify(vehData.error, 'error')
    end

    if not vehData or #vehData == 0 then 
        local msg = locale('notify.error.no_vehicles') or "Você não possui nenhum veículo nesta garagem."
        return utils.notify(msg, 'error')
    end
    
    local curPedCoords = GetEntityCoords(cache.ped)
    local allNearby = GetGamePool('CVehicle')

    local formattedVehicles = {}
    for i = 1, #vehData do
        local vd = vehData[i]
        local vehModel = vd.model
        local plate = utils.string.trim(vd.plate or "")
        local gState = vd.state
        local vehName = vd.name or vd.vehicle_name or fw.gvn(vehModel)
        
        local vehicleClass = GetVehicleClassFromName(vehModel)
        local vehicleType = utils.getCategoryByClass(vehicleClass)

        -- Veículo de Trabalho (Viaturas / Empregos)
        if vd.isWork then
            formattedVehicles[#formattedVehicles + 1] = {
                name = vehName or string.upper(vehModel),
                model = vehModel,
                plate = "SERVIÇO",
                fuel = 100,
                engine = 1000,
                body = 1000,
                state = 1,
                state_text = "Disponível para Serviço",
                last_out = 0,
                garage = data.garage,
                price = 0,
                isWork = true,
                isNearby = false,
                canStore = false
            }
        else
            -- Camada de Segurança: Se estiver no Detran e o carro estiver num raio de 200m, oculta da lista
            if data.impound and gState == 0 then
                local isNear = false
                for _, veh in ipairs(allNearby) do
                    local nearPlate = utils.getPlate(veh)
                    if nearPlate == plate then
                        isNear = true
                        break
                    end
                end

                if isNear then
                    goto next_vehicle
                end
            end

            local matchesType = false
            if not data.type or #data.type == 0 then
                matchesType = true
            else
                for _, t in ipairs(data.type) do
                    if t == vehicleType or t == "all" then
                        matchesType = true
                        break
                    end
                end
            end

            if matchesType then
                local engine = vd.engine or 1000
                local body = vd.body or 1000
                local stateText = "Na Garagem"
                
                if engine <= 0 and body <= 0 then
                    stateText = "Quebrado"
                elseif gState == 0 then 
                    stateText = "Fora da Garagem"
                elseif gState == 2 then 
                    stateText = "Apreendido"
                elseif gState == 3 then 
                    stateText = "Destruído" 
                end

                -- Verifica se este veículo está por perto (raio de 60 metros) ou se o player está dentro dele
                local isNearby = false
                if cache.vehicle and utils.getPlate(cache.vehicle) == plate then
                    isNearby = true
                else
                    for _, cVeh in ipairs(allNearby) do
                        if DoesEntityExist(cVeh) and #(GetEntityCoords(cVeh) - curPedCoords) <= 60.0 then
                            local p = utils.getPlate(cVeh)
                            if p and p == plate then
                                isNearby = true
                                break
                            end
                        end
                    end
                end

                -- Cálculo de Preço para Pátio/Detran
                local price = 0
                if data.impound then
                    price = Config.ImpoundPrice[vehicleClass] or 5000
                end

                formattedVehicles[#formattedVehicles + 1] = {
                    name = vehName,
                    model = vehModel,
                    plate = plate,
                    fuel = vd.fuel or 100,
                    engine = vd.engine or 1000,
                    body = vd.body or 1000,
                    state = gState,
                    state_text = stateText,
                    last_out = vd.last_out or 0,
                    garage = data.garage,
                    price = price,
                    isWork = false,
                    isNearby = isNearby,
                    canStore = isNearby or (cache.vehicle ~= nil and cache.vehicle ~= 0)
                }
            end
        end
        ::next_vehicle::
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "open",
        vehicles = formattedVehicles,
        garage = data.garage,
        isImpound = data.impound
    })
end

RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('storeSelectedVehicle', function(data, cb)
    SetNuiFocus(false, false)
    if cb then cb('ok') end

    local targetPlate = data.plate and utils.string.trim(data.plate)
    local garage = data.garage
    local vehToStore = nil

    -- 1. Se o player estiver dentro do veículo e a placa bater
    if cache.vehicle then
        local curPlate = utils.getPlate(cache.vehicle)
        if not targetPlate or curPlate == targetPlate then
            vehToStore = cache.vehicle
        end
    end

    -- 2. Se não estiver no veículo, procura nas proximidades (raio de 60 metros)
    if not vehToStore then
        local pCoords = GetEntityCoords(cache.ped)
        local vehicles = GetGamePool('CVehicle')
        local closestDist = 60.0

        for _, v in ipairs(vehicles) do
            if DoesEntityExist(v) then
                local dist = #(GetEntityCoords(v) - pCoords)
                if dist <= closestDist then
                    local p = utils.getPlate(v)
                    if p and targetPlate and p == targetPlate then
                        vehToStore = v
                        break
                    end
                end
            end
        end
    end

    -- 3. Fallback: veículo mais próximo até 25 metros
    if not vehToStore and not targetPlate then
        local closestVeh = lib.getClosestVehicle(GetEntityCoords(cache.ped), 25.0, true)
        if closestVeh and DoesEntityExist(closestVeh) then
            vehToStore = closestVeh
        end
    end

    if not vehToStore or not DoesEntityExist(vehToStore) then
        return utils.notify(locale('notify.error.no_vehicle_near') or "O veículo selecionado não está próximo da garagem para ser guardado.", "error", 6000)
    end

    local function canStoreOccupantsAndSpeed(veh)
        local speed = GetEntitySpeed(veh)
        if speed > 0.8 then
            utils.notify("O veículo precisa estar parado para ser guardado.", "error", 6000)
            return false
        end

        local maxSeats = GetVehicleMaxNumberOfPassengers(veh)
        for seat = -1, maxSeats - 1 do
            local occ = GetPedInVehicleSeat(veh, seat)
            if occ ~= 0 and DoesEntityExist(occ) and IsPedAPlayer(occ) then
                if IsEntityDead(occ) then
                    utils.notify("Não é possível guardar o veículo com passageiros desacordados.", "error", 6000)
                    return false
                end
                local occState = Entity(occ).state
                if occState and (occState.isHandcuffed or occState.isDead or occState.inLastStand) then
                    utils.notify("Não é possível guardar o veículo com passageiros algemados ou desacordados.", "error", 6000)
                    return false
                end
            end
        end

        for seat = -1, maxSeats - 1 do
            local occ = GetPedInVehicleSeat(veh, seat)
            if occ ~= 0 and DoesEntityExist(occ) then
                TaskLeaveAnyVehicle(occ, true, 0)
            end
        end
        Wait(600)
        return true
    end

    if not canStoreOccupantsAndSpeed(vehToStore) then
        return
    end

    utils.vanguardProgress('Estacionando veículo...', 2000)

    local netId = NetworkGetNetworkIdFromEntity(vehToStore)
    local deformation = Deformation.get(vehToStore)
    local props = lib.getVehicleProperties(vehToStore) or {}
    local healthData = {
        body = math.floor(GetVehicleBodyHealth(vehToStore) + 0.5),
        engine = math.floor(GetVehicleEngineHealth(vehToStore) + 0.5),
        fuel = math.floor(utils.getFuel(vehToStore) or 100)
    }
    props.bodyHealth = healthData.body
    props.engineHealth = healthData.engine
    props.fuelLevel = healthData.fuel

    local success, message = lib.callback.await('vanguard_garage:server:storeVehicle', false, netId, garage, deformation, props, healthData)
    if success then
        utils.notify(message or "Veículo guardado na garagem com sucesso!", "success", 6000)
    else
        utils.notify(message or "Erro ao guardar veículo.", "error", 6000)
    end
end)

RegisterNUICallback('takeOutVehicle', function(data, cb)
    local garageData = GarageZone[data.garage]
    local isImpound = garageData and garageData.impound

    -- ETAPA 1: Verificação de Vagas de Spawn (Prevenção de Colisão e Engavetamento)
    local pedHeading = GetEntityHeading(cache.ped)
    local worlcoords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.0, 0.5)
    local defaultcoords = vec(worlcoords, pedHeading + 90)
    local spList = (garageData and (garageData.spawnPoint or garageData.spawnpoint)) or (data and (data.spawnPoint or data.spawnpoint))
    local chosenSpawn = nil

    if spList then
        chosenSpawn = getAvailableSP(spList, false, nil)
    else
        chosenSpawn = defaultcoords
    end

    if not chosenSpawn then
        SetNuiFocus(false, false)
        PlaySoundFrontend(-1, "CHECKPOINT_MISSED", "HUD_MINI_GAME_SOUNDSET", true)
        utils.notify("Todas as vagas de saída estão ocupadas no momento. Aguarde liberarem a saída.", "error", 7000)
        cb('error')
        return
    end

    -- ETAPA 2: Verificação de Cooldown via Servidor com Opção de Rastrear no GPS
    if isImpound then
        local check = lib.callback.await('vanguard_garage:server:checkRecovery', false, data.plate)
        
        if check and not check.allowed then
            SetNuiFocus(false, false)
            local minutes = math.ceil(check.remaining / 60)

            local alert = lib.alertDialog({
                header = 'REGISTRO DE INCIDÊNCIA',
                content = string.format('O veículo está em período de carência do seguro. Restam %s minuto(s).\n\nDeseja rastrear a localização atual do veículo no GPS?', minutes),
                centered = true,
                cancel = true,
                labels = { confirm = 'Rastrear no GPS', cancel = 'Voltar' }
            })

            if alert == 'confirm' then
                local tracked = vehFunc.tvbp(data.plate, data.garage, true)
                if tracked then
                    utils.notify("Localização marcada no seu GPS.", "success", 7000)
                else
                    utils.notify("O veículo não foi detectado no mapa (pode estar submerso ou destruído).", "error", 7000)
                end
            end
            
            cb('ok')
            return
        end
    end

    -- ETAPA 3: Confirmação de Pagamento (Somente se não houver cooldown)
    if isImpound and data.price and data.price > 0 then
        SetNuiFocus(false, false) -- Fecha o NUI para o diálogo de pagamento
        
        local confirmPay = lib.alertDialog({
            header = 'CONFIRMAR RECUPERAÇÃO',
            content = string.format('Deseja pagar a taxa de R$ %s para recuperar o veículo %s (%s)?', lib.math.groupdigits(data.price, '.'), data.name, data.plate),
            centered = true,
            cancel = true,
            labels = { confirm = 'Pagar e Recuperar', cancel = 'Cancelar' }
        })

        if confirmPay ~= 'confirm' then
            cb('cancel')
            return
        end

        -- Tenta remover dinheiro
        local paymentType = "bank"
        if fw.gm('bank') < data.price then paymentType = "cash" end

        if fw.gm(paymentType) < data.price then
            utils.notify("Você não possui dinheiro suficiente.", 'error')
            cb('error')
            return
        end

        local success = lib.callback.await('vanguard_garage:cb_server:removeMoney', false, paymentType, data.price)
        if not success then
            utils.notify("Erro ao processar pagamento.", 'error')
            cb('error')
            return
        end
        utils.notify("Pagamento de R$ " .. data.price .. " realizado!", 'success')
    end

    SetNuiFocus(false, false)

    local isWork = data.isWork or (garageData and garageData.isWork) or (data.plate == "SERVIÇO")

    -- ETAPA 4: Spawn do Veículo
    if garageData and Config.Showrooms.Config.Enable and not isImpound and not isWork then
        exports.vanguard_garage:openShowRoom({
            garage = data.garage,
            plate = data.plate
        })
    else
        spawnvehicle({
            plate = data.plate,
            garage = data.garage,
            coords = chosenSpawn,
            model = data.model,
            name = data.name,
            isWork = isWork
        })
    end
    cb('ok')
end)

--- Store Vehicle To Garage
---@param data GarageVehicleData
local function storeVeh(data)
    local myCoords = GetEntityCoords(cache.ped)
    local vehicle = cache.vehicle or lib.getClosestVehicle(myCoords, 15.0, true)
    
    if not vehicle or not DoesEntityExist(vehicle) then
        return utils.notify(locale('notify.error.not_veh_exist'), 'error')
    end

    local vehicleClass = GetVehicleClass(vehicle)
    local vehicleType = utils.getCategoryByClass(vehicleClass)
    
    if not lib.table.contains(data.type, vehicleType) then
        return utils.notify(locale('notify.info.invalid_veh_classs', data.garage))
    end

    if data.impound then
        return utils.notify("Você não pode guardar veículos no pátio.", 'error')
    end

    local speed = GetEntitySpeed(vehicle)
    if speed > 0.8 then
        return utils.notify("O veículo precisa estar parado para ser guardado.", "error", 6000)
    end

    local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = -1, maxSeats - 1 do
        local occ = GetPedInVehicleSeat(vehicle, seat)
        if occ ~= 0 and DoesEntityExist(occ) and IsPedAPlayer(occ) then
            if IsEntityDead(occ) then
                return utils.notify("Não é possível guardar o veículo com passageiros desacordados.", "error", 6000)
            end
            local occState = Entity(occ).state
            if occState and (occState.isHandcuffed or occState.isDead or occState.inLastStand) then
                return utils.notify("Não é possível guardar o veículo com passageiros algemados ou desacordados.", "error", 6000)
            end
        end
    end

    for seat = -1, maxSeats - 1 do
        local occ = GetPedInVehicleSeat(vehicle, seat)
        if occ ~= 0 and DoesEntityExist(occ) then
            TaskLeaveAnyVehicle(occ, true, 0)
        end
    end
    Wait(600)

    utils.vanguardProgress('Estacionando veículo...', 2000)

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local deformation = Deformation.get(vehicle)
    local props = lib.getVehicleProperties(vehicle) or {}
    local healthData = {
        body = math.floor(GetVehicleBodyHealth(vehicle) + 0.5),
        engine = math.floor(GetVehicleEngineHealth(vehicle) + 0.5),
        fuel = math.floor(utils.getFuel(vehicle) or 100)
    }
    props.bodyHealth = healthData.body
    props.engineHealth = healthData.engine
    props.fuelLevel = healthData.fuel

    local success, message = lib.callback.await('vanguard_garage:server:storeVehicle', false, netId, data.garage, deformation, props, healthData)
    if success then
        utils.notify(message or locale('notify.success.store_veh'), 'success')
    else
        utils.notify(message or "Erro ao guardar veículo.", 'error')
    end
end

-- Monitoramento Otimizado de Veículos com StateBags e Sleep Dinâmico
CreateThread(function()
    local trackedVehicles = {} -- Cache local de veículos monitorados
    local lastCheck = 0
    local reportedPlates = {} -- Track reported plates locally to prevent duplicate reports
    
    while true do
        -- Sleep dinâmico: 5000ms quando não está em veículo, 2000ms quando está
        local sleepTime = cache.vehicle and 2000 or 5000
        Wait(sleepTime)
        
        local ped = cache.ped
        local playerCoords = GetEntityCoords(ped)
        
        -- Atualiza veículo atual do jogador
        if cache.vehicle and DoesEntityExist(cache.vehicle) then
            local plate = utils.getPlate(cache.vehicle)
            if plate then
                trackedVehicles[plate] = {
                    entity = cache.vehicle,
                    lastCheck = GetGameTimer()
                }
            end
        end
        
        -- Limpa veículos rastreados há mais de 30s (otimização de memória)
        local currentTime = GetGameTimer()
        for plate, data in pairs(trackedVehicles) do
            if currentTime - data.lastCheck > 30000 then
                trackedVehicles[plate] = nil
                reportedPlates[plate] = nil -- Also clear reported status
                goto continue_cleanup
            end
            
            local veh = data.entity
            if not DoesEntityExist(veh) then
                trackedVehicles[plate] = nil
                reportedPlates[plate] = nil -- Clean up reported status
                goto continue_cleanup
            end
            
            local vehCoords = GetEntityCoords(veh)
            local dist = #(playerCoords - vehCoords)
            
            -- Só verifica veículos dentro de 150m (reduzido de 200m)
            if dist < 150.0 then
                local engine = GetVehicleEngineHealth(veh)
                local submerged = IsEntityInWater(veh)
                local dead = IsEntityDead(veh)
                
                -- Condição de destruição: submerso OU morto OU motor explodido (< -500)
                if (submerged or dead or engine < -500) then
                    -- Usa cache local + StateBag para reduzir network calls
                    if not reportedPlates[plate] and not Entity(veh).state.destroyReported then
                        reportedPlates[plate] = true -- Mark locally immediately
                        Entity(veh).state:set('destroyReported', true, true)
                        TriggerServerEvent('vanguard_garage:server:destroyVehicle', plate)
                    end
                end
            else
                -- Remove do tracking se afastou mais de 150m
                trackedVehicles[plate] = nil
            end
            
            ::continue_cleanup::
        end
        
        -- Verificação de proximidade apenas quando não está em veículo (10m)
        if not cache.vehicle then
            -- Otimização: só verifica a cada 10s quando a pé
            if currentTime - lastCheck > 10000 then
                lastCheck = currentTime
                local nearbyVeh = lib.getClosestVehicle(playerCoords, 10.0, false)
                if nearbyVeh and DoesEntityExist(nearbyVeh) then
                    local plate = utils.getPlate(nearbyVeh)
                    if plate and not trackedVehicles[plate] and not reportedPlates[plate] then
                        local engine = GetVehicleEngineHealth(nearbyVeh)
                        if IsEntityDead(nearbyVeh) or IsEntityInWater(nearbyVeh) or engine < -500 then
                            if not Entity(nearbyVeh).state.destroyReported then
                                reportedPlates[plate] = true -- Mark locally immediately
                                Entity(nearbyVeh).state:set('destroyReported', true, true)
                                TriggerServerEvent('vanguard_garage:server:destroyVehicle', plate)
                            end
                        end
                    end
                end
            end
        end
    end
end)

--- exports
exports('openMenu', openMenu)
exports('storeVehicle', storeVeh)

RegisterNetEvent('vanguard_garage:client:takeOutFromShowroom', function(plate, coords)
    local vehData = lib.callback.await('vanguard_garage:cb_server:getvehiclePropByPlate', false, plate)
    if vehData then
        -- Correção para Garagem Nível 2: Se a rotação for diagonal (ex: 335º), 
        -- arredonda para o ângulo reto mais próximo para evitar spawn bugado no mundo.
        local cleanCoords = coords
        if coords and coords.w then
            local h = coords.w
            -- Arredonda para 0, 90, 180, 270 ou 360
            local roundedHeading = math.floor((h + 45) / 90) * 90
            cleanCoords = vec4(coords.x, coords.y, coords.z, roundedHeading + 0.0)
        end

        spawnvehicle({
            model = vehData.model,
            plate = plate,
            coords = cleanCoords,
            garage = vehData.garage
        })
    end
end)

-- Evento de compatibilidade para scripts legados (desmanche, etc.)
RegisterNetEvent("garages:Delete", function(veh)
    if DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end
end)
