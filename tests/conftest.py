"""
Tests Package

Test configuration and fixtures for the Sentinel MVP test suite.
"""

import pytest


@pytest.fixture
def mock_github_token(monkeypatch: pytest.MonkeyPatch) -> str:
    """Fixture to set a mock GitHub token."""
    token = "FAKE-GITHUB-TOKEN-FOR-TESTING-00000000"
    monkeypatch.setenv("GITHUB_TOKEN", token)
    return token
