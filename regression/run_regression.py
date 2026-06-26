import argparse
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent

TESTS = [
    {"id": "sanity",          "testname": "mem_ctrl_sanity_test",         "cov": False, "sanity": True},
    {"id": "base_directed",   "testname": "mem_ctrl_test",                "cov": True,  "seed": 1},
    {"id": "random_s1",       "testname": "mem_ctrl_random_test",         "cov": True,  "seed": 1},
    {"id": "random_s2",       "testname": "mem_ctrl_random_test",         "cov": True,  "seed": 2},
    {"id": "random_s3",       "testname": "mem_ctrl_random_test",         "cov": True,  "seed": 3},
    {"id": "long_read",       "testname": "mem_ctrl_long_read_test",      "cov": True},
    {"id": "write_readback",  "testname": "mem_ctrl_write_readback_test", "cov": True},
    {"id": "error_injection", "testname": "mem_ctrl_error_injection_test","cov": True},
]


def is_pass(log_path):
    for line in log_path.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] in ("UVM_FATAL", "UVM_ERROR") and parts[1] == ":":
            try:
                if int(parts[2]) > 0:
                    return False
            except ValueError:
                pass
    return True


def run_test(entry, no_cov=False):
    cov = entry.get("cov", False) and not no_cov
    seed = entry.get("seed")

    cmd = ["make", "-C", str(REPO_ROOT), "all",
           f"TESTNAME={entry['testname']}",
           f"COV={1 if cov else 0}"]
    if cov:
        cmd += [f"COV_DB_DIR={REPO_ROOT}/cov/{entry['id']}", "COV_DB_NAME=coverage"]
    if seed is not None:
        cmd.append(f"SEED={seed}")

    log_path = REPO_ROOT / "regression" / f"{entry['id']}.log"
    t0 = time.time()
    with open(log_path, "w") as f:
        result = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT)
    elapsed = time.time() - t0

    passed = result.returncode == 0 and is_pass(log_path)
    return "PASS" if passed else "FAIL", elapsed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sanity", action="store_true", help="Run sanity test only")
    parser.add_argument("--no-cov", action="store_true", help="Disable coverage for all tests")
    args = parser.parse_args()

    tests = [t for t in TESTS if not args.sanity or t.get("sanity")]

    results = []
    for entry in tests:
        print(f"\n[{entry['id']}] {entry['testname']}")
        status, elapsed = run_test(entry, no_cov=args.no_cov)
        results.append((entry["id"], status, elapsed))
        print(f"  => {status} ({elapsed:.1f}s)")

    print(f"\n{'='*48}")
    print(f"  {'ID':<24} {'STATUS':<8} {'TIME':>6}")
    print(f"  {'-'*24} {'-'*8} {'-'*6}")
    for tid, status, elapsed in results:
        print(f"  {tid:<24} {status:<8} {elapsed:>5.1f}s")
    fail_cnt = sum(1 for _, s, _ in results if s == "FAIL")
    print(f"{'='*48}")
    print(f"  TOTAL {len(results)}  PASS {len(results) - fail_cnt}  FAIL {fail_cnt}\n")
    sys.exit(0 if fail_cnt == 0 else 1)


if __name__ == "__main__":
    main()
