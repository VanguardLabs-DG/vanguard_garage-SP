local Deformation = {}

---@param value number
---@param numDecimals number
local function Round (value, numDecimals)
	return math.floor(value * 10^numDecimals) / 10^numDecimals
end

---@param vehicle integer
local function GetVehicleOffsetsForDeformation (vehicle)
	local min, max = GetModelDimensions(GetEntityModel(vehicle))
	local X = Round((max.x - min.x) * 0.5, 2)
	local Y = Round((max.y - min.y) * 0.5, 2)
	local Z = Round((max.z - min.z) * 0.5, 2)
	local halfY = Round(Y * 0.5, 2)

	return {
		vector3(-X, Y,  0.0),
		vector3(-X, Y,  Z),

		vector3(0.0, Y,  0.0),
		vector3(0.0, Y,  Z),

		vector3(X, Y,  0.0),
		vector3(X, Y,  Z),


		vector3(-X, halfY,  0.0),
		vector3(-X, halfY,  Z),

		vector3(0.0, halfY,  0.0),
		vector3(0.0, halfY,  Z),

		vector3(X, halfY,  0.0),
		vector3(X, halfY,  Z),


		vector3(-X, 0.0,  0.0),
		vector3(-X, 0.0,  Z),

		vector3(0.0, 0.0,  0.0),
		vector3(0.0, 0.0,  Z),

		vector3(X, 0.0,  0.0),
		vector3(X, 0.0,  Z),


		vector3(-X, -halfY,  0.0),
		vector3(-X, -halfY,  Z),

		vector3(0.0, -halfY,  0.0),
		vector3(0.0, -halfY,  Z),

		vector3(X, -halfY,  0.0),
		vector3(X, -halfY,  Z),


		vector3(-X, -Y,  0.0),
		vector3(-X, -Y,  Z),

		vector3(0.0, -Y,  0.0),
		vector3(0.0, -Y,  Z),

		vector3(X, -Y,  0.0),
		vector3(X, -Y,  Z),
	}
end

---@param vehicle integer
---@param deformation table[]
Deformation.set = function (vehicle, deformation)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    if type(deformation) == "string" then
        deformation = json.decode(deformation)
    end
    if not deformation or not next(deformation) then return end

    local fDeformationDamageMult = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fDeformationDamageMult")
    local damageMult = 20.0
    if fDeformationDamageMult and fDeformationDamageMult > 0 then
        if (fDeformationDamageMult <= 0.55) then
            damageMult = 1000.0
        elseif (fDeformationDamageMult <= 0.65) then
            damageMult = 400.0
        elseif (fDeformationDamageMult <= 0.75) then
            damageMult = 200.0
        end
    end

    for _, v in pairs(deformation) do
        if v and v.offset and v.damage then
            local ox = v.offset.x or (type(v.offset) == "table" and v.offset[1])
            local oy = v.offset.y or (type(v.offset) == "table" and v.offset[2])
            local oz = v.offset.z or (type(v.offset) == "table" and v.offset[3])
            local d = (tonumber(v.damage) or 0.0) * damageMult
            if d > 0.01 and ox and oy and oz then
                if d > 14.0 then
                    d = 14.5
                end
                SetVehicleDamage(vehicle, ox + 0.0, oy + 0.0, oz + 0.0, d + 0.0, 1000.0, true)
            end
        end
    end
end

---@param vehicle integer
---@return table
Deformation.get = function ( vehicle )
    if not vehicle or not DoesEntityExist(vehicle) then return {} end
    local data = {}
    local offsets = GetVehicleOffsetsForDeformation(vehicle)

    for _, v in ipairs(offsets) do
        local def = GetVehicleDeformationAtPos(vehicle, v.x, v.y, v.z)
        local mag = 0.0
        if def then
            local ok, len = pcall(function() return #def end)
            if ok and len then
                mag = len
            elseif type(def) == "table" and (def.x or def[1]) then
                local dx = def.x or def[1] or 0.0
                local dy = def.y or def[2] or 0.0
                local dz = def.z or def[3] or 0.0
                mag = math.sqrt(dx*dx + dy*dy + dz*dz)
            end
        end
        local dmg = math.floor(mag * 1000.0) / 1000.0
        if dmg > 0.001 then
            data[#data+1] = {
                offset = { x = Round(v.x, 2), y = Round(v.y, 2), z = Round(v.z, 2) },
                damage = dmg
            }
        end
    end

    return data
end

return Deformation