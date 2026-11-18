# Set up Ed-Codex reviews for Personal Radio

This guide is for `Ed-Davey/personal-radio-car-play`, where `dev` is the default branch. It uses `V1` for integration testing and protects `dev` with a clean Codex review and your approval.

| Who | What happens |
| --- | --- |
| Coding agent | Works on a feature branch from `V1`, tests the change, and brings it into `V1` for integration testing. It pushes fixes when Codex reports a problem. |
| `ed-codex[bot]` | Opens a draft promotion PR into `dev`. GitHub sees this app as the PR author, so you can approve it as `Ed-Davey`. |
| Codex review workflow | Runs when the draft opens and after each push to it. It posts findings in the PR and blocks merging while any remain. When a review comes back clean, it tries to mark the PR ready. |
| `Ed-Davey` | Receives the code-owner review request when the draft becomes ready. Reviews the latest green revision and merges in GitHub. |

The workflow runs once per triggering event. If Codex finds a problem, it waits for a fix commit. That commit starts a fresh review. After a clean review, any later commit still triggers another run. The review workflow reads code and reports findings. The coding agent handles fixes and tests as part of the feature task.

## 1. Create the private GitHub App

1. While signed in as **Ed-Davey**, open [your GitHub Apps settings](https://github.com/settings/apps) and select **New GitHub App**.
2. Enter **Ed-Codex** as the **GitHub App name**, or choose a unique name if GitHub says it is taken. For **Homepage URL**, use the [Personal Radio repository](https://github.com/Ed-Davey/personal-radio-car-play).
3. Under **Webhook**, clear **Active**. Leave user authorization, callback URLs and event subscriptions unset.
4. Under **Permissions → Repository permissions**, set **Pull requests** to **Read and write**. GitHub supplies **Metadata** access. Leave **Contents** unset. The app opens PRs and your usual GitHub credentials push feature and fix commits.
5. For **Where can this GitHub App be installed?**, choose **Only on this account**. Click **Create GitHub App**.
6. On the app’s settings page, copy the **Client ID**, scroll to **Private keys**, and click **Generate a private key**. Save the downloaded `.pem` somewhere outside the repository. Note the app slug shown at the end of its public app URL. For example, an app at `github.com/apps/ed-codex` has bot login `ed-codex[bot]`.
7. Select **Install App** in the app settings, choose **Ed-Davey**, pick **Only select repositories**, and select `personal-radio-car-play`. Install it.

The private setting limits who can install the app. The Personal Radio repository is public, so files and posted reviews can be visible publicly. Store the `.pem` and API key in the secret settings below. [Register a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app) · [How installation tokens are attributed](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation)

## 2. Add the app credentials and Codex API key to this repo

1. In **repository Settings → Environments**, choose **New environment**, name it `ed-codex-publisher`, and configure it.
2. Under **Deployment branches and tags**, choose **Selected branches and tags**. Add a **Branch** rule for `dev`.
3. Under **Environment secrets**, add `ED_CODEX_PRIVATE_KEY`. Paste the entire downloaded `.pem`, including its `BEGIN` and `END` lines. Under **Environment variables**, add `ED_CODEX_CLIENT_ID` with the Client ID from the app settings.
4. In **repository Settings → Secrets and variables → Actions → Variables**, add a **repository variable** `ED_CODEX_BOT_LOGIN`. Its value is your exact bot login, including `[bot]`, such as `ed-codex[bot]`.
5. On the OpenAI Platform, create an API key in the project you want to use for PR reviews. In **repository Settings → Secrets and variables → Actions → Secrets**, add a **repository secret** `OPENAI_API_KEY` with that key. The automatic workflow uses API usage. The GitHub comment command in step 7 uses your connected Codex setup.
6. In **repository Settings → Actions → General**, ensure the repository can run `actions/checkout`, `actions/create-github-app-token` and `openai/codex-action`. If your settings allow only selected actions, add these three.

| Where to add it | Name | Value |
| --- | --- | --- |
| Environment `ed-codex-publisher` → Secret | `ED_CODEX_PRIVATE_KEY` | Full PEM text |
| Environment `ed-codex-publisher` → Variable | `ED_CODEX_CLIENT_ID` | GitHub App Client ID |
| Repository Actions → Variable | `ED_CODEX_BOT_LOGIN` | App slug followed by `[bot]` |
| Repository Actions → Secret | `OPENAI_API_KEY` | OpenAI Platform API key |

The environment makes the PR publisher’s app key available only to its `dev` job. The review template is designed for branches in this repo controlled by you and your app. It blocks fork PRs from using the review key. [GitHub environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments#creating-an-environment) · [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) · [OpenAI API keys](https://platform.openai.com/api-keys) · [Codex in Actions](https://learn.chatgpt.com/docs/github-action)

## 3. Install the workflows on `dev` once

The files in this guide are templates. GitHub starts using them when you copy them to `.github/workflows/` and land them in `dev`. The manual publisher needs to exist on the default branch before **Run workflow** appears. Save the new required status check for step 6, after one successful run.

In Terminal from the Personal Radio repository, run:

```sh
git switch dev
git pull --ff-only origin dev
git switch -c setup/ed-codex-workflow
mkdir -p .github/workflows
cp docs/github-workflow/open-promotion-pr.yml .github/workflows/
cp docs/github-workflow/codex-review.yml .github/workflows/
```

Create `.github/CODEOWNERS` with this one line. If an owners file already exists, incorporate the entry and check whether later entries override it.

```text
* @Ed-Davey
```

Then commit and push the setup branch:

```sh
git add .github/CODEOWNERS .github/workflows/open-promotion-pr.yml .github/workflows/codex-review.yml docs/github-workflow
git commit -m 'Set up Ed-Codex promotion reviews'
git push -u origin setup/ed-codex-workflow
```

If `dev` already requires a review you cannot give on a self-authored PR, use the helper below to open this first PR as the app. You can use it for the first PR even if `dev` is still unprotected. Substitute your Client ID and downloaded key path. Use the exact bot login you set in step 2. The helper opens only `setup/ed-codex-workflow` → `dev` in this repo, and prints the PR URL and author. It needs Python 3 and `openssl` on your Mac.

```sh
python3 docs/github-workflow/open-bootstrap-pr.py \
  --client-id 'PASTE_CLIENT_ID_HERE' \
  --private-key "$HOME/Downloads/YOUR_DOWNLOADED_KEY.pem" \
  --bot-login 'ed-codex[bot]'
```

Open the URL. Verify the app is the author, review the setup files yourself and merge the PR to `dev` using the protections currently in place. If you previously opened the same setup PR as yourself, GitHub keeps its author. Use another eligible reviewer or close that PR and rerun the helper to open a bot-authored one.

Templates and helper: [PR publisher](open-promotion-pr.yml), [automatic reviewer](codex-review.yml), [bootstrap script](open-bootstrap-pr.py). [GitHub App JWT](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app) · [Manual workflow requirements](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch) · [Code-owner review](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)

## 4. Create `V1`, then work on features

Once the setup is on `dev`, create the test branch once. If `V1` already exists, switch to it and pull its changes instead of recreating it.

```sh
git switch dev
git pull --ff-only origin dev
git switch -c V1
git push -u origin V1
```

Start each feature from the latest `V1`. Once it passes its own tests, merge it into `V1` and test the integrated build. For example, after committing and testing on `feature/my-change`, run:

```sh
git switch V1
git pull --ff-only origin V1
git merge --ff-only feature/my-change
git push origin V1
```

If `V1` moved and the fast-forward fails, update the feature branch with the latest `V1` and retest before integrating. If you prefer an integration PR into `V1`, GitHub may also request you as code owner on that PR because `V1` inherits the owners file. The required final approval in this guide applies to `dev`.

A `V1` → `dev` PR contains all unpromoted changes on `V1`. If several features are in flight and you only want to promote one, create a `promote/<feature>` branch from `dev`, cherry-pick just the tested feature changes, test that branch and select it in the publisher.

## 5. Run the publisher and test the review loop

1. Push a small tested change to `V1` through a feature PR, so `V1` has something to promote. In GitHub, open **Actions → Open Ed-Codex promotion PR → Run workflow**. Choose **Use workflow from `dev`**, leave **head** as `V1`, add a title and test summary, and click **Run workflow**.
2. Open the run’s **Summary**. Follow the PR URL and confirm the author matches `ED_CODEX_BOT_LOGIN` and the PR is a draft. A second publisher run for the same head and base prints the existing URL.
3. Check the PR’s **Checks** tab for **Codex review gate**. On **Conversation**, look for a Codex summary labelled with the reviewed commit. If it lists findings, fix them and **push to the same PR branch**. Keep the existing PR. The push triggers a fresh review. Resolving discussion threads alone does not trigger a run.
4. Repeat after each fix. When the latest run says **No actionable findings**, its gate can pass. The workflow tries **Ready for review** on the app’s draft, which makes GitHub request you as code owner. If the draft stays open with a green check, use **Ready for review** on the PR after confirming the commit is unchanged. Marking ready uses the clean check for that revision. The next push starts another review.

The review summaries stay in the PR so you can see the sequence of fixes. Judge readiness using the summary for the latest commit and the current check. The workflow can find defects and miss others, so still review the diff and test notes yourself. [Pull request trigger events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request) · [Draft PR behaviour](https://docs.github.com/en/pull-requests/how-tos/create-pull-requests/changing-the-stage-of-a-pull-request)

## 6. Protect `dev` and verify your approval is required

After **Codex review gate** has passed at least once in this repo, go to **Settings → Rules → Rulesets → New ruleset → New branch ruleset**. If you already have a `dev` ruleset, edit it.

1. Name it **Protect dev**, set it **Active**, target exact branch `dev`, and leave the bypass list empty.
2. Turn on **Require a pull request before merging**, **1 required approval**, **Require review from Code Owners**, **Dismiss stale pull request approvals when new commits are pushed**, and **Require conversation resolution**. GitHub uses the owners file on `dev`, so `Ed-Davey` is the required owner. Leave **Require approval of the most recent reviewable push** off for this setup, since your credentials can push a fix even though the app authored the PR.
3. Turn on **Require status checks to pass before merging**, add **Codex review gate**, select **GitHub Actions** as the source if offered, and save. Also enable **Restrict deletions** and **Block force pushes**. Keep **Restrict updates**, **Require linear history** and **Require merge queue** off for this particular workflow. It uses normal merge commits and PR events.
4. On a test PR, verify a green check alone still leaves the approval requirement. Approve via **Files changed → Review changes → Approve**. Before merging, push one more small commit to the PR branch. Verify the new check runs and your previous approval is dismissed. Approve the final clean revision and choose **Create a merge commit**. Keep `V1` for future testing.

Use a merge commit for repeated `V1` promotions so `dev` retains the history of that long-lived branch. After the merge, bring the updated `dev` commit back into `V1` before branching new work. If `V1` has unpromoted work, preserve it when syncing. [GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository) · [Required check behaviour](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks) · [Merging long-running branches](https://docs.github.com/en/pull-requests/reference/pull-request-merges#squashing-and-merging-a-long-running-branch)

## 7. Request an extra Codex review from inside the PR

1. Connect this repository to Codex and enable repository code review in [Codex code review settings](https://chatgpt.com/settings/code-review). The Actions workflow already handles automatic runs. If the settings let you keep manual review enabled while following personal preferences, leave the personal automatic trigger off to avoid duplicate reviews.
2. In the PR’s **Conversation**, post this comment and wait for Codex’s reaction and review:

   ```text
   @codex review
   ```

3. If the extra review finds an issue, hold your approval and have the fix pushed. That reruns the required Actions gate. To manually rerun **that exact gate**, open its workflow run from the PR’s **Checks** tab and use **Re-run all jobs**. The `@codex review` command posts a separate review and does not update the required Actions check.

Verify the command on one app-authored PR. If the native integration is unavailable for that PR, use **Checks → linked workflow run → Re-run all jobs** for a new Codex pass on the same commit. [Native Codex review](https://learn.chatgpt.com/docs/third-party/github) · [Re-run workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs)

## What to tell the coding agent for each feature

> Work on a feature branch from `V1` and run the relevant tests. Integrate and test the change on `V1`. Open its promotion PR into `dev` with the Ed-Codex publisher. Watch the reviewing workflow, address actionable findings, push fixes to the same PR branch and wait for a fresh result after each push. Hand it back to me when the latest revision is green and ready for human review. Leave the `dev` merge for me. Raise any blocker that prevents a clean review or meaningful test.

## If something stalls

| Symptom | What to check |
| --- | --- |
| **Run workflow** is missing | The publisher file must be in `.github/workflows/` on default branch `dev`, and Actions must be enabled. |
| The publisher reports a credential or identity error | Check the Client ID, PEM, the `dev` deployment rule on `ed-codex-publisher`, that the app is installed on this repo, and that the exact bot login includes `[bot]`. |
| GitHub reports there are no commits between the branches | Push the tested change to the selected head branch before publishing. |
| The required check is missing or waiting | Look for conflicts with `dev`, check the PR base and the latest commit, and see the run’s logs. GitHub needs a successful run in the past seven days before the check is selectable in the ruleset. |
| The gate fails without a findings comment | Inspect the `review` job for an absent API key, missing API access, unsupported actor or unusable result. Fork PRs are outside this template’s trusted same-repository workflow. |
| The clean PR is still a draft | Open the gate run’s summary. If GitHub blocked the automatic transition, confirm the green check is for the current commit and click **Ready for review**. |
| Your approval fails | Confirm the PR author is the app and that you are the code owner on `dev`. If you made the last push, check the last-pusher rule from step 6. |
