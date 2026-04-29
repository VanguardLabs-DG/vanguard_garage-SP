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
        
        if data.plate then
            local callbackData = lib.callback.await('vanguard_garage:cb_server:getvehiclePropByPlate', false, data.plate)
            if not callbackData then
                error('Failed to load vehicle data with number plate ' .. data.plate)
            end
            for key, value in pairs(callbackData) do
                vehData[key] = value
            end
        end

        local vehEntity
        utils.createPlyVeh(vehData.model, data.coords, function(veh) vehEntity = veh end, true, vehData.mods)
        
        SetVehicleOnGroundProperly(vehEntity)

        if (not vehData.mods or json.encode(vehData.mods) == "[]") and
            (not data.prop or json.encode(data.prop) == "[]") and
            data.plate then
            SetVehicleNumberPlateText(vehEntity, data.plate)
            TriggerEvent("vehiclekeys:client:SetOwner", data.plate)
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

        SetVehicleEngineHealth(vehEntity, (engineHealth) + 0.0)
        SetVehicleBodyHealth(vehEntity, (bodyHealth) + 0.0)
        utils.setFuel(vehEntity, vehData.fuel or 100)
        
        if deformationData then
            Deformation.set(vehEntity, deformationData)
        end

        local timeout = 500 -- 5 segundos de timeout
        while vehEntity == nil and timeout > 0 do 
            Wait(10) 
            timeout = timeout - 1
        end

        if not vehEntity then 
            error('Falha ao criar entidade do veículo ou spawn cancelado.')
        end

        Entity(vehEntity).state:set('vehlabel', vehData.vehicle_name or data.vehicle_name)
        
        TriggerServerEvent("vanguard_garage:server:updateState", {
            plate = vehData.plate or data.plate,
            state = 0,
            garage = vehData.garage or data.garage,
            engine = engineHealth,
            body = bodyHealth
        })

        if GetResourceState('mri_Qcarkeys') == 'started' and Config.GiveKeys.onspawn then
            local plate = vehData.plate or data.plate
            if not exports.mri_Qcarkeys:HavePermanentKey(plate) then
                exports.mri_Qcarkeys:GiveKeyItem(plate)
            end
        end

        if Config.GiveKeys.tempkeys then
            TriggerEvent("vehiclekeys:client:SetOwner", (vehData.plate or data.plate):trim())
        end

        if not data.plate then
            local plate = GetVehicleNumberPlateText(vehEntity)
            TriggerEvent("vehiclekeys:client:SetOwner", plate)
        end

        -- Colocar o jogador dentro do carro IMEDIATAMENTE (durante o blackout)
        if Config.SpawnInVehicle then
            TaskWarpPedIntoVehicle(cache.ped, vehEntity, -1)
        end

        -- Ligar o carro e faróis (Farol alto para impacto visual) - AGORA COM O PLAYER DENTRO
        SetVehicleNeedsToBeHotwired(vehEntity, false)
        SetVehicleEngineOn(vehEntity, true, true, false)
        SetVehicleLights(vehEntity, 2) -- Ligar faróis
        SetVehicleFullbeam(vehEntity, true) -- Farol alto para o cinematic ficar mais bonito

        -- HIJACK mri_Qcarkeys: Forçar chave no contato e motor ligado
        if GetResourceState('mri_Qcarkeys') == 'started' then
            local plate = GetVehicleNumberPlateText(vehEntity)
            Entity(vehEntity).state:set('keysIn', true, true) -- Chave no contato
            TriggerEvent('mm_carkeys:client:addtempkeys', plate) -- Adiciona como chave ativa
            TriggerServerEvent('mm_carkeys:server:removevehiclekeys', plate) -- Remove do inventário (está no carro)
            SetVehicleEngineOn(vehEntity, true, true, false)
        end

        -- Criar a câmera cinematográfica (ela mesma cuidará do primeiro FadeIn)
        utils.createPreviewCam(vehEntity, true)

        -- Barra de progresso sincronizada com os 3 takes (7 segundos total)
        lib.progressCircle({
            duration = 7000,
            position = 'bottom',
            label = 'Retirando veículo...',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true, mouse = true }
        })

        -- Garantir motor e luzes ligadas para o controle do player
        SetVehicleEngineOn(vehEntity, true, true, false)
        SetVehicleLights(vehEntity, 2)

        -- Finaliza a câmera e volta para o jogador
        utils.destroyPreviewCam(vehEntity, Config.SpawnInVehicle)
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
    if type(points) ~= "table" and ignoreDist then
        return points
    end
    assert(
        type(points) == "table" and points[1], 'Invalid "points" parameter: Expected a non-empty array table.'
    )
    for k, v in pairs(points) do
        local sp = vec(v.x, v.y, v.z, v.w)
        local vehEntity = lib.getClosestVehicle(sp.xyz, 2.0, true)
        
        if ignoreDist and not vehEntity then
            return sp
        end
        
        local dist = #(defaultCoords.xyz - sp.xyz)
        if dist < 2.0 and not vehEntity then
            return sp
        end
    end
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
    
    data.type = data.type or "car"
    
    local vehData = lib.callback.await('vanguard_garage:cb_server:getVehicleList', false, data.garage, data.impound, data.shared)
    
    if not vehData or #vehData == 0 then 
        return utils.notify(locale('notify.error.no_vehicles'), 'error')
    end
    
    local formattedVehicles = {}
    for i = 1, #vehData do
        local vd = vehData[i]
        local vehModel = vd.model
        local plate = utils.string.trim(vd.plate)
        local gState = vd.state
        local vehName = vd.vehicle_name or fw.gvn(vehModel)
        
        local vehicleClass = GetVehicleClassFromName(vehModel)
        local vehicleType = utils.getCategoryByClass(vehicleClass)

        -- Camada de Segurança: Se estiver no Detran e o carro estiver num raio de 200m, oculta da lista
        if data.impound and gState == 0 then
            local vehiclesNear = GetGamePool('CVehicle')
            local isNear = false
            local playerPos = GetEntityCoords(cache.ped)
            
            for _, veh in ipairs(vehiclesNear) do
                if #(GetEntityCoords(veh) - playerPos) < 200.0 then
                    local nearPlate = utils.getPlate(veh)
                    if nearPlate == plate then
                        isNear = true
                        break
                    end
                end
            end

            if isNear then
                goto next_vehicle
            end
        end

        if lib.table.contains(data.type, vehicleType) then
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
                price = price
            }
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

