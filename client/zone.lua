gzf = {}

local CreatedZone = {}
local ped = nil
local stui = false

--- Job & Gang Checking
---@param key string
---@param val table
---@return boolean
function gzf.authorize(key, val)
    if val.impound then return true end

    local perm = val.permission or val.job or val.gang or (val.isWork and (val.workName or val.name))
    if not perm or perm == "" or perm == "nil" or perm == "false" then return true end

    local pData = (exports.qbx_core and exports.qbx_core:GetPlayerData()) or (QBCore and QBCore.Functions and QBCore.Functions.GetPlayerData()) or {}
    local pJob = (pData.job and pData.job.name) or (fw.player and fw.player.job and fw.player.job.name) or ""
    local pJobType = (pData.job and pData.job.type) or ""
    local pGang = (pData.gang and pData.gang.name) or (fw.player and fw.player.gang and fw.player.gang.name) or ""
    local permStr = tostring(perm):lower()
    local jobLower = pJob:lower()
    local jobTypeLower = pJobType:lower()
    local gangLower = pGang:lower()

    if jobLower == permStr or jobTypeLower == permStr or gangLower == permStr then
        return true
    end

    -- Mapeamentos de permissão do Paulista
    if permStr == "paramedico" or permStr == "paramedic" or permStr == "hp" or permStr == "hpheli" or permStr == "paramedicoheli" then
        if jobLower == "paramedic" or jobLower == "paramedico" or jobLower == "ambulance" or jobTypeLower == "ems" then
            return true
        end
    elseif permStr == "pm" or permStr == "pc" or permStr == "pf" or permStr == "prf" or permStr == "gcm" or permStr == "police" or permStr == "helipm" or permStr == "helipf" or permStr == "heliprf" or permStr == "bprv" or permStr == "bprv1" or permStr == "ft" or permStr == "coe" or permStr == "rocam" or permStr == "qcg" then
        if jobLower == "police" or jobLower == permStr or jobTypeLower == "leo" then
            return true
        end
    elseif permStr == "bombeiro" or permStr == "bm" or permStr == "heli bm" or permStr == "boats bm" then
        if jobLower == "fire" or jobLower == "bombeiro" then
            return true
        end
    elseif permStr == "mechanic" or permStr == "mecanico" or permStr == "mec" or permStr == "mec1" or permStr == "mec2" or permStr == "mec3" then
        if jobLower == "mechanic" or jobLower == "mecanico" or jobTypeLower == "mechanic" then
            return true
        end
    elseif permStr == "bikes" then
        return true -- Garagem pública de bicicletas
    end

    if type(val.job) == "table" or type(val.job) == "string" then
        if utils.JobCheck({garage = key, job = val.job}) then return true end
    end
    if type(val.gang) == "table" or type(val.gang) == "string" then
        if utils.GangCheck({garage = key, gang = val.gang}) then return true end
    end

    return false
end

