print("^5[rhd_garage] ^7Showroom iniciado.")

local isInShowRoom = false
local createdVehiclesInShowroom = {}
local vehicleDataCache = {}
local playerCoordsBefore = nil
local garageBeforeShowroom = nil
local currentShowroomType = nil
local showroomExitPoint = nil

local function fadeInEntity(entity)
    SetEntityAlpha(entity, 0, false)
    for i = 0, 255, 51 do
        SetEntityAlpha(entity, i, false)
        Wait(50)
    end
    SetEntityAlpha(entity, 255, false)
end

-- DUI Management & Render Thread
CreateThread(function()
    while true do
        local sleep = 1000
        if isInShowRoom and #createdVehiclesInShowroom > 0 then
            sleep = 0
            local playerPed = cache.ped
            local playerCoords = GetEntityCoords(playerPed)

            -- Safety check for ShowroomDUI existence
            if _G.ShowroomDUI then
                for i = 1, #createdVehiclesInShowroom do
                    local vehicle = createdVehiclesInShowroom[i]
                    if DoesEntityExist(vehicle) then
                        local vehCoords = GetEntityCoords(vehicle)
                        local distanceToPlayer = #(playerCoords - vehCoords)
                        
                        -- Smart DUI Creation/Destruction
                        if distanceToPlayer < 8.0 then
                            local data = vehicleDataCache[vehicle]
                            if data then
                                ShowroomDUI.Create(vehicle, data)
                                
                                local min, max = GetModelDimensions(GetEntityModel(vehicle))
                                local roofWorld = vector3(vehCoords.x, vehCoords.y, vehCoords.z + max.z + 0.9)
                                
                                -- Render the card
                                ShowroomDUI.Render(vehicle, roofWorld)
                            end
                        elseif distanceToPlayer > 12.0 then
                            ShowroomDUI.DestroyVehicleDUI(vehicle)
                        end
                    end
                end
            else
                sleep = 500 -- Wait for DUI handler to load if missing
            end
        end
        Wait(sleep)
    end
end)

local function spawnVehInShowRoom(vehicleData, coords)
    local mods = vehicleData.mods or vehicleData.vehicle
    local model = vehicleData.hash or vehicleData.model
    local modelHash = tonumber(model) or joaat(model)
    
    lib.requestModel(modelHash, 15000)
    
    local vehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, coords.w, false, false)
    SetEntityAlpha(vehicle, 0, false)
    
    if mods then
        local decodedMods = type(mods) == "string" and json.decode(mods) or mods
        if decodedMods then
            vehFunc.svp(vehicle, decodedMods)
        end
    end
    
    SetEntityHeading(vehicle, coords.w)
    SetVehicleOnGroundProperly(vehicle)
    SetEntityInvincible(vehicle, true)
    SetVehicleDoorsLocked(vehicle, 1) -- Destrancado
    
    fadeInEntity(vehicle)
    
    -- Prepare data for DUI
    local data = {
        plate = vehicleData.plate,
        label = vehicleData.vehicle_name or fw.gvn(modelHash),
        fuel = vehicleData.fuel or 100,
        engine = vehicleData.engine or 1000,
        body = vehicleData.body or 1000
    }
    
    vehicleDataCache[vehicle] = data
    table.insert(createdVehiclesInShowroom, vehicle)
end

function leaveShowRoom(plateToTakeOut)
    DoScreenFadeOut(400)
    Wait(1000)
    
    isInShowRoom = false
    
    -- Cleanup DUIs
    if _G.ShowroomDUI then
        ShowroomDUI.Cleanup()
    end
    
    for _, vehicle in pairs(createdVehiclesInShowroom) do
        if DoesEntityExist(vehicle) then
            DeleteVehicle(vehicle)
        end
    end
    createdVehiclesInShowroom = {}
    vehicleDataCache = {}
    
    TriggerServerEvent("rhd_garage:server:soloSessionLeave")
    
    if showroomExitPoint then
        showroomExitPoint:remove()
        showroomExitPoint = nil
    end
    
    local returnCoords = playerCoordsBefore
    if plateToTakeOut and returnCoords then
        SetEntityCoords(cache.ped, returnCoords.xyz)
        SetEntityHeading(cache.ped, returnCoords.w)
        TriggerEvent('rhd_garage:client:takeOutFromShowroom', plateToTakeOut, returnCoords)
    elseif returnCoords then
        SetEntityCoords(cache.ped, returnCoords.xyz)
        SetEntityHeading(cache.ped, returnCoords.w)
    end
    
    Wait(1000)
    DoScreenFadeIn(400)
end

function openShowRoom(data)
    if not Config.Showrooms then return end
    
    local level = lib.callback.await('rhd_garage:server:getGarageLevel', false) or 1
    local levelConfig = Config.GarageLevels[level]
    if not levelConfig then level = 1 levelConfig = Config.GarageLevels[1] end
    
    currentShowroomType = levelConfig.showroom
    
    garageBeforeShowroom = data.garage
    
    DoScreenFadeOut(400)
    Wait(1000)
    
    TriggerServerEvent("rhd_garage:server:soloSession")
    
    -- Load level-specific IPLs
    if level == 1 or level == 2 then
        RequestIpl("v_garages")
    elseif level == 3 then
        RequestIpl("vw_casino_garage")
        RequestIpl("sm_smugdlc_interior_priority")
    end
    
    Wait(1500)
    
    local ped = cache.ped
    playerCoordsBefore = vec4(GetEntityCoords(ped), GetEntityHeading(ped))
    
    local showroom = Config.Showrooms[currentShowroomType]
    local spawnPos = showroom.EntranceCoords
    
    SetEntityCoords(ped, spawnPos.xyz)
    SetEntityHeading(ped, spawnPos.w)
    
    showroomExitPoint = lib.points.new({
        coords = spawnPos.xyz,
        distance = 3,
    })
    
    function showroomExitPoint:onEnter()
        lib.showTextUI('[E] - Sair do Showroom', {position = "left-center"})
    end
    
    function showroomExitPoint:onExit()
        lib.hideTextUI()
    end
    
    function showroomExitPoint:nearby()
        if IsControlJustPressed(0, 38) then
            leaveShowRoom()
        end
    end
    
    local vehList = lib.callback.await('rhd_garage:cb_server:getVehicleList', false, data.garage, false, data.shared)
    
    local vehiclesToDisplay = {}
    if vehList then
        for i=1, #vehList do
            if vehList[i].state == 1 then
                table.insert(vehiclesToDisplay, vehList[i])
            end
        end
    end
    
    local maxSlots = #showroom.ParkingSlots
    local count = math.min(maxSlots, #vehiclesToDisplay)
    
    isInShowRoom = true
    DoScreenFadeIn(400)
    
    for i=1, count do
        spawnVehInShowRoom(vehiclesToDisplay[i], showroom.ParkingSlots[i].Coords)
    end
    
    utils.notify("Pressione 'W' dentro de um veículo para retirá-lo.", "info")
end

RegisterCommand("takeveh_showroom", function()
    if isInShowRoom and cache.vehicle then
        local plate = utils.getPlate(cache.vehicle)
        leaveShowRoom(plate)
    end
end)
RegisterKeyMapping("takeveh_showroom", "Retirar Veículo do Showroom", "KEYBOARD", "W")

exports('openShowRoom', openShowRoom)
