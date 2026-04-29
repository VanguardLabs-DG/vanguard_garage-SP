if Config.RadialMenu == "qb" or Config.RadialMenu == "rhd" then return end

radFunc = {}

---@param data RadialData
function radFunc.create(data)
    lib.addRadialItem({
        {
            id = data.id,
            label = data.label,
            icon = data.icon,
            onSelect = function ()
                if data.id == "open_garage" and not cache.vehicle then
                    exports.vanguard_garage:openMenu(data.args)
                elseif data.id == "store_veh" then
                    exports.vanguard_garage:storeVehicle(data.args)
                elseif data.id == "open_garage_pi" then
                    exports.vanguard_garage:openpoliceImpound(data.args)
                end
            end
        },
    })
end

---@param id string
function radFunc.remove(id)
    lib.removeRadialItem(id)
end
