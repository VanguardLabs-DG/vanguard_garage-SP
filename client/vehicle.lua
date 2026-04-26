vehFunc = {}

--- Get Vehicle Info By Plate
---@param plate string
function vehFunc.gvibp(plate)
    local vehInfo = lib.callback.await('rhd_garage:cb_server:getVehicleInfoByPlate', false, plate)
    return vehInfo and next(vehInfo) and vehInfo or false 
end

--- Get Outside Vehicle By Plate
---@param plate any
---@return integer | boolean
function vehFunc.govbp(plate)
    local Vehicles = GetGamePool("CVehicle")
    for i=1, #Vehicles do
        local entity = Vehicles[i]
        local Exist = DoesEntityExist(entity)
        if Exist then
            local vP = utils.getPlate(entity)
            if vP == plate then
                local Dead = IsEntityDead(entity)
                local Submerged = IsEntityInWater(entity)
                local EngineDead = GetVehicleEngineHealth(entity) <= 0
                
                if Dead or Submerged or EngineDead then
                    local pCoords = GetEntityCoords(cache.ped)
                    local vCoords = GetEntityCoords(entity)
                    local dist = #(pCoords - vCoords)

                    if dist > 25.0 then
                        SetEntityAsMissionEntity(entity, true, true)
                        DeleteEntity(entity)
                        return false
                    end
                end

                return entity
            end
        end
    end
    return false
end

--- Track Vehicle By Plate
---@param plate any
---@param garage string
function vehFunc.tvbp(plate, garage, setPoint)
    local coords = lib.callback.await("rhd_garage:cb_server:getoutsideVehicleCoords", false, plate, garage)
    if not coords then return false end
    if setPoint then
        SetNewWaypoint(coords.x, coords.y)
    end
    return true
end

--- Get Players Vehicle For Phone
---@return table
function vehFunc.gpvfp()
    return lib.callback.await('rhd_garage:cb_server:GetPlayerVehiclesForPhone')
end

--- Get Vehicle Properties
---@param vehicle string | integer
function vehFunc.gvp(vehicle)
    return lib.getVehicleProperties(vehicle)
end

---@param vehicle string | integer
---@param props table
function vehFunc.svp(vehicle, props)
    return lib.setVehicleProperties(vehicle, props)
end

--- exports
exports('trackveh', vehFunc.tvbp)
exports('getvehForPhone', vehFunc.gpvfp)
