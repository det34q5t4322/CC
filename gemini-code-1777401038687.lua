local mon = peripheral.find("monitor")
mon.setTextScale(0.5)
local w, h = mon.getSize()

-- Текст песни с таймингами (в секундах)
local lyrics = {
    {t = 0,  text = "Давно решил, что не влюблюсь"},
    {t = 3,  text = "Я больше никогда..."},
    {t = 5,  text = "А тут явилась ты, мой котик!"},
    {t = 10, text = "Сейчас так скучно без тебя"},
    {t = 15, text = "Ты сердце разрываешь"},
    {t = 18, text = "С моей душой играешь..."},
    {t = 22, text = "Мой зайчик, зайчик, зайчик!"},
    {t = 26, text = "И вырастают крылья за спиной"},
    {t = 30, text = "И над землей летаю я!"}
}

local function drawScene(step, currentText)
    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Пульсирующее сердечко сверху
    local heartColor = (step % 2 == 0) and colors.red or colors.pink
    mon.setCursorPos(math.floor(w/2), 2)
    mon.setBackgroundColor(heartColor)
    mon.write(" ")
    mon.setCursorPos(math.floor(w/2)-1, 1)
    mon.write(" ")
    mon.setCursorPos(math.floor(w/2)+1, 1)
    mon.write(" ")

    -- Вывод субтитров
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    local startX = math.max(1, math.floor((w - #currentText) / 2))
    mon.setCursorPos(startX, math.floor(h/2) + 1)
    mon.write(currentText)
    
    -- Нижняя надпись
    mon.setTextColor(colors.magenta)
    mon.setCursorPos(math.floor(w/2 - 4), h)
    mon.write("I Love You")
end

local startTime = os.epoch("utc") / 1000
local step = 0

while true do
    local currentTime = (os.epoch("utc") / 1000) - startTime
    local currentText = ""
    
    -- Ищем актуальную строку
    for i = #lyrics, 1, -1 do
        if currentTime >= lyrics[i].t then
            currentText = lyrics[i].text
            break
        end
    end

    drawScene(step, currentText)
    step = step + 1
    sleep(0.5)
end
