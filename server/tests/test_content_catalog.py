from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


CONTENT_PATH = Path(__file__).parents[1] / "content.json"


def test_content_catalog_is_complete_and_consistent() -> None:
    payload = json.loads(CONTENT_PATH.read_text(encoding="utf-8"))
    activities = payload["activities"]
    age_groups = {item["name"] for item in payload["age_groups"]}
    domains = {item["name"] for item in payload["domains"]}

    assert len(activities) >= 60
    assert len({item["remote_id"] for item in activities}) == len(activities)
    assert len({item["title"] for item in activities}) == len(activities)

    age_counts: Counter[str] = Counter()
    for item in activities:
        assert item["remote_id"]
        assert item["title"]
        assert item["instruction"]
        assert item["duration_min"] > 0
        assert 1 <= item["difficulty"] <= 5
        assert item["domains"]
        assert item["age_groups"]
        assert item["tags"]
        assert set(item["domains"]) <= domains
        assert set(item["age_groups"]) <= age_groups
        age_counts.update(item["age_groups"])

    assert age_groups == {
        "1-2 года",
        "2-3 года",
        "3-4 года",
        "4-5 лет",
        "5-6 лет",
        "6-7 лет",
    }
    assert all(age_counts[group] >= 10 for group in age_groups)
