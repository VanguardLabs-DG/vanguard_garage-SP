local UPDATE_SQL = {
    ADD_COLUMN_BALANCE = 'ALTER TABLE player_vehicles ADD balance int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_PAYMENTAMOUNT = 'ALTER TABLE player_vehicles ADD paymentamount int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_PAYMENTSLEFT = 'ALTER TABLE player_vehicles ADD paymentsleft int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_FINANCETIME = 'ALTER TABLE player_vehicles ADD financetime int(11) NOT NULL DEFAULT 0;',
    ADD_COLUMN_LASTOUT = 'ALTER TABLE player_vehicles ADD last_out int(11) NOT NULL DEFAULT 0;',
}

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        local results = {}
        for k, v in pairs(UPDATE_SQL) do
            local status, err = pcall(function()
                MySQL.Sync.execute(v, {})
            end)
            if not status and not string.find(string.lower(err), 'duplicate') then
                results[#results + 1] = {
                    script = k,
                    error = err
                }
            end
        end
        if #results > 0 then
            print(string.format('^1Errors: %s^0', json.encode(results)))
        end
        -- Restaura veículos que ficaram travados em state = 3 (/dv ou destruição antiga)
        pcall(function()
            local affected3 = MySQL.update.await("UPDATE player_vehicles SET state = 1, engine = 1000, body = 1000 WHERE state = 3", {})
            if affected3 and affected3 > 0 then
                print(string.format('^2[vanguard_garage]^7 %d veículos que estavam destruídos foram restaurados.', affected3))
            end
        end)

        -- Retorna veículos fora da garagem (state = 0) para a garagem (state = 1) no reinício do servidor
        pcall(function()
            local affected0 = MySQL.update.await("UPDATE player_vehicles SET state = 1 WHERE state = 0", {})
            if affected0 and affected0 > 0 then
                print(string.format('^2[vanguard_garage]^7 %d veículos fora da garagem foram retornados à garagem com sucesso.', affected0))
            end
            -- Garante garagem padrão caso o campo esteja nulo ou vazio
            MySQL.update.await("UPDATE player_vehicles SET garage = '100002' WHERE (garage IS NULL OR garage = '') AND state = 1", {})
        end)
    end
end)

local function restoreVehiclesToGarage()
    pcall(function()
        MySQL.update.await("UPDATE player_vehicles SET state = 1 WHERE state = 0", {})
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        restoreVehiclesToGarage()
    end
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
    restoreVehiclesToGarage()
end)

