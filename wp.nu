#!/usr/bin/env nu

const files = ("files" | path expand)
const data = ("data.toml" | path expand)

export def list []: nothing -> record {
    if not ($data | path exists) {
        touch $data
    }

    open $data
}

def check []: record -> record {
    let record = $in

    if not ($record.file | path exists) {
        error make { msg: "file doesn't exist" }
    }

    if ($record.tags | is-empty) {
        error make { msg: "tags are empty" }
    }

    $record
}

export def add [
    file: string
    source: string
    ...tags: string
]: nothing -> nothing {
    let record = ({ $file: { source: $source tags: $tags } } | check)
    let list = list

    if ($list | get --optional $file) != null {
        error make { msg: "file is already listed" }
    }

    $record | to toml | save --append $data
}
