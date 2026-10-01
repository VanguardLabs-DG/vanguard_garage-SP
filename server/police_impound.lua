if not Config.UsePoliceImpound then return end

lib.callback.register("vanguard_garage:cb_server:policeImpound.getVehicle", function (_, garage)
    local dataToSend = {}
    local result = MySQL.query.await("SELECT * FROM police_impound WHERE garage = ?", {garage})
    if result and next(result) then
        for k, v in pairs(result) do
            dataToSend[#dataToSend+1] = {
                citizenid = v.citizenid,
                props = json.decode(v.props),
                deformation = json.decode(v.deformation),
                plate = v.plate,
                vehicle = v.vehicle,
                owner = v.owner,
                officer = v.officer,
                fine = v.fine,
                paid = v.paid,
                date = v.date,
            }
        end
    end
    return dataToSend
end)

lib.callback.register("vanguard_garage:cb_server:policeImpound.impoundveh", function (source, impoundData )
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return false end
    local job = player.PlayerData.job
    local jobName = (job and job.name or ""):lower()
    local jobType = (job and job.type or ""):lower()
    if jobName ~= "police" and jobName ~= "pm" and jobName ~= "pc" and jobName ~= "pf" and jobName ~= "prf" and jobType ~= "leo" then
        print(("[vanguard_garage] AVISO: Jogador %s (%s) tentou apreender veículo sem ser policial!"):format(GetPlayerName(source), source))
        return false
    end
    if not impoundData or not impoundData.plate then return false end
    local cleanPlate = utils.string.trim(impoundData.plate)
    local impounded = MySQL.insert.await('INSERT INTO `police_impound` (citizenid, plate, vehicle, props, owner, officer, date, fine, garage) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        impoundData.citizenid, cleanPlate, impoundData.vehicle, json.encode(impoundData.prop), impoundData.owner, impoundData.officer, os.date('%d/%m/%Y', impoundData.date), impoundData.fine, impoundData.garage
    })
    return fw.uvspi(cleanPlate, 2)
end)

lib.callback.register("vanguard_garage:cb_server:policeImpound.cekDate", function (_, date )
    local takeout, day = false, 0
    local d, m, y = date:match("(%d+)/(%d+)/(%d+)")
    local currentDate = os.date("*t")
    local targetDate = {year = tonumber(y), month = tonumber(m), day = tonumber(d)}
    day = os.difftime(os.time(targetDate), os.time(currentDate)) / (24 * 60 * 60)
    if os.date('%d/%m/%Y') >= date then takeout = true end
    return takeout, math.ceil(day)
end)

--- events
RegisterNetEvent('vanguard_garage:server:removeFromPoliceImpound', function( plate )
    if GetInvokingResource() then return end
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local job = player.PlayerData.job
    local jobName = (job and job.name or ""):lower()
    local jobType = (job and job.type or ""):lower()
    local isOfficer = (jobName == "police" or jobName == "pm" or jobName == "pc" or jobName == "pf" or jobName == "prf" or jobType == "leo")
    local cleanPlate = plate and utils.string.trim(plate)
    if not cleanPlate then return end

    local result = MySQL.single.await("SELECT paid FROM police_impound WHERE plate = ?", {cleanPlate})
    if isOfficer or (result and result.paid == 1) then
        fw.uvspi(cleanPlate, 0)
    end
end)

RegisterNetEvent('vanguard_garage:server:policeImpound.sendBill', function( citizenid, fine, plate )
    if GetInvokingResource() then return end
    local Player = fw.gpbi(citizenid)
    if not Player then return end
    local paid = lib.callback.await("vanguard_garage:cb_client:sendFine", Player.source, fine)
    if paid then MySQL.update("UPDATE police_impound SET paid = 1 WHERE plate = ?", { plate }) end
end)