"""
Tests for GitHub Queue

Unit tests for the ITaskQueue interface and GitHubQueue implementation
using mocked HTTP responses.
"""

from datetime import UTC, datetime
from unittest.mock import patch

import pytest
import respx
from httpx import Response

from src.models import TaskType, WorkItem, WorkItemStatus
from src.queue import GitHubQueue, ITaskQueue


class TestITaskQueue:
    """Tests for the ITaskQueue abstract interface."""

    def test_is_abstract(self) -> None:
        """Test that ITaskQueue cannot be instantiated directly."""
        with pytest.raises(TypeError):
            ITaskQueue()  # type: ignore

    def test_abstract_methods(self) -> None:
        """Test that all required methods are abstract."""
        abstract_methods = {
            "get_next",
            "claim",
            "update_status",
            "complete",
            "fail",
            "add_comment",
            "close",
        }
        # Verify all methods are in __abstractmethods__
        assert abstract_methods.issubset(ITaskQueue.__abstractmethods__)


class TestGitHubQueueInit:
    """Tests for GitHubQueue initialization."""

    def test_init_with_token(self) -> None:
        """Test initialization with explicit token."""
        queue = GitHubQueue(token="test-token", org="testorg", repo="testrepo")
        assert queue.token == "test-token"
        assert queue.org == "testorg"
        assert queue.repo == "testrepo"
        assert "Authorization" in queue.headers
        assert queue.headers["Authorization"] == "token test-token"

    def test_init_with_env_token(self) -> None:
        """Test initialization using environment variable for token."""
        with patch.dict("os.environ", {"GITHUB_TOKEN": "env-token"}):
            queue = GitHubQueue(org="testorg", repo="testrepo")
            assert queue.token == "env-token"

    def test_init_with_bot_login(self) -> None:
        """Test initialization with bot_login for assignment."""
        queue = GitHubQueue(
            token="test-token",
            org="testorg",
            repo="testrepo",
            bot_login="sentinel-bot",
        )
        assert queue.bot_login == "sentinel-bot"

    def test_init_empty_defaults(self) -> None:
        """Test initialization with empty defaults."""
        queue = GitHubQueue(token="test-token")
        assert queue.org == ""
        assert queue.repo == ""
        assert queue.bot_login == ""


class TestGitHubQueueGetNext:
    """Tests for GitHubQueue.get_next method."""

    @pytest.fixture
    def queue(self) -> GitHubQueue:
        """Create a GitHubQueue instance for testing."""
        return GitHubQueue(token="test-token", org="testorg", repo="testrepo")

    @pytest.fixture
    def sample_issue_response(self) -> dict:
        """Sample GitHub API issue response."""
        return {
            "id": 123456,
            "number": 42,
            "title": "Test Issue",
            "body": "Test body",
            "html_url": "https://github.com/testorg/testrepo/issues/42",
            "labels": [{"name": "agent:queued"}, {"name": "bug"}],
            "state": "open",
            "created_at": "2024-01-01T12:00:00Z",
            "updated_at": "2024-01-02T12:00:00Z",
        }

    @pytest.mark.asyncio
    async def test_get_next_success(self, queue: GitHubQueue, sample_issue_response: dict) -> None:
        """Test successful get_next call."""
        with respx.mock:
            respx.get("https://api.github.com/repos/testorg/testrepo/issues").mock(
                return_value=Response(200, json=[sample_issue_response])
            )

            result = await queue.get_next()

            assert result is not None
            assert result.issue_number == 42
            assert result.repository == "testorg/testrepo"
            assert result.title == "Test Issue"
            assert result.status == WorkItemStatus.QUEUED

    @pytest.mark.asyncio
    async def test_get_next_empty_queue(self, queue: GitHubQueue) -> None:
        """Test get_next with empty queue."""
        with respx.mock:
            respx.get("https://api.github.com/repos/testorg/testrepo/issues").mock(
                return_value=Response(200, json=[])
            )

            result = await queue.get_next()

            assert result is None

    @pytest.mark.asyncio
    async def test_get_next_no_org_repo(self) -> None:
        """Test get_next returns None when org/repo not configured."""
        queue = GitHubQueue(token="test-token")
        result = await queue.get_next()
        assert result is None

    @pytest.mark.asyncio
    async def test_get_next_api_error(self, queue: GitHubQueue) -> None:
        """Test get_next handles API errors."""
        with respx.mock:
            respx.get("https://api.github.com/repos/testorg/testrepo/issues").mock(
                return_value=Response(500, json={"message": "Server error"})
            )

            result = await queue.get_next()

            assert result is None

    @pytest.mark.asyncio
    async def test_get_next_rate_limit(self, queue: GitHubQueue) -> None:
        """Test get_next returns None on rate limit (logs error)."""
        with respx.mock:
            respx.get("https://api.github.com/repos/testorg/testrepo/issues").mock(
                return_value=Response(429, json={"message": "Rate limit exceeded"})
            )

            # The code catches rate limit errors and returns None
            result = await queue.get_next()
            assert result is None


