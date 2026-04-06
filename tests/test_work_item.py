"""
Tests for WorkItem Model

Unit tests for the WorkItem model, TaskType enum, WorkItemStatus enum,
and credential scrubbing functionality.
"""

from datetime import UTC, datetime

import pytest

from src.models import TaskType, WorkItem, WorkItemStatus, scrub_secrets


class TestTaskType:
    """Tests for the TaskType enum."""

    def test_task_type_values(self) -> None:
        """Test that TaskType has expected values."""
        assert TaskType.PLAN.value == "PLAN"
        assert TaskType.IMPLEMENT.value == "IMPLEMENT"
        assert TaskType.BUGFIX.value == "BUGFIX"

    def test_task_type_count(self) -> None:
        """Test that TaskType has exactly 3 values."""
        assert len(TaskType) == 3

    def test_task_type_string_conversion(self) -> None:
        """Test that TaskType can be converted to string."""
        # StrEnum string representation is just the value
        assert str(TaskType.PLAN) == "PLAN"
        assert TaskType.IMPLEMENT.value == "IMPLEMENT"


class TestWorkItemStatus:
    """Tests for the WorkItemStatus enum."""

    def test_status_values(self) -> None:
        """Test that WorkItemStatus maps to correct GitHub labels."""
        assert WorkItemStatus.QUEUED.value == "agent:queued"
        assert WorkItemStatus.IN_PROGRESS.value == "agent:in-progress"
        assert WorkItemStatus.RECONCILING.value == "agent:reconciling"
        assert WorkItemStatus.SUCCESS.value == "agent:success"
        assert WorkItemStatus.ERROR.value == "agent:error"
        assert WorkItemStatus.INFRA_FAILURE.value == "agent:infra-failure"
        assert WorkItemStatus.STALLED_BUDGET.value == "agent:stalled-budget"

    def test_status_count(self) -> None:
        """Test that WorkItemStatus has exactly 7 values."""
        assert len(WorkItemStatus) == 7

    def test_from_label_valid(self) -> None:
        """Test conversion from valid label to status."""
        assert WorkItemStatus.from_label("agent:queued") == WorkItemStatus.QUEUED
        assert WorkItemStatus.from_label("agent:in-progress") == WorkItemStatus.IN_PROGRESS
        assert WorkItemStatus.from_label("agent:success") == WorkItemStatus.SUCCESS

    def test_from_label_invalid(self) -> None:
        """Test conversion from invalid label returns None."""
        assert WorkItemStatus.from_label("invalid-label") is None
        assert WorkItemStatus.from_label("") is None
        assert WorkItemStatus.from_label("bug") is None

    def test_all_labels(self) -> None:
        """Test that all_labels returns all status label strings."""
        labels = WorkItemStatus.all_labels()
        assert len(labels) == 7
        assert "agent:queued" in labels
        assert "agent:success" in labels
        assert "agent:error" in labels


