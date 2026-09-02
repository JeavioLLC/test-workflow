# CI/CD Pipeline

Implements the CI/CD & Software Delivery Framework (`CI_CD Framework.docx`) for this Python project, using **Amazon ECR** for image storage and **Amazon ECS Fargate** for deployment.

## Pipeline

| Workflow                     | Trigger                                        | Purpose                                                                                   |
| ----------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `ci-pr-validation.yml`        | Pull request → `develop`, `main`, `release/**`  | Lint, unit tests + 80% coverage, secret/SAST/dependency/license gates (via jeavio-governance) |
| `cd-develop.yml`              | Push to `develop`                               | Build one image, deploy to Development. Stops here.                                       |
| `promote-to-qa.yml`           | Manual (Actions tab → Run workflow, requires `image_tag`) | Deploy the exact image tag you name to QA, unchanged.                   |
| `cd-release.yml`              | Push to `release/v*`                            | Version taken from branch name, build one image, deploy to Staging. Stops here.           |
| `promote-to-production.yml`   | Manual (Actions tab → Run workflow, requires `image_tag`) | Deploy the exact version you name to Production, unchanged. Automated rollback on failure. |
| `deploy-template.yml`         | Called by every workflow above                 | Shared ECS Fargate deploy step, reused unchanged per environment                          |

### Flow

```
feature/*  --PR-->  develop
                       │  (push)
                       ▼
       cd-develop.yml: build image dev-<sha>  ->  Deploy Dev   [stops]

                       │  someone runs promote-to-qa.yml by hand,
                       │  naming the exact dev-<sha> tag they tested
                       ▼        (this manual trigger IS the approval)
                  Deploy QA


develop  --(cut by hand)-->  release/v1.0.0
                       │  (push)
                       ▼
   cd-release.yml: version = "1.0.0" from branch name
                       │
                       ▼
       build image:1.0.0  ->  Deploy Staging   [stops]

                       │  someone runs promote-to-production.yml by hand,
                       │  naming the exact version they validated
                       ▼        (this manual trigger IS the approval)
              Deploy Production  ->  Rollback (on failure)
```

No image is ever rebuilt between stages (Build Once, Deploy Anywhere): `cd-develop.yml` builds once for Development, and `promote-to-qa.yml` redeploys that exact image to QA; `cd-release.yml` builds once (tagged with the version from the release branch name) for Staging, and `promote-to-production.yml` redeploys that exact image to Production.

### Development/Staging are shared environments — name your tag explicitly

Development and Staging are each a single ECS service reused by everyone. If two developers merge to `develop` close together, the second merge's `cd-develop.yml` run redeploys Development on top of whoever is still testing the first. Because of this, `promote-to-qa.yml` / `promote-to-production.yml` **require** an explicit `image_tag` input — they never assume "whatever is currently deployed upstream" is the thing you tested, since that could by then be someone else's untested build. Find your tag from your own `cd-develop.yml` (or `cd-release.yml`) run's "Build & Push Image" step summary before promoting.

`cd-develop.yml` also sets `concurrency: group: deploy-development` so two deploys can't race the same ECS service at once — this only prevents a corrupted/flapping deployment, it does not stop a later merge from legitimately overwriting Development while your testing is still in progress. If concurrent feature testing on a shared Dev environment becomes a recurring problem, the real fix is isolated per-developer/per-branch environments — ask if you want that built out.

### Manual approval gates (no native Environment reviewers on this plan)

Environment "Required reviewers" needs a public repo or a GitHub Team/Enterprise Cloud plan for private repos — this repo is private on Free/Pro, where Environments only expose Deployment branches/tags + secrets/variables, not protection rules.

So promotion is a **separate, manually-triggered workflow** instead of a pause mid-pipeline:

- `promote-to-qa.yml` and `promote-to-production.yml` only run when someone goes to the **Actions tab → select the workflow → Run workflow**. That click is the approval — there's nothing to configure for it.
- Who can click it is controlled by normal repo permissions: only collaborators with **Write** access (or higher) can trigger a `workflow_dispatch`. Manage this under Settings → Collaborators and teams.
- `image_tag` is a required input — see "Development/Staging are shared environments" below for why it's never defaulted.

## Required one-time repo/AWS setup

1. **ECR repository**: create one repository (e.g. `my-app`) that holds every tag — `dev-<sha>` from develop builds and `<major>.<minor>.<patch>` from release builds.
2. **ECS Fargate**: a cluster, service and task definition must already exist per environment (development/qa/staging/production) before the first deploy — the pipeline updates the image on an existing task definition/service, it does not provision infrastructure.
3. **GitHub Environments** (Settings → Environments): create `development`, `qa`, `staging`, `production`. On each, set:
   - Variables: `AWS_REGION`, `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_DEFINITION_FAMILY`, `CONTAINER_NAME`, `APP_URL` (the base URL of that environment, e.g. an ALB DNS name)
   - Secret: `AWS_ROLE_ARN` — an IAM role (OIDC, via `aws-actions/configure-aws-credentials`) scoped to that environment's ECS/SSM resources
