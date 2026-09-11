# CI/CD Pipeline

Implements the CI/CD & Software Delivery Framework (`CI_CD Framework.docx`) for this monorepo: a Python backend (`backend/`) deployed to **Amazon ECS Fargate** (images in **Amazon ECR**), and a React frontend (`frontend/`) deployed as a static build to **Amazon S3 + CloudFront**. The two pipelines are fully independent — separate workflow files, separate triggers (path-filtered to `backend/**` / `frontend/**`), separate AWS resources — but follow the same shape and the same branching model.

These workflows are written to be **reused across projects**: copy `.github/workflows/` into a new repo, point `APP_NAME`/`ECR_REPOSITORY`/bucket names at that project's own resources, and follow the setup guide below. Nothing in the YAML is project-specific beyond the config values described here.

## Branching strategy

```
feature/*  --PR-->  develop
                       │  (push)
                       ▼
       cd-develop*.yml: build once, tag dev-<sha>  ->  Deploy to Development   [stops]

                       │  someone runs promote-to-qa*.yml by hand,
                       │  naming the exact tag they tested
                       ▼        (this manual trigger IS the approval)
                  Deploy to QA


develop  --(cut by hand)-->  release/v1.0.0
                       │  (push)
                       ▼
   cd-release*.yml: version = "1.0.0" taken from the branch name
                       │
                       ▼
       build once, tag 1.0.0  ->  Deploy to Staging   [stops]

                       │  someone runs promote-to-production*.yml by hand,
                       │  naming the exact version they validated
                       ▼        (this manual trigger IS the approval)
              Deploy to Production  ->  Automated rollback (on failure)
```

- **PRs** into `develop`, `main`, or `release/**` must pass `ci-pr-validation.yml` / `ci-pr-validation-frontend.yml` (see "Checks & where to find reports" below).
- **`develop`** auto-deploys to Development on every push. It's a shared environment — a later merge can redeploy over whoever's still testing, so QA/Production promotion always requires you to name the *exact* tag/version you tested, never "whatever's currently deployed."
- **`release/vX.Y.Z`** branches are cut by hand from `develop` and auto-deploy to Staging. The version in the branch name becomes the image tag / build tag for that release — no rebuild happens after this point.
- **Promotion to QA and Production is manual** (Actions tab → Run workflow), because private repos on this GitHub plan don't get native Environment "Required reviewers." The manual trigger *is* the approval; who can click it is controlled by normal repo **Write** access (Settings → Collaborators and teams).
- No image/bundle is ever rebuilt between stages (Build Once, Deploy Anywhere) — promotion always redeploys the exact artifact that was built earlier.

## Workflows at a glance

**Backend:**

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `ci-pr-validation.yml` | PR → `develop`, `main`, `release/**` | Quality & security gates |
| `cd-develop.yml` | Push to `develop` | Build once, deploy to Development |
| `promote-to-qa.yml` | Manual, requires `image_tag` | Deploy that exact image to QA |
| `cd-release.yml` | Push to `release/v*` | Build once (version from branch name), deploy to Staging |
| `promote-to-production.yml` | Manual, requires `image_tag` | Deploy that exact image to Production, with automated rollback |
| `deploy-template.yml` | Called by the workflows above | Shared ECS deploy step, reused per environment |

**Frontend** (same shape, `frontend-` suffixed workflow files, inputs named `build_tag` instead of `image_tag`) — `ci-pr-validation-frontend.yml`, `cd-develop-frontend.yml`, `promote-to-qa-frontend.yml`, `cd-release-frontend.yml`, `promote-to-production-frontend.yml`, `deploy-template-frontend.yml`.

## AWS setup

Each environment (**development**, **qa**, **staging**, **production**) needs its own AWS resources and its own IAM role — never share a role across environments, since that defeats the point of scoping blast radius per environment.

### Resources that must already exist per environment

The pipeline deploys to existing infrastructure; it does not provision any of this.

| Environment resource | Backend | Frontend |
| --- | --- | --- |
| Compute/hosting | ECS cluster + service + an initial task definition revision | S3 bucket (private, CloudFront-only via OAC) + CloudFront distribution |
| Shared, repo-level | One ECR repository holding every tag | One S3 "artifacts" bucket holding every immutable build |

**Gotcha to watch for**: if your ECS task definition's `logConfiguration` uses `awslogs-create-group: true`, deploys will fail with `AccessDenied` on `logs:CreateLogGroup` unless `ecsTaskExecutionRole` is explicitly granted that permission. Simplest fix: pre-create the CloudWatch log group yourself and drop the `awslogs-create-group` flag.

