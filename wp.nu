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

export def 'store path' []: [
    nothing -> list<string>
    string -> list<string>
    list<string> -> list<string>
] {
    get-input
    | to-wp
    | with-path
    | get path
}

def to-wp []: list<string> -> list<record> {
    each {|input|
        let list = store list

        let from_hash = ($list | get --optional $input)
        if $from_hash != null {
            return {
                hash: $input
                meta: $from_hash
            }
        }

        let wp = ($input | read)

        let from_path = ($list | get --optional $wp.hash)
        if $from_path != null {
            {
                hash: $wp.hash
                meta: $from_path
            }
        } else {
            null
        }
    } | compact
}

def with-path []: list<record> -> list<record> {
    each {|wp|
        let p = {
            parent: (store dir)
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

def new-only []: list<record> -> list<record> {
    each {|wp|
        # get list every time, otherwise data could be stale
        let new = (store list | get --optional $wp.hash | is-empty)

        if $new {
            $wp
        } else {
            null
        }
    }
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

    let status = (git status | complete)
    if $status.exit_code != 0 { return }

    git reset HEAD | complete
    git add $store | complete
    git add $wp.path | complete
    git commit -m $'store: ($action) ($hash)' | complete

    ignore
}

def store-save []: record -> nothing {
    save --force (store file)
}

def get-input []: any -> list<string> {
    let input = $in

    if ($input | is-empty) {
        ls | get name
    } else {
        $input | append [] | uniq
    }
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
    get-input
    | to-wp
    | with-path
    | add-user-data $tags $source $interactive
    | each {|wp|
        store list | upsert $wp.hash $wp.meta | store-save

        if $git { $wp | store-git 'edit' }
        if $interactive { $wp | show 'edited' false }
    } | ignore
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
    get-input
    | each { $in | read }
    | new-only
    | add-user-data $tags $source $interactive
    | tags-only
    | with-path
    | each {|wp|
        cp --no-clobber $wp.src $wp.path
        store list | upsert $wp.hash $wp.meta | store-save

        if $git { $wp | store-git 'add' }
        if $interactive { $wp | show 'added' false } else { $wp.hash }
    }
}

export def 'store del' [
    --git (-g)
    --interactive (-i)
]: [
    nothing -> nothing
    string -> nothing
    list<string> -> nothing
] {
    get-input
    | to-wp
    | with-path
    | each {|wp|
        if $interactive {
            $wp | show 'next' true
            let confirm = (input --numchar 1 $'(ansi g)confirm?(ansi rst) ')
            if ($confirm | str downcase) != 'y' { return }
        }

        rm --force $wp.path
        store list | reject $wp.hash | store-save

        if $git { $wp | store-git 'del' }
    } | ignore
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
    | store path
}

export def 'pick all' [
    ...tags: string
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
    | store path
}

export def 'pick random' []: nothing -> list<string> {
    store list | columns | shuffle | store path
}

export def --wrapped 'pick fzf' [...args: string]: nothing -> list<string> {
    let dir = store dir

    store list | transpose hash meta | each {|wp|
        let p = { parent: $dir, stem: $wp.hash, extension: $wp.meta.extension }
        ($p | path join | append $wp.meta.tags)
    } | each {|lst| $lst | str join ' ' } | to text
    | ^fzf --accept-nth='1' --with-nth='2..' ...$args
    | lines
}

export alias a = store add
export alias e = store edit
export alias d = store del
export alias p = store path
