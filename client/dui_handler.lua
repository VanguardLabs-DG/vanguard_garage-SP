print("^5[rhd_garage] ^7DUI Handler iniciado.")

--- @class ShowroomDUI
local ShowroomDUI = {}
local activeDUIs = {} -- vehicle -> instance
local maxDUIs = 5
local duiPool = {}

local function GetDuiUrl()
    return "nui://" .. GetCurrentResourceName() .. "/dui/index.html"
end

function ShowroomDUI.Create(vehicle, data)
    if activeDUIs[vehicle] then return end
    if not DoesEntityExist(vehicle) then return end

    -- Find an available slot or reuse
    local duiId = nil
    for i=1, maxDUIs do
        local inUse = false
        for _, inst in pairs(activeDUIs) do
            if inst.id == i then inUse = true; break end
        end
        if not inUse then duiId = i; break end
    end

    if not duiId then return end

    local txdName = "rhd_showroom_" .. tostring(duiId)
    local txn = "card"
    
    local dui = CreateDui(GetDuiUrl(), 1024, 640)
    
    local timeout = 50
    while not IsDuiAvailable(dui) and timeout > 0 do
        Wait(10)
        timeout = timeout - 1
    end

    if not IsDuiAvailable(dui) then 
        DestroyDui(dui)
        return 
    end

    local handle = GetDuiHandle(dui)
    local txdHandle = CreateRuntimeTxd(txdName)
    CreateRuntimeTextureFromDuiHandle(txdHandle, txn, handle)

    local instance = {
        id = duiId,
        dui = dui,
        txd = txdName,
        txn = txn,
        lastData = nil
    }

    activeDUIs[vehicle] = instance
    
    -- Delay the first update to ensure JS listener is ready
    SetTimeout(600, function()
        if activeDUIs[vehicle] then
            ShowroomDUI.Update(vehicle, data)
        end
    end)
end

function ShowroomDUI.Update(vehicle, data)
    local instance = activeDUIs[vehicle]
    if not instance or not data then return end

    -- Prevent redundant updates
    if instance.lastData and instance.lastData.plate == data.plate then
        return 
    end
    instance.lastData = data

    SendDuiMessage(instance.dui, json.encode({
        type = "UPDATE_VEHICLE",
        payload = {
            name = data.label,
            plate = data.plate,
            fuel = data.fuel,
            engine = (data.engine or 1000) / 10,
            body = (data.body or 1000) / 10
        }
    }))
end

function ShowroomDUI.Render(vehicle, center)
    local instance = activeDUIs[vehicle]
    if not instance then return end

    SetDrawOrigin(center.x, center.y, center.z, 0)

    local screenAspect = GetAspectRatio(false)
    local width = 0.3
    local height = width * (screenAspect * (640 / 1024))
    
    DrawSprite(
        instance.txd, 
        instance.txn, 
        0.0, 0.0,
        width, height,
        0.0,
        255, 255, 255, 255
    )

    ClearDrawOrigin()
end

function ShowroomDUI.Cleanup()
    for veh, instance in pairs(activeDUIs) do
        if instance.dui then
            DestroyDui(instance.dui)
        end
    end
    activeDUIs = {}
end

function ShowroomDUI.DestroyVehicleDUI(vehicle)
    if activeDUIs[vehicle] then
        DestroyDui(activeDUIs[vehicle].dui)
        activeDUIs[vehicle] = nil
    end
end

_G.ShowroomDUI = ShowroomDUI
