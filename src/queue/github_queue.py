"""
GitHub Queue Module

Provides the abstract ITaskQueue interface and concrete GitHubQueue implementation
for managing work items backed by GitHub Issues.

See: Issue #3 - Phase 1, Stories 2 & 3
"""

import logging
import os
from abc import ABC, abstractmethod
from datetime import UTC, datetime

import httpx

from src.models.work_item import (
    WorkItem,
    WorkItemStatus,
    scrub_secrets,
)

logger = logging.getLogger("sentinel.queue")


class ITaskQueue(ABC):
    """Abstract interface for the work queue.

    Defines the contract for queue implementations that manage work items.
    This abstraction allows swapping the backing store (GitHub, Linear, Jira, etc.)
    without changing the Sentinel orchestration logic.

    All methods are async to support non-blocking I/O operations.
    """

    @abstractmethod
    async def get_next(self) -> WorkItem | None:
        """Get the next queued work item from the queue.

        Returns:
            The next WorkItem if available, None if queue is empty
        """
        pass

    @abstractmethod
    async def claim(self, work_item: WorkItem, sentinel_id: str) -> bool:
        """Claim ownership of a work item.

        Atomically assigns the work item to a Sentinel instance.
        Uses an assign-then-verify pattern to prevent race conditions.

        Args:
            work_item: The work item to claim
            sentinel_id: Unique identifier of the Sentinel instance

        Returns:
            True if claim was successful, False if item was already claimed
        """
        pass

    @abstractmethod
    async def update_status(self, work_item: WorkItem, status: WorkItemStatus) -> bool:
        """Update the status of a work item.

        Updates the GitHub labels to reflect the new status.

        Args:
            work_item: The work item to update
            status: The new status to set

        Returns:
            True if update was successful, False otherwise
        """
        pass

    @abstractmethod
    async def complete(self, work_item: WorkItem) -> bool:
        """Mark a work item as successfully completed.

        Sets the status to SUCCESS and posts a completion comment.

        Args:
            work_item: The work item to complete

        Returns:
            True if completion was successful, False otherwise
        """
        pass

    @abstractmethod
    async def fail(self, work_item: WorkItem, error: str) -> bool:
        """Mark a work item as failed with an error message.

        Sets the status to ERROR and posts the error as a comment.
        The error message is scrubbed for sensitive data before posting.

        Args:
            work_item: The work item to fail
            error: Error message describing the failure

        Returns:
            True if failure was recorded successfully, False otherwise
        """
        pass

    @abstractmethod
    async def add_comment(self, work_item: WorkItem, body: str) -> bool:
        """Add a comment to the work item's GitHub issue.

        The comment body is scrubbed for sensitive data before posting.

        Args:
            work_item: The work item to comment on
            body: The comment body text

        Returns:
            True if comment was posted successfully, False otherwise
        """
        pass

    @abstractmethod
    async def close(self) -> None:
        """Close the queue and release resources.

        Should be called during graceful shutdown to release HTTP connections
        and any other held resources.
        """
        pass


