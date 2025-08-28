#!/usr/bin/env nu

const files = ("files" | path expand)
const data = ("data.toml" | path expand)

export def list []: nothing -> record {
    if not ($data | path exists) {
        touch $data
    }

    open $data
}

export def add [
    file: string
    source: string
    ...tags: string
]: nothing -> nothing {
    let record = { $file: { source: $source tags: $tags } }
}
