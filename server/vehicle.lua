if GetCurrentResourceName() ~= "vanguard_garage" then return end

vehFunc = vehFunc or {}
vehFuncS = vehFuncS or {}

--- Server-safe getVehicleProperties
function vehFunc.gvp(vehicle)
    if lib and lib.getVehicleProperties then
        local ok, res = pcall(lib.getVehicleProperties, vehicle)
        if ok and res and type(res) == "table" then return res end
    end
    if type(vehicle) == "table" then return vehicle end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return {} end
    local plate = GetVehicleNumberPlateText(vehicle)
    local cleanPlate = plate and plate:gsub('^%s*(.-)%s*$', '%1')
    return {
        model = GetEntityModel(vehicle),
        plate = cleanPlate or plate or '',
        bodyHealth = GetVehicleBodyHealth(vehicle),
        engineHealth = GetVehicleEngineHealth(vehicle),
        fuelLevel = Entity(vehicle).state.fuel or 100,
    }
end
vehFuncS.gvp = vehFunc.gvp

--- Get Vehicle Out By Plate
---@param plate any
---@return table | boolean
function vehFuncS.govbp(plate)
    local cleanPlate = utils.string.trim(plate)
    if not cleanPlate then return false end

    -- 1. Checa registro em memória primeiro
    local cachedEntity = SpawnedVehicleEntities and SpawnedVehicleEntities[cleanPlate]
    if cachedEntity and DoesEntityExist(cachedEntity) then
        local engineHealth = GetVehicleEngineHealth(cachedEntity)
        if engineHealth > 0 then
            return {
                exist = true,
                coords = GetEntityCoords(cachedEntity)
            }
        end
    end

    -- 2. Fallback em todos os veículos do servidor
    local veh = GetAllVehicles()
    for i=1, #veh do
        local entity = veh[i]
        local Plate = utils.getPlate(entity)
        if Plate == cleanPlate then
            local engineHealth = GetVehicleEngineHealth(entity)
            if engineHealth <= 0 then
                return false
            end
            return {
                exist = DoesEntityExist(entity),
                coords = GetEntityCoords(entity)
            }
        end
    end
    return false
end

lib.callback.register('vanguard_garage:cb_server:GetPlayerVehiclesForPhone', function(source)
    return fw.gvfp(source)
end)

lib.callback.register('vanguard_garage:cb_server:getoutsideVehicleCoords', function(_, plate, garage)
    local vehicle = vehFuncS.govbp(plate)
    local coords = vehicle and vehicle.exist and vehicle.coords or nil
    if not coords and garage then
        local gz = GarageZone[garage]
        if gz and GarageZone[garage].impound then return end
        local gp = gz and #gz.zones.points
        local gc = gp and gz.zones.points[gp]
        coords = gc and vec(gc.x, gc.y, gc.z) or nil
        
        if not coords then
            local hg = Config.HouseGarages
            for _, v in pairs(hg) do
                if v.label == garage then
                    local tl = v.takeVehicle
                    coords = vec(tl.x, tl.y, tl.z)
                end
            end
        end
    end
    return coords
end)