4. **Repository-level** (not environment-scoped) config, used by the build steps and by the promote workflows' image-resolution step:
   - Variables: `AWS_REGION`, `ECR_REPOSITORY`, `APP_NAME`
   - Secret: `AWS_ROLE_ARN` (a role with ECR push + `ssm:GetParameter` permissions)
5. **Branch protection**, matching the framework's branching strategy: require the `CI - PR Validation` status checks on `main`, `develop`, and `release/**` before merge.
6. **Optional**: set the repo/org variable `COVERAGE_THRESHOLD` (e.g. `85`) to change the minimum unit test coverage enforced by `ci-pr-validation.yml`'s `test` job — defaults to `80` if unset.
7. **Jeavio Governance tool** (secret-detection/sast-scan/dependency-scan/license-scan jobs), repo-level, separate from the deploy pipeline's AWS account/role above:
   - Secret: `GOVERNANCE_AWS_ROLE_ARN` — an OIDC role in the Jeavio governance AWS account with read access to the `jeavio-governance` CodeArtifact package, the `governance/*` ECR repositories, and the `governance-dependency-check-volume` S3 bucket.
   - Variable (optional): `GOVERNANCE_AWS_REGION` — defaults to `ap-south-1` if unset.
   - Variable (optional): `PIP_VERSION` — pip version reported in the license scan; defaults to `24.0` if unset.

## Rollback

1. **ECS Deployment Circuit Breaker** — `deploy-template.yml` enables this on the service before every deploy (`deploymentCircuitBreaker: {enable: true, rollback: true}`). If the new tasks never reach a healthy steady state (crash-looping, failing ELB/container health checks), ECS itself detects this and automatically reverts the service to the previous task definition — no scripting involved, happens within the deploy. Because `aws ecs wait services-stable` reports success even in this case (the service genuinely is stable, just on the old revision), a follow-up "Verify deployment did not auto-rollback" step compares the post-deploy task definition against the one captured before the deploy and fails the job loudly if ECS silently reverted it.
2. **Automated rollback job** (`promote-to-production.yml`'s `rollback`) — if the `deploy-production` job fails for any reason, this job force-redeploys the `previous_task_definition` captured by `deploy-template.yml`.

## Traceability: "current version per environment"

Every deploy (`deploy-template.yml`) writes the deployed image URI to SSM Parameter Store at `/${APP_NAME}/${environment}/current-image` — an audit trail of what's running where, queryable independent of which pipeline run deployed it. The promote workflows also read it to print a non-blocking `::notice::` if the tag you named differs from what's currently live upstream (expected when Development/Staging has since moved on to someone else's build — just a prompt to double-check you meant to promote your own).

## Security/quality gates: the Jeavio Governance tool

`secret-detection`, `sast-scan`, `dependency-scan`, and `license-scan` all run the same tool (`sast-automation/jeavio-governance.sh` in this repo) against different `TEST_TYPE`s (`detect-secrets`, `source-code-sast`, `dependency-vuln`, `dependency-license` respectively), using the `--ci` flag added for pipeline use (see `sast-automation/jeavio-governance.sh` — it's fully backward compatible with local/manual runs that omit `--ci`).

- A `prepare-governance-tool` job fetches the script from AWS CodeArtifact **once** (OIDC via `GOVERNANCE_AWS_ROLE_ARN`) and uploads it as the `jeavio-governance-tool` GitHub Actions artifact; every scan job downloads that artifact instead of each re-authenticating to CodeArtifact independently.
- Each scan job then authenticates to AWS itself (OIDC, same role) — `--scan --ci` still needs to pull the actual `governance/*` scanner images from ECR and sync vulnerability data from S3, which the shared artifact download doesn't cover.
- `--ci` mode makes `jeavio-governance` exit non-zero if any sub-scan fails or reports a violation, which is what makes these jobs actually gate the PR (by default the tool only logs failures, it doesn't fail the run — see `--ci`'s `CI_EXIT_STATUS`/`SCAN_RESULTS` tracking in the script).
- Reports land in `~/jeavio-governance/sast-reports` on the runner and are uploaded (`if: always()`) as the `secret-detection-reports` / `sast-scan-reports` / `dependency-scan-reports` / `license-scan-reports` artifacts (14-day retention) for anyone to review from that workflow run's Summary page.
- `TECH_STACK`/`TECH_DOMAIN` in each job's generated `config.env` assume this is a Python (`web`) project — adjust if that changes.
- **Caveat**: every scan is a full-tree scan of whatever `actions/checkout` pulled down (the whole PR branch) — there's no diff-only/incremental mode in this tool (confirmed: no `git diff`, no SonarQube PR-decoration params anywhere in `sast-automation/`). A PR can fail this gate on a pre-existing issue it didn't introduce, not just on newly introduced ones.
- **Caveat**: `secret-detection-reports` can contain the actual secret values `detect-secrets` found — anyone with repo/Actions read access can download that artifact. Tighten retention or restrict repo visibility if that's a concern.
