if Config.RadialMenu ~= "qb" then return end

radFunc = {}
local radaial = {}

---@param data RadialData
function radFunc.create(data)
    local id = data.id:gsub("%s+", "")
    radaial[id] = exports['qb-radialmenu']:AddOption({
        id = id,
        title = data.label,
        icon = data.icon == "parking" and "square-parking" or data.icon,
        type = 'client',
        event = data.event,
        garage = data.args,
        shouldClose = true
    }, radaial[id])
    return radaial[id]
end

---@param id string
function radFunc.remove(id)
    if radaial[id] then
        exports['qb-radialmenu']:RemoveOption(radaial[id])
    end
end


---@param self table
RegisterNetEvent("vanguard_garage:radial:open", function (self)
    if not cache.vehicle then
        exports.vanguard_garage:openMenu(self.garage)
    end
end)

---@param self table
RegisterNetEvent("vanguard_garage:radial:store", function (self)
    exports.vanguard_garage:storeVehicle(self.garage)
end)

RegisterNetEvent('vanguard_garage:radial:open_policeimpound', function(self)
    if not cache.vehicle then
        exports.vanguard_garage:openpoliceImpound( self.garage )
    end
end)