class TestGitHubQueueClaim:
    """Tests for GitHubQueue.claim method."""

    @pytest.fixture
    def queue(self) -> GitHubQueue:
        """Create a GitHubQueue instance for testing."""
        return GitHubQueue(
            token="test-token",
            org="testorg",
            repo="testrepo",
            bot_login="sentinel-bot",
        )

    @pytest.fixture
    def work_item(self) -> WorkItem:
        """Create a sample WorkItem for testing."""
        return WorkItem(
            issue_number=42,
            repository="testorg/testrepo",
            task_type=TaskType.IMPLEMENT,
            status=WorkItemStatus.QUEUED,
            title="Test Issue",
            body="Test body",
            labels=["agent:queued"],
            created_at=datetime(2024, 1, 1, tzinfo=UTC),
            updated_at=datetime(2024, 1, 1, tzinfo=UTC),
        )

    @pytest.mark.asyncio
    async def test_claim_without_bot_login(self, work_item: WorkItem) -> None:
        """Test claim without bot_login (no assignment verification)."""
        queue = GitHubQueue(token="test-token", org="testorg", repo="testrepo")

        with respx.mock:
            # Mock label removal
            respx.delete(
                "https://api.github.com/repos/testorg/testrepo/issues/42/labels/agent:queued"
            ).mock(return_value=Response(204))

            # Mock label addition
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/labels").mock(
                return_value=Response(200, json={"labels": [{"name": "agent:in-progress"}]})
            )

            # Mock comment posting
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/comments").mock(
                return_value=Response(201, json={"id": 1})
            )

            result = await queue.claim(work_item, "sentinel-123")

            assert result is True

    @pytest.mark.asyncio
    async def test_claim_with_bot_login_success(
        self, queue: GitHubQueue, work_item: WorkItem
    ) -> None:
        """Test claim with bot_login and successful assignment verification."""
        with respx.mock:
            # Mock assignment
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/assignees").mock(
                return_value=Response(201, json={"assignees": [{"login": "sentinel-bot"}]})
            )

            # Mock verification fetch
            respx.get("https://api.github.com/repos/testorg/testrepo/issues/42").mock(
                return_value=Response(
                    200,
                    json={
                        "number": 42,
                        "assignees": [{"login": "sentinel-bot"}],
                    },
                )
            )

            # Mock label operations
            respx.delete(
                "https://api.github.com/repos/testorg/testrepo/issues/42/labels/agent:queued"
            ).mock(return_value=Response(204))

            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/labels").mock(
                return_value=Response(200, json={})
            )

            # Mock comment posting
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/comments").mock(
                return_value=Response(201, json={})
            )

            result = await queue.claim(work_item, "sentinel-123")

            assert result is True

    @pytest.mark.asyncio
    async def test_claim_race_condition_lost(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test claim fails when losing race condition."""
        with respx.mock:
            # Mock assignment
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/assignees").mock(
                return_value=Response(201, json={})
            )

            # Mock verification - different assignee (race lost)
            respx.get("https://api.github.com/repos/testorg/testrepo/issues/42").mock(
                return_value=Response(
                    200,
                    json={
                        "number": 42,
                        "assignees": [{"login": "other-bot"}],
                    },
                )
            )

            result = await queue.claim(work_item, "sentinel-123")

            assert result is False

    @pytest.mark.asyncio
    async def test_claim_assignment_failure(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test claim fails when assignment fails."""
        with respx.mock:
            # Mock assignment failure
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/assignees").mock(
                return_value=Response(422, json={"message": "Invalid assignee"})
            )

            result = await queue.claim(work_item, "sentinel-123")

            assert result is False


