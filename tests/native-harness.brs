sub main()
    input = ParseJson(ReadAsciiFile("pkg:/input.json"))
    output = { random: [], hashes: [], lengths: [], cases: [] }
    for each seed in input.seeds
        state = { value: seed }
        values = []
        for i = 1 to 10
            values.push(sRandom(state))
        end for
        output.random.push(values)
    end for
    for each text in input.texts
        output.hashes.push(sHash(text))
        output.lengths.push(sSlideMs(text))
    end for
    for each fixture in input.cases
        playlist = { channelId: fixture.id, versions: [] }
        for each fixtureVersion in fixture.versions
            version = sHydrate(fixtureVersion.manifest, fixtureVersion.platform, fixtureVersion.pointer, fixture.id)
            playlist.versions.push(version)
        end for
        playlist.versions.SortBy("v")
        positions = []
        for each at in fixture.times
            p = sResolve(playlist, at * 1.0#)
            item = p.item
            result = { key: p.key, type: item.type, id: sValue(item.id, ""), startMs: p.startMs, endMs: p.endMs, offsetExact: p.offsetExact, adId: "", channelBump: "", platformBump: "", audio: "", audioOffset: 0 }
            if item.slice <> invalid then result["adId"] = item.slice.id
            if item.channelBump <> invalid then result["channelBump"] = item.channelBump.id
            if item.platformBump <> invalid then result["platformBump"] = item.platformBump.id
            if item.channelAudio <> invalid
                result.audio = sValue(item.channelAudio.filename, "")
                result["audioOffset"] = item.channelAudio.startOffset
            end if
            positions.push(result)
        end for
        output.cases.push(positions)
    end for
    print FormatJson(output)
end sub
