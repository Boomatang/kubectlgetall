# kubectlgetall

List all CR's for all CRD types on a cluster in a given namespace.

**Requires kubectl to be installed.**

## Usage

```shell
kubectlgetall <namespace>
```

There are some flags that can be passed.
```shell
kubectlgetall --help
Usage: kubectlgetall [OPTIONS] NAMESPACE

  Returns a list of CR for the different CRDs in a given namespace

Options:
  --version                       Show the version and exit.
  -s, --sort                      Prints the resources in an order. Initial
                                  results take longer to show. Unsorted return
                                  results faster but can hit rate limits.
  -e, --exclude TEXT              Exclude crd types. Multiple can be excluded
                                  eg: "-e <crd type> -e <other type>"
  -o, --output [tty|json|sqlite]  Changes the output format of the results
                                  [default: tty]
  -d, --database TEXT             Path to the sqlite file to save the results.
                                  If the file does not exist it will be
                                  created.
  -l, --label TEXT                Set the label that will be saved with
                                  entries when using the --database option.
  --help                          Show this message and exit.

```

## Dev
### Creating the changelog

On new changes a news fragment is required.
This can be created by and news fragments to the `changes` directory.
These files are should have the following naming schema `<issue id>.<feature|bugfix|dic|removal|misc>`.
Using `towncrier create -c "change message" <file name>` will also create the file for you in the correct location.

fdsafa
fdsafa
