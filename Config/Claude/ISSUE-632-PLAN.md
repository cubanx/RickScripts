# Issue #632: Updated Load More Logic - Implementation Plan

## Status: ALL PHASES COMPLETE ✅ 🎉

### Current Branch: `632-updated-load-more-logic-1`
### Last Commit: `523e6f883` - "feat:implement version-aware load more logic"

## Implementation Overview

Changed from global load more logic (fixed `DefaultLoadMoreTargets = 4`) to per-community logic where v2 users get the sum of all their communities' `dailyTargetResetValue`s.

## Phase 1: Server-Side Logic ✅ COMPLETE

### Files Modified:
- `apps/prospector-app/server/user/adjust-open-targets.server.ts`
- `apps/prospector-app/server/user/adjust-open-targets.server.test.ts`
- `apps/prospector-app/server/user/generate-fake-user.server.ts`
- `apps/prospector-app/server/user/create-user.server.ts` (lint fix)

### Key Implementation Details:
- V1 users: Use `DefaultLoadMoreTargets = 4` (backward compatible)
- V2 users: Sum of `community.dailyTargetResetValue` with invariant validation
- Added `tiny-invariant` for v2 user validation
- 25 comprehensive tests covering all scenarios

### Test Coverage:
- V1 backward compatibility (3 tests)
- V2 success cases (5 tests) 
- V2 error cases (3 tests)
- Event creation tests (3 tests)
- Original functionality (11 tests)

## Phase 2: API Endpoint Updates ✅ COMPLETE

### Target: `/api/load-more-targets.ts` endpoint
- API endpoint already correctly delegates to version-aware server logic ✅
- No code changes needed - endpoint was already perfect ✅
- Existing 2 API tests verify correct delegation ✅
- Version-aware logic fully tested in server layer (25 tests) ✅
- No redundant testing added at API layer ✅

## Phase 3: Frontend Updates ✅ COMPLETE

### Target: Frontend components
- Frontend already correctly implemented - no changes needed ✅
- Uses `user.canLoadMoreTargets` boolean for show/hide logic ✅
- Server sets this flag correctly based on version-aware calculations ✅
- All 10 component tests pass including Load More functionality ✅
- Clean separation of concerns - frontend doesn't need version knowledge ✅

## Blocked Issues:
- Issue #633: Depends on #632 completion
- Issue #634: Depends on #632 completion

## Notes:
- All 25 tests passing
- Clean test infrastructure with direct overrides
- Ready to continue with Phase 2 when returning to this branch