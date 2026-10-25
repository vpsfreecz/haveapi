# Endpoint performance checks

The Ruby performance suite sends real Rack requests through routing,
authentication, authorization, typed validation and serialization. It covers
public, Basic and token requests, valid and invalid typed input, nested resources,
lists, SQLite pagination and eager loading, and documentation OPTIONS/HTML.
Deterministic specs check response contracts, isolation, allocation growth and
query/authorization counts. Paired timing runs compare exact baseline and
candidate sources with one neutral harness and third-party dependency graph.

These are synthetic in-process workloads. SQLite results describe the fixture's
query behavior; they do not measure production database, network server or
vpsAdmin latency. The checks detect specific regressions and do not guarantee
every future performance characteristic.

## Local commands

Use the repository's Nix environments and prepare dependencies before running
measurements. `nix develop .#server-ruby` prepares the server bundle; the top-level
`nix develop` prepares contributor tools. Weekly Rust examples also need the
Ruby dependencies from `nix develop .#client-rust`. SDK generation, Cargo and
formatting are outside these measurements. Resolved component lockfiles remain
local library inputs and must not be committed.

Run deterministic specs in the prepared top-level shell:

```sh
make test-performance
```

The runner consumes the same neutral fixtures for both implementation roots,
using a fresh process for each sample. Keep the harness in a candidate repository
checkout containing the exact baseline and candidate Git objects. Export both
source revisions separately, retain their archive hashes and source manifests,
and run `make doc` in each exported root. Do not point one process at both roots.
Then run outside Bundler with the prepared gem stores:

```sh
env -u RUBYOPT -u RUBYLIB -u BUNDLE_BIN_PATH -u BUNDLE_GEMFILE \
  -u BUNDLE_LOCKFILE -u BUNDLE_PATH -u BUNDLE_FROZEN -u BUNDLER_SETUP \
  GEM_PATH="$PWD/.gems:$PWD/clients/rust/.gems:$(ruby -e 'puts Gem.default_dir')" \
  make performance PERFORMANCE_ARGS='--baseline-root /absolute/baseline --baseline-sha BASELINE_FULL_SHA --candidate-root /absolute/candidate --candidate-sha CANDIDATE_FULL_SHA --profile quick --budgets servers/ruby/benchmarks/performance_budgets.json --output /absolute/new-evidence-directory'
```

Run inside the prepared top-level Nix shell, from the candidate checkout.
Replace the paths and full 40-character lowercase SHAs. Use `--profile weekly`
for the expanded workload. The runner verifies source paths, source identities,
response contracts and dependency/runtime identities before accepting a result.
An incompatible graph or fixture contract fails; prepare a separately reviewed
environment/reference migration instead of mixing versions or relaxing checks.

To reclassify retained samples without making requests:

```sh
make performance-compare \
  PERFORMANCE_ARGS='--input /absolute/evidence/samples.json --budgets servers/ruby/benchmarks/performance_budgets.json --output /absolute/new-comparison-directory'
```

The commands invoke `servers/ruby/benchmarks/endpoints.rb run` and `compare`
directly. `run` retains `samples.json`, `report.json` and process diagnostics.
`compare` reads the same versioned samples format. Exit codes are 0 for pass,
1 for regression, 2 for inconclusive and 3 for errors, including missing workload,
wrong responses, inputs or provenance. Every nonzero exit blocks CI. Keep failed
evidence and diagnose it before deciding whether another run is justified; there
is no automatic retry or baseline update.

## Timing and work gates

Quick workloads include seven API cases, SQLite page/includes cases, and
documentation OPTIONS plus both HTML shapes at size 8. List and includes quick
cases use 32 rows; pagination uses page size 32 over 128 rows. Weekly adds
member/admin variants, larger payloads, list/includes output up to 1,024 rows,
page size 32 over up to 10,000 SQLite rows, documentation shapes at size 16 and
Rust async/blocking action/authentication examples. An output of 1,024 rows uses
an unpaginated relation; it is not an invalid request above the pagination limit.