class TestWorkItem:
    """Tests for the WorkItem model."""

    @pytest.fixture
    def sample_work_item(self) -> WorkItem:
        """Create a sample WorkItem for testing."""
        return WorkItem(
            issue_number=42,
            repository="owner/repo",
            task_type=TaskType.IMPLEMENT,
            status=WorkItemStatus.QUEUED,
            title="Test Issue",
            body="This is a test issue body",
            labels=["bug", "agent:queued"],
            created_at=datetime(2024, 1, 1, 12, 0, 0, tzinfo=UTC),
            updated_at=datetime(2024, 1, 2, 12, 0, 0, tzinfo=UTC),
        )

    def test_work_item_creation(self, sample_work_item: WorkItem) -> None:
        """Test basic WorkItem creation."""
        assert sample_work_item.issue_number == 42
        assert sample_work_item.repository == "owner/repo"
        assert sample_work_item.task_type == TaskType.IMPLEMENT
        assert sample_work_item.status == WorkItemStatus.QUEUED
        assert sample_work_item.title == "Test Issue"
        assert sample_work_item.body == "This is a test issue body"
        assert sample_work_item.labels == ["bug", "agent:queued"]
        assert sample_work_item.sentinel_id is None

    def test_work_item_with_sentinel_id(self) -> None:
        """Test WorkItem creation with sentinel_id."""
        item = WorkItem(
            issue_number=1,
            repository="owner/repo",
            title="Test",
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
            sentinel_id="sentinel-123",
        )
        assert item.sentinel_id == "sentinel-123"

    def test_work_item_repository_validation(self) -> None:
        """Test repository format validation."""
        # Valid formats
        item = WorkItem(
            issue_number=1,
            repository="owner/repo",
            title="Test",
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
        )
        assert item.repository == "owner/repo"

        # Invalid format - no slash
        with pytest.raises(ValueError, match="owner/repo"):
            WorkItem(
                issue_number=1,
                repository="invalidrepo",
                title="Test",
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            )

        # Invalid format - empty parts
        with pytest.raises(ValueError, match="owner/repo"):
            WorkItem(
                issue_number=1,
                repository="/repo",
                title="Test",
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            )

    def test_work_item_issue_number_validation(self) -> None:
        """Test issue_number must be positive."""
        with pytest.raises(ValueError):
            WorkItem(
                issue_number=0,
                repository="owner/repo",
                title="Test",
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            )

        with pytest.raises(ValueError):
            WorkItem(
                issue_number=-1,
                repository="owner/repo",
                title="Test",
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            )

    def test_work_item_title_validation(self) -> None:
        """Test title must be non-empty."""
        with pytest.raises(ValueError):
            WorkItem(
                issue_number=1,
                repository="owner/repo",
                title="",
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            )

    def test_get_status_label(self, sample_work_item: WorkItem) -> None:
        """Test get_status_label returns correct label."""
        assert sample_work_item.get_status_label() == "agent:queued"

        sample_work_item.status = WorkItemStatus.IN_PROGRESS
        assert sample_work_item.get_status_label() == "agent:in-progress"

    def test_has_label(self, sample_work_item: WorkItem) -> None:
        """Test has_label method."""
        assert sample_work_item.has_label("bug") is True
        assert sample_work_item.has_label("agent:queued") is True
        assert sample_work_item.has_label("nonexistent") is False

    def test_is_terminal_status(self, sample_work_item: WorkItem) -> None:
        """Test is_terminal_status method."""
        # Non-terminal statuses
        assert sample_work_item.is_terminal_status() is False  # QUEUED

        sample_work_item.status = WorkItemStatus.IN_PROGRESS
        assert sample_work_item.is_terminal_status() is False

        sample_work_item.status = WorkItemStatus.RECONCILING
        assert sample_work_item.is_terminal_status() is False

        # Terminal statuses
        sample_work_item.status = WorkItemStatus.SUCCESS
        assert sample_work_item.is_terminal_status() is True

        sample_work_item.status = WorkItemStatus.ERROR
        assert sample_work_item.is_terminal_status() is True

        sample_work_item.status = WorkItemStatus.INFRA_FAILURE
        assert sample_work_item.is_terminal_status() is True

        sample_work_item.status = WorkItemStatus.STALLED_BUDGET
        assert sample_work_item.is_terminal_status() is True

    def test_from_github_issue(self) -> None:
        """Test WorkItem creation from GitHub API data."""
        issue_data = {
            "number": 123,
            "title": "Test Issue",
            "body": "Issue body",
            "labels": [
                {"name": "bug"},
                {"name": "agent:queued"},
            ],
            "created_at": "2024-01-01T12:00:00Z",
            "updated_at": "2024-01-02T12:00:00Z",
        }

        item = WorkItem.from_github_issue(issue_data, "owner/repo")

        assert item.issue_number == 123
        assert item.repository == "owner/repo"
        assert item.title == "Test Issue"
        assert item.body == "Issue body"
        assert item.status == WorkItemStatus.QUEUED
        assert item.labels == ["bug", "agent:queued"]
        assert item.task_type == TaskType.BUGFIX  # inferred from "bug" label

    def test_from_github_issue_plan_inference(self) -> None:
        """Test Plan task type inference from labels and title."""
        # From label
        issue_data = {
            "number": 1,
            "title": "Test",
            "body": None,
            "labels": [{"name": "agent:plan"}],
            "created_at": "2024-01-01T12:00:00Z",
            "updated_at": "2024-01-01T12:00:00Z",
        }
        item = WorkItem.from_github_issue(issue_data, "owner/repo")
        assert item.task_type == TaskType.PLAN

        # From title
        issue_data["labels"] = []
        issue_data["title"] = "[Plan] Architecture design"
        item = WorkItem.from_github_issue(issue_data, "owner/repo")
        assert item.task_type == TaskType.PLAN

    def test_from_github_issue_status_inference(self) -> None:
        """Test status inference from labels."""
        issue_data = {
            "number": 1,
            "title": "Test",
            "body": None,
            "labels": [{"name": "agent:in-progress"}],
            "created_at": "2024-01-01T12:00:00Z",
            "updated_at": "2024-01-01T12:00:00Z",
        }
        item = WorkItem.from_github_issue(issue_data, "owner/repo")
        assert item.status == WorkItemStatus.IN_PROGRESS

    def test_model_serialization(self, sample_work_item: WorkItem) -> None:
        """Test model serialization with credential scrubbing."""
        data = sample_work_item.model_dump()

        assert data["issue_number"] == 42
        assert data["repository"] == "owner/repo"
        assert data["task_type"] == TaskType.IMPLEMENT
        assert data["status"] == WorkItemStatus.QUEUED
        assert data["title"] == "Test Issue"

    def test_model_serialization_scrubs_secrets(self) -> None:
        """Test that serialization scrubs secrets from body."""
        item = WorkItem(
            issue_number=1,
            repository="owner/repo",
            title="Test",
            body="My token is ghp_1234567890abcdefghijklmnopqrstuvwxyz1234",
            labels=[],
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
        )

        # The model serializer should scrub secrets
        data = item.model_dump()
        assert "ghp_" not in str(data)


