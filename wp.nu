#!/usr/bin/env nu

const defaults = {
    store: (path self '.' | path join 'store')
    data:  (path self '.' | path join 'store.toml')
}

const envs = {
    store: 'WP_STORE_DIR'
    data:  'WP_STORE_FILE'
}

const extensions = [ png jpg jpeg ]

export def 'store dir' []: nothing -> string {
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

export def 'store file' []: nothing -> string {
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

def 'store path' [hash: string, extension: string]: nothing -> string {
    {
        parent: (store dir)
        stem: $hash
        extension: $extension
    } | path join
}

export def list []: nothing -> record {
    store file | open
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

def read []: string -> record<hash: string, extension: string> {
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

export def 'store add' [
    file: string
    source: string
    ...tags: string
    --git (-g)
]: nothing -> string {
    let result = ($file | read)

    let hash = $result.hash
    let extension = $result.extension

    # cache
    let list = list
    let data = store file

    if ($list | get --optional $result.hash) != null {
        error make { msg: "file is already listed" }
    }

    let stored = ({
        extension: $extension
        source: $source
        tags: ($tags | uniq)
    } | check)

    let store_path = (store path $hash $extension)

    cp $file $store_path
    $list | insert $hash $stored | save --force $data

    if ($git) {
        git reset HEAD
        git add $store_path $data
        git commit -m $"store: add ($hash)"
    } 

    $hash
}

export def 'store del' [
    hash: string
    --git (-g)
]: nothing -> string {
    # cache
    let list = list
    let data = store file

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

export def stored [
    hash: string
    --absolute (-a)
]: nothing -> string {
    let stored = (list | get $hash)

    store path $hash $stored.extension
    | if ($absolute) {
        $in | path expand
    } else {
        $in | path relative-to $env.PWD
    }
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
    } | transpose --as-record --header-row --ignore-titles | save --force (store file)
}

export def 'tag filter' []: closure -> list<string> {
    let closure = $in
    list | items {|hash, stored|
        do $closure $stored.tags
        | if $in { $hash }
    } | compact
}