### IAM roles (GitHub OIDC)

Each project needs **one repo-level role per pipeline, plus one role per environment per pipeline** — 2 roles at repo level (backend + frontend) and 2 roles × 4 environments = 8 environment-scoped roles, all federated via `token.actions.githubusercontent.com`.

| Role | Scope | Permissions needed |
| --- | --- | --- |
| Backend, repo-level | Any ref/environment in this repo | `ecr:GetAuthorizationToken`, push permissions on the one ECR repo, `ssm:GetParameter` on `/{APP_NAME}/*/current-image` |
| Backend, per environment | `environment:<name>` only | `ecs:DescribeServices`, `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `iam:PassRole` on the ECS task execution role (condition: `iam:PassedToService=ecs-tasks.amazonaws.com`), `ssm:PutParameter` on `/{APP_NAME}/<env>/current-image` |
| Frontend, repo-level | Any ref/environment in this repo | Read/write/list on the artifacts bucket, `ssm:GetParameter` on `/{APP_NAME}/*/frontend/current-build` |
| Frontend, per environment | `environment:<name>` only | Read/write/list on that environment's website bucket, read on the artifacts bucket, `cloudfront:CreateInvalidation` on that environment's distribution, `ssm:GetParameter`/`PutParameter` on `/{APP_NAME}/<env>/frontend/current-build` |

Trust policy condition, per role:
```
"StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
"StringLike":   { "token.actions.githubusercontent.com:sub": "repo:<ORG>@*/<REPO>@*:*" }                          // repo-level
"StringLike":   { "token.actions.githubusercontent.com:sub": "repo:<ORG>@*/<REPO>@*:environment:<name>" }        // per environment
```

> **Org-specific note**: if your GitHub organization customizes its OIDC subject claim to embed numeric org/repo IDs (some do, to survive renames) — check by looking at an existing working role's trust policy, or by inspecting a successful `AssumeRoleWithWebIdentity` call in AWS CloudTrail (`userIdentity.userName` shows the exact `sub` string GitHub sent). If it does, the `sub` pattern above needs `@*` after both the org and repo name, e.g. `repo:<ORG>@*/<REPO>@*:environment:<name>`. Using the plain pattern against a customized org will make every `AssumeRoleWithWebIdentity` call fail silently — the deploy step just times out with an AWS auth error, with nothing pointing at the trust policy as the cause.

### Sample policies

One example of each of the four role types — fill in `<ACCOUNT_ID>`, `<REGION>`, `<APP_NAME>`, and the bucket/repo/distribution names for your project. The env-level examples use `qa` as the sample environment; repeat the same shape for `development`/`staging`/`production` with their own resource names.

**Backend, repo-level** (attach to the role trusted for `repo:<ORG>/<REPO>:*`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EcrAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "EcrPushAppImage",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "arn:aws:ecr:<REGION>:<ACCOUNT_ID>:repository/<ECR_REPOSITORY>"
    },
    {
      "Sid": "SsmReadCurrentImage",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:<REGION>:<ACCOUNT_ID>:parameter/<APP_NAME>/*/current-image"
    }
  ]
}
```

**Backend, per environment** (attach to the role trusted for `repo:<ORG>/<REPO>:environment:qa`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EcsDeploy",
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassEcsTaskRoles",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::<ACCOUNT_ID>:role/ecsTaskExecutionRole",
      "Condition": {
        "StringEquals": { "iam:PassedToService": "ecs-tasks.amazonaws.com" }
      }
    },
    {
      "Sid": "SsmWriteCurrentImage",
      "Effect": "Allow",
      "Action": "ssm:PutParameter",
      "Resource": "arn:aws:ssm:<REGION>:<ACCOUNT_ID>:parameter/<APP_NAME>/qa/current-image"
    }
  ]
}
```

**Frontend, repo-level** (attach to the role trusted for `repo:<ORG>/<REPO>:*`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ArtifactsBucketReadWrite",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::<FRONTEND_ARTIFACTS_BUCKET>/*"
    },
    {
      "Sid": "ArtifactsBucketList",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<FRONTEND_ARTIFACTS_BUCKET>"
    },
    {
      "Sid": "SsmReadCurrentBuild",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:<REGION>:<ACCOUNT_ID>:parameter/<APP_NAME>/*/frontend/current-build"
    }
  ]
}
```

