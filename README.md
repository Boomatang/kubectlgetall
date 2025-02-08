# kubectlgetall

List all CR's for all CRD types on a cluster in a given namespace.

**Requires kubectl to be installed.**

## Installation
Installing with no external dependencies.
```shell
pipx install kubectallgetall
```

Install with nice formatting.
```shell
pipx install kubectallgetall[rich]
```

## Usage

```shell
kubectlgetall <namespace>
```

There are some flags that can be passed.
```shell
kubectlgetall --help
usage: kubectlgetall [-h] [--version] [-s] [-e [EXCLUDE ...]]
                     [-o {tty,json,sqlite}] [-d DATABASE] [-l LABEL] [--debug]
                     namespace

Returns a list of CR for the different CRDs in a given namespace

positional arguments:
  namespace

options:
  -h, --help            show this help message and exit
  --version             show program's version number and exit
  -s, --sort            Prints the resources in an order. Initial results take
                        longer to show. Unsorted return results faster but can
                        hit rate limits.
  -e, --exclude [EXCLUDE ...]
                        Exclude crd types. Multiple can be excluded eg: "-e
                        <CRD> <CRD>"
  -o, --output {tty,json,sqlite}
                        Changes the output format of the results (default:
                        tty)
  -d, --database DATABASE
                        Path to the sqlite file to save the results. If the
                        file does not exist it will be created.
  -l, --label LABEL     Set the label that will be saved with entries when
                        using the --database option.
  --debug               Enable debug mode.

```

## Dev
### Creating the changelog

On new changes a news fragment is required.
This can be created by and news fragments to the `changes` directory.
These files are should have the following naming schema `<issue id>.<feature|bugfix|dic|removal|misc>`.
Using `towncrier create -c "change message" <file name>` will also create the file for you in the correct location.