RegisterNUICallback('takeOutVehicle', function(data, cb)
    local garageData = GarageZone[data.garage]
    local isImpound = garageData and garageData.impound

    -- ETAPA 1: Verificação de Cooldown via Servidor (RP - GRATUITO)
    if isImpound then
        local check = lib.callback.await('vanguard_garage:server:checkRecovery', false, data.plate)
        
        if check and not check.allowed then
            SetNuiFocus(false, false)
            local minutes = math.ceil(check.remaining / 60)

            local alert = lib.alertDialog({
                header = 'REGISTRO DE INCIDÊNCIA',
                content = 'Este veículo não está no pátio no momento. Deseja registrar uma queixa de perda ou roubo para que o seguro inicie as buscas?',
                centered = true,
                cancel = true,
                labels = { confirm = 'Registrar Queixa', cancel = 'Voltar' }
            })

            if alert == 'confirm' then
                utils.notify("Queixa registrada. O seguro está investigando. Volte em " .. minutes .. " minutos.", "info", 10000)
            end
            
            cb('ok')
            return
        end
    end

    -- ETAPA 2: Confirmação de Pagamento (Somente se não houver cooldown)
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

    -- ETAPA 3: Spawn do Veículo
    if garageData and Config.Showrooms.Config.Enable and not isImpound then
        exports.vanguard_garage:openShowRoom({
            garage = data.garage,
            plate = data.plate
        })
    else
        local pedHeading = GetEntityHeading(cache.ped)
        local worlcoords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.0, 0.5)
        local defaultcoords = vec(worlcoords, pedHeading + 90)
        
        if garageData and garageData.spawnpoint then
            defaultcoords = getAvailableSP(garageData.spawnpoint, false, defaultcoords)
        end

        spawnvehicle({
            plate = data.plate,
            garage = data.garage,
            coords = defaultcoords,
            model = data.model,
            name = data.name
        })
    end
    cb('ok')
end)

--- Store Vehicle To Garage
---@param data GarageVehicleData
local function storeVeh(data)
    local myCoords = GetEntityCoords(cache.ped)
    local vehicle = cache.vehicle or lib.getClosestVehicle(myCoords)
    
    local vehicleClass = GetVehicleClass(vehicle)
    local vehicleType = utils.getCategoryByClass(vehicleClass)
    
    if not vehicle then return
        utils.notify(locale('notify.error.not_veh_exist'), 'error')
    end
    
    if not lib.table.contains(data.type, vehicleType) then return
        utils.notify(locale('notify.info.invalid_veh_classs', data.garage))
    end

    if data.impound then return
        utils.notify("Você não pode guardar veículos no pátio.", 'error')
    end
    
    local prop = vehFunc.gvp(vehicle)
    local plate = prop and utils.string.trim(prop.plate) or data.plate
    local shared = data.shared
    local deformation = Deformation.get(vehicle)
    local fuel = utils.getFuel(vehicle)
    local engine = GetVehicleEngineHealth(vehicle)
    local body = GetVehicleBodyHealth(vehicle)
    local model = prop.model
    
    local isOwned = lib.callback.await('vanguard_garage:cb_server:getvehowner', false, plate, shared, {
        mods = prop,
        deformation = deformation,
        fuel = fuel,
        engine = engine,
        body = body,
        vehicle_name = Entity(vehicle).state.vehlabel
    })
    
    if type(isOwned) == "table" and isOwned.error then
        return utils.notify(isOwned.error, 'error', 10000)
    end
    
    if not isOwned and not data.vehicles then return
        utils.notify(locale('notify.error.not_owned'), 'error')
    end
    if isOwned and data.vehicles then return
        utils.notify(locale('notify.error.is_service_garage'), 'error')
    end

    if cache.vehicle and cache.seat == -1 then
        TaskLeaveAnyVehicle(cache.ped, true, 0)
        Wait(1000)
    end
    if DoesEntityExist(vehicle) then
        if GetResourceState('mri_Qcarkeys') == 'started' and Config.GiveKeys.onspawn then
            exports.mri_Qcarkeys:RemoveKeyItem(plate)
        end
        
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        local veh = NetworkGetEntityFromNetworkId(netId)
        SetNetworkIdCanMigrate(netId, true)
        if veh and DoesEntityExist(veh) then
            SetEntityAsMissionEntity(veh, true, true)
            DeleteVehicle(veh)
        end
        
        if vehicle and DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
        
        TriggerServerEvent('vanguard_garage:server:updateState', {plate = plate, state = 1, garage = data.garage})
        utils.notify(locale('notify.success.store_veh'), 'success')
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
                
                -- Condição de destruição: submerso OU morto OU motor <= 0
                if (submerged or dead or engine <= 0) then
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
                        if IsEntityDead(nearbyVeh) or IsEntityInWater(nearbyVeh) or engine <= 0 then
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
