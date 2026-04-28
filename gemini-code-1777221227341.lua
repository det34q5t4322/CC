local mon = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
mon.setTextScale(0.5)
local w, h = mon.getSize()

-- Таблица кодов с твоего скрина
local ru = {
    ["А"]="\191", ["Б"]="\192", ["В"]="\193", ["Г"]="\194", ["Д"]="\195", ["Е"]="\196", ["Ё"]="\197", ["Ж"]="\198", ["З"]="\199", ["И"]="\200", ["Й"]="\201", ["К"]="\202", ["Л"]="\203", ["М"]="\204", ["Н"]="\205", ["О"]="\206", ["П"]="\207", ["Р"]="\208", ["С"]="\209", ["Т"]="\210", ["У"]="\211", ["Ф"]="\212", ["Х"]="\213", ["Ц"]="\214", ["Ч"]="\215", ["Ш"]="\216", ["Щ"]="\217", ["Ъ"]="\218", ["Ы"]="\219", ["Ь"]="\220", ["Э"]="\221", ["Ю"]="\222", ["Я"]="\223",
    ["а"]="\224", ["б"]="\225", ["в"]="\226", ["г"]="\227", ["д"]="\228", ["е"]="\229", ["ё"]="\230", ["ж"]="\231", ["з"]="\232", ["и"]="\233", ["й"]="\234", ["к"]="\235", ["л"]="\236", ["м"]="\237", ["н"]="\238", ["о"]="\239", ["п"]="\240", ["р"]="\241", ["с"]="\242", ["т"]="\243", ["у"]="\244", ["ф"]="\245", ["х"]="\246", ["ц"]="\247", ["ч"]="\248", ["ш"]="\249", ["щ"]="\250", ["ъ"]="\251", ["ы"]="\252", ["ь"]="\253", ["э"]="\254", ["ю"]="\255", ["я"]="\13"
}

local function encode(text)
    local result = ""
    local i = 1
    while i <= #text do
        local found = false
        for char, code in pairs(ru) do
            if text:sub(i, i + #char - 1) == char then
                result = result .. code
                i = i + #char
                found = true
                break
            end
        end
        if not found then
            result = result .. text:sub(i, i)
            i = i + 1
        end
    end
    return result
end

local full_lyrics = {
    {t=0,  s="Давно решил"},
    {t=2,  s="Что не влюблюсь"},
    {t=4,  s="Я больше никогда"},
    {t=7,  s="А тут явилась ты"},
    {t=9,  s="Мой котик котик"},
    {t=12, s="Ты сердце разрываешь"},
    {t=15, s="С моей душой играешь"},
    {t=18, s="Мой зайчик"},
    {t=20, s="Я летаю!"}
}

local colors_rainbow = {colors.red, colors.orange, colors.yellow, colors.green, colors.lightBlue, colors.magenta}

local function draw(step, text)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    -- Сердечки по бокам
    local c = (step % 2 == 0) and colors.red or colors.pink
    mon.setBackgroundColor(c)
    mon.setCursorPos(2, 2) mon.write(" ")
    mon.setCursorPos(w-1, 2) mon.write(" ")

    -- Радужный текст
    local encoded = encode(text)
    local startX = math.max(1, math.floor((w - #encoded) / 2) + 1)
    for i = 1, #encoded do
        mon.setCursorPos(startX + i - 1, math.floor(h/2) + 1)
        mon.setTextColor(colors_rainbow[(i + step) % #colors_rainbow + 1])
        mon.setBackgroundColor(colors.black)
        mon.write(encoded:sub(i, i))
    end
end

local start = os.epoch("utc") / 1000
local step = 0

while true do
    local now = (os.epoch("utc") / 1000) - start
    local line = ""
    for i = #full_lyrics, 1, -1 do
        if now >= full_lyrics[i].t then
            line = full_lyrics[i].s
            break
        end
    end
    
    draw(step, line)
    if step % 2 == 0 and speaker then
        speaker.playNote("bit", 2, 12)
    end
    
    step = step + 1
    sleep(0.3)
end
