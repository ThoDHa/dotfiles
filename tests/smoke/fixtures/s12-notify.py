"""Notification helpers with inline retry handling."""
import time


def send_notification(channel, message):
    for attempt in range(3):
        try:
            deliver(channel, message)
            return True
        except DeliveryError:
            time.sleep(2 ** attempt)
    return False


def deliver(channel, message):
    raise NotImplementedError("delivery backend not configured")


class DeliveryError(RuntimeError):
    pass
