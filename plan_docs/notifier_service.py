"""
OS-APOW Work Event Notifier
A FastAPI-based webhook receiver that maps provider events (GitHub, etc.)
to a unified Work Item queue.
"""

import hmac
import hashlib
import os
import sys
from typing import Dict, Any
from fastapi import FastAPI, Request, HTTPException, Header, Depends

# Canonical shared model and queue
from src.models.work_item import (
    TaskType,
    WorkItemStatus,
    WorkItem,
)
from src.queue.github_queue import ITaskQueue, GitHubQueue


# --- 0. Environment validation at import time (I-5 / R-6) ---

_WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")
_GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")

_PLACEHOLDER_VALUES = {"your_webhook_secret_here", "YOUR_GITHUB_TOKEN", ""}

if _WEBHOOK_SECRET in _PLACEHOLDER_VALUES:
    print(
        "FATAL: WEBHOOK_SECRET is missing or still set to a placeholder value. "
        "Set it to the GitHub App webhook secret.",
        file=sys.stderr,
    )
    sys.exit(1)

if _GITHUB_TOKEN in _PLACEHOLDER_VALUES:
    print(
        "FATAL: GITHUB_TOKEN is missing or still set to a placeholder value.",
        file=sys.stderr,
    )
    sys.exit(1)

WEBHOOK_SECRET = _WEBHOOK_SECRET.encode()

# --- 1. FastAPI Application ---


app = FastAPI(title="OS-APOW Event Notifier")


def get_queue() -> ITaskQueue:
    """Dependency injection for the queue implementation.
    Phase 1: GitHub. Can be swapped for Linear, Jira, etc."""
    return GitHubQueue(token=_GITHUB_TOKEN)


async def verify_signature(request: Request, x_hub_signature_256: str = Header(None)):
    if not x_hub_signature_256:
        raise HTTPException(status_code=401, detail="X-Hub-Signature-256 missing")

    body = await request.body()
    signature = "sha256=" + hmac.new(WEBHOOK_SECRET, body, hashlib.sha256).hexdigest()

    if not hmac.compare_digest(signature, x_hub_signature_256):
        raise HTTPException(status_code=401, detail="Invalid signature")


# --- 2. Endpoints ---


@app.post("/webhooks/github", dependencies=[Depends(verify_signature)])
async def handle_github_webhook(
    request: Request, queue: ITaskQueue = Depends(get_queue)
):
    payload = await request.json()
    event_type = request.headers.get("X-GitHub-Event")

    if event_type == "issues" and payload.get("action") == "opened":
        issue = payload["issue"]
        labels = [label["name"] for label in issue.get("labels", [])]

        if "[Application Plan]" in issue["title"] or "agent:plan" in labels:
            work_item = WorkItem(
                id=str(issue["id"]),
                issue_number=issue["number"],
                source_url=issue["html_url"],
                target_repo_slug=payload["repository"]["full_name"],
                task_type=TaskType.PLAN,
                context_body=issue.get("body") or "",
                status=WorkItemStatus.QUEUED,
                node_id=issue["node_id"],
            )
            await queue.add_to_queue(work_item)
            return {"status": "accepted", "item_id": work_item.id}

    return {"status": "ignored", "reason": "No actionable OS-APOW event mapping found"}


@app.get("/health")
def health_check():
    return {"status": "online", "system": "OS-APOW Notifier"}


if __name__ == "__main__":
    import uvicorn

    # In dev, run with: uv run uvicorn notifier_service:app --reload
    uvicorn.run(app, host="0.0.0.0", port=8000)
