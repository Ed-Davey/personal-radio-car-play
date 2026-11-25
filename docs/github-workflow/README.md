# Set up Ed-Codex reviews for Personal Radio

Personal Radio uses `dev` for approved changes and `V1` for integration testing. GitHub's native Codex integration reviews the PR, and GitHub Actions records that review as **Native Codex review** for the exact commit. Ed-Davey gives the final approval.

| Who | What happens |
| --- | --- |
| Coding agent | Starts each feature from `dev`, tests it with the other features on `V1`, and fixes Codex findings on the same feature branch. |
| `ed-codex[bot]` | Publishes the tested feature branch into `dev` as ready for review. Ed-Davey can approve because the app is the PR author. |
| Native Codex | Reviews on opening and on each new push. Findings and manual reviews appear in the PR conversation. |
| GitHub Actions | Checks the review summary came from the OpenAI GitHub App and confirms the reviewed commit matches the current PR head. The status passes when the review completes with no findings. |
| Ed-Davey | Reviews the code and test notes after the latest status passes, then approves and merges. |

## 1. Create the private GitHub App

1. While signed in as **Ed-Davey**, open [your GitHub Apps settings](https://github.com/settings/apps) and select **New GitHub App**.
2. Enter **Ed-Codex** as the **GitHub App name**, or choose a unique name if GitHub says it is taken. For **Homepage URL**, use the [Personal Radio repository](https://github.com/Ed-Davey/personal-radio-car-play).
3. Under **Webhook**, clear **Active**. Leave user authorization, callback URLs and event subscriptions unset.
4. Under **Permissions → Repository permissions**, set **Pull requests** to **Read and write**. GitHub supplies **Metadata** access. Leave **Contents** unset. The app opens PRs and your usual GitHub credentials push feature and fix commits.
5. For **Where can this GitHub App be installed?**, choose **Only on this account**. Click **Create GitHub App**.
6. On the app’s settings page, copy the **Client ID**, scroll to **Private keys**, and click **Generate a private key**. Save the downloaded `.pem` somewhere outside the repository. Note the app slug shown at the end of its public app URL. For example, an app at `github.com/apps/ed-codex` has bot login `ed-codex[bot]`.
7. Select **Install App** in the app settings, choose **Ed-Davey**, pick **Only select repositories**, and select `personal-radio-car-play`. Install it.

The private setting limits who can install the app. The Personal Radio repository is public, so files and posted reviews can be visible publicly. Store the `.pem` in the secret settings below. [Register a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app) · [How installation tokens are attributed](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation)

## 2. Add the publisher credentials

1. In **repository Settings → Environments**, create `ed-codex-publisher`.
2. Under **Deployment branches and tags**, choose **Selected branches and tags**, then add a **Branch** rule for `dev`.
3. Add the full PEM as environment secret `ED_CODEX_PRIVATE_KEY` and the app's Client ID as environment variable `ED_CODEX_CLIENT_ID`.
4. Under **Settings → Secrets and variables → Actions → Variables**, add the repository variable `ED_CODEX_BOT_LOGIN` with value `ed-codex[bot]` or your app's exact bot login.
5. If Actions has an allowlist, allow `actions/checkout`, `actions/github-script` and `actions/create-github-app-token`.

The publisher key stays in the `dev`-only environment. The status workflow uses the built-in GitHub Actions token and the connected Codex Code Review allowance. It runs without `OPENAI_API_KEY`. [GitHub environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) · [Codex usage allowances](https://learn.chatgpt.com/docs/pricing#what-counts-as-code-review-usage)

## 3. Enable native reviews and land the workflow setup

1. Open [Codex code review settings](https://chatgpt.com/settings/code-review) and select this repository.
2. Enable **Automatic review**, set **Review** to **All PRs**, and set **Trigger** to **On every push**. App-authored PRs need the repository settings. For settings that follow personal preferences, enable personal automatic review and check your review trigger too.
3. Merge the workflow setup PR into `dev`. The reviewed workflow on `dev` can then record reviews. If a setup PR is authored by Ed-Davey, the repo admin PR-only override covers this bootstrap. The [bootstrap helper](open-bootstrap-pr.py) is available for an app-authored bootstrap.
4. Check **Actions → Record native Codex review** exists on `dev`. Keep the status optional until the live test below succeeds.

The [publisher template](open-promotion-pr.yml) and [review template](codex-review.yml) mirror the active workflows. [Native Codex reviews](https://learn.chatgpt.com/docs/third-party/github) · [Manual workflow requirements](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch)

## 4. Create `V1`, then branch each feature from `dev`

Create `V1` from `dev` once. If `V1` already exists, switch to it and pull its changes.

```sh
git switch dev
git pull --ff-only origin dev
git switch -c V1
git push -u origin V1
```

Start each feature from the current `dev`.

```sh
git fetch origin
git switch -c feature/my-change origin/dev
```

After committing and testing the feature, merge it into `V1` and test the collected changes. Preserve the feature commit in the merge so the publisher can verify that it was integrated.

```sh
git switch V1
git pull --ff-only origin V1
git merge --no-ff feature/my-change
# Build and test V1, then push it.
git push origin V1
git push -u origin feature/my-change
```

Keep `V1` out of the feature branch's history. Integration conflicts belong on `V1`, so each feature PR into `dev` can be reviewed independently. If another feature changes `dev` before this one merges, check and test the feature again against the updated base as needed.

## 5. Verify the review loop

1. From **Actions → Open Ed-Codex feature PR → Run workflow**, use `dev`, enter the tested `feature/...` branch, title and test summary. Open the PR URL in the run summary. Confirm the author matches `ED_CODEX_BOT_LOGIN` and the PR is ready. Publishing the same branch twice returns its existing PR.
2. Watch for a native review summary in the conversation for the current SHA and the **Native Codex review** status in the merge box. The status stays pending until there is a completed result for that commit. Findings fail the status.
3. Fix any findings on the same feature branch and integrate the fix into `V1`. Confirm the push automatically starts a new native review on the new commit and that the status passes only when that review is clean. Resolving the discussion alone does not replace the new review.
4. To request a review yourself, comment `@codex review` in the PR. To refresh the status from a review already in the conversation, run **Record native Codex review** from `dev` with that PR number. This is useful for a PR already open when the new workflow lands.

The gate reads the OpenAI app's review summary, which currently contains a machine-readable review status and full SHA. This format is undocumented and may change. Missing, stale or unrecognised reviews leave the check blocked. Native Codex focuses on serious issues, so still run tests and review the diff. [Codex review scope](https://learn.chatgpt.com/docs/third-party/github#request-a-codex-review) · [GitHub commit statuses](https://docs.github.com/en/rest/commits/statuses)

## 6. Require the status and your approval on `dev`

After **Native Codex review** has passed on a live PR, open **Settings → Rules → Rulesets → Protect dev**.

1. Keep the rule active on `dev` and the repository admin bypass **For pull requests only** if you use it.
2. Require a PR, one approval, Code Owner review, stale approval dismissal and conversation resolution. `.github/CODEOWNERS` assigns Ed-Davey. Leave approval of the most recent reviewable push off so Ed-Davey can approve an app-authored PR after pushing a fix.
3. Enable **Require status checks to pass before merging** and add **Native Codex review**. Select **GitHub Actions** as the expected source if available. If a rule names the retired **Codex review gate**, replace that entry in the same edit. Keep branch deletion and force-push restrictions.
4. On a test PR, confirm the green status still requires Ed's approval. Confirm that new commits clear the old approval and require fresh review. Approve the final clean revision, then choose **Create a merge commit** to preserve the tested feature commits.

If an existing PR still shows failed API-based jobs, merge the updated `dev` into its feature branch and integrate that revision into `V1`. Confirm the new SHA gets a fresh native review and a green status. Earlier runs remain in Actions history. [Rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository) · [Required status checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)

## If something stalls

| Symptom | What to check |
| --- | --- |
| **Run workflow** is missing | Check that the workflow is on default branch `dev` and Actions is enabled. |
| Publisher credentials or identity fail | Check the Client ID, PEM, `dev` environment branch rule, app installation and exact bot login. |
| Publisher reports the feature is missing from `V1` | Merge the exact feature tip into `V1` without squashing, test it and push `V1`. |
| No native review starts | Confirm the PR is ready, repo automatic reviews include all PRs and the trigger is every push. Try `@codex review` and check the connected account's Code Review allowance. |
| Native Codex is clean but the status is pending | Confirm the summary is for the current commit. Run **Record native Codex review** from `dev` and inspect the recorder log. |
| Approval is still required | Confirm the PR was authored by the app, Ed-Davey is the code owner and the approval is for the current head. |
