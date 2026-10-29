sub init()
    m.top.functionName = "runBroadcast"
end sub

' One persistent worker owns manifests and computed cycles across channel changes.
sub runBroadcast()
    m.port = CreateObject("roMessagePort")
    m.top.observeField("request", m.port)
    m.liveBase = "https://jbuopkuluyfjwgsrigry.supabase.co/storage/v1/object/public/broadcast/"
    m.snapshotBase = "https://spelunkr.tv/broadcast/"
    m.assets = {}
    m.playlists = {}
    m.media = {}
    m.lineup = invalid
    m.lineupAt = 0.0#
    m.source = "live"
    m.lastError = "Spelunkr's broadcast is temporarily unavailable."
    m.assetPattern = CreateObject("roRegex", "^(manifests|platform|details)/[a-zA-Z0-9_./-]+[.]json$", "")
    m.videoPattern = CreateObject("roRegex", "[.](mp4|m4v|mov)$", "i")
    m.encoder = CreateObject("roUrlTransfer")
    m.pendingGuide = invalid
    m.pendingTune = invalid
    m.lastSerial = -1
    directQueue(m.top.request)
    while true
        if m.pendingTune <> invalid
            directHandleTune()
        else if m.pendingGuide <> invalid
            request = m.pendingGuide
            m.pendingGuide = invalid
            directGuide(request)
        else
            event = Wait(0, m.port)
            if Type(event) = "roSGNodeEvent" then directQueue(event.GetData())
        end if
        directPoll()
    end while
end sub

sub directQueue(request as Dynamic)
    if request = invalid then return
    if request.serial <= m.lastSerial then return
    m.lastSerial = request.serial
    if request.action = "guide"
        m.pendingGuide = request
    else if request.action = "tune"
        m.pendingTune = request
    end if
end sub

sub directPoll()
    event = Wait(1, m.port)
    while Type(event) = "roSGNodeEvent"
        directQueue(event.GetData())
        event = Wait(1, m.port)
    end while
end sub

