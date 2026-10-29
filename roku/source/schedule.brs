' Native port of Spelunkr's engine 5. See PROVENANCE.md and the pinned JS reference.
' All timestamps and unsigned arithmetic use Double to avoid Roku's Int32 overflow.
function sMod(value as Double, divisor as Double) as Double
    return value - Int(value / divisor) * divisor
end function

function sI32(value as Double) as Integer
    value = sMod(value, 4294967296.0#)
    if value >= 2147483648.0# then value -= 4294967296.0#
    return value
end function

function sUnsigned(value as Integer) as Double
    if value < 0 then return value + 4294967296.0#
    return value * 1.0#
end function

function sXor(a as Integer, b as Integer) as Integer
    return (a or b) and (not (a and b))
end function

function sShift(value as Integer, bits as Integer) as Integer
    return Int(sUnsigned(value) / (2.0# ^ bits))
end function

function sImul(a as Integer, b as Integer) as Integer
    au = sUnsigned(a)
    bu = sUnsigned(b)
    al = sMod(au, 65536)
    bl = sMod(bu, 65536)
    high = sMod(Int(au / 65536) * bl + Int(bu / 65536) * al, 65536)
    return sI32(al * bl + high * 65536.0#)
end function

function sRandom(state as Object) as Double
    state.value = sI32(state.value + 1831565813.0#)
    value = state.value
    n = sImul(sXor(value, sShift(value, 15)), 1 or value)
    n = sXor(n, sI32(n * 1.0# + sImul(sXor(n, sShift(n, 7)), 61 or n)))
    return sUnsigned(sXor(n, sShift(n, 14))) / 4294967296.0#
end function

' Roku strings are UTF-8; the website hashes and measures UTF-16 code units.
function sUtf16(text as String) as Object
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(text)
    units = []
    i = 0
    while i < bytes.count()
        code = bytes[i]
        if code < 128
            i += 1
        else if code < 224
            code = (code - 192) * 64 + bytes[i + 1] - 128
            i += 2
        else if code < 240
            code = (code - 224) * 4096 + (bytes[i + 1] - 128) * 64 + bytes[i + 2] - 128
            i += 3
        else
            code = (code - 240) * 262144 + (bytes[i + 1] - 128) * 4096 + (bytes[i + 2] - 128) * 64 + bytes[i + 3] - 128 - 65536
            units.push(55296 + Int(code / 1024))
            code = 56320 + (code mod 1024)
            i += 4
        end if
        units.push(code)
    end while
    return units
end function

function sHash(text as String) as Integer
    value = 0
    for each code in sUtf16(text)
        value = sI32(value * 31.0# + code)
    end for
    return value
end function

function sCopy(source as Object) as Object
    target = {}
    target.append(source)
    return target
end function

function sArray(source as Dynamic) as Object
    if source = invalid then return []
    return source
end function

function sValue(value as Dynamic, fallback as Dynamic) as Dynamic
    if value = invalid then return fallback
    return value
end function

function sSlideMs(text as String) as Double
    return maximum(2500, 1500 + sUtf16(text).count() * 55)
end function

function sBumpPool(bumps as Dynamic) as Object
    result = { live: [], yearRound: [], seasonal: [] }
    for each bump in sArray(bumps)
        if bump.active <> false
            duration = 0.0#
            for each slide in sArray(bump.slides)
                duration += sSlideMs(slide.text)
            end for
            bump.slideMs = duration
            result.live.push(bump)
            if bump.date_range = invalid
                result.yearRound.push(bump)
            else
                range = bump.date_range
                if Len(range[0]) > 5
                    date = CreateObject("roDateTime")
                    date.FromISO8601String(range[0] + "T00:00:00Z")
                    bump.dateStart = date.AsSeconds() * 1000.0#
                    date.FromISO8601String(range[1] + "T23:59:59Z")
                    bump.dateEnd = date.AsSeconds() * 1000.0# + 999
                    bump.dateFull = true
                else
                    bump.dateStart = Val(Left(range[0], 2)) * 100 + Val(Right(range[0], 2))
                    bump.dateEnd = Val(Left(range[1], 2)) * 100 + Val(Right(range[1], 2))
                    bump.dateFull = false
                end if
                result.seasonal.push(bump)
            end if
        end if
    end for
    return result
end function

function sInSeason(bump as Object, at as Double, monthDay as Integer) as Boolean
    if bump.dateFull then return at >= bump.dateStart and at <= bump.dateEnd
    if bump.dateStart <= bump.dateEnd then return monthDay >= bump.dateStart and monthDay <= bump.dateEnd
    return monthDay >= bump.dateStart or monthDay <= bump.dateEnd
end function

function sSeason(pool as Object, at as Double) as Object
    if pool.seasonal.count() = 0 then return { items: pool.yearRound, key: "" }
    date = CreateObject("roDateTime")
    date.FromSeconds(Int(at / 1000))
    monthDay = date.GetMonth() * 100 + date.GetDayOfMonth()
    active = {}
    ids = []
    for each bump in pool.seasonal
        if sInSeason(bump, at, monthDay)
            active[bump.id] = true
            ids.push(bump.id)
        end if
    end for
    if ids.count() = 0 then return { items: pool.yearRound, key: "" }
    items = []
    for each bump in pool.live
        if bump.date_range = invalid
            items.push(bump)
        else if active.doesExist(bump.id)
            items.push(bump)
        end if
    end for
    return { items: items, key: ids.join("|") }
end function

function sPick(pool as Object, breakIndex as Integer, channel as String, seed as String, at as Double) as Dynamic
    items = sSeason(pool, at).items
    if items.count() = 0 then return invalid
    rng = { value: sHash(channel + "-break-" + breakIndex.ToStr() + "-" + seed) }
    return items[Int(sRandom(rng) * items.count())]
end function

function sShuffle(items as Object, recent as Object, seed as Integer) as Object
    rng = { value: seed }
    order = items.slice(0)
    for i = order.count() - 1 to 1 step -1
        j = Int(sRandom(rng) * (i + 1))
        temp = order[i]
        order[i] = order[j]
        order[j] = temp
    end for
    window = Int(order.count() / 2)
    limits = {}
    for i = minimum(window, recent.count()) to 1 step -1
        limits[recent[recent.count() - i].id] = window + 1 - i
    end for
    for i = 1 to minimum(window, recent.count())
        bump = recent[recent.count() - i]
        position = -1
        for j = 0 to order.count() - 1
            if order[j].id = bump.id then position = j
        end for
        limit = sValue(limits[bump.id], 0)
        if position >= 0 and position < limit
            choices = []
            for j = limit to order.count() - 1
                if sValue(limits[order[j].id], 0) <= position then choices.push(j)
            end for
            swap = choices[Int(sRandom(rng) * choices.count())]
            temp = order[position]
            order[position] = order[swap]
            order[swap] = temp
        end if
    end for
    return order
end function

function sDeck(carry as Dynamic) as Object
    if carry = invalid then return { order: [], pos: 0, key: invalid, recent: [], rounds: 0 }
    return { order: carry.order, pos: carry.pos, key: carry.key, recent: carry.recent.slice(0), rounds: 0 }
end function

function sDeal(deck as Object, pool as Object, channel as String, seed as String, at as Double) as Dynamic
    seasonal = sSeason(pool, at)
    if seasonal.items.count() = 0 then return invalid
    if deck.key <> seasonal.key or deck.pos >= deck.order.count()
        hash = sHash(channel + "-deck-" + seed + "-" + deck.rounds.ToStr())
        deck.rounds++
        deck.order = sShuffle(seasonal.items, deck.recent, hash)
        deck.pos = 0
        deck.key = seasonal.key
    end if
    bump = deck.order[deck.pos]
    deck.pos++
    deck.recent.push(bump)
    if deck.recent.count() > deck.order.count() then deck.recent.shift()
    return bump
end function

function sAudio(items as Object, id as String, breakIndex as Integer, seed as String) as Dynamic
    if items.count() = 0 then return invalid
    rng = { value: sHash(id + "-audio-" + breakIndex.ToStr() + "-" + seed) }
    audio = sCopy(items[Int(sRandom(rng) * items.count())])
    audio.startOffset = Int(sRandom(rng) * 60)
    return audio
end function

function sYear(item as Object) as Dynamic
    if item.year = invalid then return invalid
    if m.sYearRegex = invalid then m.sYearRegex = CreateObject("roRegex", "^\s*[+-]?\d+", "")
    matches = m.sYearRegex.Match(item.year.ToStr())
    if matches.count() = 0 then return invalid
    return Val(matches[0])
end function

function sYearKey(year as Dynamic) as String
    if year = invalid then return "null"
    return year.ToStr()
end function

' Stable mergesort preserves JS's phase, case-sensitive ID, then input-index order.
function sRankBefore(a as Object, b as Object) as Boolean
    if a.score <> b.score then return a.score < b.score
    if a.id <> b.id then return a.id < b.id
    return a.index < b.index
end function

function sRankSort(items as Object) as Object
    count = items.count()
    width = 1
    source = items.slice(0)
    while width < count
        target = []
        for start = 0 to count - 1 step width * 2
            left = start
            middle = minimum(start + width, count)
            right = middle
            finish = minimum(start + width * 2, count)
            while left < middle or right < finish
                useLeft = right >= finish
                if left < middle and right < finish then useLeft = sRankBefore(source[left], source[right])
                if useLeft
                    target.push(source[left])
                    left++
                else
                    target.push(source[right])
                    right++
                end if
            end while
        end for
        source = target
        width *= 2
    end while
    return source
end function

function sAdRates(items as Object, block as Dynamic, gap as Double, sliceMs as Double) as Object
    totalMs = 0.0#
    sinceAd = 0.0#
    blockMs = 0.0#
    total = 0
    byYear = {}
    for i = 0 to items.count() - 1
        item = items[i]
        duration = item.duration * 1000.0#
        totalMs += duration
        sinceAd += duration
        blockMs += duration
        card = false
        if block <> invalid then card = i < items.count() - 1 and blockMs < block.lengthMs
        if card
            totalMs += block.cardMs
            sinceAd += block.cardMs
            blockMs += block.cardMs
        else
            blockMs = 0
            following = items[(i + 1) mod items.count()]
            if item.offAir <> true and following.offAir <> true and sinceAd >= gap
                total++
                year = sYearKey(sYear(item))
                if not byYear.doesExist(year) then byYear[year] = { year: sYear(item), count: 0 }
                byYear[year].count++
                totalMs += 20000 + sliceMs
                sinceAd = 10000
            else
                totalMs += 20000
                sinceAd += 20000
            end if
        end if
    end for
    return { cycleMs: totalMs, total: total, byYear: byYear }
end function

function sAdPlan(version as Object) as Object
    slices = version.ads.slices
    ranked = []
    sum = 0.0#
    years = []
    for i = 0 to slices.count() - 1
        ad = slices[i]
        rng = { value: sHash("ad-" + ad.id) }
        ranked.push({ index: i, id: ad.id, score: Int(sRandom(rng) * 1000000) })
        years.push(sYear(ad))
        sum += ad.lengthMs
    end for
    ordered = sRankSort(ranked)
    phases = []
    for i = 0 to ordered.count() - 1
        ordered[i].phase = Int(i * 1000000.0# / ordered.count())
        phases[ordered[i].index] = ordered[i].phase
    end for
    start = version.ads.start
    if start = invalid then start = sMod(sUnsigned(sHash("ads-" + version.channelId)), 1000)
    return { ordered: ordered, phases: phases, years: years, slices: slices, start: start * 1000, decades: version.ads.decades, rates: sAdRates(version.items, version.block, sValue(version.ads.gapMs, 1200000), sum / slices.count()), tierCache: {} }
end function

function sYearMatches(a as Dynamic, b as Dynamic, tolerance as Integer, decades as Boolean) as Boolean
    if tolerance = -1 then return true
    if a = invalid or b = invalid then return false
    if decades then return Abs(Int(a / 10) - Int(b / 10)) <= tolerance
    return Abs(a - b) <= tolerance
end function

function sAdTier(plan as Object, year as Dynamic, tolerance as Integer, decades = false as Boolean) as Object
    list = []
    places = []
    for each ranked in plan.ordered
        i = ranked.index
        if plan.slices[i].anywhere = true or sYearMatches(plan.years[i], year, tolerance, decades)
            list.push(i)
            places.push(ranked.phase)
        end if
    end for
    rate = 0
    for each key in plan.rates.byYear
        bucket = plan.rates.byYear[key]
        if sYearMatches(bucket.year, year, tolerance, decades) then rate += bucket.count
    end for
    demand = 0.0#
    if plan.rates.cycleMs > 0 then demand = rate * 1209600000.0# / plan.rates.cycleMs
    healthy = list.count() > 0 and list.count() >= demand
    roundMs = 1209600000.0#
    if not healthy and list.count() > 0 then roundMs = maximum(3600000, Int(list.count() * plan.rates.cycleMs / rate))
    return { list: list, places: places, roundMs: roundMs, healthy: healthy, tolerance: tolerance }
end function

function sAdTiers(plan as Object, year as Dynamic) as Object
    key = sYearKey(year)
    if plan.tierCache.doesExist(key) then return plan.tierCache[key]
    tiers = []
    if year = invalid
        tiers.push(sAdTier(plan, year, -1))
    else
        tiers.push(sAdTier(plan, year, 3))
        tiers.push(sAdTier(plan, year, 6))
        if plan.decades <> invalid then tiers.push(sAdTier(plan, year, plan.decades, true))
        tiers.push(sAdTier(plan, year, -1))
    end if
    first = 0
    for i = 0 to tiers.count() - 1
        if tiers[i].healthy or tiers[i].tolerance = -1
            first = i
            exit for
        end if
    end for
    result = tiers.slice(first)
    plan.tierCache[key] = result
    return result
end function

function sPhase(at as Double, roundMs as Double, start as Integer) as Integer
    return sMod(Int(sMod(at, roundMs) * 1000000.0# / roundMs) + start, 1000000)
end function

function sLowerBound(places as Object, phase as Integer) as Integer
    low = 0
    high = places.count()
    while low < high
        mid = Int((low + high) / 2)
        if places[mid] < phase
            low = mid + 1
        else
            high = mid
        end if
    end while
    return low
end function

function sChooseAd(plan as Object, used as Object, year as Dynamic, at as Double, fromMs as Double) as Integer
    if used.count() >= plan.phases.count() then used.clear()
    tiers = sAdTiers(plan, year)
    middles = []
    for each tier in tiers
        count = tier.list.count()
        if count > 0
            first = sPhase(fromMs, tier.roundMs, plan.start)
            last = sPhase(at, tier.roundMs, plan.start)
            span = 0
            if at > fromMs
                span = sMod(last - first + 1000000, 1000000)
                if at - fromMs >= tier.roundMs then span = 1000000
            end if
            recent = Int(minimum(86400000, tier.roundMs) * 1000000.0# / tier.roundMs)
            middle = sLowerBound(tier.places, first + 1)
            middles.push({ tier: tier, middle: middle })
            for j = 0 to count - 1
                index = (middle + j) mod count
                distance = sMod(tier.places[index] - first + 1000000, 1000000)
                if distance = 0 then distance = 1000000
                if distance > span then exit for
                choice = tier.list[index]
                if not used.doesExist(choice.ToStr())
                    used[choice.ToStr()] = true
                    return choice
                end if
            end for
            for j = 1 to count
                index = (middle - j + count * 2) mod count
                if sMod(first - tier.places[index] + 1000000, 1000000) >= recent then exit for
                choice = tier.list[index]
                if not used.doesExist(choice.ToStr())
                    used[choice.ToStr()] = true
                    return choice
                end if
            end for
        end if
    end for
    for each info in middles
        tier = info.tier
        count = tier.list.count()
        for j = 1 to count
            choice = tier.list[(info.middle - j + count * 2) mod count]
            if not used.doesExist(choice.ToStr())
                used[choice.ToStr()] = true
                return choice
            end if
        end for
    end for
    return -1
end function

function sHydrate(manifest as Object, platform as Dynamic, pointer as Object, channel as String) as Dynamic
    if manifest.engine > 5 then return invalid
    if manifest.items = invalid then return invalid
    if manifest.items.count() = 0 then return invalid
    for each item in manifest.items
        if item.duration = invalid then return invalid
        if item.duration <= 0 or Int(item.duration) <> item.duration then return invalid
    end for
    version = { v: pointer.v, epochMs: pointer.epochMs * 1.0#, effectiveAtMs: sValue(pointer.effectiveAtMs, pointer.epochMs) * 1.0#, startIndex: sValue(pointer.startIndex, 0), channelId: channel, engine: sValue(manifest.engine, 1), items: manifest.items, block: manifest.block, ads: manifest.ads, bumps: invalid, fwd: [], back: [], built: {}, builtKeys: [], adCarry: [], deckCarry: [], plan: invalid }
    if version.startIndex < 0 or version.startIndex >= version.items.count() then return invalid
    if version.ads <> invalid
        if sArray(version.ads.slices).count() = 0 then version.ads = invalid
    end if
    if platform <> invalid
        if sArray(manifest.bumps).count() > 0 and sArray(platform.bumps).count() > 0
            audio = sArray(manifest.audio)
            if manifest.audioOverlay = true
                audio = []
                if manifest.audioPools <> invalid
                    for each key in manifest.audioPools
                        for each track in manifest.audioPools[key]
                            audio.push(track)
                        end for
                    end for
                end if
            end if
            version.bumps = { channel: sBumpPool(manifest.bumps), platform: sBumpPool(platform.bumps), channelAudio: audio, platformAudio: sArray(platform.audio) }
        end if
    end if
    return version
end function

sub sAppend(cycle as Object, entry as Object, duration as Double)
    entry.index = cycle.entries.count()
    entry.v = cycle.v
    entry.key = cycle.v.ToStr() + ":" + cycle.k.ToStr() + ":" + entry.index.ToStr()
    entry.offMs = cycle.lengthMs
    entry.durMs = duration
    cycle.entries.push(entry)
    cycle.lengthMs += duration
end sub

function sMakeCycle(version as Object, k as Integer, startMs as Double) as Object
    seed = version.v.ToStr() + "." + k.ToStr()
    cycle = { k: k, v: version.v, startMs: startMs, lengthMs: 0.0#, entries: [] }
    firstIndex = 0
    if k = 0 then firstIndex = version.startIndex
    deck = invalid
    carry = invalid
    if k >= 1
        carry = version.adCarry[k]
    end if
    if version.bumps <> invalid and version.engine >= 5
        deckCarry = invalid
        if k >= 1 then deckCarry = version.deckCarry[k]
        deck = sDeck(deckCarry)
    end if
    if version.ads <> invalid and version.bumps <> invalid
        if version.plan = invalid then version.plan = sAdPlan(version)
    end if
    used = {}
    recent = []
    adFrom = invalid
    if carry <> invalid
        for each pair in carry.recent
            if pair[0] >= 0 and pair[0] < version.ads.slices.count() then used[pair[0].ToStr()] = true
            recent.push(pair)
        end for
        adFrom = carry.fromMs
    end if
    adsMade = 0
    outFrom = invalid
    time = startMs
    blockTime = 0.0#
    adTime = 0.0#
    cardIndex = 0
    for index = firstIndex to version.items.count() - 1
        item = version.items[index]
        video = sCopy(item)
        video.type = "video"
        video.videoIndex = index
        length = item.duration * 1000.0#
        sAppend(cycle, video, length)
        time += length
        blockTime += length
        adTime += length
        if version.bumps <> invalid
            isCard = false
            if version.block <> invalid then isCard = index < version.items.count() - 1 and blockTime < version.block.lengthMs
            if isCard
                sting = invalid
                length = version.block.cardMs
                stings = sArray(version.block.stings)
                if stings.count() > 0
                    rng = { value: sHash(version.channelId + "-card-" + index.ToStr() + "-" + seed) }
                    sting = stings[Int(sRandom(rng) * stings.count())]
                    length = sting.lengthMs
                end if
                sAppend(cycle, { type: "up-next", breakIndex: index, cardIndex: cardIndex, sting: sting }, length)
                cardIndex++
                time += length
                blockTime += length
                adTime += length
            else
                blockTime = 0
                seasonAt = time
                if k < 0 then seasonAt = version.epochMs
                if deck <> invalid
                    channelBump = sDeal(deck, version.bumps.channel, version.channelId, seed, seasonAt)
                else
                    channelBump = sPick(version.bumps.channel, index, version.channelId, seed, seasonAt)
                end if
                platformBump = sPick(version.bumps.platform, index, "spelunkr", seed, seasonAt)
                if channelBump <> invalid and platformBump <> invalid
                    channelAudio = sAudio(version.bumps.channelAudio, channelBump.id, index, seed)
                    platformAudio = sAudio(version.bumps.platformAudio, platformBump.id, index, seed)
                    nextItem = version.items[(index + 1) mod version.items.count()]
                    playAd = false
                    if version.ads <> invalid then playAd = item.offAir <> true and nextItem.offAir <> true and adTime >= sValue(version.ads.gapMs, 1200000)
                    if playAd
                        fromMs = sValue(adFrom, time - adTime)
                        choice = sChooseAd(version.plan, used, sYear(item), time, fromMs)
                        adFrom = invalid
                        recent.push([choice, time])
                        adsMade++
                        ad = version.ads.slices[choice]
                        openMs = 3500 + channelBump.slideMs + 2000
                        closeMs = platformBump.slideMs + 2000
                        sAppend(cycle, { type: "bump-break", half: "open", breakIndex: index, channelBump: channelBump, channelAudio: channelAudio }, openMs)
                        sAppend(cycle, { type: "ad", breakIndex: index, slice: ad, sliceIndex: choice }, ad.lengthMs)
                        sAppend(cycle, { type: "bump-break", half: "close", breakIndex: index, platformBump: platformBump, platformAudio: platformAudio }, closeMs)
                        time += openMs + ad.lengthMs + closeMs
                        adTime = closeMs
                        outFrom = time
                    else
                        length = 3500 + channelBump.slideMs + 2000 + 300 + platformBump.slideMs + 2000
                        sAppend(cycle, { type: "bump-break", breakIndex: index, channelBump: channelBump, platformBump: platformBump, channelAudio: channelAudio, platformAudio: platformAudio }, length)
                        time += length
                        adTime += length
                    end if
                end if
            end if
        end if
    end for
    if k >= 0
        if version.ads <> invalid and version.bumps <> invalid
            if adsMade = 0 then outFrom = sValue(adFrom, startMs)
            kept = []
            for each pair in recent
                if pair[1] >= time - 86400000 then kept.push(pair)
            end for
            version.adCarry[k + 1] = { fromMs: outFrom, recent: kept }
        end if
        if deck <> invalid then version.deckCarry[k + 1] = { order: deck.order, pos: deck.pos, key: deck.key, recent: deck.recent }
    end if
    return cycle
end function

sub sCacheCycle(version as Object, cycle as Object)
    key = cycle.k.ToStr()
    if not version.built.doesExist(key) then version.builtKeys.push(key)
    version.built[key] = cycle
    if version.builtKeys.count() > 3
        oldest = version.builtKeys.shift()
        version.built.delete(oldest)
    end if
end sub

function sEnsureCycle(version as Object, k as Integer) as Object
    if k >= 0
        while version.fwd.count() <= k
            index = version.fwd.count()
            startMs = version.epochMs
            if index > 0 then startMs = version.fwd[index - 1].startMs + version.fwd[index - 1].lengthMs
            cycle = sMakeCycle(version, index, startMs)
            version.fwd.push({ startMs: startMs, lengthMs: cycle.lengthMs })
            sCacheCycle(version, cycle)
        end while
        return version.fwd[k]
    end if
    while version.back.count() < -k
        index = version.back.count()
        finish = version.epochMs
        if index > 0 then finish = version.back[index - 1].startMs
        cycle = sMakeCycle(version, -(index + 1), 0)
        cycle.startMs = finish - cycle.lengthMs
        version.back.push({ startMs: cycle.startMs, lengthMs: cycle.lengthMs })
        sCacheCycle(version, cycle)
    end while
    return version.back[-k - 1]
end function

function sCycleAt(version as Object, at as Double) as Integer
    if at < version.epochMs
        k = -1
        while sEnsureCycle(version, k).startMs > at
            k--
        end while
        return k
    end if
    k = maximum(0, version.fwd.count() - 1)
    cycle = sEnsureCycle(version, k)
    while at >= cycle.startMs + cycle.lengthMs
        k++
        cycle = sEnsureCycle(version, k)
    end while
    low = 0
    high = k
    while low < high
        mid = Int((low + high + 1) / 2)
        if version.fwd[mid].startMs <= at
            low = mid
        else
            high = mid - 1
        end if
    end while
    return low
end function

function sResolve(playlist as Object, at as Double) as Dynamic
    version = invalid
    for each candidate in playlist.versions
        if candidate.effectiveAtMs <= at then version = candidate
    end for
    if version = invalid
        for each candidate in playlist.versions
            if version = invalid
                version = candidate
            else if candidate.effectiveAtMs <= version.effectiveAtMs
                version = candidate
            end if
        end for
    end if
    if version = invalid then return invalid
    k = sCycleAt(version, at)
    summary = sEnsureCycle(version, k)
    key = k.ToStr()
    if not version.built.doesExist(key)
        start = summary.startMs
        if k < 0 then start = 0
        cycle = sMakeCycle(version, k, start)
        cycle.startMs = summary.startMs
        sCacheCycle(version, cycle)
    end if
    cycle = version.built[key]
    elapsed = at - cycle.startMs
    low = 0
    high = cycle.entries.count() - 1
    while low < high
        mid = Int((low + high + 1) / 2)
        if cycle.entries[mid].offMs <= elapsed
            low = mid
        else
            high = mid - 1
        end if
    end while
    item = cycle.entries[low]
    startMs = cycle.startMs + item.offMs
    endMs = startMs + item.durMs
    for each candidate in playlist.versions
        if candidate.v > version.v and candidate.effectiveAtMs > at and candidate.effectiveAtMs < endMs then endMs = candidate.effectiveAtMs
    end for
    return { item: item, index: low, key: item.key, startMs: startMs, endMs: endMs, offset: Int((at - startMs) / 1000), offsetExact: (at - startMs) / 1000.0#, version: version.v, cycle: k }
end function
