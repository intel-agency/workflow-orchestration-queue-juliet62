"""
OS-APOW Unified Work Item Model

Canonical data model shared by both the Sentinel Orchestrator and the
Work Event Notifier. Both components import from this module to prevent
model divergence.

See: OS-APOW Plan Review, I-1 / R-3
"""

import re
from enum import Enum
from pydantic import BaseModel


class TaskType(str, Enum):
    """The kind of work the agent should perform."""

    PLAN = "PLAN"
    IMPLEMENT = "IMPLEMENT"
    BUGFIX = "BUGFIX"


class WorkItemStatus(str, Enum):
    """Maps directly to GitHub Issue labels used as state indicators."""

    QUEUED = "agent:queued"
    IN_PROGRESS = "agent:in-progress"
    RECONCILING = "agent:reconciling"
    SUCCESS = "agent:success"
    ERROR = "agent:error"
    INFRA_FAILURE = "agent:infra-failure"
    STALLED_BUDGET = "agent:stalled-budget"


class WorkItem(BaseModel):
    """Unified work item used across all OS-APOW components.

    Fields populated by the Notifier are marked Optional so the Sentinel
    can construct WorkItems from its own polling results without requiring
    the raw webhook payload.
    """

    id: str
    issue_number: int
    source_url: str
    context_body: str
    target_repo_slug: str
    task_type: TaskType
    status: WorkItemStatus
    node_id: str


# --- Credential Scrubber (R-7) ---
# Regex patterns that match common secret formats. Used to sanitize
# worker output before posting to GitHub issue comments.

_SECRET_PATTERNS = [
    re.compile(r"ghp_[A-Za-z0-9_]{36,}"),  # GitHub PAT (classic)
    re.compile(r"ghs_[A-Za-z0-9_]{36,}"),  # GitHub App installation token
    re.compile(r"gho_[A-Za-z0-9_]{36,}"),  # GitHub OAuth token
    re.compile(r"github_pat_[A-Za-z0-9_]{22,}"),  # GitHub fine-grained PAT
    re.compile(r"Bearer\s+[A-Za-z0-9\-._~+/]+=*", re.IGNORECASE),
    re.compile(r"token\s+[A-Za-z0-9\-._~+/]{20,}", re.IGNORECASE),
    re.compile(r"sk-[A-Za-z0-9]{20,}"),  # OpenAI-style API keys
    re.compile(r"[A-Za-z0-9]{32,}\.zhipu[A-Za-z0-9]*"),  # ZhipuAI keys
]


def scrub_secrets(text: str, replacement: str = "***REDACTED***") -> str:
    """Strip known secret patterns from text for safe public posting."""
    for pattern in _SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    return text
