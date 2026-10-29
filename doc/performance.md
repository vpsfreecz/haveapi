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

## All-client documentation contract

The required performance workflow first runs `make test-performance-clients`
against the selected candidate in the prepared, unbundled benchmark shell:

```sh
export HAVEAPI_BENCHMARK_GEM_HOME="$PWD/servers/ruby/benchmarks/.gems"
nix-shell servers/ruby/benchmarks/shell.nix --run 'make test-performance-clients'
```

Prepare the frozen benchmark bundle as described below before running this
command. It loads the actual Go, Rust and TypeScript generator sources and fails
if a dependency or profile is missing. It needs no Go, Rust or TypeScript
compiler. The ordinary `make test-performance` remains a separate server-bundle
check; both checks are required.

The explicit coverage matrix must equal the live renderer registry. Its 15
entries include every callback, async, blocking and generated variant. Each
entry renders initialization, Basic, token and OAuth2 authentication, public and
protected actions, and a failed action sample. Basic authentication and action
samples must produce code for every renderer. Generated TypeScript's OAuth2
limitation and the Ruby library/CLI's existing unsupported-OAuth2 comments have
explicit expectations. New renderer IDs or providers require reviewed coverage;
they cannot silently disappear from measurement.

Direct checks hold the selected action, sample and provider constant while adding
128 unrelated resource subtrees. Setup and context ownership copying happen
outside measurement. Three batches of eight renders check allocations, and a
separate Ruby-call count checks traversal growth; each allows 32 additional
objects or calls per render. Output must remain identical and inputs unchanged.

Rack HTML checks enable all three generated profiles and request the overview,
authentication page, resource directory and every resource page. Each panel is
compared with the real renderer output at both detail levels, including successful and failed
samples. Admin/member/admin requests verify isolation through the same adapters;
a selected resource page must not render another resource's action examples.
The fixture uses scalar fields so Go action panels exercise supported code paths.

Allocation measurements cover two dimensions at the unchanged 2.5 increment
ratio. With 2, 4 and 8 resources, a fixed request set (overview, authentication,
directory and resource0) measures growth from the authorized description and
navigation.
Separately, one selected resource with 2, 4 and 8 ordinary actions measures
panel growth and detects repeated whole-resource or whole-description copies.
Both dimensions retain the existing samples and admin-only action. Measured
page bytes are recorded separately from complete-site correctness bytes; summing
all resource pages would also count their repeated page structure.

The log retains the named registry, kinds, allocations, Ruby-call counts and
page byte counts. These deterministic checks measure the selected candidate.
They use no wall-clock threshold and provide no historical timing result. The
paired timing suite below retains its original workloads, fixed reference and budgets; its
reference predates generated TypeScript support. Relevant pushes and pull
requests, manual runs and scheduled runs must pass the all-client contract before
the paired comparison. Changes under any client directory trigger the gate.

## Local commands

The benchmark has its own third-party tool bundle and pinned Nix shell in
`servers/ruby/benchmarks/`. This keeps contributor Nix updates separate from the
calibrated measurement runtime. Prepare the ordinary frozen bundle once:

```sh
export HAVEAPI_BENCHMARK_GEM_HOME="$PWD/servers/ruby/benchmarks/.gems"
nix-shell servers/ruby/benchmarks/shell.nix --run '
  set -e
  gem install bundler --version 4.0.23 --no-document
  BUNDLE_IGNORE_CONFIG=1 BUNDLE_FROZEN=1 BUNDLE_PATH__SYSTEM=1 \
    BUNDLE_GEMFILE="$PWD/servers/ruby/benchmarks/Gemfile" bundle _4.0.23_ install
'
```

The tool Gemfile installs no HaveAPI package. Its tracked lock is an application
lock; component library locks remain local contributor inputs. Launch the runner
outside Bundler so both exported sources use the same Ruby and gem paths. The
shell clears inherited Bundler settings, `RUBYOPT`, `RUBYLIB` and
`RUBYGEMS_GEMDEPS`.

Run deterministic specs in the prepared contributor shell with
`make test-performance`. For a comparison, keep the neutral harness in a candidate
checkout containing both exact Git objects. Export the baseline and candidate
separately, retain their archive hashes and manifests, and run `make doc` in each
exported root. Then run from the candidate checkout:

```sh
nix-shell servers/ruby/benchmarks/shell.nix --run '
  make performance PERFORMANCE_ARGS="--baseline-root /absolute/baseline --baseline-sha BASELINE_FULL_SHA --candidate-root /absolute/candidate --candidate-sha CANDIDATE_FULL_SHA --profile quick --budgets servers/ruby/benchmarks/performance_budgets.json --output /absolute/new-evidence-directory"
'
```

