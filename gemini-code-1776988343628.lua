local m = peripheral.find("monitor")
rednet.open("top")

local history = {}
local smooth_history = {}
local max_points = 70
local lastE = -1

-- Функция для сглаживания (усредняет последние 4 пакета данных)
local function getSmoothDelta()
    if #history == 0 then return 0 end
    local sum = 0
    local count = math.min(4, #history) 
    for i = #history - count + 1, #history do
        sum = sum + history[i]
    end
    return sum / count
end

local function draw(d, avgDelta)
    m.setBackgroundColor(colors.black)
    m.clear()
    m.setTextScale(0.5)
    local W, H = m.getSize()
    local midY = math.floor(H / 2) + 2

    -- 1. ТЕКСТОВАЯ ПАНЕЛЬ
    m.setCursorPos(2, 2)
    m.setTextColor(colors.cyan)
    m.write("CORE: " .. string.format("%.2f", d.energy/10^12) .. " TRF")

    m.setCursorPos(W/2 - 10, 2)
    m.setTextColor(colors.orange)
    m.write("REACT: " .. (d.status and "ON" or "OFF") .. " | " .. math.floor(d.temp) .. "K")
    
    m.setCursorPos(W - 25, 2)
    if avgDelta >= 0 then 
        m.setTextColor(colors.lime)
        m.write("NET: +" .. math.floor(avgDelta/10^6) .. "M RF/t")
    else 
        m.setTextColor(colors.red)
        m.write("NET: " .. math.floor(avgDelta/10^6) .. "M RF/t") 
    end

    -- 2. СЕТКА (Горизонт)
    m.setCursorPos(1, midY)
    m.setTextColor(colors.gray)
    m.write(string.rep("-", W))

    -- 3. СГЛАЖЕННЫЙ ГРАФИК
    local scale = 10 * 10^6 -- Масштаб: 10 миллионов RF/t на 1 пиксель экрана
    for i, val in ipairs(smooth_history) do
        local x = W - #smooth_history + i
        if val > 0 then
            local up = math.min(math.floor(val / scale), midY - 4)
            m.setTextColor(colors.lime)
            for j = 1, up do 
                m.setCursorPos(x, midY - j)
                m.write("|") 
            end
        elseif val < 0 then
            local down = math.min(math.floor(math.abs(val) / scale), H - midY - 1)
            m.setTextColor(colors.red)
            for j = 1, down do 
                m.setCursorPos(x, midY + j)
                m.write("|") 
            end
        end
    end
end

while true do
    local id, data = rednet.receive("MEGABASE_DATA", 5)
    if data then
        local delta = 0
        if lastE ~= -1 then delta = (data.energy - lastE) / 10 end
        lastE = data.energy

        -- Сохраняем сырые скачки
        table.insert(history, delta)
        if #history > max_points then table.remove(history, 1) end
        
        -- Вычисляем и сохраняем плавную линию
        local avgDelta = getSmoothDelta()
        table.insert(smooth_history, avgDelta)
        if #smooth_history > max_points then table.remove(smooth_history, 1) end

        draw(data, avgDelta)
    else
        m.clear()
        m.setCursorPos(5, 5)
        m.setTextColor(colors.red)
        m.write("CONNECTION LOST - WAITING FOR DATA...")
    end
end