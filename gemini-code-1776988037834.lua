local m = peripheral.find("monitor")
rednet.open("top") -- Убедись, что модем сверху

local history = {}
local max_points = 70 -- Сколько столбиков влезет на экран

local function draw(d)
    m.setBackgroundColor(colors.black)
    m.clear()
    m.setTextScale(0.5)
    local W, H = m.getSize()
    local midY = math.floor(H / 2) + 2 -- Линия горизонта

    -- 1. ТЕКСТОВАЯ ПАНЕЛЬ (СВЕРХУ)
    m.setCursorPos(2, 2)
    m.setTextColor(colors.cyan)
    m.write("CORE: " .. string.format("%.2f", d.energy/10^12) .. " TRF")

    m.setCursorPos(W/2 - 10, 2)
    m.setTextColor(colors.orange)
    m.write("REACT: " .. (d.status and "ON" or "OFF") .. " | " .. math.floor(d.temp) .. "K")

    m.setCursorPos(W - 20, 2)
    m.setTextColor(colors.magenta)
    m.write("SPS: " .. math.floor(d.sps/10^6) .. "M RF/t")

    -- 2. СЕТКА
    m.setCursorPos(1, midY)
    m.setTextColor(colors.gray)
    m.write(string.rep("-", W))

    -- 3. ДВОЙНОЙ ГРАФИК
    -- Масштаб: 1 деление = 20 млн RF/t (чтобы твои 100М были высотой в 5 блоков)
    local scale = 20 * 10^6 

    for i, val in ipairs(history) do
        local x = W - #history + i
        
        -- ПРИХОД (Зеленый - вверх)
        local up = math.min(math.floor(val.p / scale), midY - 4)
        m.setTextColor(colors.lime)
        for j = 1, up do
            m.setCursorPos(x, midY - j)
            m.write("|")
        end

        -- РАСХОД (Красный - вниз)
        local down = math.min(math.floor(val.s / scale), H - midY - 1)
        m.setTextColor(colors.red)
        for j = 1, down do
            m.setCursorPos(x, midY + j)
            m.write("|")
        end
    end
end

while true do
    local id, data = rednet.receive("MEGABASE_DATA", 5)
    if data then
        -- Записываем текущие показатели в историю
        table.insert(history, {p = data.prod, s = data.sps})
        if #history > max_points then table.remove(history, 1) end
        
        draw(data)
    else
        -- Если данные перестали приходить
        m.setCursorPos(W/2 - 5, H/2)
        m.setTextColor(colors.red)
        m.write("CONNECTION LOST")
    end
end