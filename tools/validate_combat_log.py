"""Validate conservation and aggregation in a completed gameplay JSON export.

Usage: python tools/validate_combat_log.py path/to/trencho_match_....json
Uses only the Python standard library. Intended for gameplay exports, not fixtures
that directly edit health, scores, or Command balances.
"""
import json
import math
import sys
from pathlib import Path


def validate(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    errors = []

    def check(condition, label):
        if not condition:
            errors.append(label)

    def same(left, right):
        return math.isclose(left, right, abs_tol=0.001, rel_tol=1e-8)

    match = data["match"]
    check(data["schema_version"] in ("0.1", "0.2"), "Supported schema")
    check(bool(data["stat_snapshot"]["units"]), "Unit stat snapshot exists")
    check(match["timestamp_end"] is not None, "Match completed")
    events = data["events"]
    timestamps = [entry["timestamp"] for entry in events]
    check(all(math.isfinite(t) and 0 <= t <= match["duration_seconds"] + 0.001
              for t in timestamps), "Finite event times within simulation duration")
    check(timestamps == sorted(timestamps), "Monotonic event timestamps")
    for collection, id_key in (("soldiers", "unit_id"), ("squads", "squad_id"),
                               ("orders", "order_id"), ("defensive_points", "point_id")):
        ids = [row[id_key] for row in data[collection]]
        check(len(ids) == len(set(ids)), f"Unique {id_key}")
    for team in (1, 2):
        squads = [row for row in data["squads"] if row["team"] == team]
        soldiers = [row for row in data["soldiers"] if row["team"] == team]
        types = [row for row in data["unit_type_aggregates"].values() if row["team"] == team]
        economy = data["economy"][str(team)]
        check(same(economy["initial_command"] + economy["command_generated"]
                   - economy["command_lost_to_cap"] - economy["command_spent"],
                   economy["final_command"]), f"Team {team} Command conservation")
        check(same(sum(row["command_cost"] for row in squads), economy["command_spent"]),
              f"Team {team} package spend")
        for metric in ("damage_dealt", "damage_received", "kills", "deaths", "score_contribution",
                       "time_alive", "time_actively_attacking", "distance_travelled"):
            totals = [sum(row[metric] for row in rows) for rows in (squads, soldiers, types)]
            check(same(min(totals), max(totals)), f"Team {team} {metric} aggregates reconcile")
        score = match["final_score_player" if team == 2 else "final_score_enemy"]
        check(same(sum(row["score_contribution"] for row in squads), score), f"Team {team} score attribution")
        score_events = [entry for entry in events if entry["type"] == "SCORE_EVENT" and entry["team"] == team]
        check(same(sum(entry["score_delta"] for entry in score_events), score), f"Team {team} score events")
    if data["schema_version"] == "0.2":
        for point in data["defensive_points"]:
            check(point["deleted_time"] is None or bool(point.get("delete_reason")),
                  "Deleted point has an explicit reason")
        for entry in events:
            if entry["type"] == "DEFENSIVE_POINT_BROKEN":
                check(all(key in entry for key in ("team", "surviving_defenders_at_break",
                      "living_assigned_squads_before_break", "inbound_defenders_at_break", "break_cause")),
                      "Point break has survivor diagnostics")
    for entry in events:
        if entry["type"] == "DAMAGE_DEALT":
            check(entry["overkill_damage"] >= 0 and entry["damage_applied"] >= 0,
                  "Nonnegative damage and overkill")
            check(same(entry["target_hp_before"] - entry["target_hp_after"], entry["damage_applied"]),
                  "Damage event matches removed HP")
            check(same(entry["damage_attempted"], entry["damage_applied"] + entry["overkill_damage"]),
                  "Attempted damage reconciles")
    if errors:
        raise ValueError("\n".join(dict.fromkeys(errors)))
    print(f"VALID: {match['match_id']} | {match['duration_seconds']:.2f}s | "
          f"{len(data['squads'])} squads | {len(events)} events")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tools/validate_combat_log.py MATCH.json")
    try:
        validate(sys.argv[1])
    except (ValueError, KeyError, OSError, TypeError) as error:
        raise SystemExit(f"INVALID: {error}") from error