function directJson(url as String) as Dynamic
    transfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    transfer.SetMessagePort(port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    transfer.SetUrl(url)
    transfer.AddHeader("Accept", "application/json")
    if not transfer.AsyncGetToString() then return invalid
    event = Wait(12000, port)
    if Type(event) = "roUrlEvent"
        if event.GetResponseCode() >= 200 and event.GetResponseCode() < 300 then return ParseJson(event.GetString())
    else
        transfer.AsyncCancel()
    end if
    return invalid
end function

function directLineup() as Dynamic
    at = epochMs()
    if m.lineup <> invalid
        if at - m.lineupAt < 60000 then return m.lineup
    end if
    data = directJson(m.liveBase + "lineup.json")
    if data <> invalid
        m.source = "live"
    else if m.lineup <> invalid
        m.source = "cached"
        m.lineupAt = at
        return m.lineup
    else
        data = directJson(m.snapshotBase + "lineup.json")
        m.source = "snapshot"
    end if
    if data = invalid then return invalid
    if data.engine > 5
        m.lastError = "Spelunkr updated its broadcast engine. This Roku app needs an update."
        return invalid
    end if
    if data.channels = invalid then return invalid
    channels = []
    for each channel in data.channels
        if channel.dial <> invalid and channel.debugOnly <> true and channel.comingSoon <> true then channels.push(channel)
    end for
    channels.SortBy("dial")
    data.channels = channels
    m.lineup = data
    m.lineupAt = at
    print "[Spelunkr] Direct "; m.source; " lineup: "; channels.count(); " channels"
    return data
end function

function directAsset(path as String) as Dynamic
    if not m.assetPattern.IsMatch(path) or Instr(1, path, "..") > 0 then return invalid
    if m.assets.doesExist(path) then return m.assets[path]
    primary = m.liveBase
    if m.source = "snapshot" then primary = m.snapshotBase
    data = directJson(primary + path)
    if data = invalid and primary <> m.snapshotBase then data = directJson(m.snapshotBase + path)
    if data <> invalid
        m.assets[path] = data
        if m.assets.count() > 200
            keys = m.assets.keys()
            m.assets.delete(keys[0])
        end if
    end if
    return data
end function

function directChannel(entry as Object) as Dynamic
    signature = FormatJson(entry.versions)
    if m.playlists.doesExist(entry.id)
        cached = m.playlists[entry.id]
        if cached.signature = signature then return cached.playlist
    end if
    playlist = { channelId: entry.id, versions: [] }
    for each pointer in sArray(entry.versions)
        manifest = directAsset(pointer.manifest)
        if manifest = invalid then return invalid
        if manifest.engine > 5
            m.lastError = "Spelunkr updated this channel's engine. This Roku app needs an update."
            return invalid
        end if
        platform = invalid
        if manifest.platform <> invalid
            platform = directAsset(manifest.platform)
            if platform = invalid then return invalid
        end if
        version = sHydrate(manifest, platform, pointer, entry.id)
        if version = invalid then return invalid
        playlist.versions.push(version)
    end for
    if playlist.versions.count() = 0 then return invalid
    playlist.versions.SortBy("v")
    m.playlists[entry.id] = { signature: signature, playlist: playlist }
    return playlist
end function

function directProgram(channel as Object, position as Object) as Object
    item = position.item
    title = item.title
    if title = invalid
        title = "Station break"
        if item.type = "ad" then title = "A word from the past"
        if item.type = "up-next" then title = "Up next"
    end if
    id = sValue(item.id, "")
    image = ""
    if id <> "" then image = "https://archive.org/services/img/" + m.encoder.Escape(id)
    return { key: position.key, type: item.type, id: id, title: title, year: sValue(item.year, "").ToStr(), startMs: position.startMs, endMs: position.endMs, image: image, description: sValue(channel.description, "") }
end function

sub directGuide(request as Object)
    lineup = directLineup()
    if lineup = invalid
        m.top.guideResult = { ok: false, complete: true, error: m.lastError }
        return
    end if
    at = epochMs()
    startMs = Int(at / 1800000) * 1800000.0#
    guide = { serverTime: at, generatedAt: lineup.generatedAt, source: m.source, startMs: startMs, endMs: startMs + 7200000, channels: [] }
    order = []
    for i = 0 to lineup.channels.count() - 1
        entry = lineup.channels[i]
        guide.channels.push({ id: entry.id, number: entry.dial, name: entry.name, color: entry.color, description: sValue(entry.description, ""), programs: [] })
        if entry.id = request.channelId then order.push(i)
    end for
    for i = 0 to lineup.channels.count() - 1
        if lineup.channels[i].id <> request.channelId then order.push(i)
    end for
    loaded = 0
    errors = 0
    for each i in order
        entry = lineup.channels[i]
        row = guide.channels[i]
        try
            playlist = directChannel(entry)
            if playlist <> invalid
                row.now = directProgram(entry, sResolve(playlist, at))
                cursor = startMs
                count = 0
                while cursor < guide.endMs and count < 600
                    position = sResolve(playlist, cursor)
                    if position.endMs <= cursor then exit while
                    program = directProgram(entry, position)
                    if program.type <> "video" and row.programs.count() > 0
                        row.programs[row.programs.count() - 1].endMs = program.endMs
                    else
                        row.programs.push(program)
                    end if
                    cursor = position.endMs
                    count++
                end while
            else
                row.error = m.lastError
                errors++
            end if
        catch error
            print "[Spelunkr] Channel error "; entry.id; ": "; error.message
            row.error = "This channel's broadcast is temporarily unavailable."
            errors++
        end try
        loaded++
        if request.progressive = true
            if loaded = 1 or loaded mod 5 = 0
                guide.serverTime = epochMs()
                m.top.guideResult = { ok: true, complete: false, loaded: loaded, data: guide }
            end if
        end if
        ' Channel surfing takes priority between guide rows.
        directPoll()
        if m.pendingTune <> invalid then directHandleTune()
    end for
    guide.serverTime = epochMs()
    m.top.guideResult = { ok: true, complete: true, loaded: loaded, data: guide }
    print "[Spelunkr] Direct guide ready: "; loaded; " channels, "; errors; " errors"
end sub

function directArchive(id as String, file as String) as String
    parts = file.split("/")
    encoded = []
    for each part in parts
        encoded.push(m.encoder.Escape(part))
    end for
    return "https://archive.org/download/" + m.encoder.Escape(id) + "/" + encoded.join("/")
end function

function directMedia(item as Object) as String
    file = sValue(item.file, item.mp4)
    if file <> invalid
        if m.videoPattern.IsMatch(file) then return directArchive(item.id, file)
    end if
    if m.media.doesExist(item.id) then return m.media[item.id]
    data = directJson("https://archive.org/metadata/" + m.encoder.Escape(item.id))
    if data = invalid then return ""
    choice = invalid
    rank = 0
    for each candidate in sArray(data.files)
        name = LCase(candidate.name)
        if Right(name, 4) = ".mp4" or Right(name, 4) = ".m4v"
            score = 1
            if candidate.format = "h.264" then score = 2
            if candidate.format = "h.264 IA" then score = 3
            if score > rank
                choice = candidate.name
                rank = score
            end if
        end if
    end for
    if choice = invalid then return ""
    url = directArchive(item.id, choice)
    m.media[item.id] = url
    return url
end function

sub directHandleTune()
    request = m.pendingTune
    m.pendingTune = invalid
    try
        result = directTune(request.channelId)
        if result <> invalid
            m.top.tuneResult = { ok: true, token: request.token, data: result }
        else
            m.top.tuneResult = { ok: false, token: request.token, error: m.lastError }
        end if
    catch error
        print "[Spelunkr] Tune error: "; error.message
        m.top.tuneResult = { ok: false, token: request.token, error: "This channel's signal wandered off. Trying again..." }
    end try
end sub

function directTune(id as String) as Dynamic
    lineup = directLineup()
    if lineup = invalid then return invalid
    channel = invalid
    for each entry in lineup.channels
        if entry.id = id then channel = entry
    end for
    if channel = invalid then return invalid
    playlist = directChannel(channel)
    if playlist = invalid then return invalid
    at = epochMs()
    position = sResolve(playlist, at)
    item = position.item
    result = directProgram(channel, position)
    result.append({ serverTime: at, channel: { id: id, number: channel.dial, name: channel.name, color: channel.color }, offset: position.offsetExact, url: "", seek: 0.0#, cards: [], audioUrl: "", audioSeek: 0.0# })
    audioBase = sValue(lineup.audioBase, "https://audio.spelunkr.tv/bumps/")
    if item.type = "video"
        result.url = directMedia(item)
        result.seek = sValue(item.inS, 0) + position.offsetExact
        if result.url = "" then result.message = "This tape has no Roku-compatible video. The next program will tune automatically."
    else if item.type = "ad"
        result.url = directArchive(item.slice.tape, item.slice.file)
        result.seek = sValue(item.slice.inMs, 0) / 1000.0# + position.offsetExact
    else
        groups = []
        if item.channelBump <> invalid then groups.push(item.channelBump)
        if item.platformBump <> invalid then groups.push(item.platformBump)
        cursor = 3500.0#
        if item.half = "close" then cursor = 0
        for i = 0 to groups.count() - 1
            for each slide in sArray(groups[i].slides)
                length = sSlideMs(slide.text)
                result.cards.push({ text: slide.text, start: cursor, end: cursor + length })
                cursor += length
            end for
            cursor += 2000
            if i = 0 and groups.count() > 1 then cursor += 300
        end for
        audio = sValue(item.channelAudio, item.platformAudio)
        if audio <> invalid
            if audio.filename <> invalid
                result.audioUrl = audioBase + m.encoder.Escape(audio.filename)
                result.audioSeek = sValue(audio.startOffset, 0) + position.offsetExact
            end if
        end if
        if item.type = "up-next"
            following = sResolve(playlist, position.endMs)
            result.cards = [{ text: "UP NEXT" + Chr(10) + sValue(following.item.title, channel.name), start: 0, end: item.durMs }]
            if item.sting <> invalid
                result.audioUrl = audioBase + m.encoder.Escape(item.sting.track)
                result.audioSeek = item.sting.startMs / 1000.0# + position.offsetExact
            end if
        end if
    end if
    readyAt = epochMs()
    result.seek += (readyAt - at) / 1000.0#
    result.audioSeek += (readyAt - at) / 1000.0#
    result.serverTime = readyAt
    print "[Spelunkr] Direct tune "; id; " "; position.key; " "; item.type
    return result
end function
