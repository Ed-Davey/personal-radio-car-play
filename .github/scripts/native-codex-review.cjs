"use strict";

const STATUS_CONTEXT = "Native Codex review";
const CODEX_BOT_ID = 199175422;
const CODEX_APP_ID = 1144995;
const CODEX_LOGIN = "chatgpt-codex-connector[bot]";
const CODEX_SLUG = "chatgpt-codex-connector";
const SUMMARY = "<!-- codex-pull-request-review-summary -->";
const STATE_PREFIX = "<!-- codex-review-state:";
const STATE_LINE = /^<!-- codex-review-state:v1 (\{.*\}) -->$/;
const COMMIT_SHA = /^[0-9a-f]{40}$/;

const waiting = { state: "pending", description: "Waiting for a native Codex review of this commit" };
const unverifiable = { state: "failure", description: "Native Codex review metadata could not be verified" };

function isNativeCodexComment(comment) {
  return comment.user?.id === CODEX_BOT_ID
    && comment.user?.login === CODEX_LOGIN
    && comment.user?.type === "Bot"
    && comment.performed_via_github_app?.id === CODEX_APP_ID
    && comment.performed_via_github_app?.slug === CODEX_SLUG;
}

function isSummary(comment) {
  return isNativeCodexComment(comment)
    && typeof comment.body === "string"
    && comment.body.split(/\r?\n/, 1)[0] === SUMMARY;
}

function evaluateReview(summaries, sha) {
  if (summaries.length === 0) return waiting;
  if (summaries.length !== 1) return unverifiable;

  const [summary] = summaries;
  const lines = summary.body.split(/\r?\n/);
  const stateLines = lines.filter(line => line.startsWith(STATE_PREFIX));
  const stateData = lines[1]?.match(STATE_LINE);
  if (!stateData || stateLines.length !== 1) return unverifiable;

  let review;
  try {
    review = JSON.parse(stateData[1])?.code_review;
  } catch {
    return unverifiable;
  }

  if (!review || typeof review !== "object") return unverifiable;
  if (review.commit_sha === null && review.status === null) return waiting;
  if (typeof review.commit_sha !== "string" || !COMMIT_SHA.test(review.commit_sha)) return unverifiable;
  if (review.commit_sha !== sha || review.status === "running") return waiting;
  if (review.status !== "completed"
      || typeof review.has_any_findings !== "boolean"
      || typeof review.has_unresolved_findings !== "boolean") return unverifiable;

  if (review.has_any_findings || review.has_unresolved_findings) {
    return { state: "failure", description: "Native Codex reported findings on this commit", summary };
  }
  return { state: "success", description: "Native Codex found no issues on this commit", summary };
}

function pullRequestNumber({ eventName, payload, actor, ref, repo }) {
  if (eventName === "pull_request_target") return payload.pull_request?.number;
  if (eventName === "issue_comment") {
    if (payload.issue?.pull_request && payload.comment?.user?.id === CODEX_BOT_ID) {
      return payload.issue.number;
    }
  }
  if (eventName === "workflow_dispatch" && actor === repo.owner && ref === "refs/heads/dev") {
    const input = payload.inputs?.pull_request;
    const text = typeof input === "number" ? String(input) : input;
    if (typeof text !== "string" || !/^[1-9]\d*$/.test(text) || !Number.isSafeInteger(Number(text))) {
      throw new Error("Enter a valid pull request number.");
    }
    return Number(text);
  }
}

function inScope(pull, repository) {
  return pull.state === "open"
    && pull.base.ref === "dev"
    && pull.base.repo.full_name.toLowerCase() === repository
    && pull.head.repo?.full_name.toLowerCase() === repository
    && typeof pull.head.sha === "string"
    && COMMIT_SHA.test(pull.head.sha);
}

async function publishNativeReview(github, context) {
  const number = pullRequestNumber(context);
  if (!Number.isSafeInteger(number) || number < 1) return;

  const params = context.repo;
  const repository = `${params.owner}/${params.repo}`.toLowerCase();
  const getPull = async () => (await github.rest.pulls.get({ ...params, pull_number: number })).data;
  const pull = await getPull();
  if (!inScope(pull, repository)) return;
  const sha = pull.head.sha;
  const target = { ...params, sha, context: STATUS_CONTEXT };

  // Revoke a past pass before consulting the latest issue comments. Any API
  // error from this point leaves the gate waiting for another trusted event.
  await github.rest.repos.createCommitStatus({ ...target, ...waiting });

  // The REST App and author metadata attest the original commenter. This
  // repository trusts its moderators, who can also edit or delete comments.
  const summaries = [];
  let pages = 0;
  for await (const page of github.paginate.iterator(github.rest.issues.listComments, {
    ...params, issue_number: number, per_page: 100
  })) {
    if (++pages > 20) throw new Error("Too many comments to verify the native review.");
    for (const comment of page.data) {
      if (isSummary(comment)) summaries.push(comment);
    }
    if (summaries.length > 1) break;
  }
  const { state, description, summary } = evaluateReview(summaries, sha);
  if (state === "pending") return;

  if (summary) {
    const { data: latest } = await github.rest.issues.getComment({ ...params, comment_id: summary.id });
    if (!isSummary(latest) || latest.body !== summary.body) return;
  }
  const current = await getPull();
  if (!inScope(current, repository) || current.head.sha !== sha) return;

  const status = { ...target, state, description };
  if (summary && Number.isSafeInteger(summary.id)) {
    status.target_url = `${current.html_url}#issuecomment-${summary.id}`;
  }
  await github.rest.repos.createCommitStatus(status);
}

module.exports = { publishNativeReview };