Replace paths and full 40-character lowercase SHAs. Use `--profile weekly` for
the expanded workload. The runner checks the exact calibrated Ruby and available
dependency versions before timing, then requires each worker's complete activated
graph to match the weekly calibration. Source and loaded-file checks and
response validation must also pass. An unsupported declaration or runtime change
requires a separately reviewed environment migration; it does not update the
reference or budgets.

To reclassify retained samples without making requests:

```sh
make performance-compare \
  PERFORMANCE_ARGS='--input /absolute/evidence/samples.json --budgets servers/ruby/benchmarks/performance_budgets.json --output /absolute/new-comparison-directory'
```

The commands invoke `servers/ruby/benchmarks/endpoints.rb run` and `compare`
directly. `run` retains `samples.json`, `report.json` and process diagnostics.
`compare` reads compact samples format version 2; unsupported versions are
rejected without conversion. `report.json` retains the original measurement's
`harness_sha256`. Its `comparison` metadata identifies policy
`per-revision-response-stability-v1`, the loaded comparator file's SHA-256 and
the SHA-256 of the exact consumed `samples.json` bytes. Error reports retain
these identities when available; they omit unavailable measurement/input fields
instead of identifying old measurements with the current harness. The existing
`budget_sha256` identifies the budget. Replaying samples classifies the recorded
measurements under the identified comparison policy. It makes no requests and
leaves the original result unchanged.
`report.json` contains source/profile identity, overall outcome and per-workload
results, without raw samples or response bodies.
Exit codes are 0 for a pass
or an inconclusive timing result, 1 for a regression and 3 for errors, including
missing workloads, invalid or unstable responses, inputs or provenance. An
inconclusive report remains explicitly inconclusive; a successful process exit
does not establish a measured performance pass. Deterministic failures and regressions block CI.
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

The HTML workloads retain one GET to the version overview for each operation,
with unchanged fixture dimensions, counters and budgets. The validator accepts
the legacy complete-page layout or the current overview as explicit, separate
shapes. It checks the overview's resource-directory link, complete authorized
resource/action anchor map and real initialization panels, and rejects action
bodies or private sample values there. The current overview intentionally omits resource examples;
its smaller response does not establish that resource-page rendering is faster.
The separate all-client checks cover the directory inventory, resource pages and
both detail levels.

Documentation HTML on sources supporting the optional documentation OAuth client
uses a real encrypted session cookie. Historical sources retain their Basic
authentication setup; API, OPTIONS and direct renderer lanes keep their original
credentials. Cookie issuance happens during fixture setup, with stable per-role
CSRF. Every HTML request still decrypts the cookie and validates its token through
the OAuth provider. Samples record the selected identity mode and role.

Historical complete-page shapes can contain several megabytes of HTML, so a
single request can provide substantial measurement work. The weekly shape doubles
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
It compares canonical response identities and occurrence totals across samples
from the same verified source SHA. Both columns of a baseline/self pair belong
to the baseline SHA. JSON map order may vary; raw byte stability is not required.
It does not retain request order or independently reprove each live
authorization/counter check.
The compact artifact is a summary, not an execution transcript.

Responses may differ between baseline and candidate without failing or skipping
the performance comparison. Each workload reports `raw_changed` and
`canonical_changed`, together with baseline/candidate bytes per request and
their byte and percentage changes. These diagnostics use the
occurrence-weighted output distributions from baseline/candidate pairs only;
baseline/self pairs do not affect the size comparison. Reports retain no raw
bodies. Response growth alone does not fail the comparison or change its timing
and allocation limits. Equal response lengths do not prove correctness. The CI
step summary shows these diagnostics beside wall, CPU, allocation and overall
outcomes, including regressions and inconclusive timing.

Allocation growth above baseline median plus the larger of 10% or 32 objects
per request fails. Additional fixed-reference ceilings use measured accepted
counts with 25% headroom plus 32 objects/request. Exact SQL query and required
authorization counts prevent a fast but incomplete operation from passing.
Scaling bounds reflect actual output work; growing responses need not allocate
a constant amount. Budget changes require measured justification and review.
Missing or uncalibrated budgets for the existing calibrated workloads fail rather
than disabling the gate.

