# Module for managing wallpapers from a hashed store.
#
# This module is used as a helper to manage images in a directory via a TOML
# file, where all data about the wallpapers is stored.
#
# Locations for these entities can be changed via environment variables:
#
# `WP_DIR` - directory for the images;
# `WP_FILE` - file for the wallpaper data;
#
# The default values are "./store" and "./store.toml" (relative to the
# module's location) respectively.
#
# TOML is required as a file format and an extension. Though this script uses
# it's own rules and logic for the wallpapers, it was planned as a helper
# for a Nix flake, where only JSON and TOML could be read conveniently for this
# kind of task.
#
# Because of this, the module could be pretty inefficient. TOML is not a
# database and needs to be read and overwritten every time. To compensate,
# most of the commands mostly use streaming model for the data and accept
# lists as the input.
#
# To be added to the store, images are read and their SHA256 hash is computed.
# This hash becomes a unique identifier for the image in the store. This means
# that the same image cannot be added twice to the store.
#
# After the image was added to the wallpaper data file, it is copied to the
# store directory. Because the hashes are unique, the images are listed
# on a single level without any subdirectories, and the hash is used for the
# new filename.
#
# Original extension is kept intact. Right now only "png", "jpg" and "jpeg"
# are supported as extensions for safety. Otherwise it would be pretty easy to
# add a non-image.
#
# The main purpose of this machinery is giving tags to the wallpapers. Tree-like
# structure (directories) is not the right layout to keep this kind of data.
# But when managing files is not a concern, something else could be used.
#
# For simplicity, only one general type of data is supported: list of strings
# - tags. Each image has one of those. It cannot be empty and it is required.
# Each tag should be not empty as well, and cannot contain any spaces.
#
# If you would like to use separate "author" or "color" fields, I recommend to
# either use just the text by itself or prefix it with "author:" or "color:".
# Your imagination is your only limitation.
#
# As an optional data field, which is encouraged to be used in public wallpaper
# repositories, "source" exists. It is just a string. Most of the commands don't
# care about the source field, and work with it via an explicit argument.
#
# It is a Nushell module, so it works cross-platform on a basic level. But
# some additional dependencies are required to use the following:
#
# - Git integration: git;
# - Interactive commands (`--interactive` flag): kitty terminal emulator;
# - `pick fzf`: fzf;
#
# Git integration assumes that this module is located in a git repository.
#
# Source: https://github.com/shimeoki/wallpapers. MIT license.

const self = path self
const repo = path self '.'

const defaults = {
    dir:  ($repo | path join 'store')
    file: ($repo | path join 'store.toml')
}

const envs = {
    dir:  'WP_DIR'
    file: 'WP_FILE'
}

const extensions = [ png jpg jpeg ]

def gen-help [cmd: string]: nothing -> record {
    let mod = ($self | path basename | str replace --regex '\.nu$' '')
    let name = ($'($mod) ($cmd)' | str trim)

    let cmds = (scope commands | where {|e| $e.name | str starts-with $name })
    let self_cmd = ($cmds | where name == $name)

    let brief = ($self_cmd | get description | first)
    let extra = ($self_cmd | get extra_description | first)
    let help = ([ $brief '' $extra '' 'Commands:' ] | str join "\n")

    print $help

    $cmds
    | where name != $name
    | select name description
    | transpose --as-record --header-row
}

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

export def 'env dir' []: nothing -> string {
    let dir = ($env | get --optional $envs.dir | default $defaults.dir)

    if not ($dir | path exists) {
        # todo: logging?
        mkdir $dir
    }

    if ($dir | path type) != dir {
        err $"'($envs.store)' is not a directory"
    }

    $dir | path expand
}

export def 'env file' []: nothing -> string {
    let file = ($env | get --optional $envs.file | default $defaults.file)

    if ($file | path parse | get extension) != toml {
        err $"'($envs.data)' extension should be toml"
    }

    if not ($file | path exists) {
        # todo: logging?
        touch $file
    }

    # todo: handle symlinks?
    if ($file | path type) != file {
        err $"'($envs.data)' is not a file"
    }

    $file | path expand
}

