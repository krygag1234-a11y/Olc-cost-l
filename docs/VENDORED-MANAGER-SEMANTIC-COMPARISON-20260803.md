# Semantic comparison: legacy patch-stack vs vendored manager

Date: 2026-08-03.

Compared sources:

- legacy reproducible result: `Olc-cost-l` commit `54aab55`, pinned upstream manager `ad8ec6f`, full manager patch-stack, `OLC_PATCH_ONLY=1`;
- vendored source: `components/olcrtc-manager` from branch `codex/vendored-manager`, commit `20acda0` before the live-matrix fixes.

The comparison was built on the RU audit host in isolated directories. Production services were not restarted or changed.

## Results

- Legacy patch-only generation completed successfully.
- `go test ./...` passed for both legacy and vendored trees.
- Vite production build passed for the vendored tree: 1580 modules transformed.
- Backend API route inventories are identical: 59 unique `/api/*` routes in each tree, with no route present only on one side.
- Frontend API reference inventories are identical: 47 unique `/api/*` references in each tree, with no reference present only on one side.
- JSON field/tag inventories are identical: 175 unique tags in each tree, with no config/API tag present only on one side.

## Expected source differences

The trees are not byte-identical. Vendored source contains fixes implemented after the `54aab55` control point, primarily:

- exact backup state for present and absent files;
- backup schema 3 and missing-module decisions;
- stricter feature/component detection and tests;
- access-control synchronization fixes;
- Jitsi HTTPS discovery/forced-IP refinements;
- later UI layout and modal fixes.

These additions do not remove a legacy API route, UI API call, or JSON field. The vendored source is therefore the semantic successor of the legacy patch-stack, not a byte-for-byte snapshot of its earlier state.

## Conclusion

The legacy manager patch-stack can be removed from the production build path after the remaining live install/update, backup/import, TUI, and rollback tests pass. It should not be kept as an active second implementation.
