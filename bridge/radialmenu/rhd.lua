if Config.RadialMenu ~= "rhd" then return end

radFunc = {}

---@param data RadialData
function radFunc.create(data)
    exports.rhd_radialmenu:addRadialItem({
        id = data.id,
        label = data.label,
        icon = data.icon,
        action = function ()
            if data.id == "open_garage" and not cache.vehicle then
                exports.vanguard_garage:openMenu(data.args)
            elseif data.id == "store_veh" then
                exports.vanguard_garage:storeVehicle(data.args)
            elseif data.id == "open_garage_pi" then
                exports.vanguard_garage:openpoliceImpound(data.args)
            end
        end
    })
end

---@param id string
function radFunc.remove(id)
    exports.rhd_radialmenu:removeRadialItem(id)
end
