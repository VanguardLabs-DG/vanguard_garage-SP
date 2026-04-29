utils = {}
utils.string = {}

local server = IsDuplicityVersion()

---@param rot vector3
local RotationToDirection = function(rot)
    local rotZ = math.rad(rot.z)
    local rotX = math.rad(rot.x)
    local cosOfRotX = math.abs(math.cos(rotX))
    return vector3(-math.sin(rotZ) * cosOfRotX, math.cos(rotZ) * cosOfRotX, math.sin(rotX))
end

function utils.string.trim(s)
    if not s or type(s) ~= 'string' then return end
    local trimmed = s:gsub('^%s*(.-)%s*$', '%1')
    return trimmed
end

function utils.string.isEmpty(s)
    return s:match("^%s*$")
end

function utils.raycastCam(distance)
    local camRot = GetGameplayCamRot()
    local camPos = GetGameplayCamCoord()
    local dir = RotationToDirection(camRot)
    local dest = camPos + (dir * distance)
    local ray = StartShapeTestRay(camPos, dest, 17, -1, 0)
    local _, hit, endPos = GetShapeTestResult(ray)
    if hit == 0 then endPos = dest end
    local inwater, watercoords = TestProbeAgainstWater(camPos.x, camPos.y, camPos.z, endPos.x, endPos.y, endPos.z)
    return hit, endPos, inwater, watercoords
end

function utils.notify(msg, type, duration)
    lib.notify({
        description = msg,
        type = type,
        duration = duration or 5000
    })
end

function utils.drawtext (type, text, icon)
    if type == 'show' then
        lib.showTextUI(text,{
            position = "right-center",
            icon = icon or '',
            style = {
                borderRadius= 5,
            }
        })
    elseif type == 'hide' then
        lib.hideTextUI()
    end
end

function utils.createMenu( data )
    lib.registerContext(data)
    lib.showContext(data.id)
end

utils.previewCam = nil