class GitHubQueue(ITaskQueue):
    """GitHub-backed work queue implementation.

    Implements the ITaskQueue interface using GitHub Issues API.
    Uses httpx AsyncClient for efficient connection pooling.

    Attributes:
        token: GitHub personal access token for authentication
        org: GitHub organization name
        repo: GitHub repository name
        bot_login: Optional bot username for assignment operations
    """

    def __init__(
        self,
        token: str | None = None,
        org: str = "",
        repo: str = "",
        bot_login: str = "",
    ):
        """Initialize the GitHub queue.

        Args:
            token: GitHub PAT token (defaults to GITHUB_TOKEN env var)
            org: GitHub organization name
            repo: GitHub repository name
            bot_login: Bot username for assignment operations
        """
        self.token = token or os.environ.get("GITHUB_TOKEN", "")
        self.org = org
        self.repo = repo
        self.bot_login = bot_login

        self.headers = {
            "Authorization": f"token {self.token}",
            "Accept": "application/vnd.github.v3+json",
        }

        self._client = httpx.AsyncClient(
            headers=self.headers,
            timeout=30.0,
            limits=httpx.Limits(max_connections=10, max_keepalive_connections=5),
        )

    def _repo_api_url(self, repo_slug: str) -> str:
        """Build the GitHub API URL for a repository.

        Args:
            repo_slug: Repository in owner/repo format

        Returns:
            Full API URL for the repository
        """
        return f"https://api.github.com/repos/{repo_slug}"

    # --- ITaskQueue Implementation ---

    async def get_next(self) -> WorkItem | None:
        """Get the next queued work item from GitHub.

        Queries GitHub for open issues labeled 'agent:queued' in the
        configured repository.

        Returns:
            The next WorkItem if available, None if queue is empty or error occurs
        """
        if not self.org or not self.repo:
            logger.warning("get_next requires org and repo to be set")
            return None

        url = f"{self._repo_api_url(f'{self.org}/{self.repo}')}/issues"
        params = {"labels": WorkItemStatus.QUEUED.value, "state": "open"}

        try:
            response = await self._client.get(url, params=params)

            if response.status_code in (403, 429):
                # Propagate rate-limit errors for backoff handling
                response.raise_for_status()

            if response.status_code != 200:
                logger.error(
                    f"GitHub API error: {response.status_code} {response.text[:200]}"
                )
                return None

            issues = response.json()
            if not issues:
                return None

            # Return the first issue as a WorkItem
            issue = issues[0]
            repo_slug = f"{self.org}/{self.repo}"

            return WorkItem.from_github_issue(issue, repo_slug)

        except httpx.HTTPStatusError as e:
            logger.error(f"HTTP error fetching queued tasks: {e}")
            return None
        except Exception as e:
            logger.error(f"Error fetching queued tasks: {e}")
            return None

    async def claim(self, work_item: WorkItem, sentinel_id: str) -> bool:
        """Claim a work item using assign-then-verify distributed locking.

        Steps:
          1. Attempt to assign bot_login to the issue.
          2. Re-fetch the issue to verify we are the assignee.
          3. Only then update labels and post the claim comment.

        Args:
            work_item: The work item to claim
            sentinel_id: Unique identifier of the Sentinel instance

        Returns:
            True if claim was successful, False otherwise
        """
        base = self._repo_api_url(work_item.repository)
        url_issue = f"{base}/issues/{work_item.issue_number}"

        # Step 1: Attempt assignment (if bot_login is configured)
        if self.bot_login:
            resp = await self._client.post(
                f"{url_issue}/assignees",
                json={"assignees": [self.bot_login]},
            )
            if resp.status_code not in (200, 201):
                logger.warning(
                    f"Failed to assign #{work_item.issue_number}: {resp.status_code}"
                )
                return False

            # Step 2: Re-fetch and verify assignee
            verify_resp = await self._client.get(url_issue)
            if verify_resp.status_code == 200:
                assignees = [
                    a["login"] for a in verify_resp.json().get("assignees", [])
                ]
                if self.bot_login not in assignees:
                    logger.warning(
                        f"Lost race on #{work_item.issue_number} — "
                        f"assignees are {assignees}, expected {self.bot_login}"
                    )
                    return False
            else:
                logger.warning(
                    f"Could not verify assignment for #{work_item.issue_number}: "
                    f"{verify_resp.status_code}"
                )
                return False

        # Step 3: Update labels
        url_labels = f"{url_issue}/labels"
        resp = await self._client.delete(f"{url_labels}/{WorkItemStatus.QUEUED.value}")
        if resp.status_code not in (200, 204, 404, 410):
            logger.error(f"Label removal failed: {resp.status_code}")
            return False

        await self._client.post(
            url_labels,
            json={"labels": [WorkItemStatus.IN_PROGRESS.value]},
        )

        # Step 4: Post claim comment
        msg = (
            f"🚀 **Sentinel {sentinel_id}** has claimed this task.\n"
            f"- **Start Time:** {datetime.now(UTC).isoformat()}\n"
            f"- **Environment:** `devcontainer-opencode.sh` initializing..."
        )
        await self.add_comment(work_item, msg)

        logger.info(f"Successfully claimed Task #{work_item.issue_number}")
        return True

    async def update_status(self, work_item: WorkItem, status: WorkItemStatus) -> bool:
        """Update the status of a work item on GitHub.

        Removes the previous status label and adds the new one.

        Args:
            work_item: The work item to update
            status: The new status to set

        Returns:
            True if update was successful, False otherwise
        """
        base = self._repo_api_url(work_item.repository)
        url_labels = f"{base}/issues/{work_item.issue_number}/labels"

        # Remove IN_PROGRESS label if present
        resp = await self._client.delete(
            f"{url_labels}/{WorkItemStatus.IN_PROGRESS.value}"
        )
        if resp.status_code not in (200, 204, 404, 410):
            logger.error(f"Label cleanup failed: {resp.status_code}")

        # Add new status label
        resp = await self._client.post(url_labels, json={"labels": [status.value]})

        if resp.status_code in (200, 201):
            logger.info(
                f"Updated status of #{work_item.issue_number} to {status.value}"
            )
            return True

        logger.error(f"Failed to update status: {resp.status_code}")
        return False

    async def complete(self, work_item: WorkItem) -> bool:
        """Mark a work item as successfully completed.

        Args:
            work_item: The work item to complete

        Returns:
            True if completion was successful, False otherwise
        """
        success = await self.update_status(work_item, WorkItemStatus.SUCCESS)

        if success:
            msg = (
                f"✅ **Task Completed**\n"
                f"- **Completed At:** {datetime.now(UTC).isoformat()}\n"
                f"- **Status:** Success"
            )
            await self.add_comment(work_item, msg)

        return success

    async def fail(self, work_item: WorkItem, error: str) -> bool:
        """Mark a work item as failed with an error message.

        Args:
            work_item: The work item to fail
            error: Error message describing the failure

        Returns:
            True if failure was recorded successfully, False otherwise
        """
        success = await self.update_status(work_item, WorkItemStatus.ERROR)

        if success:
            safe_error = scrub_secrets(error)
            msg = (
                f"❌ **Task Failed**\n"
                f"- **Failed At:** {datetime.now(UTC).isoformat()}\n"
                f"- **Error:**\n```\n{safe_error}\n```"
            )
            await self.add_comment(work_item, msg)

        return success

    async def add_comment(self, work_item: WorkItem, body: str) -> bool:
        """Add a comment to the work item's GitHub issue.

        The comment body is scrubbed for sensitive data before posting.

        Args:
            work_item: The work item to comment on
            body: The comment body text

        Returns:
            True if comment was posted successfully, False otherwise
        """
        base = self._repo_api_url(work_item.repository)
        comment_url = f"{base}/issues/{work_item.issue_number}/comments"

        safe_body = scrub_secrets(body)

        try:
            resp = await self._client.post(comment_url, json={"body": safe_body})

            if resp.status_code in (200, 201):
                logger.debug(f"Posted comment to #{work_item.issue_number}")
                return True

            logger.error(f"Failed to post comment: {resp.status_code}")
            return False

        except Exception as e:
            logger.error(f"Error posting comment: {e}")
            return False

    async def close(self) -> None:
        """Close the queue and release HTTP client resources."""
        await self._client.aclose()
        logger.info("GitHub queue closed")

    # --- Additional Helper Methods ---

    async def fetch_all_queued(self) -> list[WorkItem]:
        """Fetch all queued work items from GitHub.

        Unlike get_next which returns only the first item, this method
        returns all items in the queue.

        Returns:
            List of all queued WorkItems
        """
        if not self.org or not self.repo:
            logger.warning("fetch_all_queued requires org and repo to be set")
            return []

        url = f"{self._repo_api_url(f'{self.org}/{self.repo}')}/issues"
        params = {"labels": WorkItemStatus.QUEUED.value, "state": "open"}

        try:
            response = await self._client.get(url, params=params)

            if response.status_code in (403, 429):
                response.raise_for_status()

            if response.status_code != 200:
                logger.error(
                    f"GitHub API error: {response.status_code} {response.text[:200]}"
                )
                return []

            issues = response.json()
            repo_slug = f"{self.org}/{self.repo}"

            work_items = []
            for issue in issues:
                try:
                    work_items.append(WorkItem.from_github_issue(issue, repo_slug))
                except Exception as e:
                    logger.warning(f"Failed to parse issue: {e}")

            return work_items

        except Exception as e:
            logger.error(f"Error fetching all queued tasks: {e}")
            return []

    async def post_heartbeat(
        self, work_item: WorkItem, sentinel_id: str, elapsed_secs: int
    ) -> bool:
        """Post a heartbeat comment to keep observers informed.

        Args:
            work_item: The work item being processed
            sentinel_id: ID of the Sentinel instance
            elapsed_secs: Elapsed time in seconds

        Returns:
            True if heartbeat was posted successfully
        """
        minutes = elapsed_secs // 60
        msg = (
            f"💓 **Heartbeat** — Sentinel {sentinel_id} still working.\n"
            f"- **Elapsed:** {minutes}m\n"
            f"- **Timestamp:** {datetime.now(UTC).isoformat()}"
        )
        return await self.add_comment(work_item, msg)
