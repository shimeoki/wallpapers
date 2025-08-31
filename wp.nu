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

def read []: string -> record {
    let src = ($in | path expand)

    if not ($src | path exists) {
        error make { msg: $"'($src)' doesn't exist" }
    }

    # todo: handle symlinks?
    if ($src | path type) != file {
        error make { msg: $"'($src)' is not a file" }
    }

    let extension = ($src | path parse | get extension)
    if $extension not-in $extensions {
        error make { msg: $"'($src)' extension is not one of '($extensions)'" }
    }

    let hash = (open $src | hash sha256)

    {
        hash: $hash
        src: $src
        meta: {
            extension: $extension
        }
    }
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
        let wp = ($list | get --optional $hash)

        if $wp != null {
           { parent: $dir, stem: $hash, extension: $wp.extension } | path join
        } else {
            null
        }
    }
    | compact
    | if not $absolute { $in | path relative-to $env.PWD } else { $in }
}

def from-hash [list: record]: list<string> -> list<record> {
    each {|hash|
        let wp = ($list | get --optional $hash)

        if $wp == null {
            null
        } else {
            {
                hash: $hash
                meta: $wp
            }
        }
    } | compact
}

def with-path [dir: string]: list<record> -> list<record> {
    each {|wp|
        let p = {
            parent: $dir
            stem: $wp.hash
            extension: $wp.meta.extension
        }

        let path = ($p | path join | path expand)

        $wp | insert path $path
    }
}

def show [header: string, image: bool]: record -> nothing {
    let wp = $in

    print $"(ansi bb)\n($header):(ansi rst)" ''

    if $image {
        let src = ($wp | get --optional src)
        let path = ($wp | get --optional path)

        let img = if ($path | is-empty) {
            $src
        } else {
            $path
        }

        kitten icat --stdin=no $img
    }

    print $'hash: (ansi y)($wp.hash)(ansi rst)' ''

    let tags = ($wp.meta | get --optional tags)
    if ($tags | is-empty) {
        print $'(ansi dgr)no tags provided(ansi rst)' ''
    } else {
        print $'tags: (ansi c)($tags)(ansi rst)' ''
    }

    let source = ($wp.meta | get --optional source)
    if ($source | is-empty) {
        print $'(ansi dgr)no source provided(ansi rst)' ''
    } else {
        print $'source: (ansi b)($source)(ansi rst)' ''
    }
}

def add-source [source]: record -> record {
    let wp = $in

    if ($source | is-empty) {
        $wp
    } else {
        $wp | upsert meta.source $source
    }
}

def add-tags [tags: list<string>]: record -> record {
    let wp = $in

    let tags = ($tags | flatten | compact --empty | uniq)

    if ($tags | is-empty) {
        $wp
    } else {
        $wp | upsert meta.tags $tags
    }
}

def tags-only []: list<record> -> list<record> {
    each {|wp|
        let tags = ($wp.meta | get --optional tags)

        if ($tags | is-empty) {
            null
        } else {
            $wp
        }
    } | compact
}

def user-source [interactive: bool] {
    let source = $in

    if $interactive and ($source != null) {
        input $'(ansi g)specify source:(ansi rst) '
    } else {
        $source
    }
}

def user-tags [interactive: bool]: list<string> -> list<string> {
    let tags = $in

    if $interactive {
        input $'(ansi g)specify tags:(ansi rst) ' | split row ' '
    } else {
        []
    } | append $tags
}

def add-user-data [
    tags: list<string>
    source
    interactive: bool
]: list<record> -> list<record> {
    each {|wp|
        if $interactive { $wp | show 'next' true }
        let user_tags = ($tags | user-tags $interactive)
        let user_source = ($source | user-source $interactive)
        $wp | add-tags $user_tags | add-source $user_source
    }
}

