Config = {}

-- Load garage and vehicle data from JSON files
GarageZone = lib.loadJson('data.garages') ---@type table<string, GarageData>
CNV = lib.loadJson('data.vehiclesname') ---@type table<string, CustomName>

Config.Target = 'ox'           -- ox / qb
Config.RadialMenu = 'ox'       --- ox / qb / rhd
Config.FuelScript = 'cdn-fuel' --- rhd_fuel / ox_fuel / LegacyFuel / ps-fuel / cdn-fuel
Config.changeNamePrice = 15000 --- price for changing the name of the vehicle in the garage
Config.SpawnInVehicle = true  --- change this to true if you want the player to immediately enter the vehicle when the vehicle is taken out of the garage
Config.VehiclesInAllGarages = true --- Opção ZAP: deixe true para todos os veículos do player aparecerem em todas as garagens
Config.DisableVehicleCamera = false --- Desativa a movimentação de câmera ao puxar o veículo
Config.RepairOnInsurance = true -- Se true, o veículo virá 100% consertado ao pagar a franquia de 25% no Pátio. Se false, virá quebrado.
Config.LocateVehicleOutGarage = true --- Opção ZAP: encontrar veículos fora da garagem

--- Additional: (Requires ox_target or qb-target resource)
Config.UseJobVechileShop = false --- Change this to false if you do not want to use the work vehicle shop system from rhd
Config.UsePoliceImpound = true  --- change it to false if you don't want to use the police impound system from rhd

Config.InDevelopment = true     --- Turn this off when you have finished setting up this garage

-- Vehicle transfer settings
Config.TransferVehicle = {
    enable = true,  --- Enable or disable vehicle transfer functionality
    price = 100     --- Price for transferring a vehicle
}

-- Garage swap settings
Config.SwapGarage = {
    enable = true,  --- Enable or disable garage swapping functionality
    price = 500     --- Price for swapping garages
}

Config.GiveKeys = {
    tempkeys = false, -- true se você quiser dar chaves temporárias quando spawnar o veículo
    enable = true,
    onspawn = true, --- Opção ZAP: deixe true para seu player ganhar do nada uma chave do carro quando spawnar o veículo e remover quando ele guardar (ao invés dele ter que ir comprar em um chaveiro uma cópia)
    price = 500
}

-- Icon animation settings
Config.IconAnimation = "fade" --- Animation type for icons

-- Icons for different vehicle types
Config.Icons = {
    [8] = "motorcycle",  --- Icon for motorcycles
    [13] = "bicycle",    --- Icon for bicycles
    [14] = "sailboat",   --- Icon for sailboats
    [15] = "helicopter", --- Icon for helicopters
    [16] = "plane",      --- Icon for planes
}

-- Prices for impounding different vehicle types
Config.ImpoundPrice = {
    [0] = 15000,  --- Price for compact cars
    [1] = 15000,  --- Price for sedans
    [2] = 15000,  --- Price for SUVs
    [3] = 15000,  --- Price for coupes
    [4] = 15000,  --- Price for muscle cars
    [5] = 15000,  --- Price for sports classics
    [6] = 15000,  --- Price for sports cars
    [7] = 15000,  --- Price for super cars
    [8] = 15000,  --- Price for motorcycles
    [9] = 15000,  --- Price for off-road vehicles
    [10] = 15000, --- Price for industrial vehicles
    [11] = 15000, --- Price for utility vehicles
    [12] = 15000, --- Price for vans
    [13] = 15000, --- Price for cycles
    [14] = 15000, --- Price for boats
    [15] = 15000, --- Price for helicopters
    [16] = 15000, --- Price for planes
    [17] = 15000, --- Price for service vehicles
    [18] = 0,     --- Price for emergency vehicles
    [19] = 15000, --- Price for military vehicles
    [20] = 15000, --- Price for commercial vehicles
    [21] = 0      --- Price for trains (not applicable)
}

-- Garage Level System
Config.GarageLevels = {
    [1] = { slots = 2,  showroom = "level1" },
    [2] = { slots = 6,  showroom = "level2" },
    [3] = { slots = 10, showroom = "level3" },
}

