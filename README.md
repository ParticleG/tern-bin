# tern-bin

Build an unsigned, locally installable pacman package from a manually downloaded
Tern Linux tarball. This is Stencil's closed-beta terminal workspace, not the
unrelated product at `tern.sh`.

This project does not download builds, authenticate with Stencil, install
packages, or publish to AUR. Keep the beta tarballs and generated packages out
of public repositories and caches. `.gitignore` excludes both.

## Requirements

- Arch Linux on x86_64, with `base-devel` installed.
- A regular user account; do not run `build.sh` with `sudo`.
- A trusted, authenticated download named
  `Tern-<version>-linux-x86_64.tar.gz`, containing the executable `tern/tern`.
  The musl variant and other architectures are not supported.
- The runtime dependencies in `PKGBUILD.in`, including the host's Vulkan driver.

Install the packaging tools and runtime helpers if they are not already present:

```sh
sudo pacman -S --needed base-devel git desktop-file-utils gtk-update-icon-cache \
  hicolor-icon-theme libgcc libglvnd libsecret libstdc++ libxkbcommon \
  vulkan-icd-loader wayland xdg-utils
```

The recipe also depends on the virtual `vulkan-driver` package. Keep the provider
appropriate for the host's GPU installed; the script does not choose or install
one. `makepkg` reports missing dependencies and stops rather than invoking
`pacman` to install them.

Download the tarball manually while signed in to Stencil. The build service is
protected by authentication; an unauthenticated download can return a login page
instead of an archive. The SHA256 calculated by this project checks local input
consistency, not vendor authenticity.

## Build and install

```sh
cd ~/coding/OtherProjects/tern-bin
./build.sh ~/Downloads/Tern-0.5.1-linux-x86_64.tar.gz
sudo pacman -U -- packages/tern-bin-0.5.1-1-x86_64.pkg.tar.zst
```

The input may be an absolute or relative path, including a directory with spaces.
The script can be invoked from any working directory. Output always goes into
this project's `packages/` directory. `.pkg.tar.zst` is the default Arch package
format; a different `PKGEXT` in `makepkg.conf` is reflected in the printed package
path and installation command.

An existing output is never overwritten or silently reused. If the package is
already built, install it directly. For a packaging revision or another beta
build with the same Tern version, choose a new positive integer `PKGREL`:

```sh
PKGREL=2 ./build.sh ~/Downloads/Tern-0.5.1-linux-x86_64.tar.gz
sudo pacman -U -- packages/tern-bin-0.5.1-2-x86_64.pkg.tar.zst
```

For a new upstream version, pass its new tarball; no source file or checksum
needs to be edited. `PKGREL` defaults to `1` for each invocation.

Launch the installed program with `tern` or the Tern application menu entry.
The closed-beta account gate still requires a Stencil account with beta access.
This project does not bypass it.

## What the build does

1. Derives the package version from the artifact's filename and calculates SHA256
   for the tarball and the project files it packages.
2. Renders `PKGBUILD.in` in a temporary, private workspace and links the original
   tarball into it without modifying or copying the input.
3. Runs `makepkg` with source, build, log and package destinations confined to
   that workspace, overriding shared cache paths from `makepkg.conf`.
4. Validates the desktop entries, checks the helper script's syntax and runs the
   real `tern/tern --version`. A non-executable input, linked executable, load
   failure, or version mismatch fails the build. It does not launch the GUI or
   invoke `tern register`.
5. Installs the unchanged binary at `/usr/bin/tern`, desktop entries at
   `/usr/share/applications/so.stencil.tern{,.open}.desktop` and
   `/usr/share/applications/tern-bin-open.desktop`, and the helper at
   `/usr/lib/tern-bin/tern-open-focus` inside the package. `!strip` and `!debug`
   preserve the vendor binary and avoid a separate debug package.
6. Publishes the completed package without overwriting an existing file, then
   removes the temporary workspace. Newly created output directories are private
   and package files have mode `0600`.