class TestGitHubQueueUpdateStatus:
    """Tests for GitHubQueue.update_status method."""

    @pytest.fixture
    def queue(self) -> GitHubQueue:
        """Create a GitHubQueue instance for testing."""
        return GitHubQueue(token="test-token", org="testorg", repo="testrepo")

    @pytest.fixture
    def work_item(self) -> WorkItem:
        """Create a sample WorkItem for testing."""
        return WorkItem(
            issue_number=42,
            repository="testorg/testrepo",
            task_type=TaskType.IMPLEMENT,
            status=WorkItemStatus.IN_PROGRESS,
            title="Test Issue",
            labels=["agent:in-progress"],
            created_at=datetime(2024, 1, 1, tzinfo=UTC),
            updated_at=datetime(2024, 1, 1, tzinfo=UTC),
        )

    @pytest.mark.asyncio
    async def test_update_status_success(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test successful status update."""
        with respx.mock:
            # Mock label removal
            respx.delete(
                "https://api.github.com/repos/testorg/testrepo/issues/42/labels/agent:in-progress"
            ).mock(return_value=Response(204))

            # Mock label addition
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/labels").mock(
                return_value=Response(200, json={})
            )

            result = await queue.update_status(work_item, WorkItemStatus.SUCCESS)

            assert result is True

    @pytest.mark.asyncio
    async def test_update_status_failure(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test status update failure."""
        with respx.mock:
            respx.delete(
                "https://api.github.com/repos/testorg/testrepo/issues/42/labels/agent:in-progress"
            ).mock(return_value=Response(204))

            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/labels").mock(
                return_value=Response(500, json={})
            )

            result = await queue.update_status(work_item, WorkItemStatus.SUCCESS)

            assert result is False


