lib.addCommand(locale("command.admin.garagelist"), {
    help = locale("command.admin.garagelistHelp"),
    restricted = 'group.admin'
}, function(source, args, raw)
    TriggerClientEvent("vanguard_garage:client:garagelist", source)
end)