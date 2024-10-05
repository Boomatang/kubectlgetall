import asyncio
import datetime
import json
import sqlite3
import subprocess  # nosec

import click

from kubectlgetall import __version__


def db_connection(database):
    conn = sqlite3.connect(database)
    cur = conn.cursor()
    cur.execute(
        "CREATE TABLE IF NOT EXISTS results(apiVersion, kind, name, namespace, creationTimestamp, resourceVersion, resultTimestamp, resultLabel)"
    )
    return cur, conn


async def results_to_db(namespace, crd_types, exclude, database, label):
    click.echo(f"saving results for namespace {namespace} to {database}")
    cur, conn = db_connection(database)
    exclude_ = ["events.events.k8s.io", "events", ""]
    if exclude is not None:
        exclude_ = exclude_ + list(exclude)

    block = {}
    for crd in crd_types:
        if crd not in exclude_:
            await get_cr_lists_json(crd, namespace, block)

    timestamp = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    data = []
    for crd in block:
        for item in block[crd]:
            data.append(
                (
                    item["apiVersion"],
                    item["kind"],
                    item["metadata"]["name"],
                    item["metadata"]["namespace"],
                    item["metadata"]["creationTimestamp"],
                    item["metadata"].get("resourceVersion", None),
                    timestamp,
                    label,
                )
            )
    cur.executemany("INSERT INTO results VALUES(?, ?, ?, ?, ?, ?, ?, ?)", data)
    conn.commit()
    click.echo(f"saving results for namespace {namespace} to {database}: completed")


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


async def get_result_json(
    namespace: str, crd_types: list, sort: bool = False, exclude: tuple = None
):
    exclude_ = ["events.events.k8s.io", "events", ""]

    if exclude is not None:
        exclude_ = exclude_ + list(exclude)

    block = {}
    for crd in crd_types:
        if crd not in exclude_:
            await get_cr_lists_json(crd, namespace, block)

    click.echo(block)


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


async def get_cr_lists_json(crd, namespace, store: dict):
    data = subprocess.run(  # nosec
        [
            "kubectl",
            "-n",
            namespace,
            "get",
            "--ignore-not-found",
            crd,
            "--output",
            "json",
        ],
        capture_output=True,
    )
    if data.returncode == 0 and data.stdout != b"":
        d = json.loads(data.stdout.decode())
        for e in d["items"]:
            if "spec" in e:
                del e["spec"]
            if "data" in e:
                del e["data"]
        store[crd] = d["items"]


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
@click.option(
    "-o",
    "--output",
    default="tty",
    type=click.Choice(["tty", "json", "sqlite"]),
    show_default=True,
    help="Changes the output format of the results",
)
@click.option(
    "-d",
    "--database",
    help="Path to the sqlite file to save the results. If the file does not exist it will be created.",
)
@click.option(
    "-l",
    "--label",
    help="Set the label that will be saved with entries when using the --database option.",
)
def cli(namespace, sort, exclude, output, database, label):
    """
    Returns a list of CR for the different CRDs in a given namespace
    """
    if output != "tty" and sort:
        click.secho(
            f"Can't use --sort with --output set to {output}", fg="red", bold=True
        )
        exit(1)
    crd_types = get_crd_list()
    if sort:
        crd_types = sorted(crd_types)
        click.secho("Running in sorted mode", fg="red", bold=True)

    if output == "json":
        asyncio.run(get_result_json(namespace, crd_types, exclude))
    elif output == "sqlite":
        if database is None:
            click.secho(
                "Require setting --database when using --output=sqlite",
                fg="red",
                bold=True,
            )
            exit(1)
        asyncio.run(results_to_db(namespace, crd_types, exclude, database, label))
    else:
        asyncio.run(get_result(namespace, crd_types, sort, exclude))


if __name__ == "__main__":
    cli()
