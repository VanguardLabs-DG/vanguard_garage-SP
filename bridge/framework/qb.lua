if GetResourceState('qb-core') == "missing" and GetResourceState('qbx_core') == "missing" then return end

QBCore = exports['qb-core']:GetCoreObject()
local isServer = IsDuplicityVersion()

fw = {
    player = {
        name = "Unkown Players",
        money = {
            cash = 0,
            bank = 0
        },
        job = {
            name = "none",
            grade = 0
        },
        gang = {
            name = "none",
            grade = 0
        }
    },
    qb = true,
    playerLoaded = false
}

if not isServer then
    -- Vacina: Inicialização em Thread para não travar no ensure
    CreateThread(function()
        local attempts = 0
        while not QBCore and attempts < 100 do
            Wait(10)
            QBCore = exports['qb-core']:GetCoreObject()
            attempts = attempts + 1
        end

        if QBCore then
            local PlayerData = QBCore.Functions.GetPlayerData()
            if PlayerData and PlayerData.citizenid then
                local charinfo = PlayerData.charinfo
                fw.player.name = charinfo.firstname .. " " .. charinfo.lastname
                fw.player.money = PlayerData.money
                fw.player.job = { name = PlayerData.job.name, grade = PlayerData.job.grade.level }
                fw.player.gang = { name = PlayerData.gang.name, grade = PlayerData.gang.grade.level }
                fw.playerLoaded = true
            end
        end
    end)
end

--- Get Money
---@param type string
---@return integer
function fw.gm(type)
    return (fw.player and fw.player.money and fw.player.money[type]) or 0
end

---@return string
function fw.gn()
    return fw.player and fw.player.name or ""
end

--- Get Vehicle Name
---@param model string
function fw.gvn(model)
    if not model or model == "" then return "" end
    local mStr = tostring(model):lower()

    -- 1. Consulta qbx_core (moderno / compartilhado)
    local qbxVeh = nil
    if exports and exports.qbx_core then
        local ok, data = pcall(function()
            return exports.qbx_core:GetVehiclesByName(mStr)
        end)
        if ok and data and type(data) == "table" then
            qbxVeh = data
        end
    end

    -- 2. Consulta QBCore.Shared.Vehicles (fallback legado)
    local qbVeh = QBCore and QBCore.Shared and QBCore.Shared.Vehicles and (QBCore.Shared.Vehicles[model] or QBCore.Shared.Vehicles[mStr])
    local vd = qbxVeh or qbVeh

    local vm = (vd and (vd.brand or vd.make)) or ""
    local vn = (vd and vd.name) or ""

    -- 3. Se for CLIENT-SIDE, tenta as natives da engine do GTA V como fallback
    if not IsDuplicityVersion() then
        local mHash = type(model) == "number" and model or joaat(mStr)
        if vm == "" and GetMakeNameFromVehicleModel then
            local okM, makeKey = pcall(GetMakeNameFromVehicleModel, mHash)
            if okM and makeKey and makeKey ~= "" and makeKey ~= "NULL" then
                local makeLabel = GetLabelText and GetLabelText(makeKey)
                vm = (makeLabel and makeLabel ~= "NULL") and makeLabel or makeKey
            end
        end
        if vn == "" and GetDisplayNameFromVehicleModel then
            local okD, dispKey = pcall(GetDisplayNameFromVehicleModel, mHash)
            if okD and dispKey and dispKey ~= "" and dispKey ~= "NULL" then
                local dispLabel = GetLabelText and GetLabelText(dispKey)
                vn = (dispLabel and dispLabel ~= "NULL") and dispLabel or dispKey
            end
        end
    end

    if vm ~= "" and vn ~= "" then
        return ("%s %s"):format(vm, vn)
    elseif vn ~= "" then
        return vn
    elseif vm ~= "" then
        return vm
    end

    return string.upper(model)
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local PlayerData = QBCore.Functions.GetPlayerData()
    local charinfo = PlayerData.charinfo

    local Job = PlayerData.job
    local Gang = PlayerData.gang
    local Money = PlayerData.money

    fw.player.name = charinfo.firstname .. " " .. charinfo.lastname
    fw.player.money = Money

    fw.player.job = {
        name = Job.name,
        grade = Job.grade.level
    }
    fw.player.gang = {
        name = Gang.name,
        grade = Gang.grade.level
    }
    fw.playerLoaded = true
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(PlayerData)
    local Job = PlayerData.job
    local Gang = PlayerData.gang
    local Money = PlayerData.money
    local Charinfo = PlayerData.charinfo

    fw.player.name = Charinfo.firstname .. " " .. Charinfo.lastname
    fw.player.money = Money

    fw.player.job = {
        name = Job.name,
        grade = Job.grade.level
    }
    fw.player.gang = {
        name = Gang.name,
        grade = Gang.grade.level
    }