Both profiles use the recorded weekly Rust dependency closure as their expected
runtime identity. Quick includes the Rust manifests, gemspec and loaded
dependencies. Both profiles retain the benchmark Gemfile, lock and shell bytes
and hashes. Baseline and candidate must match that environment exactly;
unavailable or changed identities fail. The shared
comparison entry point activates the recorded native JSON 2.21.2 before its
first require, including in unbundled workers. A newer visible or already loaded
JSON must not silently replace that dependency; a missing or conflicting version
fails during activation. Historical
quick allocation calibration and all existing reference/budget bytes are retained
unchanged, without claiming that the original quick calibration loaded Rust.

The benchmark worker activates io-console 0.9.4 before loading source or fixture
code, so its dependency graph does not depend on which examples a page renders.
Missing or conflicting versions fail before requests begin.

The root, Ruby server and Rust generator development Gemfiles declare JSON
2.21.2 so fresh setup installs the recorded native dependency. Comparisons
accept only that exact declaration change in these three files. They retain
the original manifest contents, hashes and declaration evidence, then compare
normalized contents. Replay verifies the transformation from the retained raw
inputs. Other dependency requirements and manifest contents must match.

Comparisons outside the historical 0.30 maintenance mapping retain a
`source_versions` receipt for each source. It validates the numeric source
`VERSION`, matching Ruby server/client
and Rust generator version constants, package identities and exact synchronized
internal `haveapi-client` requirements before normalizing those version fields.
Preparation, live workers and replay bind the raw hashes to the verified source
and compare the normalized manifests. Missing, duplicate, inconsistent or tampered
metadata fails. All other manifest bytes, external dependencies, runtime and
benchmark locks remain part of the strict comparison. Older raw-manifest samples
still replay; removing a receipt from normalized samples fails source validation.
This rule permits coordinated package-version changes without changing baseline
selection or the separate historical 0.30 maintenance-lineage proof. Response
changes remain diagnostics under the existing per-revision stability policy.

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
| Existing branch push, quick | Exact event `after` | Exact nonzero event `before`, on every branch |
| New branch push, quick (zero `before`) | Exact event `after` | Merge-base with captured exact default-branch SHA |
| Weekly | Exact scheduled default-branch event SHA | Fixed accepted reference below |
| Manual with a complete explicit pair | Supplied full candidate SHA | Supplied full baseline SHA |
| Manual without either SHA | Captured default SHA | Fixed accepted reference below |

The immutable accepted reference is
`b85ec364057f536940d689b09e612512ffffaf82`. Required ancestry is checked. The
reference and budgets never move automatically. Deleted branches, malformed or
missing commits, unavailable new-branch fallback, partial manual pairs and equal
endpoints fail. PRs use the head commit, never the synthetic merge commit. An
existing branch push uses `before`, never `HEAD^` or a guessed fallback. A quick
push can compare a nonancestor before/after pair after a force push; its exact
event pair is carried through all ancestry guards. Direct CLI use of that
exception requires `--push-event selection.json` from the event resolver. Other
PR, manual and weekly ancestry restrictions remain. Relevance uses the direct
before/after tree diff, including the benchmark setup files.
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
Unrelated direct quick baselines still fail. Existing maintenance branch pushes
use their exact pushed pair; new branches retain the captured-default fallback
and reason. A `haveapi-0.30` push still requires verified maintenance lineage.

Both sources in a maintenance comparison use the prepared benchmark environment.
In addition to the JSON preparation rule above, these comparisons normalize the
shared `0.30.x` patch identity, matching local Ruby component VERSION assignments
and exactly synchronized internal `haveapi-client` requirements. All remaining
bytes in dependency manifests, gemspecs and Ruby requirements must match, as must
the resolved third-party runtime graph and benchmark lock bytes. Source `flake.nix` and `flake.lock` remain raw provenance
with source hashes; they do not supply the benchmark runtime and may differ.
Every other supported declaration remains strict. The consumed benchmark shell
and lock are retained separately and must match across workers. Raw manifest
contents and hashes remain bound to each verified source tree alongside their
normalized hashes. Replay
recomputes the transformation and rejects missing, inconsistent or changed inputs.

The HTML comparison may normalize the own-version segment of the documentation
templates' `https://webui.haveapi.org/v<own-version>/#...` anchor hrefs and
the version in the exact framework-generated HaveAPI footer. The footer must
occur once and match the verified source's own VERSION; literal examples, other
footer text and URLs remain exact. Validation runs after the timed loop. Complete
raw bodies, byte counts and hashes remain in the samples, together with the
normalized comparison digest and source version. Replay checks these again from
the raw body. This normalization applies only to the HTML documentation workloads
on the proven maintenance lineage. JSON/API
values, other URLs and hosts, example code, authorization markers, panels and all
other output are not normalized. Cross-revision differences remain diagnostic;
within-revision stability and raw/canonical integrity still apply.

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