def store-map []: nothing -> record {
    env file | open
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
            parent: (env dir)
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

def valid-source []: any -> bool {
    is-not-empty
}

def clean-tags []: list<string> -> list<string> {
    flatten | compact --empty | uniq
}

def valid-tags []: list<string> -> bool {
    let tags = $in
    ($tags | is-not-empty) and not ($tags | any {|| $in | str contains ' ' })
}

# Manage your wallpapers from the hashed store!
#
# All commands are contained under a namespace, so it should contain two words.
# For example, "img add" is a command and "img" is a namespace.
#
# Namespaces are used to provide help on grouped commands and tab completion.
# Using them just outputs a help message for the namespace and subcommands.
#
# I recommend checking out the help for the module itself (at the top of the
# file) first to get the concept, and then reading about the "img" and "pick"
# commands.
export def 'main' []: nothing -> record { gen-help '' }

export def 'store repair' []: nothing -> nothing {
    ls (env dir) # all?
    | select name
    | each {|row|
        let wp = ($row.name | read)
        let from_path = (store-map | get --optional $wp.hash)

        if ($from_path != null) {
            $wp | upsert meta $from_path
        } else {
            null
        }
    } | compact | with-path | each {|wp|
        if $wp.path != $wp.src {
            mv --no-clobber $wp.src $wp.path
        }
    } | ignore
}

export def 'store check' [
    --source (-s)
    --hash (-h)
]: nothing -> nothing {
    let hashes = store verify --source=$source --hash=$hash

    if ($hashes | is-not-empty) {
        err "check has failed"
    }

    ignore
}

export def 'store verify' [
    --source (-s)
    --hash (-h)
]: nothing -> list<string> {
    store-table
    | with-path
    | each {|wp|
        let valid_tags = ($wp.meta.tags | valid-tags)

        let valid_source = if $source {
            $wp.meta | get --optional source | valid-source
        } else {
            true
        }

        let valid_path = ($wp.path | path exists)

        let valid_hash = if $hash and $valid_path {
            ($wp.path | read | get hash) == $wp.hash
        } else {
            true
        }

        let checks = [ $valid_tags $valid_source $valid_path $valid_hash ]
        if ($checks | all {}) {
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
    let store = env file

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
    save --force (env file)
}

def get-input []: any -> list<string> {
    let input = $in

    if ($input == null) {
        ls | get name
    } else {
        $input | append [] | uniq
    }
}

# Namespace for commands to manage wallpapers in the store.
#
# These commands use a very forgiving input. You can either provide a hash
# directly or just a path.
#
# Hash is just a hash from the store. Could be useful for "img del" and
# "img edit" commands, but not for the "img add".
#
# If a provided string is not a valid hash in the store, it is assumed to
# be a path. Images on these paths are read, and their hash is used as the
# input.
#
# Because of that, you can either provide a path in the store for the image
# (if the store is not corrupted) or a path to any image in the filesystem.
# Same images have the same hash, so, for example, you can edit a wallpaper
# in the store from the source image location.
#
# By default, current directory filenames are used as the input if user input
# wasn't provided. That means, for example, you can write "wp img add"
# to add all files in the current directory in the store or write "wp img del"
# to delete all wallpapers from the store in any directory if image hashes
# in the current directory match hashes in the store.
#
# These commands provide optional git integration and interactive mode.
# In interactive mode you can see the images in the terminal (only for kitty
# terminal), and with git integration enabled every change is commited.
#
# These commands are "streamed", so even if you cancelled the command early
# with Ctrl+C or just exited the shell, all changes done until the exit are
# already applied.
export def 'img' []: nothing -> record { gen-help 'img' }

# Add wallpapers to the store.
#
# To get information about the valid inputs, consider reading help for `img`
# command.
#
# If interactive mode is not used, then the command just set the data for the
# new wallpapers from the input based on provided `tags` and `source`.
#
# Because tags cannot be empty, if they are left empty in non-interactive mode,
# no wallpapers are actually added.
#
# In interactive mode `tags` and `source` act as a default value. `tags` are
# appended to all user selected tags, and `source` is used if source is not
# selected.
#
# Because it's just a default value in interactive mode, no arguments are
# required to use this mode. In this case, if you just skip all the images,
# then all images are not added. That's because only valid data is written
# to the store, so blank input acts as invalid and is silently ignored.
#
# You cannot add the same image twice to the store. If you want to edit an
# image, consider using `img edit` command. Input that's not "new" is ignored.
export def 'img add' [
    ...tags: string
    # Tags to be set on the wallpapers.

    --source (-s): string
    # Source to be set on the wallpapers.

    --git (-g)
    # Use `git` to commit after every added image.

    --interactive (-i)
    # Interactively enter the data for each image.
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

# Edit wallpaper data in the store.
#
# To get information about the valid inputs, consider reading help for `img`
# command.
#
# If interactive mode is not used, then the command just set the data for the
# selected wallpapers from the input based on provided `tags` and `source`.
#
# Because tags cannot be empty, if they are left empty in non-interactive mode,
# no tags are actually changed. If the source is not provided, it is not
# changes as well. But if source is explicitly provided (not `null`), it is
# changed, even it is an empty string.
#
# In interactive mode `tags` and `source` act as a default value. `tags` are
# appended to all user selected tags, and `source` is used if source is not
# selected.
#
# Because it's just a default value in interactive mode, no arguments are
# required to use this mode. In this case, if you just skip all the images,
# then all images remain unedited. That's because only valid data is written
# to the store, so blank input acts as invalid and is silently ignored.
export def 'img edit' [
    ...tags: string
    # Tags to be set on the wallpapers.

    --source (-s): string
    # Source to be set on the wallpapers.

    --git (-g)
    # Use `git` to commit after every edited image.

    --interactive (-i)
    # Interactively enter the data for each image.
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

# Delete images from the store.
#
# To get information about the valid inputs, consider reading help for `img`
# command.
#
# Image is deleted both from the file and the directory. Initial source for the
# image is untouched, because the module doesn't even keep this information.
export def 'img del' [
    --git (-g)
    # Use `git` to commit after every deleted image.

    --interactive (-i)
    # Interactively select the images to delete.
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

# Get path in the store for the image.
#
# To get information about the valid inputs, consider reading help for `img`
# command.
#
# Returned paths are absolute. If you need to get relative paths, consider using
# `| path relative-to $env.PWD` pipe after the command. Be careful, because
# this construct fails under certain conditions. Check the help of the
# `path relative-to` command for more information.
export def 'img path' []: [
    nothing -> list<string>
    string -> list<string>
    list<string> -> list<string>
] {
    get-input
    | to-wp
    | with-path
    | get path
}

# Namespace for commands to manage tags in the store.
#
# These commands, opposed to "pick" commands, are using hashes and not
# interactive.
#
# "tag filter" is designed to be used with a custom wrapper (see "pick")
# commands, but "tag list" and "tag rename" could be used as is.
export def 'tag' []: nothing -> record {
    gen-help 'tag'
}

# Get all tags from the store.
#
# This function could be used to find mistyped tags or be used in completions
# or interactive menus, how it's done in `pick` commands.
export def 'tag list' []: nothing -> list<string> {
    store-table | get meta.tags | flatten | uniq
}

# Rename a tag in the store.
#
# `old` tags in the store are replaced with `new` tags. Tags should be unique,
# so if two tags after the rename are equal to each other, no duplicates remain.
#
# Empty tags and tags with spaced are not allowed. Renaming is global.
export def 'tag rename' [
    old: string
    # Tag to rename.

    new: string
    # Resulting name for the tag.
]: nothing -> nothing {
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

# Get hashes from the store based on a tag filter.
#
# Tags for each wallpaper are passed to the `filter` closure. If the closure
# returns `true`, then hash of the image is included in the result list.
export def 'tag filter' [
    filter: closure
    # The closure to pass the tags to.
]: nothing -> list<string> {
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

# Namespace for commands to get paths from the store interactively.
#
# "pick" commands act as a layer to get paths (most useful in this case)
# from the store. This could be done manually, but "pick" commands provide
# interactivity as well.
#
# Using this command as is will just produce this help message.
export def 'pick' []: nothing -> record { gen-help 'pick' }

# Get paths from the store where any tag matches.
#
# Right now it's case-sensitive, as well as `pick all`.
export def 'pick any' [
    ...tags: string
    # Tags to match.

    --interactive (-i)
    # If enabled, select additional tags to append to `tags` argument from all
    # available tags via `tag list`.
]: nothing -> list<string> {
    let dst = ($tags | select-tags $interactive)
    tag filter {|src| $src | any {|tag| $tag in $dst } } | img path
}

# Get paths from the store where all tags are matched.
#
# Doesn't do "exact" matching. For example, `[ tag-1 tag-2 ]` in the function
# as `tags` matches `[ tag-1 tag-2 tag-3 ]`.
export def 'pick all' [
    ...tags: string
    # Tags to match.

    --interactive (-i)
    # If enabled, select additional tags to append to `tags` argument from all
    # available tags via `tag list`.
]: nothing -> list<string> {
    let dst = ($tags | select-tags $interactive)
    tag filter {|src| $src | all {|tag| $tag in $dst } } | img path
}

# Get random paths from the store.
#
# By default, all paths from the store are returned.
#
# Designed to be used with a wallpaper daemon to change a wallpaper very fast.
# If you need to specify tags, consider using other `pick` functions.
export def 'pick random' [
    count?: int
    # Number of paths to return. If equals 1, return type is `string`.
]: [
    nothing -> string
    nothing -> list<string>
] {
    let paths = (store-table | get hash | shuffle | img path)

    if $count == null {
        $paths
    } else if $count == 1 {
        $paths | first
    } else if $count > 0 {
        $paths | first $count
    } else {
        []
    }
}

# Get paths from the store via picking tags with `fzf`.
#
# Because it uses `fzf`, it is expected to be available. This command is a
# wrapper, so `args` are passed to `fzf`.
#
# Each line passed to `fzf` looks like this: `<path> <tag-1> <tag-2> ...`. But
# for the picker the path (first field) is hidden.
#
# Because this function is pointless without a preview, it's recommended to use
# one. Though it's hidden, the first field is available for the preview:
# `--preview "previewer.sh {1}"`.
#
# One of the examples is provided as the `f` alias in the module. It uses
# Nushell raw strings and skips `fzf` escaping, because otherwise the previewer
# fails if path contains a single quote.
export def --wrapped 'pick fzf' [
    ...args: string
    # Options that are passed to the `fzf` call inside.
]: nothing -> list<string> {
    store-table
    | with-path
    | each {|wp| $wp.path | append $wp.meta.tags | str join ' ' }
    | to text
    | fzf --accept-nth='1' --with-nth='2..' ...$args
    | lines
}

export alias a = img add
export alias e = img edit
export alias d = img del
export alias p = img path
export alias v = store verify
export alias f = pick fzf --preview "fzf-preview.bash r#'{r1}'#"
export alias r = pick random 1
