#!/usr/bin/env nu

def files []: nothing -> string {
    let files = ($env | get --optional WP_FILES | default "files")

    if not ($files | path exists) {
        # todo: logging?
        mkdir $files
    }

    if ($files | path type) != dir {
        error make { msg: "'WP_FILES' is not a directory" }
    }

    ($files | path expand)
}

def data []: nothing -> string {
    let data = ($env | get --optional WP_DATA | default "data.toml")

    if ($data | path parse | get extension) != toml {
        error make { msg: "'WP_DATA' extension should be toml" }
    }

    if not ($data | path exists) {
        # todo: logging?
        touch $data
    }

    # todo: handle symlinks?
    if ($data | path type) != file {
        error make { msg: "'WP_DATA' is not a file" }
    }

    ($data | path expand)
}

export def list []: nothing -> record {
    data | open
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

    $record | to toml | save --append (data)
}
