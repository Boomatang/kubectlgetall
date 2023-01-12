import asyncio
import subprocess  # nosec

import click

from kubectlgetall import __version__


def get_crd_list() -> list:
    value = []
    data = subprocess.run(  # nosec
        ["kubectl", "api-resources", "--verbs=list", "--namespaced", "-o", "name"],
        capture_output=True,
    )

    if data.stderr == b"":
        value = data.stdout.decode()
        value = value.split("\n")

    return value


async def get_result(
    namespace: str, crd_types: list, sort: bool = False, exclude: tuple = None
):
    exclude_ = ["events.events.k8s.io", "events", ""]

    if exclude is not None:
        exclude_ = exclude_ + list(exclude)

    for crd in crd_types:
        if crd not in exclude_:
            if sort:
                asyncio.create_task(get_cr_lists(crd, namespace))
            else:
                await get_cr_lists(crd, namespace)


async def get_cr_lists(crd, namespace):
    data = subprocess.run(  # nosec
        ["kubectl", "-n", namespace, "get", "--ignore-not-found", crd],
        capture_output=True,
    )
    if data.returncode == 0 and data.stdout != b"":
        click.secho(crd, fg="green", bold=True)
        click.echo(data.stdout.decode())


@click.command()
@click.version_option(version=__version__)
@click.argument("namespace")
@click.option(
    "-s",
    "--sort",
    is_flag=True,
    help="Prints the resources in an order. Initial results take longer to show. "
    "Unsorted return results faster but can hit rate limits.",
)
@click.option(
    "-e",
    "--exclude",
    multiple=True,
    help='Exclude crd types. Multiple can be excluded eg: "-e <crd type> -e <other type>"',
)
def cli(namespace, sort, exclude):
    """
    Returns a list of CR for the different CRDs in a given namespace
    """

    crd_types = get_crd_list()
    if sort:
        crd_types = sorted(crd_types)
        click.secho("Running in sorted mode", fg="red", bold=True)

    asyncio.run(get_result(namespace, crd_types, sort, exclude))


if __name__ == "__main__":
    cli()
