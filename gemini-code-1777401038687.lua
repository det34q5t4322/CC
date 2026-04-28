local mon = peripheral.find("monitor")
mon.setTextScale(0.5)
local w, h = mon.getSize()

-- Рисуем маленькое сердечко по координатам
local function drawMiniHeart(x, y, color)
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(color)
    mon.write(" ")
    -- Форма сердечка из 3 пикселей
    mon.setCursorPos(x-1, y-1)
    mon.write(" ")
    mon.setCursorPos(x+1, y-1)
    mon.write(" ")
end

local function drawScene(step)
    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Текст по центру
    mon.setCursorPos(math.floor(w/2 - 4), math.floor(h/2))
    mon.setTextColor(colors.pink)
    mon.setBackgroundColor(colors.black)
    mon.write("i love you")

    -- Пульсирующие сердечки в разных углах
    local heartColor = (step % 2 == 0) and colors.red or colors.magenta
    
    -- Лево верх
    drawMiniHeart(4, 3, heartColor)
    -- Право верх
    drawMiniHeart(w-3, 4, heartColor)
    -- Лево низ
    drawMiniHeart(5, h-2, heartColor)
    -- Право низ
    drawMiniHeart(w-5, h-3, heartColor)
    
    -- Добавим еще одно маленькое прямо над надписью
    if step % 2 == 0 then
        drawMiniHeart(math.floor(w/2), math.floor(h/2 - 2), colors.pink)
    end
end

local s = 0
while true do
    drawScene(s)
    s = s + 1
    sleep(0.6)
end