Config.Showrooms = {
    Config = {
        Enable = true,
        AllowOnlyInPrivateGarages = false,
    },
    level1 = { -- 2 Car Garage
        EntranceCoords = vec4(173.2903, -1003.6, -99.65707, 0.0),
        ParkingSlots = {
            { Coords = vec4(171.2903, -1003.6, -99.65707, 0.0) }, -- Vaga 1 (Esquerda)
            { Coords = vec4(175.2903, -1003.6, -99.65707, 0.0) }, -- Vaga 2 (Direita)
        }
    },
    level2 = { -- 6 Car Garage
        EntranceCoords = vec4(197.8153, -1002.293, -99.65749, 0.0),
        ParkingSlots = {
            { Coords = vec4(193.38, -1004.22, -99.42, 335.76) },
            { Coords = vec4(195.95, -1004.22, -99.42, 335.76) },
            { Coords = vec4(198.52, -1004.22, -99.42, 335.76) },
            { Coords = vec4(201.09, -1004.22, -99.42, 335.76) },
            { Coords = vec4(203.66, -1004.22, -99.42, 335.76) },
            { Coords = vec4(206.23, -1004.22, -99.42, 335.76) },
        }
    },
    level3 = { -- Casino Garage (Old "car")
        EntranceCoords = vec4(1295.2756, 261.7921, -50.0573, 174.5392),
        ParkingSlots = {
            { Coords = vec4(1281.2789, 240.9465, -49.4692, 243.5022) },
            { Coords = vec4(1281.3644, 250.2220, -49.4689, 242.7067) },
            { Coords = vec4(1280.8601, 258.3342, -49.4696, 239.6884) },
            { Coords = vec4(1295.1112, 249.0047, -49.4691, 177.1261) },
            { Coords = vec4(1295.1277, 241.2695, -49.4692, 180.6348) },
            { Coords = vec4(1295.1410, 231.9178, -49.4692, 178.8318) },
            { Coords = vec4(1309.6279, 230.9311, -49.4691, 52.8349) },
            { Coords = vec4(1309.7224, 241.4225, -49.4700, 54.4629) },
            { Coords = vec4(1309.9415, 249.3070, -49.4696, 62.1490) },
            { Coords = vec4(1309.5300, 258.2726, -49.4688, 63.7715) },
        }
    },
    air = {
        EntranceCoords = vec4(-1264.9331, -3044.3931, -49.4903, 4.1420),
        ParkingSlots = {
            { Coords = vec4(-1276.7047, -2973.7190, -48.4897, 195.8378) },
            { Coords = vec4(-1259.4069, -2973.9412, -48.4897, 145.3174) },
            { Coords = vec4(-1256.5042, -2994.2913, -48.4899, 148.5025) },
            { Coords = vec4(-1275.6095, -2997.0205, -48.4898, 199.9497) },
            { Coords = vec4(-1280.2980, -3018.5117, -48.4901, 238.2952) },
            { Coords = vec4(-1258.7426, -3021.3916, -48.4903, 138.1917) },
        }
    },
}

-- Police impound settings
Config.PoliceImpound = {
    Target = {
        groups = {
            police = 0  --- Groups allowed to access police impound
        }
    },
    location = {
        [1] = {
            blip = {
                enable = true,       --- Enable or disable the blip on the map
                sprite = 473,        --- Sprite ID for the blip
                colour = 40          --- Colour ID for the blip
            },
            label = "Pátio do Detran",  --- Label for the police impound location
            zones = {
                points = {
                    vec3(824.69000244141, -1334.0200195312, 26.0),  --- Coordinates for the impound zone
                    vec3(831.70001220703, -1337.2700195312, 26.0),
                    vec3(831.73999023438, -1354.0300292969, 26.0),
                    vec3(832.10998535156, -1355.4799804688, 26.0),
                    vec3(824.72998046875, -1352.0400390625, 26.0),
                },
                thickness = 4.0,  --- Thickness of the zone boundaries
            },
        }
    }
}

-- Job vehicle shop settings
Config.JobVehicleShop = {
    {
        job = 'police',  --- Job associated with the vehicle shop
        label = 'Police Vehicle Shop',  --- Label for the vehicle shop
        ped = {
            model = 'csb_trafficwarden',  --- Pedestrian model for the shop
            coords = vec(457.9160, -1026.4635, 28.4376, 57.2678)  --- Coordinates for the shop
        },
        spawn = vec(443.9391, -1021.4270, 28.2857, 92.6928),  --- Coordinates where vehicles spawn
        vehicle = {
            police = {
                price = 500,  --- Price for the police vehicle
                label = 'Police 1',  --- Label for the vehicle
                prefixPlate = 'POL',  --- Prefix for the vehicle plate
                forRank = {
                    [0] = true,  --- Rank 0 can access this vehicle
                    [1] = true,  --- Rank 1 can access this vehicle
                    [2] = true   --- Rank 2 can access this vehicle
                }
            },
            police2 = {
                price = 500,  --- Price for the second police vehicle
                label = 'Police 2',  --- Label for the second vehicle
                prefixPlate = 'POL',  --- Prefix for the vehicle plate
                forRank = {
                    [0] = true,  --- Rank 0 can access this vehicle
                    [1] = true,  --- Rank 1 can access this vehicle
                    [2] = true   --- Rank 2 can access this vehicle
                }
            }
        },
    }
}

--- Do not modify this section
Config.HouseGarages = {}