class TestGitHubQueueComplete:
    """Tests for GitHubQueue.complete method."""

    @pytest.fixture
    def queue(self) -> GitHubQueue:
        """Create a GitHubQueue instance for testing."""
        return GitHubQueue(token="test-token", org="testorg", repo="testrepo")

    @pytest.fixture
    def work_item(self) -> WorkItem:
        """Create a sample WorkItem for testing."""
        return WorkItem(
            issue_number=42,
            repository="testorg/testrepo",
            task_type=TaskType.IMPLEMENT,
            status=WorkItemStatus.IN_PROGRESS,
            title="Test Issue",
            labels=["agent:in-progress"],
            created_at=datetime(2024, 1, 1, tzinfo=UTC),
            updated_at=datetime(2024, 1, 1, tzinfo=UTC),
        )

    @pytest.mark.asyncio
    async def test_complete_success(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test successful completion."""
        with respx.mock:
            # Mock label operations
            respx.delete(
                "https://api.github.com/repos/testorg/testrepo/issues/42/labels/agent:in-progress"
            ).mock(return_value=Response(204))

            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/labels").mock(
                return_value=Response(200, json={})
            )

            # Mock comment posting
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/comments").mock(
                return_value=Response(201, json={})
            )

            result = await queue.complete(work_item)

            assert result is True


class TestGitHubQueueFail:
    """Tests for GitHubQueue.fail method."""

    @pytest.fixture
    def queue(self) -> GitHubQueue:
        """Create a GitHubQueue instance for testing."""
        return GitHubQueue(token="test-token", org="testorg", repo="testrepo")

    @pytest.fixture
    def work_item(self) -> WorkItem:
        """Create a sample WorkItem for testing."""
        return WorkItem(
            issue_number=42,
            repository="testorg/testrepo",
            task_type=TaskType.IMPLEMENT,
            status=WorkItemStatus.IN_PROGRESS,
            title="Test Issue",
            labels=["agent:in-progress"],
            created_at=datetime(2024, 1, 1, tzinfo=UTC),
            updated_at=datetime(2024, 1, 1, tzinfo=UTC),
        )

    @pytest.mark.asyncio
    async def test_fail_success(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test successful failure marking."""
        with respx.mock:
            # Mock label operations
            respx.delete(
                "https://api.github.com/repos/testorg/testrepo/issues/42/labels/agent:in-progress"
            ).mock(return_value=Response(204))

            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/labels").mock(
                return_value=Response(200, json={})
            )

            # Mock comment posting
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/comments").mock(
                return_value=Response(201, json={})
            )

            result = await queue.fail(work_item, "Something went wrong")

            assert result is True

    @pytest.mark.asyncio
    async def test_fail_scrubs_secrets(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test that fail scrubs secrets from error message."""
        with respx.mock:
            respx.delete(
                "https://api.github.com/repos/testorg/testrepo/issues/42/labels/agent:in-progress"
            ).mock(return_value=Response(204))

            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/labels").mock(
                return_value=Response(200, json={})
            )

            # Capture the comment body
            comment_request = respx.post(
                "https://api.github.com/repos/testorg/testrepo/issues/42/comments"
            ).mock(return_value=Response(201, json={}))

            await queue.fail(
                work_item,
                "Error with token ghp_1234567890abcdefghijklmnopqrstuv",
            )

            # Verify the secret was scrubbed
            request_body = comment_request.calls[0].request.content
            assert b"ghp_" not in request_body


class TestGitHubQueueAddComment:
    """Tests for GitHubQueue.add_comment method."""

    @pytest.fixture
    def queue(self) -> GitHubQueue:
        """Create a GitHubQueue instance for testing."""
        return GitHubQueue(token="test-token", org="testorg", repo="testrepo")

    @pytest.fixture
    def work_item(self) -> WorkItem:
        """Create a sample WorkItem for testing."""
        return WorkItem(
            issue_number=42,
            repository="testorg/testrepo",
            task_type=TaskType.IMPLEMENT,
            status=WorkItemStatus.QUEUED,
            title="Test Issue",
            labels=[],
            created_at=datetime(2024, 1, 1, tzinfo=UTC),
            updated_at=datetime(2024, 1, 1, tzinfo=UTC),
        )

    @pytest.mark.asyncio
    async def test_add_comment_success(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test successful comment posting."""
        with respx.mock:
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/comments").mock(
                return_value=Response(201, json={"id": 123})
            )

            result = await queue.add_comment(work_item, "Test comment")

            assert result is True

    @pytest.mark.asyncio
    async def test_add_comment_failure(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test comment posting failure."""
        with respx.mock:
            respx.post("https://api.github.com/repos/testorg/testrepo/issues/42/comments").mock(
                return_value=Response(500, json={})
            )

            result = await queue.add_comment(work_item, "Test comment")

            assert result is False

    @pytest.mark.asyncio
    async def test_add_comment_scrubs_secrets(
        self, queue: GitHubQueue, work_item: WorkItem
    ) -> None:
        """Test that add_comment scrubs secrets."""
        with respx.mock:
            comment_request = respx.post(
                "https://api.github.com/repos/testorg/testrepo/issues/42/comments"
            ).mock(return_value=Response(201, json={}))

            # Use a token that matches the pattern (36+ chars after ghp_)
            await queue.add_comment(
                work_item,
                "My token is ghp_1234567890abcdefghijklmnopqrstuvwxyz1234",
            )

            request_body = comment_request.calls[0].request.content
            assert b"ghp_" not in request_body
            assert b"***REDACTED***" in request_body


class TestGitHubQueueClose:
    """Tests for GitHubQueue.close method."""

    @pytest.mark.asyncio
    async def test_close(self) -> None:
        """Test that close properly releases resources."""
        queue = GitHubQueue(token="test-token", org="testorg", repo="testrepo")

        await queue.close()

        # After close, the client should be closed
        assert queue._client.is_closed


class TestGitHubQueueFetchAllQueued:
    """Tests for GitHubQueue.fetch_all_queued method."""

    @pytest.fixture
    def queue(self) -> GitHubQueue:
        """Create a GitHubQueue instance for testing."""
        return GitHubQueue(token="test-token", org="testorg", repo="testrepo")

    @pytest.mark.asyncio
    async def test_fetch_all_queued_success(self, queue: GitHubQueue) -> None:
        """Test fetching all queued items."""
        issues = [
            {
                "id": 1,
                "number": 41,
                "title": "First Issue",
                "body": "Body 1",
                "labels": [{"name": "agent:queued"}],
                "state": "open",
                "created_at": "2024-01-01T12:00:00Z",
                "updated_at": "2024-01-01T12:00:00Z",
            },
            {
                "id": 2,
                "number": 42,
                "title": "Second Issue",
                "body": "Body 2",
                "labels": [{"name": "agent:queued"}],
                "state": "open",
                "created_at": "2024-01-02T12:00:00Z",
                "updated_at": "2024-01-02T12:00:00Z",
            },
        ]

        with respx.mock:
            respx.get("https://api.github.com/repos/testorg/testrepo/issues").mock(
                return_value=Response(200, json=issues)
            )

            result = await queue.fetch_all_queued()

            assert len(result) == 2
            assert result[0].issue_number == 41
            assert result[1].issue_number == 42

    @pytest.mark.asyncio
    async def test_fetch_all_queued_empty(self, queue: GitHubQueue) -> None:
        """Test fetching all queued when empty."""
        with respx.mock:
            respx.get("https://api.github.com/repos/testorg/testrepo/issues").mock(
                return_value=Response(200, json=[])
            )

            result = await queue.fetch_all_queued()

            assert result == []

    @pytest.mark.asyncio
    async def test_fetch_all_queued_no_org_repo(self) -> None:
        """Test fetch_all_queued returns empty when org/repo not configured."""
        queue = GitHubQueue(token="test-token")
        result = await queue.fetch_all_queued()
        assert result == []


class TestGitHubQueuePostHeartbeat:
    """Tests for GitHubQueue.post_heartbeat method."""

    @pytest.fixture
    def queue(self) -> GitHubQueue:
        """Create a GitHubQueue instance for testing."""
        return GitHubQueue(token="test-token", org="testorg", repo="testrepo")

    @pytest.fixture
    def work_item(self) -> WorkItem:
        """Create a sample WorkItem for testing."""
        return WorkItem(
            issue_number=42,
            repository="testorg/testrepo",
            task_type=TaskType.IMPLEMENT,
            status=WorkItemStatus.IN_PROGRESS,
            title="Test Issue",
            labels=[],
            created_at=datetime(2024, 1, 1, tzinfo=UTC),
            updated_at=datetime(2024, 1, 1, tzinfo=UTC),
        )

    @pytest.mark.asyncio
    async def test_post_heartbeat_success(self, queue: GitHubQueue, work_item: WorkItem) -> None:
        """Test successful heartbeat posting."""
        with respx.mock:
            comment_request = respx.post(
                "https://api.github.com/repos/testorg/testrepo/issues/42/comments"
            ).mock(return_value=Response(201, json={}))

            result = await queue.post_heartbeat(work_item, "sentinel-123", 300)

            assert result is True
            # Verify the comment contains elapsed time
            request_body = comment_request.calls[0].request.content
            assert b"5m" in request_body  # 300 seconds = 5 minutes