The repository contains only packaging code, text desktop entries and a small
shell helper. It does not vendor the closed-beta executable or its artwork.
System desktop entries use the standard `utilities-terminal` icon. On first
launch, Tern supplies its own icon and user-local desktop integration, using the
same desktop IDs as this package. Registration and runtime state belong to Tern,
not the build script. The package does not set default file handlers.

## Opening files in a Tern tab

Tern registers `so.stencil.tern.open.desktop` as its file handler. It runs
`tern --open-file %f` and is hidden (`NoDisplay=true`), so pickers that list
only visible applications, such as Dux Shell's default-apps page, do not offer
it. Opening a file through it started a separate Tern window that did not show
the file.

The package adds a separate entry, `tern-bin-open.desktop` ("Tern (open file)"),
that runs `/usr/lib/tern-bin/tern-open-focus`. The helper runs
`tern open --tab FILE...`, which opens the files in new tabs of the running Tern
and starts one if none runs. It then raises the Tern window on niri, because
`tern open` focuses the new block inside Tern but does not activate the window.
With several Tern windows the most recently focused one is raised, which is not
necessarily the one `tern open` used. Raising needs niri and `jq`; without them
the files still open and the step is skipped.

The entry has its own desktop ID because Tern's first launch and
`tern register` write user-local entries under the package's other IDs, which
take precedence over `/usr/share/applications`. Registration sets only the
`tern://` handler, so it does not undo a default chosen for this entry.

The package still does not set defaults. Choose "Tern (open file)" as the text
editor in the desktop's default-apps settings, or run:

```sh
xdg-mime default tern-bin-open.desktop text/plain text/markdown
```

## Differences from the Nix recipe

The reference uses `requireFile` because the source cannot be fetched without
an authenticated session. This project similarly requires a local artifact,
but derives the version and checksums for each invocation instead of maintaining
a fixed download URL and build-service ID.

NixOS needs `autoPatchelfHook`, explicit RUNPATH additions and a PATH wrapper.
Arch's native loader and system library paths already serve that role, so this
package neither patches nor wraps the binary. Dependencies cover the linked
C/C++ runtimes, dynamically loaded Vulkan/EGL/Wayland libraries, and the desktop,
icon and `git` helpers. `libsecret` supplies `secret-tool` for account credentials;
`gtk-update-icon-cache` supplies the cache utility without requiring all of GTK3
solely for that command.

The archive does not include license text. `LicenseRef-Proprietary` records the
closed-source classification from the reference; it grants no redistribution
rights. No AUR metadata, CI upload workflow or release automation is included.

## Updates and removal

Manage packaged updates through a new local build and `pacman -U`, rather than
the in-app updater. This project does not patch the upstream updater. User state
in `~/.config/tern`, or `TERN_CONFIG_DIR`, is independent of package replacement.

```sh
sudo pacman -Rns tern-bin
```

Removing the pacman package does not remove Tern's runtime state or its
user-local registration files. Tern provides `tern unregister` for its own
integration; run that before uninstalling if you want to remove it.

## Checks

```sh
shellcheck build.sh tern-open-focus
bash -n PKGBUILD.in
pacman -Qip packages/tern-bin-0.5.1-1-x86_64.pkg.tar.zst
pacman -Up --print-format '%n %v' packages/tern-bin-0.5.1-1-x86_64.pkg.tar.zst
```

The final command resolves the local installation transaction without installing
it. Every real build also performs the native version and desktop entry checks.

## References

- [Tern packaging guide, pinned commit](https://github.com/pelikanade/flake/blob/f6f8217278a4a119c8e3a5b27b5a30ffef57cbd1/docs/tern.md)
- [Nix package recipe at the same commit](https://github.com/pelikanade/flake/blob/f6f8217278a4a119c8e3a5b27b5a30ffef57cbd1/modules/packages/tern.nix)
