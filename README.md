# kubectlgetall

List all CR's for all CRD types on a cluster in a given namespace.

**Requires kubectl to be installed.**

## Installation
 Install it to a user-writable directory like `~/.local/bin` and ensure it is on your `PATH`.

### Prebuilt release
Download the matching archive from the GitHub Releases page, then extract and
install it:

```shell
tar -xzf kubectlgetall_<version>_<os>_<arch>.tar.gz
mkdir -p ~/.local/bin
cp kubectlgetall ~/.local/bin/
```

### Build from source
```shell
zig build -Doptimize=ReleaseSmall -p ~/.local
```

Make sure `~/.local/bin` is on your `PATH`.

## Usage

```shell
kubectlgetall -n <namespace>
```

There are some flags that can be passed.
```shell
USAGE:
  kubectlgetall <COMMAND> [FLAGS] 

COMMANDS:
get                   Get list of resource on cluster.
diff                  Show the resources Added, Updated and Removed
                      from a cluster by comparing two labels defined in the database.

GLOBAL FLAGS:
-h, --help            Display this help and exit.
--version             Display version, and exit.
--log-level <LEVEL>   Set the log level. All logs are saved to file. 
                      Possible values are (debug, info, warn, error). Default level is warn.
```

## Dev
### Creating the changelog

On new changes a news fragment is required.
Create one interactively with:
```
zig build changie:add
```
This places a YAML fragment in `.changes/unreleased/`.
The available change kinds are: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.

### Release workflow
1. Ensure the version in `build.zig.zon` is correct for this release.
2. Batch the unreleased fragments into a versioned changelog file:
```
zig build changie:batch
```
3. Review the generated file in `.changes/` for the release version.
4. Merge all versioned changelogs into `CHANGELOG.md`:
```
zig build changie:merge
```
5. Commit changes.
6. Build release artifacts:
```
zig build release
```
7. Create a GitHub release for the current commit with the release version as the tag.
   - Release notes should be the changelog entry for that version.
   - Attach all artifacts from `dist/` to the GitHub release.
