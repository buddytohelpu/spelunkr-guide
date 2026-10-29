function epochMs() as Double
    date = CreateObject("roDateTime")
    return date.AsSeconds() * 1000.0# + date.GetMilliseconds()
end function

function clockText(ms as Double) as String
    date = CreateObject("roDateTime")
    date.FromSeconds(Int(ms / 1000))
    date.ToLocalTime()
    hour = date.GetHours()
    suffix = "AM"
    if hour >= 12 then suffix = "PM"
    hour = hour mod 12
    if hour = 0 then hour = 12
    return hour.ToStr() + ":" + Right("0" + date.GetMinutes().ToStr(), 2) + " " + suffix
end function

function dialText(number as Integer) as String
    if number < 10 then return "0" + number.ToStr()
    return number.ToStr()
end function

function minimum(a as Dynamic, b as Dynamic) as Dynamic
    if a < b then return a
    return b
end function

function maximum(a as Dynamic, b as Dynamic) as Dynamic
    if a > b then return a
    return b
end function
