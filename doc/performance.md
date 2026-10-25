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
`nix develop` prepares contributor tools. Both profiles render full Rust-enabled
pages and need the Ruby dependencies from `nix develop .#client-rust`. SDK
generation, Cargo and formatting are outside these measurements. Resolved
component lockfiles remain local library inputs and must not be committed.

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
`compare` reads compact samples format version 2; unsupported versions are
rejected without conversion. Historical evidence remains attributable to its
recorded implementation. `report.json` contains source/profile identity,
overall outcome and per-workload results, without raw samples or response bodies.
Exit codes are 0 for a pass
or an inconclusive timing result, 1 for a regression and 3 for errors, including
missing workloads, wrong responses, inputs or provenance. An inconclusive report
remains explicitly inconclusive; a successful process exit does not establish a
measured performance pass. Deterministic failures and regressions block CI.
Keep the original evidence and diagnose failures or insufficient timing signal;
there is no automatic retry loop or baseline update.

## Timing and work gates

Quick workloads include seven API cases, SQLite page/includes cases, and
documentation OPTIONS plus both HTML shapes at size 8. List and includes quick
cases use 32 rows; pagination uses page size 32 over 128 rows. Weekly adds
member/admin variants, larger payloads, list/includes output up to 1,024 rows,
page size 32 over up to 10,000 SQLite rows, documentation shapes at size 16 and
Rust async/blocking action/authentication examples. An output of 1,024 rows uses
an unpaginated relation; it is not an invalid request above the pagination limit.

Both profiles also render complete Rust-enabled HTML pages for admin and member
users. Quick uses 16 resources; weekly uses 32. Each resource has four actions,
two samples per action and four parameters. These cases validate the full page,
Rust panels, authorization boundaries and operation counts. They use relative
allocation and deterministic checks without inventing fixed-reference allocation
ceilings for the new shapes. Existing calibrated workload budgets remain intact.

These shapes exercise complete pages with several megabytes of HTML, so a
single request provides substantial measurement work. The weekly shape doubles
the resource count. Actual batch durations and output sizes belong in each
run's evidence; these synthetic shapes do not define production latency targets.

| Measurement policy | Quick | Weekly |
| --- | --- | --- |
| Baseline request work per batch | 1 second | 2 seconds |
| Minimum adequate observed batch | 750 ms | 1.5 seconds |
| Baseline/self pairs | 3 | 3 |
| Baseline/candidate pairs | 5 | 7 |
| Required agreement | 4 of 5 | 6 of 7 |
| Relative wall/CPU regression budget | 20% | 10% |
| Minimum detectable batch increase | 50 ms | 50 ms |

A baseline pilot selects a common count of 1–100,000 requests for both revisions.
One bounded calibration adjustment can increase an undersized baseline batch.
Reports retain observed duration, chosen count, adjustment and any cap limitation;
a capped batch below the adequacy threshold is insufficient timing evidence.
Cheap workloads have two warmup batches of about 100 ms each, outside the
measurement. If the baseline pilot already meets the profile's work target with
one expensive request, both revisions use count 1 and no extra request warmups.
That case measures the first complete request after equivalent fixture setup;
the candidate cannot choose a different warmup policy.

Wall and process CPU time are compared separately after normalization per request.
The minimum detectable increase is the larger of the profile's relative budget
and 50 ms divided by the common request count. Paired baseline/self observations
retain the measured noise. A consistent increase beyond the budget and noise
fails. Reports distinguish ordinary variation from insufficient timing signal.
Inconclusive timing remains labeled as such; it does not trigger automatic
workflow retries. The agreement rules are engineering thresholds, not statistical
confidence levels.

Candidate order alternates. Setup, mount, schema, seeds, token issuance, reset,
response parsing/digests and counter checks stay outside the timed loop. GC
remains enabled, including collections triggered by measured requests. A
30-second watchdog surrounds each request batch, including pilot and warmups.
This also bounds every individual request without instrumenting the cheap request
loop. It is supplementary runaway protection, not a regression budget. Setup has
a separate 120-second timeout. Supervision records source, workload and phase and terminates
and reaps stuck workers.

Within each measurement or warmup, the worker validates each distinct raw body
once for that scenario and retains an immutable proof of its parsed values and
output semantics. Every operation still checks the raw digest and exact bytes,
HTTP status and content type, called index, and execution/authorization/query
records. A hash collision cannot reuse a proof. Proofs are discarded at the
sample boundary and never shared between users, scenarios or source revisions.
Samples retain metrics, one uniform validated counter record with its operation
count, and distinct response examples with occurrence counts and raw bodies.
Replay checks those counts, counters, examples and raw/canonical identities,
including comparison mode, verified own version and source/environment/inputs.
It compares response occurrence totals across paired samples; it does not retain
request order or independently reprove each live authorization/counter check.
The compact artifact is a summary, not an execution transcript.