A baseline pilot selects 1–2,000 requests targeting 150 ms per batch and records
when the cap cannot reach that target. Both revisions use the same count.
Two warmup batches precede measured work. Quick uses three baseline/self pairs
and nine baseline/candidate pairs; weekly uses five and fifteen. Candidate order
alternates to reduce order effects. Setup, mount, schema, seeds, token issuance,
reset, response parsing/digests and counter checks stay outside the timed loop.
GC remains enabled, including collections triggered by measured work.

Each wall and process-CPU metric is checked separately per request. A meaningful
slowdown exceeds both 20% and 0.20 ms. The noise allowance is the maximum of
observed baseline/self differences, 5% of baseline median and 0.05 ms. Quick
requires eight of nine pairs on the passing side of the allowance; weekly
requires fourteen of fifteen. Consistent slowdowns fail; disagreement is
inconclusive and also blocks. This agreement rule is not a statistical confidence
interval. High noise does not widen the accepted performance budget.

Allocation growth above baseline median plus the larger of 10% or 32 objects
per request fails. Additional fixed-reference ceilings use measured accepted
counts with 25% headroom plus 32 objects/request. Exact SQL query and required
authorization counts prevent a fast but incomplete operation from passing.
Scaling bounds reflect actual output work; growing responses need not allocate
a constant amount. Budget changes require measured justification and review.
Missing or uncalibrated budgets fail rather than disabling the gate.

## GitHub workflow and baseline selection

The `servers/ruby performance` workflow runs on pushes, ordinary pull requests,
manual dispatch and Sunday at 03:00 UTC. It always creates the `Performance gate`
aggregate check. Relevant-path detection happens after event resolution, inside
the workflow; an irrelevant valid change can succeed without running benchmarks.
Source/dependency/fixture/budget/workflow/flake changes trigger measurement.
Missing event/source evidence fails even when no relevant path can be established.

| Event | Candidate | Baseline |
| --- | --- | --- |
| Pull request | Exact event head SHA | Merge-base of head and exact event base SHA |
| Feature push, including a new branch | Event `after` | Merge-base with captured default-branch SHA; compares the whole feature |
| Default-branch push | Event `after` | Event `before`, covering the whole pushed batch |
| Weekly | Exact scheduled default-branch event SHA | Fixed accepted reference below |
| Manual with a complete explicit pair | Supplied full candidate SHA | Supplied full baseline SHA |
| Manual without either SHA | Captured default SHA | Fixed accepted reference below |

The immutable accepted reference is
`b85ec364057f536940d689b09e612512ffffaf82`. Required ancestry is checked. The
reference and budgets never move automatically. Deleted branches, initial
default pushes without a predecessor, missing commits, partial manual pairs,
unrelated history or equal baseline/candidate fail. PRs use the head commit,
never the synthetic merge commit; default pushes use `before`, never `HEAD^`.
The weekly profile always requires that fixed baseline, including an explicit
manual pair. An explicit quick pair may select another ancestor.

The workflow uses ephemeral GitHub-hosted Ubuntu workers, `contents: read`,
disabled checkout credential persistence, ordinary `pull_request` events and no
secrets, publication context or PR comments. The comparison job has a hard
10-minute quick limit and 30-minute weekly limit. Quick targets 5–10 minutes;
a timeout blocks and needs diagnosis. Superseded runs are cancelled only within
the same event/branch or PR concurrency group.

Success, regression, inconclusive and preparation-failure artifacts are retained
for 30 days. They include event selection, exact SHAs and source trees/archive
hashes, matched dependency manifests, resolved locks, runtime/input graphs, raw
samples, reports, process diagnostics and runner exit. The aggregate rejects
failed, cancelled or unexpectedly skipped required work; it cannot turn missing
reports or an inconclusive result into a pass.
Repository rules determine whether this aggregate check is required for merging;
the workflow does not change branch protection or repository permissions.

A newly added workflow's manual dispatch may be unavailable until its definition
exists on the default branch. Preserve a dispatch refusal and run the same weekly
CLI locally if needed; disclose that hosted weekly execution remains unverified.
Workflow enablement alone is not a reason to integrate source into the default
branch. Push verification still checks the exact published candidate.

The separate [documentation benchmark](client-examples.md#documentation-benchmark)
remains available for diagnosis and custom page shapes. Its JSON trials/medians
are useful measurements; the paired endpoint runner owns required timing gates.
