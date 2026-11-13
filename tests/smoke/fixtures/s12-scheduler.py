"""Scheduled job runner; two notification call sites."""
from notify import send_notification


def run_job(job):
    ok = send_notification("email", f"job {job} started")
    if not ok:
        raise RuntimeError("start notification failed")


def finish_job(job):
    ok = send_notification("email", f"job {job} finished")
    if not ok:
        raise RuntimeError("finish notification failed")
