//! Provides help strings for the commands defined in the application.
//! The help documentation is manually formatted.

const std = @import("std");

const main_msg =
    \\USAGE:
    \\  kubectlgetall <COMMAND> [FLAGS]
    \\
    \\COMMANDS:
    \\get                   Get list of resource on cluster.
    \\diff                  Show the resources Added, Updated and Removed
    \\                      from a cluster by comparing two labels defined in the database.
    \\snapshot              Take a snapshot of the resources on the cluster at give intervals.
    \\
    \\GLOBAL FLAGS:
    \\-h, --help            Display this help and exit.
    \\--version             Display version, and exit.
    \\--log-level <LEVEL>   Set the log level. All logs are saved to file. 
    \\                      Possible values are (debug, info, warn, error). Default level is warn.
    \\
;

const get_msg =
    \\USAGE:
    \\  kubectlgetall get [FLAGS]
    \\
    \\Get list of resource on a cluster.
    \\
    \\REQUIREMENTS:
    \\kubectl must be installed and available on PATH.
    \\An active connection to a Kubernetes cluster is required.
    \\
    \\FLAGS:
    \\-h, --help                Display this help and exit.
    \\-n, --namespace <STR>     Namespace to get resources from.
    \\-A, --all-namespaces      If present, list all objects across all namespaces.     
    \\                          Specifying --namespace will be ignored.
    \\-s, --sort                Prints the resources in order.
    \\-e, --exclude <STR>...    Exclude crd types. Multiple can be excluded eg: "-e <CRD> -e <CRD>"
    \\-o, --output <OUTPUT>     Changes the output format of the results. [default: tty, tty|json|sqlite]
    \\-d, --database <PATH>     Path to the sqlite file to save the results.
    \\                          If the files does not exist it will be created.
    \\-l, --label <STR>         Set the label that will be saved with entries when using the --database option.
    \\
;

const diff_msg =
    \\USAGE:
    \\  kubectlgetall diff <BASE> <HEAD> [FLAGS]
    \\
    \\Show the resources Added, Updated and Removed
    \\from a cluster by comparing two labels defined in the database.
    \\
    \\REQUIREMENTS:
    \\A SQLite database populated by the get command. See: kubectlgetall get --help
    \\
    \\ARGUMENTS:
    \\BASE    The older label. Serves as the baseline for comparison.
    \\HEAD    The newer label. Compared against BASE to identify what has changed.
    \\
    \\Items in HEAD but not BASE are reported as new.
    \\Items in BASE but not HEAD are reported as removed.
    \\Items in both but differing in value are reported as updated.
    \\
    \\FLAGS:
    \\-h, --help                Display this help and exit.
    \\-d, --database <PATH>     Path to SQLite database to load data from.
    \\-e, --exclude <STR>...    Exclude resource types. Multiple can be excluded eg: "-e <KIND> -e <KIND>"
    \\-o, --output <OUTPUT>     Changes the output format of the results. [default: tty, tty|json]
    \\
;

const snapshot_msg =
    \\USAGE:
    \\  kubectlgetall snapshot [FLAGS]
    \\
    \\Take a snapshot of the resources on the cluster at given intervals.
    \\
    \\REQUIREMENTS:
    \\kubectl must be installed and available on PATH.
    \\An active connection to a Kubernetes cluster is required.
    \\
    \\FLAGS:
    \\-h, --help                Display this help and exit.
    \\-n, --namespace <STR>     Namespace to get resources from.
    \\-A, --all-namespaces      If present, list all objects across all namespaces.     
    \\                          Specifying --namespace will be ignored.
    \\-d, --database <PATH>     Path to the sqlite file to save the results.
    \\                          If the files does not exist it will be created. [REQUIRED]
    \\-l, --label <STR>         Set the label that will be saved with entries in the database.
    \\                          Labels will have a suffix of the snapshot iteration, <LABEL-N> [REQUIRED]
    \\--delay <TIME>            Time delay between snaphoting the cluster.
    \\                          Format can be INT, or INTs, INTm, INTh. 
    \\                          Default time delay of 60, 60s, 1m.
    \\-c, --count <INT>         Number of sanpshots to take. Default 0, meaning unlimited.
    \\--limit <TIME>            Max runtime of sanpshot.
    \\                          If time limit is reached before the count limit is reached the appliction will exit.
    \\                          Format can be INT, or INTs, INTm, INTh. Default of time limit of 0, meaning unlimited.
    \\-e, --exclude <STR>...    Exclude crd types. Multiple can be excluded eg: "-e <CRD> -e <CRD>"
    \\
;

fn print(
    io: std.Io,
    file: std.Io.File,
    msg: []const u8,
) !void {
    var buf: [1024]u8 = undefined;
    var writer = file.writer(io, &buf);
    try writer.interface.writeAll(msg);
    return writer.interface.flush();
}

pub fn main(io: std.Io, file: std.Io.File) !void {
    return print(io, file, main_msg);
}

pub fn get(io: std.Io, file: std.Io.File) !void {
    return print(io, file, get_msg);
}

pub fn diff(io: std.Io, file: std.Io.File) !void {
    return print(io, file, diff_msg);
}

pub fn snapshot(io: std.Io, file: std.Io.File) !void {
    return print(io, file, snapshot_msg);
}
