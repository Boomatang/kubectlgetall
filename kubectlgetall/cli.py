import argparse
import asyncio
import datetime
import json
import logging
import sqlite3
import subprocess  # nosec
from typing import Any

from kubectlgetall import __version__

logger: logging.Logger = logging.getLogger("kubectlgetall")


def db_connection(database: str) -> tuple[sqlite3.Cursor, sqlite3.Connection]:
    conn = sqlite3.connect(database)
    cur = conn.cursor()
    cur.execute(
        "CREATE TABLE IF NOT EXISTS results(apiVersion, kind, name, namespace, creationTimestamp, resourceVersion, resultTimestamp, resultLabel)"
    )
    return cur, conn


async def results_to_db(
    namespace: str, crd_types: list[str], exclude: tuple[str], database: str, label: str
) -> None:
    logger.info(f"saving results for namespace {namespace} to {database}")
    cur, conn = db_connection(database)
    exclude_ = ["events.events.k8s.io", "events", ""]
    if exclude is not None:
        exclude_ = exclude_ + list(exclude)

    block: dict[str, Any] = {}
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
    logger.info(f"saving results for namespace {namespace} to {database}: completed")


def get_crd_list() -> list[str]:
    value: list[str] = []
    data = subprocess.run(  # nosec
        ["kubectl", "api-resources", "--verbs=list", "--namespaced", "-o", "name"],
        capture_output=True,
    )

    if data.stderr == b"":
        value = data.stdout.decode().split("\n")

    return value


async def get_result_json(
    namespace: str,
    crd_types: list[str],
    sort: bool = False,
    exclude: tuple[str] | None = None,
) -> None:
    exclude_ = ["events.events.k8s.io", "events", ""]

    if exclude is not None:
        exclude_ = exclude_ + list(exclude)

    block: dict[str, Any] = {}
    for crd in crd_types:
        if crd not in exclude_:
            await get_cr_lists_json(crd, namespace, block)

    print(block)


async def get_result(
    namespace: str,
    crd_types: list[str],
    sort: bool = False,
    exclude: tuple[str] | None = None,
) -> None:
    exclude_ = ["events.events.k8s.io", "events", ""]

    if exclude is not None:
        exclude_ = exclude_ + list(exclude)

    for crd in crd_types:
        if crd not in exclude_:
            if sort:
                asyncio.create_task(get_cr_lists(crd, namespace))
            else:
                await get_cr_lists(crd, namespace)


async def get_cr_lists_json(crd: str, namespace: str, store: dict[str, Any]) -> None:
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


async def get_cr_lists(crd: str, namespace: str) -> None:
    data = subprocess.run(  # nosec
        ["kubectl", "-n", namespace, "get", "--ignore-not-found", crd],
        capture_output=True,
    )
    if data.returncode == 0 and data.stdout != b"":
        print(crd)
        print(data.stdout.decode())


def configure_logger(logger: logging.Logger, debug: bool = False) -> None:
    ch = logging.StreamHandler()
    if debug:
        logger.setLevel(logging.DEBUG)
        ch.setLevel(logging.DEBUG)
    else:
        logger.setLevel(logging.INFO)
        ch.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    ch.setFormatter(formatter)
    logger.addHandler(ch)


def cli() -> None:
    """
    Returns a list of CR for the different CRDs in a given namespace
    """

    parser = argparse.ArgumentParser(
        prog="kubectlgetall",
        description="Returns a list of CR for the different CRDs in a given namespace",
    )

    parser.add_argument("namespace")
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s, version {__version__}",
    )
    parser.add_argument(
        "-s",
        "--sort",
        action="store_true",
        help="Prints the resources in an order. Initial results take longer to show. "
        "Unsorted return results faster but can hit rate limits.",
    )
    parser.add_argument(
        "-e",
        "--exclude",
        nargs="*",
        help='Exclude crd types. Multiple can be excluded eg: "-e <CRD> <CRD>"',
    )
    parser.add_argument(
        "-o",
        "--output",
        default="tty",
        choices=["tty", "json", "sqlite"],
        help="Changes the output format of the results (default: %(default)s)",
    )
    parser.add_argument(
        "-d",
        "--database",
        help="Path to the sqlite file to save the results. If the file does not exist it will be created.",
    )
    parser.add_argument(
        "-l",
        "--label",
        help="Set the label that will be saved with entries when using the --database option.",
    )
    parser.add_argument("--debug", help="Enable debug mode.", action="store_true")
    args = parser.parse_args()
    configure_logger(logger, debug=args.debug)
    logger.debug(f"{args=}")

    command(
        args.namespace, args.sort, args.exclude, args.output, args.database, args.label
    )


def command(
    namespace: str,
    sort: bool,
    exclude: tuple[str],
    output: str,
    database: str,
    label: str,
) -> None:
    if output != "tty" and sort:
        logger.error(f"Can't use --sort with --output set to {output}")
        exit(1)
    crd_types = get_crd_list()
    if sort:
        crd_types = sorted(crd_types)
        logger.info("Running in sorted mode")

    if output == "json":
        asyncio.run(
            get_result_json(namespace=namespace, crd_types=crd_types, exclude=exclude)
        )
    elif output == "sqlite":
        if database is None:
            logger.error("Require setting --database when using --output=sqlite")
            exit(1)
        asyncio.run(results_to_db(namespace, crd_types, exclude, database, label))
    else:
        asyncio.run(get_result(namespace, crd_types, sort, exclude))


if __name__ == "__main__":
    cli()