**Frontend, per environment** (attach to the role trusted for `repo:<ORG>/<REPO>:environment:qa`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadArtifactsBucket",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<FRONTEND_ARTIFACTS_BUCKET>/*"
    },
    {
      "Sid": "ListArtifactsBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<FRONTEND_ARTIFACTS_BUCKET>"
    },
    {
      "Sid": "WebsiteBucketReadWrite",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::<FRONTEND_S3_BUCKET_QA>/*"
    },
    {
      "Sid": "ListWebsiteBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<FRONTEND_S3_BUCKET_QA>"
    },
    {
      "Sid": "CloudFrontInvalidate",
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::<ACCOUNT_ID>:distribution/<CLOUDFRONT_DISTRIBUTION_ID>"
    },
    {
      "Sid": "SsmReadWriteCurrentBuild",
      "Effect": "Allow",
      "Action": ["ssm:GetParameter", "ssm:PutParameter"],
      "Resource": "arn:aws:ssm:<REGION>:<ACCOUNT_ID>:parameter/<APP_NAME>/qa/frontend/current-build"
    }
  ]
}
```

### GitHub configuration

**Repository-level** (Settings → Secrets and variables → Actions):

| Name | Type | Used for |
| --- | --- | --- |
| `AWS_ROLE_ARN` | Secret | Backend repo-level role |
| `AWS_REGION` | Variable | Backend AWS region |
| `ECR_REPOSITORY` | Variable | Backend image repo name |
| `FRONTEND_AWS_ROLE_ARN` | Secret | Frontend repo-level role |
| `FRONTEND_ARTIFACTS_BUCKET` | Variable | Frontend build artifacts bucket |
| `APP_NAME` | Variable | Namespace prefix for S3 paths + SSM parameter paths (shared by both pipelines) |
| `GOVERNANCE_AWS_ROLE_ARN` | Secret | Jeavio Governance tool (see below) |
| `GOVERNANCE_AWS_REGION` | Variable (optional) | Defaults to `ap-south-1` |
| `COVERAGE_THRESHOLD` | Variable (optional) | Minimum test coverage %, defaults to `80` |
| `NODE_VERSION` / `PYTHON_VERSION` / `PIP_VERSION` | Variable (optional) | Toolchain versions, sensible defaults if unset |

Only redeclare a variable at the environment level if its value actually differs per environment — anything set at repo level already applies everywhere by default.

**Per GitHub Environment** (Settings → Environments → create `development`, `qa`, `staging`, `production`):

| Name | Type | Used for |
| --- | --- | --- |
| `AWS_ROLE_ARN` | Secret | Backend role scoped to this environment |
| `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_DEFINITION_FAMILY`, `CONTAINER_NAME` | Variable | This environment's ECS target |
| `FRONTEND_AWS_ROLE_ARN` | Secret | Frontend role scoped to this environment |
| `FRONTEND_S3_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID` | Variable | This environment's website bucket + distribution |

## Checks & where to find reports

Every PR into `develop`/`main`/`release/**` runs, per pipeline: **lint**, **unit tests + coverage** (gated by `COVERAGE_THRESHOLD`), and four security/quality scans via the shared Jeavio Governance tool — **secret detection**, **SAST**, **dependency vulnerability scan**, and **license compliance scan**. A `quality-gate` job fails the PR if anything above failed, was cancelled, or was skipped.

To review results: open the PR's checks (or the workflow run directly) → **Summary** tab → **Artifacts**. Look for `coverage-report`, `secret-detection-reports`, `sast-scan-reports`, `dependency-scan-reports`, `license-scan-reports` (frontend jobs suffix these with `-frontend`; 14-day retention). Note that `secret-detection-reports` can contain the actual secret values found — restrict who can download Actions artifacts if that's a concern.

Governance scans require their own repo-level secret (`GOVERNANCE_AWS_ROLE_ARN`, table above) — this is a separate AWS account/role from either deploy pipeline's.

For branch protection, require the `Quality Gate` job (not every individual check) as a required status check on `develop`/`main`/`release/**` — it already aggregates everything else. Don't mark the frontend check as required until you've confirmed your branch protection rule tolerates a check that only runs on PRs touching `frontend/**`.

## Rollback & traceability

- **Backend**: ECS's own Deployment Circuit Breaker auto-reverts a deploy if new tasks never reach a healthy steady state. `promote-to-production.yml` additionally force-redeploys the previous task definition if the promotion job itself fails.
- **Frontend**: no infra-level equivalent (static hosting) — `promote-to-production-frontend.yml` force-resyncs the previous build and re-invalidates CloudFront on failure.
- **What's live where**: every deploy writes to SSM Parameter Store — `/{APP_NAME}/{environment}/current-image` (backend) and `/{APP_NAME}/{environment}/frontend/current-build` (frontend) — as an audit trail, independent of which workflow run did the deploying.
