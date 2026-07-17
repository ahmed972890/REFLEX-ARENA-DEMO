from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints

# 80 ms is below any human reaction time; >10 s is noise. Server-side bounds
# keep garbage out of the leaderboard even if the UI is bypassed.
PlayerName = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True, min_length=2, max_length=20, pattern=r"^[A-Za-z0-9 _\-]+$"
    ),
]


class ScoreSubmission(BaseModel):
    player: PlayerName
    score_ms: int = Field(ge=80, le=10_000)


class SubmissionResult(BaseModel):
    improved: bool
    best_ms: int
    rank: int


class LeaderboardEntry(BaseModel):
    rank: int
    player: str
    best_ms: int
    games: int
    updated_at: str


class LeaderboardResponse(BaseModel):
    entries: list[LeaderboardEntry]


class Stats(BaseModel):
    total_submissions: int
    players: int