function utils.createPreviewCam(vehicle, isWithdraw)
    if not DoesEntityExist(vehicle) then return end

    if not Config.DisableVehicleCamera then
        local vehpos = GetEntityCoords(vehicle)
        local camF = GetGameplayCamFov()

        if isWithdraw then
            -- SEQUÊNCIA FORZA STYLE v8 (ULTRA ESTÁVEL)
            Citizen.CreateThread(function()
                -- Limpeza de segurança: Garante que não haja câmeras órfãs
                if utils.previewCam and DoesCamExist(utils.previewCam) then
                    DestroyCam(utils.previewCam, false)
                end

                local mainCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", false)
                utils.previewCam = mainCam
                
                -- TAKE 1: DIAGONAL FRONTAL DIREITA
                if not DoesEntityExist(vehicle) then return end
                local startPos = GetOffsetFromEntityInWorldCoords(vehicle, 1.8, 3.5, 0.4)
                local endPos = GetOffsetFromEntityInWorldCoords(vehicle, 1.6, 3.6, 0.45)
                
                SetCamCoord(mainCam, startPos.x, startPos.y, startPos.z)
                PointCamAtEntity(mainCam, vehicle, 0.5, 0.8, 0.3, true)
                SetCamFov(mainCam, camF - 18)
                SetCamActive(mainCam, true)
                RenderScriptCams(true, false, 0, false, false)
                
                -- Agora que a câmera está ativa e no lugar, abrimos a imagem
                DoScreenFadeIn(500)

                local driftCam1 = CreateCam("DEFAULT_SCRIPTED_CAMERA", false)
                SetCamCoord(driftCam1, endPos.x, endPos.y, endPos.z)
                PointCamAtEntity(driftCam1, vehicle, 0.5, 0.8, 0.3, true)
                SetCamFov(driftCam1, camF - 18)
                SetCamActiveWithInterp(driftCam1, mainCam, 2000, 1, 1)

                Wait(1800)
                DoScreenFadeOut(300)
                Wait(350)
                if DoesCamExist(mainCam) then DestroyCam(mainCam, false) end
                mainCam = driftCam1

                -- TAKE 2: HERO SHOT (GRADE -> RODA -> LATERAL)
                if not DoesEntityExist(vehicle) then return end
                -- StartPos: Perto da grade/roda
                local sideStart = GetOffsetFromEntityInWorldCoords(vehicle, -1.0, 4.0, -0.4)
                -- EndPos: Mais afastado para dar imponência
                local sideEnd = GetOffsetFromEntityInWorldCoords(vehicle, -2.5, 3.2, -0.45)
                
                SetCamCoord(mainCam, sideStart.x, sideStart.y, sideStart.z)
                -- Mira mais centralizada no carro (-0.5) para ele não sumir da tela
                PointCamAtEntity(mainCam, vehicle, -0.5, -3.0, 0.8, true)
                SetCamFov(mainCam, camF - 18)
                SetCamActive(mainCam, true)
                
                DoScreenFadeIn(400)
                Wait(400)

                local driftCam2 = CreateCam("DEFAULT_SCRIPTED_CAMERA", false)
                SetCamCoord(driftCam2, sideEnd.x, sideEnd.y, sideEnd.z)
                PointCamAtEntity(driftCam2, vehicle, -0.5, -3.0, 0.8, true)
                SetCamFov(driftCam2, camF - 18)
                SetCamActiveWithInterp(driftCam2, mainCam, 2600, 1, 1)

                Wait(2400)
                DoScreenFadeOut(300)
                Wait(350)
                if DoesCamExist(mainCam) then DestroyCam(mainCam, false) end
                mainCam = driftCam2

                -- TAKE 3: TRASEIRA INVERTIDA (DE DENTRO P/ FORA)
                if not DoesEntityExist(vehicle) then return end
                local rearStart = GetOffsetFromEntityInWorldCoords(vehicle, -1.0, -3.0, 0.5)
                local rearEnd = GetOffsetFromEntityInWorldCoords(vehicle, -2.2, -4.2, 0.7)
                
                SetCamCoord(mainCam, rearStart.x, rearStart.y, rearStart.z)
                PointCamAtEntity(mainCam, vehicle, -0.5, -1.0, 0.3, true)
                SetCamFov(mainCam, camF - 15)
                SetCamActive(mainCam, true)
                DoScreenFadeIn(500)

                local driftCam3 = CreateCam("DEFAULT_SCRIPTED_CAMERA", false)
                SetCamCoord(driftCam3, rearEnd.x, rearEnd.y, rearEnd.z)
                PointCamAtEntity(driftCam3, vehicle, -0.5, -1.0, 0.3, true)
                SetCamFov(driftCam3, camF - 15)
                SetCamActiveWithInterp(driftCam3, mainCam, 2000, 1, 1)

                utils.previewCam = driftCam3
            end)
        else
            -- Entrada Cinematográfica (Visão de cima para lateral)
            local endPos = GetOffsetFromEntityInWorldCoords(vehicle, 3.5, 5.0, 1.2)
            local startPos = GetOffsetFromEntityInWorldCoords(vehicle, 4.0, 6.0, 3.0)

            if not utils.previewCam then utils.previewCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", false) end

            SetCamCoord(utils.previewCam, startPos.x, startPos.y, startPos.z)
            PointCamAtCoord(utils.previewCam, vehpos.x, vehpos.y, vehpos.z)
            SetCamActive(utils.previewCam, true)
            RenderScriptCams(true, false, 0, false, false)

            Wait(50)
            local tempCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", false)
            SetCamCoord(tempCam, endPos.x, endPos.y, endPos.z)
            PointCamAtCoord(tempCam, vehpos.x, vehpos.y, vehpos.z + 0.2)
            SetCamFov(tempCam, camF - 10)
            SetCamActiveWithInterp(tempCam, utils.previewCam, 1200, 1, 1)
            
            Citizen.CreateThread(function()
                Wait(1250)
                if DoesCamExist(utils.previewCam) and utils.previewCam ~= tempCam then DestroyCam(utils.previewCam, false) end
                utils.previewCam = tempCam
            end)
        end
    end
end

function utils.destroyPreviewCam(vehicle, enterVehicle)
    if utils.previewCam then
        if enterVehicle then
            DoScreenFadeOut(0)
            Wait(100)
            RenderScriptCams(false, false, 0, false, false)
            DestroyCam(utils.previewCam, false)
            utils.previewCam = nil
            Wait(100)
            DoScreenFadeIn(100)
        else
            RenderScriptCams(false, true, 800, true, true)
            Citizen.CreateThread(function()
                Wait(850)
                if utils.previewCam then
                    DestroyCam(utils.previewCam, false)
                    utils.previewCam = nil
                end
            end)
        end
    end
end