Allocation growth above baseline median plus the larger of 10% or 32 objects
per request fails. Additional fixed-reference ceilings use measured accepted
counts with 25% headroom plus 32 objects/request. Exact SQL query and required
authorization counts prevent a fast but incomplete operation from passing.
Scaling bounds reflect actual output work; growing responses need not allocate
a constant amount. Budget changes require measured justification and review.
Missing or uncalibrated budgets for the existing calibrated workloads fail rather
than disabling the gate.

Both profiles use the already recorded weekly Rust dependency closure as their
expected runtime identity. Quick includes the Rust manifests, gemspec, resolved
lock and actually loaded dependencies too. Baseline and candidate must match
that environment exactly; unavailable or changed identities fail. The shared
comparison entry point activates the recorded native JSON 2.21.2 before its
first require, including in unbundled workers. A newer visible or already loaded
JSON must not silently replace that dependency; a missing or conflicting version
fails during activation. Historical
quick allocation calibration and all existing reference/budget bytes are retained
unchanged, without claiming that the original quick calibration loaded Rust.

The root, Ruby server and Rust generator development Gemfiles declare JSON
2.21.2 so fresh setup installs the recorded native dependency. Comparisons
accept only that exact declaration change in these three files. They retain
the original manifest contents, hashes and declaration evidence, then compare
normalized contents. Replay verifies the transformation from the retained raw
inputs. Other dependency requirements and manifest contents must match.

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
| `haveapi-0.30` push with verified maintenance lineage | Event `after` | Event `before`, covering the whole pushed batch |
| Feature push with verified maintenance lineage | Event `after` | Merge-base with captured `origin/haveapi-0.30` head |
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

### Maintained 0.30 release comparisons

The original fixed reference remains the measured baseline for weekly runs.
Its maintenance counterpart is
`8b7abc097db49893da9cc8fa4395648901fec71d`. The resolver and direct runner accept
this one nonliteral ancestry relationship only when the counterpart is a literal
candidate ancestor and the complete binary tree delta from the original reference
equals the published 0.30.1 metadata commit
`1c3c98f0d77e0b23c8da1a8937f25c5799864a3b` relative to its parent. They verify
the exact four trees and canonical full-index delta hash, retain both raw diffs
and bind the receipt to
the candidate SHA. Cherry-pick trailers do not establish this proof. A different
mapping needs a new review; the reference and budget calibration never change.
Diff rendering uses full blob IDs and explicit formatting options, independent
of repository-dependent abbreviation and user diff display settings. Ordinary
master ancestry is checked before probing the maintenance mapping, so a master
clone does not need maintenance objects for that path.
Unrelated quick baselines still fail. Maintenance feature selection records both
the captured default and release heads; missing release refs fail closed.

These verified maintenance comparisons reuse the candidate's prepared environment
for both sources. In addition to the JSON preparation rule above, they normalize
the shared `0.30.x` patch identity, matching
local Ruby component VERSION assignments and exactly synchronized internal
`haveapi-client` requirements. All remaining bytes in dependency manifests, gemspecs,
Ruby requirements and flake inputs must match, as must the resolved third-party
runtime graph and retained lock bytes. Raw manifest contents and hashes remain
bound to each verified source tree alongside their normalized hashes. Replay
recomputes the transformation and rejects missing, inconsistent or changed inputs.

The HTML comparison may normalize the own-version segment of the documentation
templates' `https://webui.haveapi.org/v<own-version>/#...` anchor hrefs and
the version in the exact framework-generated HaveAPI footer. The footer must
occur once and match the verified source's own VERSION; literal examples, other
footer text and URLs remain exact. Validation runs after the timed loop. Complete raw bodies, byte counts and hashes remain in
the samples, together with the normalized comparison digest and source version.
Replay checks these again from the raw body. The exception applies only to the
HTML documentation workloads on the proven maintenance lineage. JSON/API
values, other URLs and hosts, example code, authorization markers, panels and all
other output remain exact. A version change cannot hide a response difference.

The workflow uses ephemeral GitHub-hosted Ubuntu workers, `contents: read`,
disabled checkout credential persistence, ordinary `pull_request` events and no
secrets, publication context or PR comments. The comparison job has a hard
15-minute quick limit and 45-minute weekly limit. Measured page sizes and sample
counts must leave room for preparation, ordinary workloads and evidence
validation within those limits. Actual hosted campaign duration requires its own
run receipt; the page probe alone does not prove it. A timeout blocks and needs
diagnosis. Superseded runs are cancelled only within
the same event/branch or PR concurrency group.

Success, regression, inconclusive and preparation-failure artifacts are retained
for 30 days. They include event selection, exact SHAs and source trees/archive
hashes, matched dependency manifests, resolved locks, runtime/input graphs, raw
samples, reports, process diagnostics and runner exit. The aggregate rejects
failed, cancelled or unexpectedly skipped required work and requires the retained
report. A completed comparison can retain inconclusive timing diagnostics while
its deterministic checks pass; the report keeps that distinction visible.
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
