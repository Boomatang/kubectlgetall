# diff Demo

The diff demo is a bit more complex, but carries more power.
For the demo a preconfigured kind cluster will be used as this works best with a installed application.
The application that will be used is [kuadrant](https://kuadrant.io).
What the application does, or how it is set up has little affect on the demo.
But what it will show is all the resources that are created and updated when using applictions.

[![asciicast](https://asciinema.org/a/lGJb04MO90oLxpCo.svg)](https://asciinema.org/a/lGJb04MO90oLxpCo)

1. Setting up the kind cluster.
In the main operator for kuadrant, the [kuadrant-operator](https://github.com/kuadrant/kuadrant-operator), there is a make target that can be used to set up a dev cluster.
For what we need to do this is good enough for us. 
Follow their guide on getting the local set create. 
Hint: `make local-setup`

2. Take an initial dump of the resources on the cluster, and save them to the database.
```
kubectlgetall get --all-namespaces --output sqlite --database diff_demo.db --label initial
```

3. Apply the resource in the `diff_demo` directory.
This applies three resources to the cluster, kuadrant CR, RateLimitPolicy, and HTTProute.
We will see afterwards all the resources changed by adding these resources.
```
kubectl apply -k diff_demo
```

4. Wait for the RateLimitPolicy to become "Enforced".
Again what this is doing does not matter for the demo, but we do want to capture all the resources that may have changed.
```
kubectl wait ratelimitpolicy/httpbin-ratelimit --for=condition=Enforced --timeout=300s
```
5. Take a new dump from the cluster once the resources have being applied.
Setting a new label
```
kubectlgetall get --all-namespaces --output sqlite --database diff_demo.db --label resources_added
```

6. Final the `diff` command can be used to compare the resources from the `initial` label, and the `resources_added` label.
As events can be noisy below we filter those out.
```
kubectlgetall diff --database diff_demo.db initial resources_added --exclude event
```

## Other outputs
Like the other commands the output can be configured to output in JSON using the `--output` flag.
Unlike the `get` command the output type can not be `sqlite`. 
That type does not make sense currently for this command.