function gzf.refresh ()
    if not GarageZone or type(GarageZone) ~= "table" then 
        return 
    end

    gb.refresh(GarageZone)
    if next(CreatedZone) then
        for k, v in pairs(CreatedZone) do
            v:remove()
        end
        CreatedZone = {}
    end

    for k, v in pairs(GarageZone) do
        local markerCoords = v.marker or (v.marker_x and vec3(v.marker_x, v.marker_y, v.marker_z))
        local displayLabel = v.label or v.name or k

        local args = {
            garage = k,
            impound = v.impound,
            shared = v.shared,
            type = v.type or { "car", "motorcycle", "cycles" },
            spawnpoint = v.spawnPoint or v.spawnpoint or v.spawn,
            spawn = v.spawn or v.spawnPoint or v.spawnpoint,
            vehicles = v.vehicles,
            ignoreDist = true
        }

        local zoneOptions = {}

        if type(v.interaction) == "table" and v.interaction.coords then
            zoneOptions.coords = v.interaction.coords.xyz
            zoneOptions.radius = 2.5

            function zoneOptions:inside()
                if not stui then
                    local dl = cache.vehicle and ('[E] - %s'):format(displayLabel) or displayLabel
                    utils.drawtext('show', dl, 'warehouse')
                    stui = true
                end
                if IsControlJustPressed(0, 38) and cache.vehicle then
                    if not gzf.authorize(k, v) then
                        utils.notify("Você não tem permissão para esta garagem.", "error")
                        return
                    end
                    exports.vanguard_garage:storeVehicle(args)
                end
            end

            function zoneOptions:onEnter()
                if not gzf.authorize(k, v) then return end
                local model = v.interaction.model
                local pc = v.interaction.coords
                if ped then DeleteEntity(ped) ped = nil end
                ped = utils.createTargetPed(model, pc, {
                    {
                        name = "open_garage",
                        label = "Abrir Garagem",
                        icon = "fas fa-warehouse",
                        action = function ()
                            args.ignoreDist = true
                            exports.vanguard_garage:openMenu(args)
                        end,
                    }
                })
            end

            function zoneOptions:onExit()
                stui = false
                utils.drawtext('hide')
                local id = Config.Target == "ox" and "open_garage" or "Open Garage"
                utils.removeTargetPed(ped, id)
            end

            CreatedZone[k] = lib.zones.sphere(zoneOptions)
        else
            -- Interação padrão por tecla E (keypressed)
            local function handleInside()
                if not stui then
                    local prompt = cache.vehicle and ('[E] - Guardar em %s'):format(displayLabel) or ('[E] - %s'):format(displayLabel)
                    local icon = cache.vehicle and 'parking' or 'warehouse'
                    utils.drawtext('show', prompt, icon)
                    stui = true
                end

                if IsControlJustPressed(0, 38) then -- Tecla E
                    if not gzf.authorize(k, v) then
                        utils.notify("Você não tem permissão para esta garagem.", "error")
                        return
                    end

                    if cache.vehicle then
                        exports.vanguard_garage:storeVehicle(args)
                    else
                        exports.vanguard_garage:openMenu(args)
                    end
                end
            end

            local function handleEnter()
                if not gzf.authorize(k, v) then return end
                local prompt = cache.vehicle and ('[E] - Guardar em %s'):format(displayLabel) or ('[E] - %s'):format(displayLabel)
                local icon = cache.vehicle and 'parking' or 'warehouse'
                utils.drawtext('show', prompt, icon)
                stui = true
            end

            local function handleExit()
                stui = false
                utils.drawtext('hide')
            end

            if markerCoords then
                zoneOptions.coords = markerCoords
                zoneOptions.radius = 1.8 -- Raio restrito ao ponto exato do blip/marcador (cabine)
                zoneOptions.inside = handleInside
                zoneOptions.onEnter = handleEnter
                zoneOptions.onExit = handleExit
                CreatedZone[k] = lib.zones.sphere(zoneOptions)
            elseif v.zones and v.zones.points then
                zoneOptions.points = v.zones.points
                zoneOptions.thickness = v.zones.thickness or 4.0
                zoneOptions.inside = handleInside
                zoneOptions.onEnter = handleEnter
                zoneOptions.onExit = handleExit
                CreatedZone[k] = lib.zones.poly(zoneOptions)
            end
        end
    end
end

-- Thread de Renderização de Marcadores Visuais no Chão
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = cache.ped or PlayerPedId()
        local pCoords = GetEntityCoords(ped)

        if GarageZone and type(GarageZone) == "table" then
            for _, v in pairs(GarageZone) do
                local mCoords = v.marker or (v.marker_x and vec3(v.marker_x, v.marker_y, v.marker_z))
                if mCoords then
                    local dist = #(pCoords - mCoords)
                    if dist <= 25.0 then
                        sleep = 0
                        -- Marcador circular no chão
                        DrawMarker(27, mCoords.x, mCoords.y, mCoords.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.3, 230, 180, 40, 160, false, false, 2, false)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

lib.onCache('vehicle', function(value)
    stui = false
    utils.drawtext('hide')
end)

function gzf.save ( data )
    TriggerServerEvent("vanguard_garage:server:saveGarageZone", data)
end

-- Inicializa ao carregar o script
CreateThread(function()
    Wait(1000)
    gzf.refresh()
end)