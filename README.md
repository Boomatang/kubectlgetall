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
  --version           Show the version and exit.
  -s, --sort          Prints the resources in an order. Initial results take
                      longer to show. Unsorted return results faster but can
                      hit rate limits.
  -e, --exclude TEXT  Exclude crd types. Multiple can be excluded eg: "-e <crd
                      type> -e <other type>"
  --help              Show this message and exit.


```