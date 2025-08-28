#!/usr/bin/env nu

# fix: don't hardcode default source
const default_source = '/home/d/Pictures/bg/landscape'

const envs = {
    store:  'WP_STORE'
    data:   'WP_DATA'
    source: 'WP_SOURCE'
}

def store []: nothing -> string {
    let store = ($env | get --optional $envs.store | default "files")

    if not ($store | path exists) {
        # todo: logging?
        mkdir $store
    }

    if ($store | path type) != dir {
        error make { msg: $"'($envs.store)' is not a directory" }
    }

    ($store | path expand)
}

def data []: nothing -> string {
    let data = ($env | get --optional $envs.data | default "store.toml")

    if ($data | path parse | get extension) != toml {
        error make { msg: $"'($envs.data)' extension should be toml" }
    }

    if not ($data | path exists) {
        # todo: logging?
        touch $data
    }

    # todo: handle symlinks?
    if ($data | path type) != file {
        error make { msg: $"'($envs.data)' is not a file" }
    }

    ($data | path expand)
}

def source []: nothing -> string {
    let source = ($env | get --optional $envs.source | default $default_source)

    if not ($source | path exists) {
        error make { msg: $"'($envs.source)' doesn't exist" }
    }

    if ($source | path type) != dir {
        error make { msg: $"'($envs.source)' is not a directory" }
    }

    ($source | path expand)
}

def 'source path' []: string -> string {
    let path = $in
    let prefix = ($path | str substring ..0)

    # todo: windows paths?
    if ($prefix == '.') or ($prefix == '/') {
        $path
    } else {
        $path | path join (source)
    } | path expand
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
