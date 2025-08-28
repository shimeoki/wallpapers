#!/usr/bin/env nu

# fix: don't hardcode default source
const defaults = {
    store: './store'
    data:  './store.toml'
    files: '/home/d/Pictures/bg/landscape'
}

const envs = {
    store: 'WP_STORE'
    data:  'WP_DATA'
    files: 'WP_FILES'
}

const extensions = [ png jpg jpeg ]

def store []: nothing -> string {
    let store = ($env | get --optional $envs.store | default $defaults.store)

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
    let data = ($env | get --optional $envs.data | default $defaults.data)

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

def files []: nothing -> string {
    let files = ($env | get --optional $envs.files | default $defaults.files)

    if not ($files | path exists) {
        error make { msg: $"'($envs.files)' doesn't exist" }
    }

    if ($files | path type) != dir {
        error make { msg: $"'($envs.files)' is not a directory" }
    }

    ($files | path expand)
}

def 'files path' []: string -> string {
    let path = $in
    let prefix = ($path | str substring ..0)

    # todo: windows paths?
    if ($path | path exists) and (($prefix == '.') or ($prefix == '/')) {
        $path
    } else {
        $path | path join (files)
    } | path expand
}

def 'files read' []: string -> record<hash: string, extension: string> {
    let path = $in

    if not ($path | path exists) {
        error make { msg: $"'($path)' doesn't exist" }
    }

    # todo: handle symlinks?
    if ($path | path type) != file {
        error make { msg: $"'($path)' is not a file" }
    }

    let extension = ($path | path parse | get extension)
    if $extension not-in $extensions {
        error make { msg: $"'($path)' extension is not one of '($extensions)'" }
    }

    let hash = (open $path | hash sha256)

    { hash: $hash, extension: $extension }
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
