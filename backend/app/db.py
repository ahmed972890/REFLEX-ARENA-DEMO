import logging
import time
from datetime import UTC, datetime
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from .config import get_settings

logger = logging.getLogger(__name__)

# Single-table layout:
#   PLAYER#<name>  — one item per player, best_ms + games counter
#   META#stats     — atomic counter of total submissions
# The "gsi1" index (gsi1pk="LB", gsi1sk=best_ms) serves the sorted leaderboard.
# At real scale the single "LB" partition would be write-sharded — see docs/DECISIONS.md.
LEADERBOARD_PK = "LB"
STATS_PK = "META#stats"

_table = None


def _now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def get_table():
    global _table
    if _table is None:
        settings = get_settings()
        resource = boto3.resource(
            "dynamodb",
            region_name=settings.aws_region,
            endpoint_url=settings.dynamodb_endpoint,
            config=Config(
                retries={"max_attempts": 5, "mode": "adaptive"},
                connect_timeout=2,
                read_timeout=5,
            ),
        )
        _table = resource.Table(settings.dynamodb_table)
    return _table


def ensure_table() -> None:
    """Create the table when running against DynamoDB Local (retries while it boots)."""
    settings = get_settings()
    client = get_table().meta.client
    for attempt in range(10):
        try:
            client.describe_table(TableName=settings.dynamodb_table)
            return
        except client.exceptions.ResourceNotFoundException:
            break
        except Exception:
            logger.info("waiting for DynamoDB endpoint (attempt %d)", attempt + 1)
            time.sleep(1)
    try:
        client.create_table(
            TableName=settings.dynamodb_table,
            BillingMode="PAY_PER_REQUEST",
            AttributeDefinitions=[
                {"AttributeName": "pk", "AttributeType": "S"},
                {"AttributeName": "gsi1pk", "AttributeType": "S"},
                {"AttributeName": "gsi1sk", "AttributeType": "N"},
            ],
            KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"}],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "gsi1",
                    "KeySchema": [
                        {"AttributeName": "gsi1pk", "KeyType": "HASH"},
                        {"AttributeName": "gsi1sk", "KeyType": "RANGE"},
                    ],
                    "Projection": {"ProjectionType": "ALL"},
                }
            ],
        )
        client.get_waiter("table_exists").wait(TableName=settings.dynamodb_table)
        logger.info("created table %s", settings.dynamodb_table)
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ResourceInUseException":
            raise


def check_ready() -> None:
    """Raises if the datastore is unreachable — used by the readiness probe."""
    get_table().load()


def submit_score(player: str, score_ms: int) -> dict[str, Any]:
    """Record an attempt; keep only each player's personal best on the leaderboard.

    A conditional write makes this safe under concurrency: the item is only
    replaced when the new score is strictly better (lower).
    """
    table = get_table()
    key = f"PLAYER#{player.lower()}"
    improved = True
    try:
        table.update_item(
            Key={"pk": key},
            UpdateExpression=(
                "SET player=:p, best_ms=:s, gsi1pk=:lb, gsi1sk=:s, updated_at=:t ADD games :one"
            ),
            ConditionExpression="attribute_not_exists(pk) OR best_ms > :s",
            ExpressionAttributeValues={
                ":p": player,
                ":s": score_ms,
                ":lb": LEADERBOARD_PK,
                ":t": _now_iso(),
                ":one": 1,
            },
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ConditionalCheckFailedException":
            raise
        improved = False
        table.update_item(
            Key={"pk": key},
            UpdateExpression="ADD games :one",
            ExpressionAttributeValues={":one": 1},
        )
    table.update_item(
        Key={"pk": STATS_PK},
        UpdateExpression="ADD total_submissions :one",
        ExpressionAttributeValues={":one": 1},
    )
    best_ms = int(table.get_item(Key={"pk": key})["Item"]["best_ms"])
    return {"improved": improved, "best_ms": best_ms, "rank": _rank_of(best_ms)}


def _rank_of(score_ms: int) -> int:
    """Rank = 1 + number of players with a strictly better (lower) best."""
    table = get_table()
    better = 0
    kwargs: dict[str, Any] = {
        "IndexName": "gsi1",
        "KeyConditionExpression": "gsi1pk = :lb AND gsi1sk < :s",
        "ExpressionAttributeValues": {":lb": LEADERBOARD_PK, ":s": score_ms},
        "Select": "COUNT",
    }
    while True:
        page = table.query(**kwargs)
        better += page["Count"]
        if "LastEvaluatedKey" not in page:
            return better + 1
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]


def leaderboard(limit: int) -> list[dict[str, Any]]:
    result = get_table().query(
        IndexName="gsi1",
        KeyConditionExpression="gsi1pk = :lb",
        ExpressionAttributeValues={":lb": LEADERBOARD_PK},
        ScanIndexForward=True,  # ascending: lower reaction time is better
        Limit=limit,
    )
    return [
        {
            "rank": idx + 1,
            "player": item["player"],
            "best_ms": int(item["gsi1sk"]),
            "games": int(item.get("games", 1)),
            "updated_at": item.get("updated_at", ""),
        }
        for idx, item in enumerate(result["Items"])
    ]


def stats() -> dict[str, int]:
    table = get_table()
    meta = table.get_item(Key={"pk": STATS_PK}).get("Item", {})
    players = 0
    kwargs: dict[str, Any] = {
        "IndexName": "gsi1",
        "KeyConditionExpression": "gsi1pk = :lb",
        "ExpressionAttributeValues": {":lb": LEADERBOARD_PK},
        "Select": "COUNT",
    }
    while True:
        page = table.query(**kwargs)
        players += page["Count"]
        if "LastEvaluatedKey" not in page:
            break
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]
    return {"total_submissions": int(meta.get("total_submissions", 0)), "players": players}
