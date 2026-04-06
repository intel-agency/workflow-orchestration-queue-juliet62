"""
Queue Package

Exports the queue interface and implementations for the Sentinel MVP.
"""

from .github_queue import GitHubQueue, ITaskQueue

__all__ = [
    "ITaskQueue",
    "GitHubQueue",
]
