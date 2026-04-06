"""
WorkItem Model Module

Canonical data model for the Sentinel MVP orchestration system.
Provides Pydantic-based validation, serialization, and GitHub label mapping.

See: Issue #3 - Phase 1, Story 1
"""

import re
from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field, field_validator, model_serializer


class TaskType(StrEnum):
    """The kind of work the agent should perform.

    Attributes:
        PLAN: Task is for planning/architecture work
        IMPLEMENT: Task is for implementation work
        BUGFIX: Task is for bug fixing work
    """

    PLAN = "PLAN"
    IMPLEMENT = "IMPLEMENT"
    BUGFIX = "BUGFIX"


class WorkItemStatus(StrEnum):
    """Maps directly to GitHub Issue labels used as state indicators.

    These enum values are the actual label strings used on GitHub issues
    to track the state of work items in the orchestration queue.

    Attributes:
        QUEUED: Item is waiting to be picked up (label: agent:queued)
        IN_PROGRESS: Item is being actively worked on (label: agent:in-progress)
        RECONCILING: Item is being reconciled (label: agent:reconciling)
        SUCCESS: Item completed successfully (label: agent:success)
        ERROR: Item failed with an error (label: agent:error)
        INFRA_FAILURE: Item failed due to infrastructure issues (label: agent:infra-failure)
        STALLED_BUDGET: Item stalled due to budget constraints (label: agent:stalled-budget)
    """

    QUEUED = "agent:queued"
    IN_PROGRESS = "agent:in-progress"
    RECONCILING = "agent:reconciling"
    SUCCESS = "agent:success"
    ERROR = "agent:error"
    INFRA_FAILURE = "agent:infra-failure"
    STALLED_BUDGET = "agent:stalled-budget"

    @classmethod
    def from_label(cls, label: str) -> "WorkItemStatus | None":
        """Convert a GitHub label string to a WorkItemStatus enum value.

        Args:
            label: The GitHub label string (e.g., "agent:queued")

        Returns:
            The corresponding WorkItemStatus enum value, or None if not found
        """
        try:
            return cls(label)
        except ValueError:
            return None

    @classmethod
    def all_labels(cls) -> list[str]:
        """Get all valid status labels.

        Returns:
            List of all status label strings
        """
        return [status.value for status in cls]


