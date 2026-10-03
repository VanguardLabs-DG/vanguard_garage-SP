-- ============================================================================
-- VANGUARD_GARAGE - ADMIN INTEGRATION (mri_Qadmin Plugin)
-- ============================================================================

local function response(ok, code, message, data)
    local res = {
        ok = ok == true,
        code = tostring(code or (ok and "ok" or "error")),
        message = tostring(message or (ok and "Operação concluída." or "A operação não pôde ser concluída."))
    }
    if data ~= nil then
        res.data = data
    end
    return res
end

local function trim(val)
    if type(val) ~= "string" then return nil end
    return val:match("^%s*(.-)%s*$")
end

local function cleanString(val, maxLen, allowEmpty)
    local cleaned = trim(val)
    if cleaned == nil then return nil end
    if cleaned == "" then return allowEmpty and "" or nil end
    if #cleaned > (maxLen or 100) or cleaned:find("[%z\1-\31\127]") then return nil end
    return cleaned
end

local function finiteNumber(val, minVal, maxVal)
    local num = tonumber(val)
    if not num or num ~= num or num == math.huge or num == -math.huge then return nil end
    if minVal and num < minVal then return nil end
    if maxVal and num > maxVal then return nil end
    return num
end

local function integer(val, minVal, maxVal)
    local num = finiteNumber(val, minVal, maxVal)
    if not num or num % 1 ~= 0 then return nil end
    return num
end

local function normalizeCoords(coords, heading)
    if type(coords) ~= "table" then return nil end
    local x = finiteNumber(coords.x, -20000.0, 20000.0)
    local y = finiteNumber(coords.y, -20000.0, 20000.0)
    local z = finiteNumber(coords.z, -2000.0, 10000.0)
    if not x or not y or not z then return nil end
    local h = finiteNumber(heading ~= nil and heading or coords.heading or coords.h or 0.0, -3600.0, 3600.0)
    return {
        x = math.floor(x * 100 + 0.5) / 100,
        y = math.floor(y * 100 + 0.5) / 100,
        z = math.floor(z * 100 + 0.5) / 100,
        heading = h and (math.floor(h * 10 + 0.5) / 10 % 360.0) or 0.0
    }
end

local function distanceSquared(c1, c2)
    local dx = (c1.x or 0) - (c2.x or 0)
    local dy = (c1.y or 0) - (c2.y or 0)
    local dz = (c1.z or 0) - (c2.z or 0)
    return (dx * dx) + (dy * dy) + (dz * dz)
end

local function revisionOf(records)
    local encoded = json.encode(records or {})
    local hash = 0
    for i = 1, #encoded do
        hash = (hash * 31 + string.byte(encoded, i)) % 4294967296
    end
    return string.format("%08x", hash)
end

local function hasGaragePermission(source)
    if not source or source == 0 then return true end
    if IsPlayerAceAllowed(source, 'qadmin.garages')
        or IsPlayerAceAllowed(source, 'command')
        or IsPlayerAceAllowed(source, 'admin') then
        return true
    end
    local ok, hasPerm = pcall(function()
        return exports.qbx_core:HasPermission(source, 'admin') or exports.qbx_core:HasPermission(source, 'god')
    end)
    if ok and hasPerm then return true end
    return false
end

-- ============================================================================
-- DATABASE FETCH & NORMALIZATION
-- ============================================================================

local function fetchGarages()
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT id, garage_id, name, permission, payment,
                   marker_x, marker_y, marker_z,
                   spawn_x, spawn_y, spawn_z, spawn_h,
                   spawns
              FROM custom_garages
             ORDER BY id ASC
        ]])
    end)
    if not ok then return nil, tostring(rows) end
    return rows or {}
end

