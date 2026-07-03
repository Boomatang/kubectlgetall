# Get Demo

This shows how to get a list of all the resources from a cluster using `kubectlgetall get`.
A KinD cluster is used in for the demo.

[![asciicast](https://asciinema.org/a/1260080.svg)](https://asciinema.org/a/1260080)

## Simple examples
1. Create the cluster. This creates a very basic cluster.
```sh
kind create cluster
```

2. List all the resources from the cluster.
```sh
kubectlgetall get --all-namespaces
```
This will return a long list of resources on the cluster group by type. 
By default, this is not a sorted list, but can be sorted by adding the `--sort` flag.

3. List resources from a specified namespace.
```sh
kubectlgetall get --namespace kube-system
```

4. List resources from the namespace your kubeconfig defaults too.
```sh
kubectlgetall get
```

## Output types
There are three formats the `get` command can output, TTY, JSON, or SQLite.
TTY is the default output that show the tables, and is the output type format used in the simple examples.

1. The JSON output gives all the data as a JSON object.
```sh
kubectlgetall get --output json
```
2. The output is not pretty printed, but this can be done by piping the results into `jq`.
```sh
kubectlgetall get --output json | jq
```

3. The next output type is SQLite. 
This is more complex, but allows creating historical views of a cluster.
When the output is set to `sqlite`, the path to a SQLite database most also be given.
If the database does not exist, it will be created.
```sh
kubectlgetall get --output sqlite --database example.db
```
If everything works as expected by default there will be no output to the terminal.

4. While saving the results to the database is useful, it is much better to include a label on the entries.
When the label is added this can be used to look results from multiple runs at a later date.
```sh
kubectlgetall get --output sqlite --database example.db --label demo1
```

## Other Options
There are other options that can be set on the `get` function, such as the log level.
These options can be viewed by passing the `--help` flag.
```sh
kubectlgetall get --help
```
