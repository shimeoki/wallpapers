# wallpapers

My public wallpaper collection in a single repository.

## Where are the wallpapers?

The thing is: there are none right now.

Initially this repository was made to provide wallpapers for my
[NixOS configuration](https://github.com/shimeoki/nixconfig), but there is also
no `flake.nix` for now.

I wanted to provide a framework for myself to conveniently manage the wallpapers
before actually adding them. One part is done: it's the [wp script](#wp).

My priorities are on other things right now, so I don't know when I will be able
to add Nix functionality and add the wallpapers after that.

## wp

It's a Nushell script for managing wallpapers from the terminal.

All relevant documentation is provided in the script itself. I recommend to read
the huge comment at the top, which serves as the help for the module in general.

The script is mostly complete and should be fully usable right now. Though the
command's signatures are not considered stable and breaking changes should be
expected.

If you want to try it yourself, after you have acquired the script file (either
by cloning the repository or just copying `wp.nu`), add this to your
configuration:

```nu
use /path/to/wp.nu
```

where you should replace `/path/to/` with the path to the downloaded file.

If you copied the repository, delete the `.gitignore` file. If you copied the
file manually (for example, to add to the Nushell configuration directory), you
should configure these variables

```nu
$env.WP_DIR = '/path/to/wallpapers'
$env.WP_FILE = '/path/to/wallpapers.toml'
```

as well, to not create the directory and the file in the same directory as
`wp.nu`. For the Git integration, it is expected that these paths are located in
a single repository.

After that, restart the shell and you should have the `wp` commands available.
