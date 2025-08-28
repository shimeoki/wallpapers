#!/usr/bin/env nu

# fix: don't hardcode default source
const defaults = {
    store: (path self '.' | path join 'store' | path expand)
    data:  (path self '.' | path join 'store.toml' | path expand)
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

    $store | path expand
}

def 'store path' [hash: string, extension: string]: nothing -> string {
    {
        parent: (store)
        stem: $hash
        extension: $extension
    } | path join
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

    $data | path expand
}

def files []: nothing -> string {
    let files = ($env | get --optional $envs.files | default $defaults.files)

    if not ($files | path exists) {
        error make { msg: $"'($envs.files)' doesn't exist" }
    }

    if ($files | path type) != dir {
        error make { msg: $"'($envs.files)' is not a directory" }
    }

    $files | path expand
}

def 'files path' []: string -> string {
    let path = $in
    let prefix = ($path | path parse | get parent | str substring ..0)

    # todo: windows paths?
    let relative = ($prefix == '.' or $prefix == '/')
    let in_files = ([ (files) $path ] | path join)

    if (not $relative) and ($in_files | path exists) {
        $in_files
    } else {
        $path
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

def check [ # returns the same record
]: record<extension: string, source: string, tags: list<string>> -> record {
    let record = $in

    if ($record.extension not-in $extensions) {
        error make { msg: "unsupported extension" }
    }

    # no source check

    if ($record.tags | is-empty) {
        error make { msg: "tags are empty" }
    }

    $record
}

export def add [
    file: string
    source: string
    ...tags: string
    --git (-g)
]: nothing -> string {
    let file_path = ($file | files path)
    let file_read = ($file_path | files read)

    let hash = $file_read.hash
    let extension = $file_read.extension

    # cache
    let list = list
    let data = data

    if ($list | get --optional $file_read.hash) != null {
        error make { msg: "file is already listed" }
    }

    let stored = ({
        extension: $extension
        source: $source
        tags: ($tags | uniq)
    } | check)

    let store_path = (store path $hash $extension)

    cp $file_path $store_path
    $list | insert $hash $stored | save --force $data

    if ($git) {
        git reset HEAD
        git add $store_path $data
        git commit -m $"store: add ($hash)"
    } 

    $hash
}

export def del [
    hash: string
    --git (-g)
]: nothing -> string {
    # cache
    let list = list
    let data = data

    let stored = ($list | get --optional $hash)

    if $stored == null {
        error make { msg: "file is not listed" }
    }

    let store_path = (store path $hash $stored.extension)

    rm $store_path
    $list | reject $hash | save --force $data

    if ($git) {
        git reset HEAD
        git add $store_path $data
        git commit -m $"store: del ($hash)"
    }

    $hash
}

export def 'tag list' []: nothing -> list<string> {
    list | values | get tags | flatten | uniq
}

export def 'tag rename' [old: string, new: string] {
    list | transpose hash stored | each {|wp|
        let tags = ($wp.stored.tags | each {|tag|
            if ($tag == $old) { $new } else { $tag }
        } | uniq)

        { hash: $wp.hash, stored: ($wp.stored | update tags $tags) }
    } | transpose --as-record --header-row --ignore-titles | save --force (data)
}

export def 'tag filter' []: closure -> list<string> {
    let closure = $in
    list | items {|hash, stored|
        do $closure $stored.tags
        | if $in { $hash }
    } | compact
}
