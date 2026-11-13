"""Validate deploy-config.yaml keys."""
import sys

import yaml

REQUIRED_KEYS = ("region", "replicas", "timeout_seconds")


def validate(path):
    with open(path) as fh:
        data = yaml.safe_load(fh)
    missing = [k for k in REQUIRED_KEYS if k not in data]
    if missing:
        print(f"missing keys: {missing}")
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(validate(sys.argv[1]))
