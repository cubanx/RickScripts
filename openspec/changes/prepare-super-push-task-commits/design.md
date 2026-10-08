## Working slice

Start from a source task branch with unrelated commits and staged/dirty/untracked
work, advance a local bare remote's main, and prepare one explicitly selected docs
commit. Prove only that commit is replayed over the new main in a clean detached
worktree and the source is unchanged. Publication boundaries remain faked.

## Scope and validation

Accept only full SHAs, in ancestor order, reachable from source HEAD but not
already on main. Reject root/merge commits and duplicate or missing scope. Do not
select branch history by default. Replay one commit at a time with hooks/signing
disabled; conflicts/empty cherry-picks stop. Missing dependencies are not guessed.

Classify net diff and every introduced commit using existing Git raw/numstat
metadata rules. Docs need only Git validation, and at most three attempts may
recover main movement during local preparation before evidence/approval. Other
failures are not retryable. Non-docs require a caller-selected external executable
and argument array, exit zero, clean worktree and unchanged candidate. Validators
are explicit local execution, not automatic repository discovery or provider
operation authorization. Output is omitted; execution is bounded to ten minutes.

## Human and Pi boundaries

`Invoke-SuperPush -TaskCommit ... [-ValidationCommand ...]` owns the human flow.
No-argument attached use prompts for full SHAs with no default. No-argument
detached broker use does not prepare or rewrite. `New-SuperPushCandidate` returns
Root, OldSha/NewSha, source identity and scope for pre-approval Pi preparation.
A Git-admin receipt binds local validation to candidate identity; its fingerprint
is included in repeated publication state comparisons. This is not a signature
or approval grant. The separately reviewed dotfiles tool must bind receipt
identity along with exact SHA before/after native approval.

Once preparation returns, races stop; after approval no reconstruction is allowed.
Original token acquisition, one push, revocation and sanitized audit/diagnostic
behavior are retained. Local docs preparation retries cannot retry a push.

## Recovery and lifecycle

Remove failed preparation worktrees only. Retain successful candidates for review
and recovery, report their path, restore caller location and document caller-owned
cleanup. Source HEAD/index/files and unrelated history are never rewritten.
Do not install, commit or publish during this task. Dotfiles integration is a
separate implementation scope, not hidden permission or an automatic follow-up.