class TestScrubSecrets:
    """Tests for the scrub_secrets function."""

    def test_scrub_github_pat_classic(self) -> None:
        """Test scrubbing of GitHub classic PAT."""
        # Token must be 36+ chars after ghp_
        text = "Token: ghp_1234567890abcdefghijklmnopqrstuvwxyz1234"
        result = scrub_secrets(text)
        assert "ghp_" not in result
        assert "***REDACTED***" in result

    def test_scrub_github_app_token(self) -> None:
        """Test scrubbing of GitHub App installation token."""
        text = "Token: ghs_1234567890abcdefghijklmnopqrstuvwxyz1234"
        result = scrub_secrets(text)
        assert "ghs_" not in result
        assert "***REDACTED***" in result

    def test_scrub_github_oauth_token(self) -> None:
        """Test scrubbing of GitHub OAuth token."""
        text = "Token: gho_1234567890abcdefghijklmnopqrstuvwxyz1234"
        result = scrub_secrets(text)
        assert "gho_" not in result

    def test_scrub_github_fine_grained_pat(self) -> None:
        """Test scrubbing of GitHub fine-grained PAT."""
        text = "Token: github_pat_1234567890abcdefghijklmnopqrst"
        result = scrub_secrets(text)
        assert "github_pat_" not in result

    def test_scrub_bearer_token(self) -> None:
        """Test scrubbing of Bearer tokens."""
        text = "Authorization: Bearer abc123def456ghi789jkl=="
        result = scrub_secrets(text)
        assert "Bearer abc" not in result

    def test_scrub_generic_token(self) -> None:
        """Test scrubbing of generic tokens."""
        text = "token abcdefghijklmnopqrstuvwxyz1234"
        result = scrub_secrets(text)
        assert result != text

    def test_scrub_openai_key(self) -> None:
        """Test scrubbing of OpenAI-style keys."""
        text = "API key: sk-1234567890abcdefghijklmnop"
        result = scrub_secrets(text)
        assert "sk-" not in result

    def test_scrub_zhipu_key(self) -> None:
        """Test scrubbing of ZhipuAI keys."""
        text = "Key: abcdefghijklmnopqrstuvwxyz123456.zhipuXYZ"
        result = scrub_secrets(text)
        assert ".zhipu" not in result

    def test_scrub_multiple_secrets(self) -> None:
        """Test scrubbing multiple secrets in one text."""
        text = "ghp_111111111111111111111111111111111111 and sk-2222222222222222222222"
        result = scrub_secrets(text)
        assert "ghp_" not in result
        assert "sk-" not in result
        assert result.count("***REDACTED***") == 2

    def test_scrub_empty_string(self) -> None:
        """Test scrubbing empty string."""
        assert scrub_secrets("") == ""

    def test_scrub_none_equivalent(self) -> None:
        """Test scrubbing returns input unchanged if falsy."""
        # The function doesn't handle None, it expects str
        # But it should handle empty string
        assert scrub_secrets("") == ""

    def test_scrub_custom_replacement(self) -> None:
        """Test scrubbing with custom replacement string."""
        text = "Token: ghp_1234567890abcdefghijklmnopqrstuvwxyz1234"
        result = scrub_secrets(text, replacement="[SECRET]")
        assert "[SECRET]" in result
        assert "ghp_" not in result

    def test_no_secrets_unchanged(self) -> None:
        """Test that text without secrets is unchanged."""
        text = "This is a normal string without any secrets"
        result = scrub_secrets(text)
        assert result == text


class TestWorkItemEdgeCases:
    """Edge case tests for WorkItem model."""

    def test_work_item_with_none_body(self) -> None:
        """Test WorkItem with None body."""
        item = WorkItem(
            issue_number=1,
            repository="owner/repo",
            title="Test",
            body=None,
            labels=[],
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
        )
        assert item.body is None

    def test_work_item_with_empty_labels(self) -> None:
        """Test WorkItem with empty labels list."""
        item = WorkItem(
            issue_number=1,
            repository="owner/repo",
            title="Test",
            labels=[],
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
        )
        assert item.labels == []

    def test_work_item_default_values(self) -> None:
        """Test WorkItem default values."""
        item = WorkItem(
            issue_number=1,
            repository="owner/repo",
            title="Test",
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
        )
        assert item.task_type == TaskType.IMPLEMENT
        assert item.status == WorkItemStatus.QUEUED
        assert item.body is None
        assert item.labels == []
        assert item.sentinel_id is None

    def test_from_github_issue_with_missing_body(self) -> None:
        """Test from_github_issue handles missing body."""
        issue_data = {
            "number": 1,
            "title": "Test",
            "labels": [],
            "created_at": "2024-01-01T12:00:00Z",
            "updated_at": "2024-01-01T12:00:00Z",
        }
        item = WorkItem.from_github_issue(issue_data, "owner/repo")
        assert item.body is None
