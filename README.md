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
kubectlgetall --help
    -h, --help
            Display this help and exit.

    -n, --namespace <STR>
            Namespace to get resources from.

    -A, --all-namespaces
            If present, list all objects across all namespaces. Specifing --namespace will be ignored.

    -s, --sort
            Prints the resources in order.

    -e, --exclude <STR>...
            Exclude crd types. Multiple can be excluded eg: "-e <CRD> -e <CRD>"

    -o, --output <OUTPUT>
            Changes the output format of the results.

    -d, --database <PATH>
            Path to the sqlite file to save the results. If the files does not exist it will be created.

    -l, --label <STR>
            Set the label that will be saved with entries when using the --database option.

        --log-level <LEVEL>
            Set the log level. All logs are saved to file. Possible values are (debug, info, warn, error). Defualt level is warn.

```

## Dev
### Creating the changelog

For new changes a news fragment is required. Add a fragment to
`changelog.d/` with the naming schema
`<issue id>.<feature|bugfix|doc|removal|misc>`.
Using `towncrier create -c "change message" <file name>` will create the file
for you in the correct location.

### Release process
1. Ensure all changes have news fragments in `changelog.d/`.
2. Update the version in `build.zig.zon`.
3. Run `zig build changelog_release` to update `CHANGELOG.md`.
4. Run `zig build release` to generate release archives in `dist/`.
5. Tag and publish the release with the generated archives and changelog.