def store-git [action: string]: record -> nothing {
    let wp = $in
    let hash = ($wp.hash | str substring ..31)
    let store = store file

    cd $repo

    git reset HEAD | complete
    git add $store | complete
    git add $wp.path | complete
    git commit -m $'store: ($action) ($hash)' | complete

    ignore
}

export def 'store edit' [
    ...tags: string
    --source (-s): string
    --git (-g)
    --interactive (-i)
]: [
    nothing -> nothing
    string -> nothing
    list<string> -> nothing
] {
    let input = $in

    let hashes = if ($input | is-empty) {
        store list | columns
    } else {
        $input | append [] | uniq
    }

    let list = store list
    let file = store file
    let dir = store dir

    $hashes
    | from-hash $list
    | with-path $dir 
    | add-user-data $tags $source $interactive
    | each {|wp|
        store list | upsert $wp.hash $wp.meta | save --force $file

        if $git { $wp | store-git 'edit' }
        if $interactive { $wp | show 'edited' false }
    }
}

export def 'store add' [
    ...tags: string
    --source (-s): string
    --git (-g)
    --interactive (-i)
]: [
    nothing -> list<string>
    string -> list<string>
    list<string> -> list<string>
] {
    let input = $in

    let paths = if ($input | is-empty) {
        ls | get name
    } else {
        $input | append []
    }

    let file = store file
    let dir = store dir

    $paths
    | each { $in | read }
    | add-user-data $tags $source $interactive
    | tags-only
    | with-path $dir
    | each {|wp|
        cp --no-clobber $wp.src $wp.path
        store list | upsert $wp.hash $wp.meta | save --force $file

        if $git { $wp | store-git 'add' }
        if $interactive { $wp | show 'added' false } else { $wp.hash }
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

export def 'tag rename' [old: string, new: string]: nothing -> nothing {
    store list | transpose hash meta | each {|wp|
        let tags = ($wp.meta.tags | each {|tag|
            if ($tag == $old) { $new } else { $tag }
        } | uniq)

        { hash: $wp.hash, meta: ($wp.meta | update tags $tags) }
    }
    | transpose --as-record --header-row --ignore-titles
    | save --force (store file)
}

export def 'tag filter' []: closure -> list<string> {
    let closure = $in
    store list | items {|hash, stored|
        do $closure $stored.tags
        | if $in { $hash }
    } | compact
}

export def 'pick any' [
    ...tags: string
    --absolute (-a)
    --interactive (-i)
]: nothing -> list<string> {
    let dst = if $interactive {
        let selected = (tag list | input list --multi 'select the tags')
        ($tags | append $selected | flatten | uniq)
    } else {
        ($tags | flatten | uniq)
    }

    {|src| $src | any {|tag| $tag in $dst } }
    | tag filter
    | store path --absolute=$absolute
}

export def 'pick all' [
    ...tags: string
    --absolute (-a)
    --interactive (-i)
]: nothing -> list<string> {
    let dst = if $interactive {
        let selected = (tag list | input list --multi 'select the tags')
        ($tags | append $selected | flatten | uniq)
    } else {
        ($tags | flatten | uniq)
    }

    {|src| $src | all {|tag| $tag in $dst } }
    | tag filter
    | store path --absolute=$absolute
}

export def 'pick random' [
    --absolute (-a)
]: nothing -> list<string> {
    store list | columns | shuffle | store path --absolute=$absolute
}

export def --wrapped 'pick fzf' [
    ...args: string
    --absolute (-a)
]: nothing -> list<string> {
    let dir = store dir

    store list | transpose hash meta | each {|wp|
        let p = { parent: $dir, stem: $wp.hash, extension: $wp.meta.extension }
        ($p | path join | append $wp.meta.tags)
    } | each {|lst| $lst | str join ' ' } | to text
    | ^fzf --accept-nth='1' --with-nth='2..' ...$args
    | lines
    | if not $absolute { $in | path relative-to $env.PWD } else { $in }
}

export alias a = store add
export alias e = store edit