local function normalizeGarages(rows)
    local records = {}
    for _, row in ipairs(rows or {}) do
        local spawnsList = {}
        if row.spawns and row.spawns ~= "" and row.spawns ~= "null" then
            local ok, decoded = pcall(json.decode, row.spawns)
            if ok and type(decoded) == "table" and #decoded > 0 then
                for _, sp in ipairs(decoded) do
                    if sp and tonumber(sp.x) and tonumber(sp.y) and tonumber(sp.z) then
                        spawnsList[#spawnsList + 1] = {
                            x = tonumber(sp.x),
                            y = tonumber(sp.y),
                            z = tonumber(sp.z),
                            heading = tonumber(sp.heading or sp.h or 0)
                        }
                    end
                end
            end
        end

        if #spawnsList == 0 and tonumber(row.spawn_x) and tonumber(row.spawn_y) and tonumber(row.spawn_z) then
            spawnsList[1] = {
                x = tonumber(row.spawn_x),
                y = tonumber(row.spawn_y),
                z = tonumber(row.spawn_z),
                heading = tonumber(row.spawn_h or 0)
            }
        end

        local mainSpawn = spawnsList[1] or {
            x = tonumber(row.spawn_x or 0.0),
            y = tonumber(row.spawn_y or 0.0),
            z = tonumber(row.spawn_z or 0.0),
            heading = tonumber(row.spawn_h or 0.0)
        }

        local isPayment = row.payment == true or row.payment == "true" or row.payment == 1

        records[#records + 1] = {
            id = tonumber(row.id),
            garageId = tostring(row.garage_id or ""),
            name = row.name,
            permission = row.permission,
            payment = isPayment,
            x = tonumber(row.marker_x),
            y = tonumber(row.marker_y),
            z = tonumber(row.marker_z),
            coords = { x = tonumber(row.marker_x), y = tonumber(row.marker_y), z = tonumber(row.marker_z) },
            marker = { x = tonumber(row.marker_x), y = tonumber(row.marker_y), z = tonumber(row.marker_z) },
            spawn = mainSpawn,
            spawns = spawnsList
        }
    end
    return records
end

local function getGarageCatalog()
    local ok, types = pcall(function()
        return exports["vanguard_garage"]:GetGarageTypes()
    end)
    if ok and type(types) == "table" then
        return types
    end
    return {
        { value = "Garage", label = "Garage (Pública / Pessoal)", vehicles = {}, count = 0 }
    }
end

local function buildGaragePayload(source)
    local rows, err = fetchGarages()
    if not rows then
        return {
            id = "garages",
            resource = "vanguard_garage",
            status = "attention",
            detail = "Tabela custom_garages indisponível: " .. tostring(err),
            capabilities = { list = false, create = false, update = false, delete = false, reload = false, teleport = false },
            records = {},
            revision = ""
        }
    end

    local records = normalizeGarages(rows)
    local canMutate = hasGaragePermission(source)

    return {
        id = "garages",
        resource = "vanguard_garage",
        status = "online",
        detail = "Schema custom_garages sincronizado ao vivo com vanguard_garage.",
        capabilities = {
            list = true,
            create = canMutate,
            update = canMutate,
            delete = canMutate,
            reload = canMutate,
            teleport = canMutate
        },
        records = records,
        revision = revisionOf(records),
        catalog = {
            garageTypes = getGarageCatalog()
        }
    }
end

-- ============================================================================
-- CRUD OPERATIONS
-- ============================================================================

