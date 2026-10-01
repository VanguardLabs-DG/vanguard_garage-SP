gb = {}

local GarageBlip = {} ---@type table<string, integer>

--- Refresh Blip
---@param data table <string, GarageData>
function gb.refresh ( data )
    data = data or GarageZone
    if not data or type(data) ~= "table" then return end
    
    if GarageBlip and next(GarageBlip) then
        for k, v in pairs(GarageBlip) do
            if DoesBlipExist(v) then
                RemoveBlip(v)
            end
        end
    end

    GarageBlip = {}
    for k, v in pairs(data) do
        if v.blip then
            local location = nil
            if v.marker then
                location = v.marker
            elseif v.marker_x and v.marker_y and v.marker_z then
                location = vec3(v.marker_x, v.marker_y, v.marker_z)
            elseif v.zones and v.zones.points and type(v.zones.points) == 'table' and #v.zones.points > 0 then
                location = v.zones.points[1]
            end

            if location then
                local blip = AddBlipForCoord(location.x, location.y, location.z)
                GarageBlip[k] = blip
                
                local sprite = v.blip.type or v.blip.sprite or 357
                local color = v.blip.color or 32
                local scale = tonumber(v.blip.scale) or 0.6
                if scale > 1.0 then scale = scale / 10.0 end
                local label = v.blip.label or "Garagem"

                SetBlipSprite(blip, sprite)
                SetBlipScale(blip, scale)
                SetBlipColour(blip, color)
                SetBlipDisplay(blip, 4)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(label)
                EndTextCommandSetBlipName(blip)
            end
        end
    end
end