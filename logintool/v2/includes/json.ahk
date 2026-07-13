; Minimal JSON parser (objects -> Map, arrays -> Array). Enough for the
; SkuLoginSense output: strings, numbers, true/false/null, no exotic escapes
; beyond \uXXXX.

JsonParse(text) {
    pos := 1
    value := JsonValue(text, &pos)
    return value
}

JsonWs(text, &pos) {
    while pos <= StrLen(text) {
        c := SubStr(text, pos, 1)
        if (c != " " && c != "`t" && c != "`n" && c != "`r")
            break
        pos++
    }
}

JsonValue(text, &pos) {
    JsonWs(text, &pos)
    c := SubStr(text, pos, 1)
    if (c = "{")
        return JsonObject(text, &pos)
    if (c = "[")
        return JsonArray(text, &pos)
    if (c = '"')
        return JsonString(text, &pos)
    if (SubStr(text, pos, 4) = "true") {
        pos += 4
        return true
    }
    if (SubStr(text, pos, 5) = "false") {
        pos += 5
        return false
    }
    if (SubStr(text, pos, 4) = "null") {
        pos += 4
        return ""
    }
    return JsonNumber(text, &pos)
}

JsonObject(text, &pos) {
    result := Map()
    pos++  ; {
    JsonWs(text, &pos)
    if (SubStr(text, pos, 1) = "}") {
        pos++
        return result
    }
    loop {
        JsonWs(text, &pos)
        key := JsonString(text, &pos)
        JsonWs(text, &pos)
        pos++  ; :
        result[key] := JsonValue(text, &pos)
        JsonWs(text, &pos)
        c := SubStr(text, pos, 1)
        pos++
        if (c = "}")
            break
        if (c != ",")
            throw Error("JSON: expected , or } at " pos)
    }
    return result
}

JsonArray(text, &pos) {
    result := []
    pos++  ; [
    JsonWs(text, &pos)
    if (SubStr(text, pos, 1) = "]") {
        pos++
        return result
    }
    loop {
        result.Push(JsonValue(text, &pos))
        JsonWs(text, &pos)
        c := SubStr(text, pos, 1)
        pos++
        if (c = "]")
            break
        if (c != ",")
            throw Error("JSON: expected , or ] at " pos)
    }
    return result
}

JsonString(text, &pos) {
    if (SubStr(text, pos, 1) != '"')
        throw Error("JSON: expected string at " pos)
    pos++
    out := ""
    while pos <= StrLen(text) {
        c := SubStr(text, pos, 1)
        if (c = '"') {
            pos++
            return out
        }
        if (c = "\") {
            e := SubStr(text, pos + 1, 1)
            switch e {
                case '"': out .= '"'
                case "\": out .= "\"
                case "/": out .= "/"
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "b": out .= Chr(8)
                case "f": out .= Chr(12)
                case "u":
                    out .= Chr("0x" SubStr(text, pos + 2, 4))
                    pos += 4
                default: out .= e
            }
            pos += 2
            continue
        }
        out .= c
        pos++
    }
    throw Error("JSON: unterminated string")
}

JsonNumber(text, &pos) {
    start := pos
    while pos <= StrLen(text) {
        c := SubStr(text, pos, 1)
        if InStr("0123456789+-.eE", c)
            pos++
        else
            break
    }
    return Number(SubStr(text, start, pos - start))
}