local function executeGarageAction(action, data, expectedRevision, source)
    if not hasGaragePermission(source) then
        return response(false, "forbidden", "Você não tem permissão para gerenciar garagens.")
    end

    data = data or {}

    local rows, err = fetchGarages()
    if not rows then
        return response(false, "schema_unavailable", "custom_garages indisponível: " .. tostring(err))
    end

    local currentRecords = normalizeGarages(rows)
    local currentRev = revisionOf(currentRecords)

    if action == "reload" then
        local ok, reloadErr = pcall(function()
            return exports["vanguard_garage"]:ReloadCustomGarages(-1)
        end)
        if not ok or reloadErr ~= true then
            return response(false, "reload_failed", "Falha ao recarregar garagens no servidor: " .. tostring(reloadErr))
        end
        return response(true, "reloaded", "Garagens recarregadas e publicadas imediatamente.", {
            revision = currentRev
        })
    end

    if action == "create" then
        local garageId = cleanString(data.garageId or data.garage_id, 10, false)
        local name = cleanString(data.name, 100, false)
        local permission = cleanString(data.permission or data.perm or "", 100, true)
        local payment = data.payment == true or data.payment == "true" or data.payment == 1
        local marker = normalizeCoords(data.marker)

        local spawnsList = {}
        if type(data.spawns) == "table" and #data.spawns > 0 then
            for _, rawSp in ipairs(data.spawns) do
                local sp = normalizeCoords(rawSp)
                if sp and sp.heading then
                    spawnsList[#spawnsList + 1] = sp
                end
            end
        end

        if #spawnsList == 0 and data.spawn then
            local sp = normalizeCoords(data.spawn)
            if sp and sp.heading then
                spawnsList[1] = sp
            end
        end

        if not garageId or not garageId:match("^[%w_%-]+$") then
            return response(false, "invalid_garage_id", "O identificador deve ter até 10 caracteres (letras, números, '_' ou '-').")
        end
        local numericGarageId = garageId:match("^%d+$") and tonumber(garageId) or nil
        if numericGarageId and numericGarageId < 10000 then
            return response(false, "reserved_garage_id", "IDs somente numéricos devem ser 10000 ou maiores.")
        end
        if not name then
            return response(false, "invalid_name", "Informe o tipo ou lista de veículos da garagem.")
        end
        if permission == nil then
            return response(false, "invalid_permission", "Permissão inválida.")
        end
        if not marker then
            return response(false, "invalid_placement", "Capture o ponto de entrada da garagem.")
        end
        if #spawnsList == 0 then
            return response(false, "invalid_placement", "Capture ao menos um ponto de spawn com direção.")
        end

        -- Valida distância das vagas até a entrada (máximo 100m)
        for i, sp in ipairs(spawnsList) do
            if distanceSquared(marker, sp) > 100.0 * 100.0 then
                return response(false, "spawn_too_far", string.format("A vaga %d de spawn deve ficar a no máximo 100 metros da entrada.", i))
            end
        end

        -- Valida espaçamento mínimo entre vagas de spawn (mínimo 0.5m / 0.25m²)
        for i = 1, #spawnsList - 1 do
            for j = i + 1, #spawnsList do
                if distanceSquared(spawnsList[i], spawnsList[j]) < 0.25 then
                    return response(false, "spawns_too_close", string.format("As vagas %d e %d estão muito próximas (mínimo 0.5m de distância entre si).", i, j))
                end
            end
        end

        -- Checa duplicata no cache em memória (garagens estáticas) e no banco de dados
        if GarageZone and GarageZone[garageId] then
            return response(false, "duplicate", "Já existe uma garagem carregada com esse identificador: " .. garageId)
        end
        local duplicate = MySQL.scalar.await("SELECT id FROM custom_garages WHERE garage_id = ? LIMIT 1", { garageId })
        if duplicate then
            return response(false, "duplicate", "Já existe uma garagem com esse identificador: " .. garageId)
        end

        local mainSpawn = spawnsList[1]
        local spawnsJson = json.encode(spawnsList)

        local newRow = {
            garage_id = garageId,
            name = name,
            permission = permission,
            payment = payment and "true" or "false",
            marker_x = marker.x,
            marker_y = marker.y,
            marker_z = marker.z,
            spawn_x = mainSpawn.x,
            spawn_y = mainSpawn.y,
            spawn_z = mainSpawn.z,
            spawn_h = mainSpawn.heading or 0.0,
            spawns = spawnsJson
        }

        local insertedId = MySQL.insert.await([[
            INSERT INTO custom_garages
                (garage_id, name, permission, payment, marker_x, marker_y, marker_z, spawn_x, spawn_y, spawn_z, spawn_h, spawns)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            newRow.garage_id, newRow.name, newRow.permission, newRow.payment,
            newRow.marker_x, newRow.marker_y, newRow.marker_z,
            newRow.spawn_x, newRow.spawn_y, newRow.spawn_z, newRow.spawn_h,
            newRow.spawns
        })

        if not insertedId or insertedId == 0 then
            return response(false, "database_error", "Falha ao gravar no banco de dados.")
        end

        newRow.id = insertedId

        -- Live sync
        local synced, syncErr = pcall(function()
            return exports["vanguard_garage"]:ApplyCustomGarageMutation("upsert", newRow)
        end)

        if not synced or syncErr ~= true then
            -- Rollback
            MySQL.update.await("DELETE FROM custom_garages WHERE id = ?", { insertedId })
            pcall(function() exports["vanguard_garage"]:ReloadCustomGarages(-1) end)
            return response(false, "sync_failed", "A garagem foi revertida pois o cache live recusou: " .. tostring(syncErr))
        end

        local afterRows = fetchGarages() or {}
        local afterRecords = normalizeGarages(afterRows)
        return response(true, "created", string.format("Garagem %s criada e ativa imediatamente.", garageId), {
            id = insertedId,
            revision = revisionOf(afterRecords)
        })
    end

    if action == "update" then
        local id = integer(data.id, 1)
        if not id then return response(false, "invalid_id", "ID de garagem inválido.") end

        local target = MySQL.single.await("SELECT * FROM custom_garages WHERE id = ? LIMIT 1", { id })
        if not target then return response(false, "not_found", "Garagem não encontrada.") end

        local name = cleanString(data.name, 100, false) or target.name
        local permission = cleanString(data.permission or data.perm or "", 100, true)
        if permission == nil then permission = target.permission end
        local payment = data.payment ~= nil and (data.payment == true or data.payment == "true" or data.payment == 1)
            or (target.payment == "true" or target.payment == 1)

        local marker = normalizeCoords(data.marker) or {
            x = tonumber(target.marker_x),
            y = tonumber(target.marker_y),
            z = tonumber(target.marker_z)
        }

        local spawnsList = {}
        if type(data.spawns) == "table" and #data.spawns > 0 then
            for _, rawSp in ipairs(data.spawns) do
                local sp = normalizeCoords(rawSp)
                if sp and sp.heading then
                    spawnsList[#spawnsList + 1] = sp
                end
            end
        end

        if #spawnsList == 0 and data.spawn then
            local sp = normalizeCoords(data.spawn)
            if sp and sp.heading then
                spawnsList[1] = sp
            end
        end

        if #spawnsList == 0 and target.spawns then
            local okDec, dec = pcall(json.decode, target.spawns)
            if okDec and type(dec) == "table" then
                for _, sp in ipairs(dec) do
                    local nSp = normalizeCoords(sp)
                    if nSp then spawnsList[#spawnsList + 1] = nSp end
                end
            end
        end

        if #spawnsList == 0 then
            spawnsList[1] = {
                x = tonumber(target.spawn_x),
                y = tonumber(target.spawn_y),
                z = tonumber(target.spawn_z),
                heading = tonumber(target.spawn_h or 0)
            }
        end

        for i, sp in ipairs(spawnsList) do
            if distanceSquared(marker, sp) > 100.0 * 100.0 then
                return response(false, "spawn_too_far", string.format("A vaga %d de spawn deve ficar a no máximo 100 metros da entrada.", i))
            end
        end

        -- Valida espaçamento mínimo entre vagas de spawn (mínimo 0.5m / 0.25m²)
        for i = 1, #spawnsList - 1 do
            for j = i + 1, #spawnsList do
                if distanceSquared(spawnsList[i], spawnsList[j]) < 0.25 then
                    return response(false, "spawns_too_close", string.format("As vagas %d e %d estão muito próximas (mínimo 0.5m de distância entre si).", i, j))
                end
            end
        end

        local mainSpawn = spawnsList[1]
        local spawnsJson = json.encode(spawnsList)

        local updatedRow = {
            id = id,
            garage_id = target.garage_id,
            name = name,
            permission = permission,
            payment = payment and "true" or "false",
            marker_x = marker.x,
            marker_y = marker.y,
            marker_z = marker.z,
            spawn_x = mainSpawn.x,
            spawn_y = mainSpawn.y,
            spawn_z = mainSpawn.z,
            spawn_h = mainSpawn.heading or 0.0,
            spawns = spawnsJson
        }

        MySQL.update.await([[
            UPDATE custom_garages
               SET name = ?, permission = ?, payment = ?,
                   marker_x = ?, marker_y = ?, marker_z = ?,
                   spawn_x = ?, spawn_y = ?, spawn_z = ?, spawn_h = ?,
                   spawns = ?
             WHERE id = ?
        ]], {
            updatedRow.name, updatedRow.permission, updatedRow.payment,
            updatedRow.marker_x, updatedRow.marker_y, updatedRow.marker_z,
            updatedRow.spawn_x, updatedRow.spawn_y, updatedRow.spawn_z, updatedRow.spawn_h,
            updatedRow.spawns,
            id
        })

        local synced, syncErr = pcall(function()
            return exports["vanguard_garage"]:ApplyCustomGarageMutation("upsert", updatedRow)
        end)

        if not synced or syncErr ~= true then
            -- Rollback to target
            MySQL.update.await([[
                UPDATE custom_garages
                   SET name = ?, permission = ?, payment = ?,
                       marker_x = ?, marker_y = ?, marker_z = ?,
                       spawn_x = ?, spawn_y = ?, spawn_z = ?, spawn_h = ?,
                       spawns = ?
                 WHERE id = ?
            ]], {
                target.name, target.permission, target.payment,
                target.marker_x, target.marker_y, target.marker_z,
                target.spawn_x, target.spawn_y, target.spawn_z, target.spawn_h,
                target.spawns,
                id
            })
            pcall(function() exports["vanguard_garage"]:ReloadCustomGarages(-1) end)
            return response(false, "sync_failed", "Falha na sincronização ao vivo: " .. tostring(syncErr))
        end

        local afterRows = fetchGarages() or {}
        local afterRecords = normalizeGarages(afterRows)
        return response(true, "updated", string.format("Garagem %s atualizada com sucesso.", target.garage_id), {
            id = id,
            revision = revisionOf(afterRecords)
        })
    end

    if action == "delete" then
        local id = integer(data.id, 1)
        if not id then return response(false, "invalid_id", "ID de garagem inválido.") end

        local target = MySQL.single.await("SELECT * FROM custom_garages WHERE id = ? LIMIT 1", { id })
        if not target then return response(false, "not_found", "A garagem informada não existe.") end

        local affected = MySQL.update.await("DELETE FROM custom_garages WHERE id = ?", { id })
        if not affected or affected == 0 then
            return response(false, "database_error", "Não foi possível remover do banco de dados.")
        end

        local synced, syncErr = pcall(function()
            return exports["vanguard_garage"]:ApplyCustomGarageMutation("remove", target)
        end)

        if not synced or syncErr ~= true then
            -- Rollback: restaurar registro
            MySQL.insert.await([[
                INSERT INTO custom_garages
                    (id, garage_id, name, permission, payment, marker_x, marker_y, marker_z, spawn_x, spawn_y, spawn_z, spawn_h, spawns)
                VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                target.id, target.garage_id, target.name, target.permission, target.payment,
                target.marker_x, target.marker_y, target.marker_z,
                target.spawn_x, target.spawn_y, target.spawn_z, target.spawn_h,
                target.spawns
            })
            pcall(function() exports["vanguard_garage"]:ReloadCustomGarages(-1) end)
            return response(false, "sync_failed", "Remoção revertida porque o cache live recusou: " .. tostring(syncErr))
        end

        local afterRows = fetchGarages() or {}
        local afterRecords = normalizeGarages(afterRows)
        return response(true, "deleted", string.format("Garagem %s removida com sucesso.", target.garage_id), {
            id = id,
            revision = revisionOf(afterRecords)
        })
    end

    return response(false, "unsupported_action", "Ação não reconhecida: " .. tostring(action))
end

-- ============================================================================
-- OX_LIB SERVER CALLBACKS
-- ============================================================================

lib.callback.register('vanguard_garage:server:getCityModule', function(source, module)
    if module ~= "garages" then
        return response(false, "invalid_module", "Módulo não suportado.")
    end
    local payload = buildGaragePayload(source)
    return response(true, "ok", "Módulo carregado com sucesso.", payload)
end)

lib.callback.register('vanguard_garage:server:executeCityAction', function(source, module, action, data, revision)
    if module ~= "garages" then
        return response(false, "invalid_module", "Módulo não suportado.")
    end
    return executeGarageAction(action, data, revision, source)
end)

-- ============================================================================
-- MRI_QADMIN PLUGIN REGISTRATION
-- ============================================================================

local function registerAdminPlugin()
    if GetResourceState('mri_Qadmin') ~= 'started' then return end
    local ok, res = pcall(function()
        return exports['mri_Qadmin']:RegisterPlugin({
            id = 'garages',
            label = 'Garagens',
            icon = 'warehouse',
            resource = 'vanguard_garage',
            htmlPath = 'admin/index.html',
            requiredPerms = { 'qadmin.garages', 'command' },
            permDefs = {
                { id = 'qadmin.garages', label = 'Gerenciar Garagens', category = 'Garagens' }
            },
            description = 'Criação e gerenciamento dinâmico de garagens e vagas de spawn',
        })
    end)
    if ok and res then
        print('^2[vanguard_garage]^7 Plugin administrativo de Garagens registrado no mri_Qadmin com sucesso!')
    end
end

AddEventHandler('mri_Qadmin:server:pluginsReady', registerAdminPlugin)

AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName == 'mri_Qadmin' then
        registerAdminPlugin()
    end
end)

CreateThread(function()
    Wait(500)
    registerAdminPlugin()
end)
