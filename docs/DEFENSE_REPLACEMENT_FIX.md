# Defensive point replacement and command feedback

Replacing a defensive order projected homes before pruning its vacated point.
The territory owner map still referenced that old point, and the point still
existed in the order dictionary, so the new projection treated its cells as
unavailable. A 144-soldier lateral relocation left 25 player soldiers and 23 enemy
soldiers unarrived after 3,600 physics ticks in the regression workload.

Prune empty points before repacking the replacement order. Points with remaining
squads stay protected by the existing ownership checks. The existing placement,
local steering, collision clearance and territory solver are retained.

Command results now carry the issuing team, including rejection paths. The player
command UI ignores enemy results before updating feedback, failure text or the
hand message. Enemy defense arrows previously reused the player's last gesture
origin; movement orders themselves remained assigned to the enemy squads.

Regression coverage: enemy success/rejection during a player stroke, friendly
success/rejection feedback, and 144 soldiers on each team establishing, replacing
at the same center, and relocating laterally through ordinary physics. Every
replacement must allocate homes, remove its vacated point and retain traversable
home spacing. Run tools/verify.ps1 -Suite defense_regression with Godot 4.7.2.

These cases test the reported failures; bounded local steering still does not
provide general navigation through arbitrary terrain mazes or crowd enclosures.

Validation (18 October 2026): the exact staged snapshot passed a fresh import and
all default verification suites on Godot 4.7.2.stable.steam.ed1daf0bf, including
27 new regression assertions. All 144 soldiers arrived in every tested scenario
on both teams. Simulation snapshots matched at 30/144 render FPS. The sustained
battle completed with 55 accepted deployments, 349 deaths, 100 scoring events and
167 peak living units; startup smoke also passed. Related suites additionally
passed in the working copy with the pre-existing UI changes present. Verification
was headless; no interactive playtest or platform export is claimed.