function utils.createTargetPed(model, coords, options)
    local newoptions = {}
    local qbtd = nil --- qb-target distance options
    
    lib.requestModel(model, 150000)
    local ped = CreatePed(0, model, coords.x, coords.y, coords.z - 1, coords.w, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    if type(options) == "table" and #options > 0 then
        for i=1, #options do
            local data = options[i]
            local opt = {
                name = data.name,
                label = data.label,
                icon = data.icon,
            }
            if Config.Target == "ox" then
                opt.groups = data.groups
                opt.distance = data.distance
                opt.onSelect = data.action
            elseif Config.Target == "qb" then
                opt.job = data.groups
                opt.gang = data.groups
                opt.action = data.action
            end
            qbtd = data.distance
            newoptions[#newoptions+1] = opt
        end
    end

    if #newoptions > 0 then
        if Config.Target == "ox" then
            exports.ox_target:addLocalEntity(ped, newoptions)
        elseif Config.Target == "qb" then
            local param = {
                options = newoptions,
                distance = qbtd
            }
            exports['qb-target']:AddTargetEntity(ped, param)
        end
    end

    return ped
end

function utils.removeTargetPed(entity, label)
    if DoesEntityExist(entity) then
        if Config.Target == "ox" then
            exports.ox_target:removeLocalEntity(entity, label)
            DeleteEntity(entity)
        elseif Config.Target == "qb" then
            exports['qb-target']:RemoveTargetEntity(entity, label)
            DeleteEntity(entity)
        end
    end
end

function utils.getColorLevel(level)
    if not level then return end
    return level < 25 and "red" or level >= 25 and level < 50 and  "#E86405" or level >= 50 and level < 75 and "#E8AC05" or level >= 75 and "green"
end

function utils.getPlate ( vehicle )
    if not DoesEntityExist(vehicle) then return end
    local vehPlate = GetVehicleNumberPlateText(vehicle)
    return utils.string.trim(vehPlate)
end

function utils.getCategoryByClass ( vehType )
    local class = {
        [8] = "motorcycle",
        [13] = "cycles",
        [14] = "boat",
        [15] = "helicopter",
        [16] = "planes",
    }
    return class[vehType] or "car"
end


function utils.setFuel(vehicle, fuel)
    Wait(100)
    if Config.FuelScript == "ox_fuel" then
        Entity(vehicle).state.fuel = fuel or 100
    else
        exports[Config.FuelScript]:SetFuel(vehicle, fuel or 100)
    end
end

function utils.getFuel(vehicle)
    local fuelLevel = 0
    if Config.FuelScript == "ox_fuel" then
        fuelLevel = Entity(vehicle).state?.fuel or 100 
    else
        fuelLevel = exports[Config.FuelScript]:GetFuel(vehicle)
    end
    return fuelLevel
end

function utils.createPlyVeh ( model, coords, cb, network, props )
    network = network == nil and false or network
    lib.requestModel(model, 150000)
    local netid = lib.callback.await("vanguard_garage:server:spawnVehicle", false, model, coords, props)
    if not netid then 
        if cb then cb(nil) end
        return 
    end
    local veh = NetworkGetEntityFromNetworkId(netid)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehRadioStation(veh, 'OFF')
    SetModelAsNoLongerNeeded(model)
    if cb then cb(veh) else return veh end
end

function utils.createPreviewVeh ( model, coords, cb, network )
    network = network == nil and true or network
    lib.requestModel(model, 150000)
    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, coords.w, network, false)
    if network then
        local id = NetworkGetNetworkIdFromEntity(veh)
        SetNetworkIdCanMigrate(id, true)
        SetEntityAsMissionEntity(veh, true, true)
    end
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetVehRadioStation(veh, 'OFF')
    SetModelAsNoLongerNeeded(model)
    if cb then cb(veh) else return veh end
end

function utils.garageType ( data )
    local result = ""
    for i=1, #data do
        local class = data[i]
        result = result .. ("%s%s"):format(class, data[i + 1] and ", " or "")
    end
    return result
end

function utils.GangCheck ( data )
    local configGang = data.gang
    local playergang = fw.player.gang
    local allowed = false
    if type(configGang) == 'table' then
        local grade = configGang[playergang.name]
        allowed = grade and playergang.grade >= grade
    elseif type(configGang) == 'string' then
        if playergang.name == configGang then
            allowed = true
        end
    end
    return allowed
end

function utils.JobCheck ( data )
    local configJob = data.job
    local playerjob = fw.player.job
    local allowed = false

    if type(configJob) == 'table' then
        local grade = configJob[playerjob.name]
        allowed = grade and playerjob.grade >= grade
    elseif type(configJob) == 'string' then
        if playerjob.name == configJob then
            allowed = true
        end
    end
    return allowed
end

if server then
    function utils.notify(src, msg, type, duration)
        lib.notify(src, {
            description = msg,
            type = type,
            duration = duration or 5000
        })
    end
end