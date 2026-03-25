#!/usr/bin/env python3
"""
OS-APOW Subagent Trace Extractor
Isolates subagent execution threads from the main OpenCode rotating logs.
Usage: python3 trace-extract.py [--log <file>] [--sentinel-id <id>] [--scrub]
"""

import os
import sys
import json
import argparse
from pathlib import Path

# Import credential scrubber from sibling module
_script_dir = Path(__file__).resolve().parent
if str(_script_dir) not in sys.path:
    sys.path.insert(0, str(_script_dir))
try:
    from WorkItemModel import scrub_secrets
except ImportError:
    # Fallback: no-op if WorkItemModel is unavailable
    def scrub_secrets(text, replacement="***REDACTED***"):
        return text


def extract_trace(log_path, sentinel_id=None, scrub=False):
    if not os.path.exists(log_path):
        print(f"Error: Log file {log_path} not found.")
        return

    subagent_sessions = {}
    
    with open(log_path, 'r') as f:
        for line in f:
            try:
                entry = json.loads(line)
                
                # Filter by Sentinel ID if provided
                if sentinel_id and entry.get("sentinel_id") != sentinel_id:
                    continue

                # Detect Task tool calls (delegation)
                if entry.get("tool") == "Task":
                    task_args = entry.get("args", {})
                    sub_id = entry.get("childSessionId")
                    agent_name = task_args.get("agent", "unknown")
                    subagent_sessions[sub_id] = {
                        "agent": agent_name,
                        "objective": task_args.get("prompt", ""),
                        "logs": []
                    }

                # Associate log lines with subagent sessions
                sid = entry.get("sessionId")
                if sid in subagent_sessions:
                    subagent_sessions[sid]["logs"].append(entry)

            except json.JSONDecodeError:
                continue

    # Output distilled traces
    for sid, data in subagent_sessions.items():
        print(f"\n{'='*60}")
        print(f"SUBAGENT TRACE: {data['agent']} (ID: {sid})")
        objective = data["objective"][:100]
        if scrub:
            objective = scrub_secrets(objective)
        print(f"OBJECTIVE: {objective}...")
        print(f"{'='*60}")
        for log in data["logs"]:
            ts = log.get("timestamp", "")
            msg = log.get("message", "")
            if scrub:
                msg = scrub_secrets(msg)
            print(f"[{ts}] {msg}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Extract subagent traces from OpenCode logs"
    )
    parser.add_argument(
        "--log", help="Path to log file (default: most recent in opencode log dir)"
    )
    parser.add_argument("--sentinel-id", help="Filter by Sentinel instance ID")
    parser.add_argument(
        "--scrub",
        action="store_true",
        default=True,
        help="Scrub credentials from output (default: on)",
    )
    parser.add_argument(
        "--no-scrub", action="store_true", help="Disable credential scrubbing"
    )
    args = parser.parse_args()

    do_scrub = not args.no_scrub

    log_dir = Path.home() / ".local/share/opencode/log"
    target_log = args.log or sorted(log_dir.glob("*.log"))[-1]

    extract_trace(target_log, args.sentinel_id, scrub=do_scrub)