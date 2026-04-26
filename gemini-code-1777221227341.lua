-- ============================================================
--  Mekanism + Draconic Evolution  |  Telemetry Transmitter
--  ComputerCraft 1.20.1  |  Modem channel: 99
-- ============================================================

local CHANNEL  = 99
local INTERVAL = 0.75

-- ============================================================
--  Safe call helpers
-- ============================================================

local function safe(fn, ...)
    local ok, val = pcall(fn, ...)
    if ok then return val end
    return nil
end

local function getNum(dev, method)
    if not dev then return 0 end
    local v = safe(dev[method], dev)
    return (type(v) == "number") and v or 0
end

local function getBool(dev, method)
    if not dev then return false end
    local v = safe(dev[method], dev)
    return (v == true)
end

local function getStr(dev, method)
    if not dev then return "N/A" end
    local v = safe(dev[method], dev)
    return (type(v) == "string") and v or "N/A"
end

-- ============================================================
--  Device discovery
-- ============================================================

local function findDevices()
    local devs = {}

    devs.energyCore     = peripheral.find("draconic_rf_storage")
    devs.fissionReactor = peripheral.find("fissionReactorLogicAdapter")
    devs.fusionReactor  = peripheral.find("fusionReactorLogicAdapter")
    devs.boiler         = peripheral.find("boilerValve")
    devs.sps            = peripheral.find("spsPort")
    devs.chemTank       = peripheral.find("ultimateChemicalTank")
    devs.modem          = peripheral.find("modem")

    devs.turbines = {}
    local found = table.pack(peripheral.find("turbineValve"))
    for i = 1, found.n do
        table.insert(devs.turbines, found[i])
    end

    return devs
end

-- ============================================================
--  Debug: print found devices
-- ============================================================

local function printDeviceList(devs)
    print("============================================")
    print("  TELEMETRY TRANSMITTER  |  ch." .. CHANNEL)
    print("============================================")

    local function status(dev, label)
        if dev then
            local name = peripheral.getName(dev)
            print("  [OK] " .. label .. " -> " .. name)
        else
            print("  [--] " .. label .. " (not found)")
        end
    end

    status(devs.energyCore,     "Draconic Energy Core")
    status(devs.fissionReactor, "Fission Reactor")
    status(devs.fusionReactor,  "Fusion Reactor")
    status(devs.boiler,         "Boiler")
    status(devs.sps,            "SPS Port")
    status(devs.chemTank,       "Chemical Tank")
    status(devs.modem,          "Wireless Modem")

    if #devs.turbines == 0 then
        print("  [--] Turbines (not found)")
    else
        for i, t in ipairs(devs.turbines) do
            local name = peripheral.getName(t)
            print("  [OK] Turbine #" .. i .. " -> " .. name)
        end
    end

    print("============================================")
end

-- ============================================================
--  Telemetry collection
-- ============================================================

local function collectTelemetry(devs)
    local t = {}
    t.timestamp = os.clock()

    -- Draconic Energy Core
    local ec = devs.energyCore
    t.energyCore = {
        stored       = getNum(ec, "getEnergyStored"),
        max          = getNum(ec, "getMaxEnergyStored"),
        transferRate = getNum(ec, "getTransferPerTick"),
    }

    -- Mekanism Fission Reactor
    local fr = devs.fissionReactor
    t.fissionReactor = {
        active       = getBool(fr, "isActive"),
        temperature  = getNum(fr,  "getTemperature"),
        damage       = getNum(fr,  "getDamagePercent"),
        burnRate     = getNum(fr,  "getActualBurnRate"),
        heatCapacity = getNum(fr,  "getHeatCapacity"),
        fuelFilled   = getNum(fr,  "getFuelFilledPercentage"),
    }

    -- Mekanism Fusion Reactor
    local fu = devs.fusionReactor
    t.fusionReactor = {
        caseTemp     = getNum(fu,  "getCaseTemperature"),
        plasmaTemp   = getNum(fu,  "getPlasmaTemperature"),
        ignited      = getBool(fu, "isIgnited"),
        productionRate = getNum(fu, "getProductionRate"),
    }

    -- Mekanism Boiler
    local bo = devs.boiler
    t.boiler = {
        temperature  = getNum(bo, "getTemperature"),
        water        = getNum(bo, "getWater"),
        steam        = getNum(bo, "getSteam"),
        boilRate     = getNum(bo, "getBoilRate"),
        maxBoilRate  = getNum(bo, "getMaxBoilRate"),
    }

    -- Mekanism Turbines (all found)
    t.turbines = {}
    for i, turb in ipairs(devs.turbines) do
        t.turbines[i] = {
            speed        = getNum(turb, "getFlowRate"),
            production   = getNum(turb, "getProductionRate"),
            steamFlow    = getNum(turb, "getSteamInput"),
            maxSteamFlow = getNum(turb, "getMaxFlowRate"),
        }
    end

    -- Mekanism SPS
    local sp = devs.sps
    t.sps = {
        inputRate  = getNum(sp, "getInputRate"),
        outputRate = getNum(sp, "getOutputRate"),
    }

    -- Ultimate Chemical Tank
    local ct = devs.chemTank
    t.chemTank = {
        stored = getNum(ct, "getStored"),
        max    = getNum(ct, "getCapacity"),
        gas    = getStr(ct, "getGas"),
    }

    return t
end

-- ============================================================
--  Main loop
-- ============================================================

local devs = findDevices()
printDeviceList(devs)

if not devs.modem then
    print("[FATAL] Modem not found. Stopping.")
    return
end

devs.modem.open(CHANNEL)
print("[START] Transmitting on channel " .. CHANNEL)
print("--------------------------------------------")

local tick = 0
while true do
    tick = tick + 1
    local data = collectTelemetry(devs)
    data.tick = tick

    local ok, err = pcall(function()
        devs.modem.transmit(CHANNEL, CHANNEL, data)
    end)

    if not ok then
        print("[ERR] Transmit failed: " .. tostring(err))
    else
        local ec  = data.energyCore
        local fr  = data.fissionReactor
        local pct = (ec.max > 0) and math.floor(ec.stored / ec.max * 100) or 0
        term.clearLine()
        io.write(string.format(
            "\r[#%04d] E:%3d%%  Fis:%-3s  T:%.0fC  SPS-in:%.1f",
            tick,
            pct,
            fr.active and "ON" or "OFF",
            fr.temperature,
            data.sps.inputRate
        ))
    end

    os.sleep(INTERVAL)
end
