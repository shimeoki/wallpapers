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
        err $"'($src)' doesn't exist"
    }

    # todo: handle symlinks?
    if ($src | path type) != file {
        err $"'($src)' is not a file"
    }

    let extension = ($src | path parse | get extension)
    if $extension not-in $extensions {
        err $"'($src)' extension is not one of '($extensions)'"
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

def err [msg: string]: nothing -> error {
    error make { msg: $'(ansi rb)($msg)(ansi rst)' }
}

export def 'store dir' []: nothing -> string {
    let store = ($env | get --optional $envs.store | default $defaults.store)

    if not ($store | path exists) {
        # todo: logging?
        mkdir $store
    }

    if ($store | path type) != dir {
        err $"'($envs.store)' is not a directory"
    }

    $store | path expand
}

export def 'store file' []: nothing -> string {
    let data = ($env | get --optional $envs.data | default $defaults.data)

    if ($data | path parse | get extension) != toml {
        err $"'($envs.data)' extension should be toml"
    }

    if not ($data | path exists) {
        # todo: logging?
        touch $data
    }

    # todo: handle symlinks?
    if ($data | path type) != file {
        err $"'($envs.data)' is not a file"
    }

    $data | path expand
}

def store-map []: nothing -> record {
    store file | open
}

def store-table []: nothing -> table {
    store-map | transpose hash meta
}

def table-to-map []: table -> record {
    transpose --as-record --header-row --ignore-titles
}

def to-wp []: list<string> -> list<record> {
    each {|input|
        let map = store-map

        let from_hash = ($map | get --optional $input)
        if $from_hash != null {
            return {
                hash: $input
                meta: $from_hash
            }
        }

        let wp = ($input | read)

        let from_path = ($map | get --optional $wp.hash)
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

def valid-source []: string -> bool {
    is-not-empty
}

def clean-tags []: list<string> -> list<string> {
    flatten | compact --empty | uniq
}

def valid-tags []: list<string> -> bool {
    let tags = $in
    ($tags | is-not-empty) and not ($tags | any {|| $in | str contains ' ' })
}

export def 'store verify' [
    --source (-s)
]: nothing -> list<string> {
    store-table
    | each {|wp|
        let valid_tags = ($wp.meta.tags | valid-tags)

        let valid_source = if $source {
            $wp.meta | get --optional source | valid-source
        } else {
            true
        }

        if $valid_tags and $valid_source {
            null
        } else {
            $wp.hash
        }
    } | compact
}

export def 'store validate' []: nothing -> list<string> {
    store-table
    | with-path
    | each {|wp|
        let hash = ($wp.path | read | get hash)

        if $wp.hash == $hash {
            null
        } else {
            $wp.hash
        }
    } | compact
}

def add-source [source]: record -> record {
    let wp = $in

    if ($source | valid-source) {
        $wp | upsert meta.source $source
    } else {
        $wp
    }
}

def add-tags [tags: list<string>]: record -> record {
    let wp = $in

    let tags = ($tags | clean-tags)

    if ($tags | valid-tags) {
        $wp | upsert meta.tags $tags
    } else {
        $wp
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
        # get every time, otherwise data could be stale
        let new = (store-map | get --optional $wp.hash | is-empty)

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

    if ($input == null) {
        ls | get name
    } else {
        $input | append [] | uniq
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
    get-input
    | each { $in | read }
    | new-only
    | add-user-data $tags $source $interactive
    | tags-only
    | with-path
    | each {|wp|
        cp --no-clobber $wp.src $wp.path
        store-map | upsert $wp.hash $wp.meta | store-save

        if $git { $wp | store-git 'add' }
        if $interactive { $wp | show 'added' false } else { $wp.hash }
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
        store-map | upsert $wp.hash $wp.meta | store-save

        if $git { $wp | store-git 'edit' }
        if $interactive { $wp | show 'edited' false }
    } | ignore
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
        store-map | reject $wp.hash | store-save

        if $git { $wp | store-git 'del' }
    } | ignore
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

export def 'tag list' []: nothing -> list<string> {
    store-table | get meta.tags | flatten | uniq
}

export def 'tag rename' [old: string, new: string]: nothing -> nothing {
    if ($old | is-empty) or ($old | str contains ' ') {
        err 'old tag is invalid'
    }

    if ($new | is-empty) or ($new | str contains ' ') {
        err 'new tag is invalid'
    }

    store-table
    | each {|wp|
        let tags = ($wp.meta.tags | each {
            |tag| if ($tag == $old) { $new } else { $tag }
        })

        $wp | add-tags $tags
    }
    | table-to-map
    | store-save
}

export def 'tag filter' [filter: closure]: nothing -> list<string> {
    store-table
    | each {|wp|
        let pass = do $filter $wp.meta.tags

        if $pass {
            $wp.hash
        } else {
            null
        }
    } | compact
}

def select-tags [interactive: bool]: list<string> -> list<string> {
    let tags = $in

    if $interactive {
        let selected = (tag list | input list --multi 'select the tags')
        $tags | append $selected
    } else {
        $tags
    } | flatten | compact --empty | uniq
}

export def 'pick any' [
    ...tags: string
    --interactive (-i)
]: nothing -> list<string> {
    let dst = ($tags | select-tags $interactive)
    tag filter {|src| $src | any {|tag| $tag in $dst } } | store path
}

export def 'pick all' [
    ...tags: string
    --interactive (-i)
]: nothing -> list<string> {
    let dst = ($tags | select-tags $interactive)
    tag filter {|src| $src | all {|tag| $tag in $dst } } | store path
}

export def 'pick random' []: nothing -> list<string> {
    store-table | get hash | shuffle | store path
}

export def --wrapped 'pick fzf' [...args: string]: nothing -> list<string> {
    store-table
    | with-path
    | each {|wp| $wp.path | append $wp.meta.tags | str join ' ' }
    | to text
    | fzf --accept-nth='1' --with-nth='2..' ...$args
    | lines
}

export alias a = store add
export alias e = store edit
export alias d = store del
export alias p = store path