class WorkItem(BaseModel):
    """Unified work item model for the Sentinel MVP orchestration system.

    Represents a task in the orchestration queue, backed by a GitHub Issue.
    This model provides validation, serialization, and status management
    for work items processed by Sentinel instances.

    Attributes:
        issue_number: GitHub issue number
        repository: Repository identifier in owner/repo format
        task_type: Type of task (PLAN, IMPLEMENT, BUGFIX)
        status: Current status of the work item
        title: GitHub issue title
        body: GitHub issue body/description (may be None)
        labels: List of GitHub labels on the issue
        created_at: Timestamp when the item was created
        updated_at: Timestamp when the item was last updated
        sentinel_id: ID of the Sentinel instance assigned to this item (if any)
    """

    issue_number: int = Field(..., ge=1, description="GitHub issue number")
    repository: str = Field(
        ..., min_length=3, description="Repository in owner/repo format"
    )
    task_type: TaskType = Field(default=TaskType.IMPLEMENT, description="Type of task")
    status: WorkItemStatus = Field(
        default=WorkItemStatus.QUEUED, description="Current status"
    )
    title: str = Field(..., min_length=1, description="Issue title")
    body: str | None = Field(default=None, description="Issue body/description")
    labels: list[str] = Field(default_factory=list, description="GitHub labels")
    created_at: datetime = Field(..., description="Creation timestamp")
    updated_at: datetime = Field(..., description="Last update timestamp")
    sentinel_id: str | None = Field(
        default=None, description="Assigned sentinel instance ID"
    )

    @field_validator("repository")
    @classmethod
    def validate_repository(cls, v: str) -> str:
        """Validate repository format is owner/repo."""
        if "/" not in v:
            raise ValueError("Repository must be in 'owner/repo' format")
        parts = v.split("/")
        if len(parts) != 2 or not all(parts):
            raise ValueError("Repository must be in 'owner/repo' format")
        return v

    @model_serializer
    def serialize_model(self) -> dict[str, Any]:
        """Serialize the model with credential scrubbing applied.

        Ensures sensitive data in the body field is redacted before
        serialization to prevent token leakage in logs.

        Returns:
            Dictionary representation with scrubbed body field
        """
        data = {
            "issue_number": self.issue_number,
            "repository": self.repository,
            "task_type": self.task_type.value,
            "status": self.status.value,
            "title": self.title,
            "body": scrub_secrets(self.body) if self.body else None,
            "labels": self.labels,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
            "sentinel_id": self.sentinel_id,
        }
        return data

    @classmethod
    def from_github_issue(
        cls,
        issue_data: dict[str, Any],
        repository: str,
        task_type: TaskType = TaskType.IMPLEMENT,
    ) -> "WorkItem":
        """Create a WorkItem from GitHub API issue data.

        Args:
            issue_data: Dictionary containing GitHub API issue response
            repository: Repository identifier in owner/repo format
            task_type: Type of task (defaults to IMPLEMENT)

        Returns:
            A new WorkItem instance
        """
        labels = [label["name"] for label in issue_data.get("labels", [])]

        # Determine status from labels
        status = WorkItemStatus.QUEUED
        for label in labels:
            label_status = WorkItemStatus.from_label(label)
            if label_status:
                status = label_status
                break

        # Infer task type from labels if not explicitly provided
        if task_type == TaskType.IMPLEMENT:
            if "agent:plan" in labels or "[Plan]" in issue_data.get("title", ""):
                task_type = TaskType.PLAN
            elif "bug" in labels:
                task_type = TaskType.BUGFIX

        return cls(
            issue_number=issue_data["number"],
            repository=repository,
            task_type=task_type,
            status=status,
            title=issue_data.get("title", ""),
            body=issue_data.get("body"),
            labels=labels,
            created_at=datetime.fromisoformat(
                issue_data["created_at"].replace("Z", "+00:00")
            ),
            updated_at=datetime.fromisoformat(
                issue_data["updated_at"].replace("Z", "+00:00")
            ),
        )

    def get_status_label(self) -> str:
        """Get the GitHub label for the current status.

        Returns:
            The label string corresponding to the current status
        """
        return self.status.value

    def has_label(self, label: str) -> bool:
        """Check if the work item has a specific label.

        Args:
            label: The label to check for

        Returns:
            True if the label is present, False otherwise
        """
        return label in self.labels

    def is_terminal_status(self) -> bool:
        """Check if the work item is in a terminal (final) status.

        Returns:
            True if the status is terminal (SUCCESS, ERROR, INFRA_FAILURE, STALLED_BUDGET)
        """
        terminal_statuses = {
            WorkItemStatus.SUCCESS,
            WorkItemStatus.ERROR,
            WorkItemStatus.INFRA_FAILURE,
            WorkItemStatus.STALLED_BUDGET,
        }
        return self.status in terminal_statuses


# --- Credential Scrubber ---

# Regex patterns that match common secret formats
_SECRET_PATTERNS = [
    re.compile(r"ghp_[A-Za-z0-9_]{36,}"),  # GitHub PAT (classic)
    re.compile(r"ghs_[A-Za-z0-9_]{36,}"),  # GitHub App installation token
    re.compile(r"gho_[A-Za-z0-9_]{36,}"),  # GitHub OAuth token
    re.compile(r"github_pat_[A-Za-z0-9_]{22,}"),  # GitHub fine-grained PAT
    re.compile(r"Bearer\s+[A-Za-z0-9\-._~+/]+=*", re.IGNORECASE),  # Bearer tokens
    re.compile(r"token\s+[A-Za-z0-9\-._~+/]{20,}", re.IGNORECASE),  # Generic tokens
    re.compile(r"sk-[A-Za-z0-9]{20,}"),  # OpenAI-style API keys
    re.compile(r"[A-Za-z0-9]{32,}\.zhipu[A-Za-z0-9]*"),  # ZhipuAI keys
]


def scrub_secrets(text: str, replacement: str = "***REDACTED***") -> str:
    """Strip known secret patterns from text for safe logging or posting.

    This function removes sensitive credential patterns from text to prevent
    token leakage in logs, comments, or other public-facing outputs.

    Args:
        text: The text to scrub
        replacement: The string to replace secrets with (default: "***REDACTED***")

    Returns:
        The text with all matching secret patterns replaced

    Example:
        >>> scrub_secrets("My token is ghp_abc123...")
        'My token is ***REDACTED***'
    """
    if not text:
        return text

    for pattern in _SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    return text
