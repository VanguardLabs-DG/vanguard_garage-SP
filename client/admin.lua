-- ============================================================================
-- VANGUARD_GARAGE - CLIENT ADMIN NUI & WORLD CAPTURE
-- ============================================================================

local worldCaptureActive = false

local function nuiResponse(ok, code, message, data)
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

local function captureCurrentPosition()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    return {
        coords = {
            x = math.floor(coords.x * 100 + 0.5) / 100,
            y = math.floor(coords.y * 100 + 0.5) / 100,
            z = math.floor(coords.z * 100 + 0.5) / 100,
            heading = math.floor(heading * 10 + 0.5) / 10
        },
        heading = math.floor(heading * 10 + 0.5) / 10
    }
end

-- ============================================================================
-- NUI CALLBACKS
-- ============================================================================

RegisterNUICallback("getCityModule", function(data, cb)
    local module = data and data.module or "garages"
    local res = lib.callback.await("vanguard_garage:server:getCityModule", false, module)
    cb(res or nuiResponse(false, "error", "Falha ao obter dados do servidor."))
end)

RegisterNUICallback("executeCityAction", function(data, cb)
    if not data or not data.action then
        cb(nuiResponse(false, "invalid_payload", "Parâmetros insuficientes."))
        return
    end
    local res = lib.callback.await("vanguard_garage:server:executeCityAction", false, data.module or "garages", data.action, data.data, data.revision)
    cb(res or nuiResponse(false, "error", "Falha ao executar ação no servidor."))
end)

RegisterNUICallback("teleportToCoords", function(data, cb)
    local coords = data and data.coords
    if coords and coords.x and coords.y and coords.z then
        local ped = PlayerPedId()
        DoScreenFadeOut(200)
        Wait(250)
        SetEntityCoords(ped, coords.x, coords.y, coords.z + 0.2, false, false, false, true)
        if coords.heading then
            SetEntityHeading(ped, coords.heading)
        end
        Wait(250)
        DoScreenFadeIn(200)
        cb(nuiResponse(true, "teleported", "Teleportado com sucesso."))
    else
        cb(nuiResponse(false, "invalid_coords", "Coordenadas inválidas."))
    end
end)

RegisterNUICallback("detectWorldObject", function(data, cb)
    local kind = data and tostring(data.kind or "position") or "position"

    if worldCaptureActive then
        cb(nuiResponse(false, "capture_busy", "Já existe uma captura de posição em andamento."))
        return
    end

    worldCaptureActive = true

    -- Fecha temporariamente o painel mri_Qadmin para liberar visão e controles do jogador
    pcall(function()
        if exports['mri_Qadmin'] then
            exports['mri_Qadmin']:ClosePlugin('garages')
        end
    end)
    SetNuiFocus(false, false)

    CreateThread(function()
        local deadline = GetGameTimer() + 45000 -- 45s timeout
        local finished = false

        local function finish(payload)
            if finished then return end
            finished = true
            worldCaptureActive = false

            -- Reabre o painel mri_Qadmin diretamente na aba de garagens com foco limpo
            pcall(function()
                if exports['mri_Qadmin'] then
                    exports['mri_Qadmin']:OpenPlugin('garages')
                else
                    SetNuiFocus(true, true)
                end
            end)

            Wait(100)
            cb(payload)
        end

        while not finished and GetGameTimer() < deadline do
            Wait(0)
            local captured = captureCurrentPosition()

            if kind == "spawn" then
                -- Vaga de spawn: desenha anel no chão e seta direcional na altura dos olhos
                DrawMarker(
                    28,
                    captured.coords.x, captured.coords.y, captured.coords.z + 0.1,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, captured.heading,
                    0.4, 0.4, 0.4,
                    52, 152, 219, 175,
                    false, false, 0, true, false, false, false
                )
                DrawMarker(
                    0,
                    captured.coords.x, captured.coords.y, captured.coords.z + 1.1,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, captured.heading,
                    0.45, 0.45, 0.45,
                    67, 211, 139, 210,
                    false, false, 0, true, false, false, false
                )
            else
                -- Ponto de entrada / marcador de interação
                DrawMarker(
                    28,
                    captured.coords.x, captured.coords.y, captured.coords.z + 0.12,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, captured.heading,
                    0.3, 0.3, 0.3,
                    67, 211, 139, 180,
                    false, false, 0, true, false, false, false
                )
            end

            BeginTextCommandDisplayHelp("STRING")
            AddTextComponentSubstringPlayerName("Posicione-se no local desejado. ~INPUT_FRONTEND_ACCEPT~ Confirmar | ~INPUT_FRONTEND_CANCEL~ Cancelar")
            EndTextCommandDisplayHelp(0, false, true, -1)

            -- ENTER / ACCEPT
            if IsControlJustPressed(0, 191) or IsControlJustPressed(0, 201) then
                finish(nuiResponse(true, "position_captured", "Posição capturada.", captured))
            -- BACKSPACE / ESC / CANCEL
            elseif IsControlJustPressed(0, 194) or IsControlJustPressed(0, 200) or IsControlJustPressed(0, 202) then
                finish(nuiResponse(false, "selection_cancelled", "Captura cancelada."))
            end
        end

        if not finished then
            finish(nuiResponse(false, "selection_timeout", "Tempo limite de captura esgotado."))
        end
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if worldCaptureActive then
            worldCaptureActive = false
            SetNuiFocus(false, false)
        end
    end
end)
