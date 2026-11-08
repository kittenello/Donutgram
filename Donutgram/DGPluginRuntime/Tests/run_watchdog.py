import argparse
import subprocess
import sys


CASES = [
    "join", "reverse", "sparse_sort", "regexp", "replace", "sort",
    "typed_sort", "regexp_linear", "stringify", "parse", "repeat", "trim", "bigint", "pending_storm",
    "pure_promise", "caught_join", "native_wait", "wait_cancel", "detached_wait",
    "cumulative_active", "descheduled", "cpu_window", "stop_join", "stop_regexp",
    "compile", "wrappers", "transforms", "transform_limit", "transform_error", "transform_denial", "rejection_getter", "default_policy",
]


def run(command, timeout):
    try:
        result = subprocess.run(command, timeout=timeout, capture_output=True, text=True)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"external watchdog killed {command[0]} {command[1:]} after {timeout}s") from error
    if result.stdout:
        print(result.stdout, end="", flush=True)
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr, flush=True)
    if result.returncode:
        raise RuntimeError(f"child failed with {result.returncode}: {command}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--regression", required=True)
    parser.add_argument("--native", required=True)
    parser.add_argument("--bootstrap", required=True)
    parser.add_argument("--default-smoke")
    parser.add_argument("--default-host")
    parser.add_argument("--skip", action="append", default=[], help="a scenario to leave out, such as a timing case the local host cannot meet")
    args = parser.parse_args()
    unknown = set(args.skip) - set(CASES)
    if unknown:
        raise SystemExit("unknown scenarios: " + ", ".join(sorted(unknown)))
    run([args.regression, args.bootstrap], 20)
    cases = [case for case in CASES if case not in args.skip]
    for case in cases:
        run([args.native, case, args.bootstrap], 10)
    for executable in [args.default_smoke, args.default_host]:
        if executable:
            run([executable], 15)
    print(f"passed regression process and {len(cases)} isolated native-work scenarios" + (f" ({len(args.skip)} skipped)" if args.skip else ""))


if __name__ == "__main__":
    main()
