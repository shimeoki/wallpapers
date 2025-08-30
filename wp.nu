#!/usr/bin/env nu

const repo = path self '.'

const defaults = {
    store: ($repo | path join 'store')
    data:  ($repo | path join 'store.toml')
}

const envs = {
    store: 'WP_STORE_DIR'
    data:  'WP_STORE_FILE'
}

const extensions = [ png jpg jpeg ]

def store-path [hash: string, extension: string]: nothing -> string {
    {
        parent: (store dir)
        stem: $hash
        extension: $extension
    } | path join
}

def store-meta [
    extension: string
    source: string
    tags: list<string>
]: nothing -> record<extension: string, source: string, tags: list<string>> {
    {
        extension: $extension
        source: $source
        tags: ($tags | uniq)
    } | check
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

export def 'store list' []: nothing -> record {
    store file | open
}

export def 'store data' [hash: string]: nothing -> record {
    store list | get --optional $hash
}

export def 'store path' [
    --absolute (-a)
]: [
    string -> list<string>
    list<string> -> list<string>
] {
    let hashes = ($in | append [])
    let list = store list
    let dir = store dir

    $hashes | each {|hash|
        $list
        | get --optional $hash
        | if $in != null {
           { parent: $dir, stem: $hash, extension: $in.extension } | path join
        } else {
            $in
        }
    }
    | compact
    | if not $absolute { $in | path relative-to $env.PWD } else { $in }
}

export def 'store add' [
    ...tags: string
    --source (-s): string
    --git (-g)
]: [
    string -> list<string>
    list<string> -> list<string>
] {
    let paths = ($in | append [] | path expand)
    cd $repo

    let tags = ($tags | flatten | uniq)
    if ($tags | is-empty) { error make { msg: "tags are empty" } }

    let file = store file
    let dir = store dir

    $paths | each {|path|
        let read = ($path | read)
        if ($read.extension not-in $extensions) { return null }

        let meta = if $source == null { {
            extension: $read.extension
            tags: $tags
        } } else { {
            extension: $read.extension
            source: $source
            tags: $tags
        } }

        { src: $path, hash: $read.hash, meta: $meta }
    } | compact | each {|wp|
        let p = { parent: $dir, stem: $wp.hash, extension: $wp.meta.extension }
        $wp | insert dst ($p | path join | path expand)
    } | each {|wp|
        cp --no-clobber $wp.src $wp.dst
        store list | upsert $wp.hash $wp.meta | save --force $file

        if $git {
            git reset HEAD | ignore
            git add $file $wp.dst | ignore
            git commit -m $"store: add ($wp.hash | str substring ..31)" | ignore
        }

        $wp.hash
    }
}

export def 'store del' [
    hash: string
    --git (-g)
]: nothing -> nothing {
    let list = store list
    let file = store file

    let meta = ($list | get --optional $hash)
    if $meta == null {
        error make { msg: "file is not listed" }
    }

    let path = store-path $hash $meta.extension

    rm --force $path
    $list | reject $hash | save --force $file

    if ($git) {
        cd $repo
        git reset HEAD
        git add $path $file
        git commit -m $"store: del ($hash)"
    }
}

export def 'tag list' []: nothing -> list<string> {
    store list | values | get tags | flatten | uniq
}

export def 'tag rename' [old: string, new: string] {
    store list | transpose hash stored | each {|wp|
        let tags = ($wp.stored.tags | each {|tag|
            if ($tag == $old) { $new } else { $tag }
        } | uniq)

        { hash: $wp.hash, stored: ($wp.stored | update tags $tags) }
    } | transpose --as-record --header-row --ignore-titles | save --force (store file)
}

export def 'tag filter' []: closure -> list<string> {
    let closure = $in
    store list | items {|hash, stored|
        do $closure $stored.tags
        | if $in { $hash }
    } | compact
}

export alias add = store add
