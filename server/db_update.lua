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
            MySQL.update("UPDATE player_vehicles SET state = 1, engine = 1000, body = 1000 WHERE state = 3", {})
        end)
    end
end)