end)

local function loadCacheData()
    Wait(2000)
    ExecuteCommand("loaded")
    Wait(1000)
    ExecuteCommand("reloadcache")
end

if not isServer then
    AddEventHandler('onClientResourceStart', function(resource)
        if resource == GetCurrentResourceName() then
            loadCacheData()
        end
    end)
end

if Config.InDevelopment then
    RegisterCommand("loaded", function ()
        fw.playerLoaded = true
    end, false)

    RegisterCommand("reloadcache", function ()
        local PlayerData = QBCore.Functions.GetPlayerData()

        if not PlayerData['job'] then
            return
        end

        local Job = PlayerData.job
        local Gang = PlayerData.gang
        local Money = PlayerData.money

        fw.player.money = Money

        fw.player.job = {
            name = Job.name,
            grade = Job.grade.level
        }

        fw.player.gang = {
            name = Gang.name,
            grade = Gang.grade.level
        }

        TriggerServerEvent('reloadcache:server')
    end, false)
end

if isServer then
    local xPlayer = {}

    --- Get Player
    ---@param src number
    ---@return table | boolean
    function fw.gp(src)
        local idstr = tostring(src)
        local p = nil
        if exports.qbx_core then
            p = exports.qbx_core:GetPlayer(src)
        end
        if not p and QBCore and QBCore.Functions then
            p = QBCore.Functions.GetPlayer(src)
        end
        if p and p.PlayerData then
            if not xPlayer then xPlayer = {} end
            xPlayer[idstr] = p.PlayerData
            return p.PlayerData
        end
        if xPlayer and xPlayer[idstr] then
            return xPlayer[idstr]
        end
        return false
    end

    --- Get Identifier
    ---@param src number
    ---@param withLicense boolean?
    ---@return string | boolean
    ---@return string | boolean
    function fw.gi(src, withLicense)
        local pData = fw.gp(src)
        local citizenid = pData and pData.citizenid
        local license = withLicense and pData and pData.license or false
        return citizenid or false, license
    end

    --- Get Player By Identifier
    ---@param identifier string
    ---@return table | boolean
    function fw.gpbi(identifier)
        local p = QBCore.Functions.GetPlayerByCitizenId(identifier)
        return p and p.PlayerData or false
    end

    --- Player Remove Money
    ---@param src number playerid
    ---@param type string cash | bank
    ---@param amount number amount of money
    ---@return boolean
    function fw.rm(src, type, amount)
        local p = QBCore.Functions.GetPlayer(src)
        if not p then return false end
        return p.Functions.RemoveMoney(type, amount, '')
    end

    --- Get Player Name
    ---@param src number
    ---@return string
    function fw.gn(src)
        local idstr = tostring(src)
        local pData = xPlayer[idstr]
        local charinfo = (pData and pData.charinfo) or {}
        return next(charinfo) and ("%s %s"):format(charinfo.firstname, charinfo.lastname) or "Unkown Players"
    end

    --- Get Shared Vehicle
    ---@param model string
    ---@return table
    function fw.gsv(model)
        return QBCore.Shared.Vehicles[model] or {}
    end

    --- Get Vehicle Mods & Deformation By Plate
    ---@param plate any
    function fw.gmdbp(plate)
        local results = MySQL.single.await("SELECT mods, deformation FROM player_vehicles WHERE plate = ? OR fakeplate = ?", {plate, plate})
        if not results then return {prop = {}, deformation = {},} end
        return {prop = json.decode(results.mods), deformation = json.decode(results.deformation)}
    end

    --- Update Vehicle State
    ---@param plate string
    ---@param state number
    ---@param garage string
    ---@return boolean
    function fw.uvs(plate, state, garage, engine, body)
        local clean = plate and string.gsub(plate, "%s+", ""):upper() or ""
        local query = "UPDATE player_vehicles SET state = ?, garage = ?"
        local params = {state, garage}
        
        if engine and body then
            query = query .. ", engine = ?, body = ?"
            params[#params+1] = engine
            params[#params+1] = body
        end
        
        if state == 0 then
            query = query .. ", last_out = ?"
            params[#params+1] = os.time()
        end
        
        query = query .. " WHERE plate = ? OR fakeplate = ? OR TRIM(plate) = ? OR REPLACE(plate, ' ', '') = ?"
        params[#params+1] = plate
        params[#params+1] = plate
        params[#params+1] = plate
        params[#params+1] = clean
        
        local Update = MySQL.update.await(query, params)
        return Update > 0
    end

    --- Update Vehicle State Police Impound
    ---@param plate string
    ---@param state number
    ---@return boolean
    function fw.uvspi(plate, state)
        local update = MySQL.update.await([[
            UPDATE
                player_vehicles SET state = ? WHERE plate = ? OR fakeplate = ?
        ]], {state, plate, plate})
        return update > 0
    end

    --- Swap Vehicle Garage
    ---@param newgarage string
    ---@param plate string
    ---@return boolean
    function fw.svg(newgarage, plate)
        local update = MySQL.update.await("UPDATE player_vehicles SET garage = ? WHERE plate = ? OR fakeplate = ?", {newgarage, plate, plate})
        return update > 0
    end

    --- Update Vehicle Owner
    ---@param plate string
    ---@param oldOwnerId table
    ---@param newOwnerId table
    function fw.uvo(oldOwnerId, newOwnerId, plate)
        local mp = fw.gp(oldOwnerId)
        local tp = fw.gp(newOwnerId)
        if not mp then return end
        if not tp then return false, locale("notify.error.player_offline", newOwnerId) end

        local update = MySQL.update.await("UPDATE player_vehicles SET license = ?, citizenid = ? WHERE citizenid = ? AND plate = ? OR fakeplate = ?", {
            tp.license,
            tp.citizenid,
            mp.citizenid,
            plate,
            plate
        })
        return update > 0
    end

    ---- Get Vehicle Owner By Plate
    ---@param src number
    ---@param plate string
    ---@param filter {onlyOwner: boolean}
    ---@param pleaseUpdate {vehicle_name:string, mods: table, deformation: table, fuel: number, engine: number, body: number}
    ---@return table | boolean
    function fw.gvobp(src, plate, filter, pleaseUpdate)
        local identifier = fw.gi(src)
        if not identifier then return false end

        local format = [[
            SELECT
                pv.vehicle,
                p.charinfo
            FROM player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid
                WHERE
                    pv.plate = ? OR pv.fakeplate = ?
        ]]
        local value = {plate, plate}

        if filter and filter.onlyOwner then
            format = [[
                SELECT
                    pv.vehicle,
                    p.charinfo
                FROM player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid
                    WHERE
                        (pv.plate = ? OR pv.fakeplate = ?) AND pv.citizenid = ?
            ]]
            value = {plate, plate, identifier}
        end

        local results = MySQL.single.await(format, value)
        if not results then return false end
        local charinfo = type(results.charinfo) == "string" and json.decode(results.charinfo) or (results.charinfo or {})
        local ownername = ("%s %s"):format(charinfo.firstname or "Cidadão", charinfo.lastname or "")

        if pleaseUpdate then
            MySQL.update([[
                UPDATE
                    player_vehicles
                        SET
                    vehicle_name = ?, mods = ?, fuel = ?, engine = ?, body = ?, deformation = ? WHERE plate = ? OR fakeplate = ?
            ]], {
                pleaseUpdate.vehicle_name,
                json.encode(pleaseUpdate.mods or {}),
                math.floor(tonumber(pleaseUpdate.fuel) or 100),
                math.floor(tonumber(pleaseUpdate.engine) or 1000),
                math.floor(tonumber(pleaseUpdate.body) or 1000),
                json.encode(pleaseUpdate.deformation or {}),
                plate,
                plate
            })
        end

        return {
            vehmodel = results.vehicle,
            ownername = ownername
        }
    end

    --- Get Player Vehicle By Plate
    ---@param plate string
    function fw.gpvbp(plate)
        local clean = plate and string.gsub(plate, "%s+", ""):upper() or ""
        local results = MySQL.single.await([[
            SELECT
                pv.citizenid,
                pv.vehicle,
                pv.vehicle_name,
                pv.mods,
                pv.plate,
                pv.fakeplate,
                pv.garage,
                pv.fuel,
                pv.engine,
                pv.body,
                pv.state,
                pv.depotprice,
                pv.balance,
                pv.deformation,
                p.charinfo
            FROM player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid 
            WHERE pv.plate = ? OR pv.fakeplate = ? OR TRIM(pv.plate) = ? OR REPLACE(pv.plate, ' ', '') = ? LIMIT 1
        ]], {plate, plate, plate, clean})

        local vehicles = {}
        if results then
            local v = results
            local charinfo = v.charinfo and json.decode(v.charinfo) or nil
            local mods = v.mods and json.decode(v.mods) or {}
            local deformation = v.deformation and (type(v.deformation) == 'table' and v.deformation or json.decode(v.deformation)) or nil
            vehicles = {
                owner = {
                    name = charinfo and ("%s %s"):format(charinfo.firstname, charinfo.lastname) or "Desconhecido",
                    citizenid = v.citizenid,
                },
                vehicle_name = v.vehicle_name,
                mods = mods,
                vehicle = v.vehicle,
                model = joaat(v.vehicle),
                plate = v.plate,
                fakeplate = v.fakeplate,
                garage = v.garage,
                fuel = v.fuel,
                engine = v.engine,
                body = v.body,
                state = v.state,
                depotprice = v.depotprice,
                balance = v.balance,
                deformation = deformation
            }
        end

        return vehicles
    end

    --- Get Player Vehicles By Garage
    ---@param src string
    ---@param garage string
    ---@param filter {impound: boolean, shared: boolean}
    function fw.gpvbg(src, garage, filter)
        local Identifier = fw.gi(src)
        if not Identifier then return {} end
        local format, value
        if filter and filter.impound then
            format = [[
                SELECT vehicle, vehicle_name, mods, state, depotprice, plate, fakeplate, fuel, engine, body, deformation, last_out
                FROM player_vehicles WHERE citizenid = ? AND (state = 0 OR state = 3)
            ]]
            value = {Identifier}
        elseif Config.VehiclesInAllGarages then
            format = [[
                SELECT vehicle, vehicle_name, mods, state, depotprice, plate, fakeplate, fuel, engine, body, deformation, last_out
                FROM player_vehicles WHERE citizenid = ? AND (state != 2 OR state IS NULL)
            ]]
            value = {Identifier}
        else
            format = [[
                SELECT vehicle, vehicle_name, mods, state, depotprice, plate, fakeplate, fuel, engine, body, deformation, last_out
                FROM player_vehicles WHERE citizenid = ? AND (garage = ? OR state = 0 OR state = 3) AND (state != 2 OR state IS NULL)
            ]]
            value = {Identifier, garage}
        end

        if filter and filter.shared then
            format = [[
                SELECT pv.vehicle, pv.vehicle_name, pv.mods, pv.state, pv.depotprice, pv.plate, pv.fakeplate, pv.fuel, pv.engine, pv.body, pv.deformation, p.charinfo
                FROM player_vehicles pv LEFT JOIN players p ON p.citizenid = pv.citizenid WHERE pv.garage = ? AND pv.state = 1
            ]]
            value = {garage}
        end

        local vehicles = {}
        local results = MySQL.query.await(format, value)

        if results and #results > 0 then
            for i=1, #results do
                local data = results[i]
                local mods = json.decode(data.mods)
                local deformation = json.decode(data.deformation)
                local state = data.state
                local model = data.vehicle
                local plate = data.plate
                local depotprice = data.depotprice
                local fakeplate = data.fakeplate

                local sharedData = QBCore.Shared.Vehicles[model]
                local marketPrice = sharedData and sharedData.price or 0

                local stateText = "Na Garagem"
                if state == 0 then
                    stateText = "Fora da Garagem"
                elseif state == 2 then
                    stateText = "Apreendido"
                elseif state == 3 then
                    stateText = "Destruído"
                end

                vehicles[#vehicles+1] = {
                    vehicle = mods,
                    vehicle_name = data.vehicle_name,
                    fuel = data.fuel or 100,
                    engine = data.engine,
                    body = data.body,
                    state = state,
                    state_text = stateText,
                    last_out = data.last_out or 0,
                    model = model,
                    plate = plate,
                    fakeplate = fakeplate,
                    depotprice = data.depotprice,
                    deformation = deformation,
                    marketPrice = marketPrice
                }

                if filter.shared then
                    local charinfo = json.decode(data.charinfo)
                    local ownername = ("%s %s"):format(charinfo.firstname, charinfo.lastname)
                    vehicles[#vehicles].owner = ownername
                end
            end
        end
        return vehicles
    end

    --- Get Vehicles For Phone
    ---@param src any
    ---@return table
    function fw.gvfp(src)
        local idstr = tostring(src)
        local pData = xPlayer[idstr]
        local citizenid = (pData and pData.citizenid) or false
        if not citizenid then return end

        local results = MySQL.query.await([[
                SELECT
                    vehicle,
                    plate,
                    garage,
                    fuel,
                    engine,
                    body,
                    state,
                    paymentsleft
                FROM player_vehicles WHERE citizenid = ?
        ]], {citizenid})

        local vehicles = {}
        if results and results[1] then
            for i=1, #results do
                local v = results[i]
                local plate = utils.string.trim(v.plate)
                local vd = QBCore and QBCore.Shared and QBCore.Shared.Vehicles and QBCore.Shared.Vehicles[v.vehicle]
                local brand = vd and vd.brand
                local name = vd and vd.name
                local defaultname = brand and ("%s %s"):format(brand, name or "")
                local customName = CNV[plate] and CNV[plate].name
                local vehname = customName or defaultname

                local stateText = locale('status.in')

                if v.state == 0 then
                    stateText = vehFuncS.govbp(plate) and locale('status.out') or locale('status.insurance')
                elseif v.state == 2 then
                    stateText = locale('status.confiscated')
                elseif v.state == 3 then
                    stateText = locale('status.destroyed')
                end

                local inInsurance = v.state == 0
                local inPoliceImpound = v.state == 2

                local engine = v.engine > 1000 and 1000 or v.engine
                local body = v.body > 1000 and 1000 or v.body

                vehicles[#vehicles+1] = {
                    fullname = vehname,
                    brand = brand or '',
                    model = name or '',
                    plate = plate,
                    garage = v.garage,
                    state = stateText,
                    fuel = v.fuel,
                    engine = engine,
                    body = body,
                    paymentsleft = v.paymentsleft,
                    disableTracking = inInsurance or inPoliceImpound,
                }
            end
        end
        return vehicles
    end

    --- Insert new vehicle to database
    ---@param vehicle table
    function fw.inv(vehicle)
        MySQL.insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            vehicle.license,
            vehicle.citizenid,
            vehicle.model,
            joaat(vehicle.model),
            json.encode(vehicle.props),
            vehicle.plate,
            0
        })
    end

    RegisterNetEvent('QBCore:Player:SetPlayerData', function(PlayerData)
        local src = PlayerData.source
        local idstr = tostring(src)
        xPlayer[idstr] = PlayerData
    end)

    RegisterNetEvent('QBCore:Server:PlayerLoaded', function(player)
        local src = player.PlayerData.source
        local idstr = tostring(src)
        xPlayer[idstr] = player.PlayerData
        lib.print.info(("Register new cache for %s"):format(GetPlayerName(src)))
    end)

    AddEventHandler("playerDropped", function ()
        local src = source
        local idstr = tostring(src)
        xPlayer[idstr] = nil
        lib.print.info(("Remove cache from %s"):format(GetPlayerName(src)))
    end)

    if Config.InDevelopment then
        RegisterNetEvent('reloadcache:server', function()
            local p = QBCore.Functions.GetPlayer(source)
            if not p then return false end
            local idstr = tostring(source)
            xPlayer[idstr] = p.PlayerData
        end)
    end

    AddEventHandler('onResourceStart', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        Wait(1000)
        local players = QBCore.Functions.GetPlayers()
        for i = 1, #players do
            local src = players[i]
            local p = QBCore.Functions.GetPlayer(src)
            if p then
                local idstr = tostring(src)
                xPlayer[idstr] = p.PlayerData
                lib.print.info(("Restoring cache for %s"):format(GetPlayerName(src)))
            end
        end
    end)
end