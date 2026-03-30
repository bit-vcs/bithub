#!/usr/bin/env node
/**
 * VRT ワークフロー CLI
 *
 * コーディングエージェントが VRT + Semantic 検証ループを回すための CLI。
 *
 * コマンド:
 *   init      — ベースラインを作成 (初回 or リセット時)
 *   capture   — 現在の状態をスナップショットとして取得
 *   verify    — ベースライン vs スナップショットを検証
 *   approve   — 現在のスナップショットをベースラインに昇格
 *   report    — 直近の検証結果を表示
 *   graph     — 依存グラフを表示
 *   affected  — 変更の影響範囲を表示
 */

import { execSync, ExecSyncOptions } from "node:child_process";
import { resolve, join } from "node:path";
import {
  readFile,
  writeFile,
  readdir,
  mkdir,
  cp,
  rm,
  stat,
} from "node:fs/promises";
import { existsSync } from "node:fs";
import { buildDepGraph, findAffectedComponents, graphStats } from "./dep-graph.ts";
import { extractDiffSemantics, parseDiff, buildIntent } from "./intent.ts";
import { collectScreenshots } from "./playwright-analyzer.ts";
import { compareScreenshots } from "./heatmap.ts";
import { classifyVisualDiff } from "./visual-semantic.ts";
import { diffA11yTrees, parsePlaywrightA11ySnapshot, checkA11yTree } from "./a11y-semantic.ts";
import { crossValidate, crossValidationToQualityChecks } from "./cross-validation.ts";
import { loadExpectation, crossValidateWithExpectation, scoreLoop } from "./expectation.ts";
import { runQualityChecks } from "./quality.ts";
import { runVerificationLoop, generateReport as generateAgentReport } from "./agent.ts";
import type { VrtDiff, A11yDiff, VisualSemanticDiff, UnifiedAgentContext, VrtExpectation, PageExpectation } from "./types.ts";

// ---- Paths ----
// baselines/ と snapshots/ は test-results/ の外に配置 (Playwright が test-results をクリアするため)

const VRT_ROOT = resolve(import.meta.dirname!, "..");
const PROJECT_ROOT = resolve(VRT_ROOT, "..");
const BASELINES_DIR = join(VRT_ROOT, "baselines");
const SNAPSHOTS_DIR = join(VRT_ROOT, "snapshots");
const OUTPUT_DIR = join(VRT_ROOT, "output");
const REPORT_PATH = join(VRT_ROOT, "vrt-report.json");
const EXPECTATION_PATH = join(VRT_ROOT, "expectation.json");

const EXEC_OPTS: ExecSyncOptions = {
  cwd: VRT_ROOT,
  stdio: "inherit",
  env: {
    ...process.env,
    VRT_OUTPUT_DIR: VRT_ROOT,
  },
};

// ---- Commands ----

async function init() {
  console.log("=== VRT Init: Creating baselines ===\n");

  await mkdir(BASELINES_DIR, { recursive: true });

  console.log("Running Playwright to capture baseline screenshots + a11y...");
  try {
    execSync(
      `npx playwright test e2e/vrt-capture.spec.ts --reporter=list`,
      {
        ...EXEC_OPTS,
        env: { ...EXEC_OPTS.env, VRT_MODE: "baseline" },
      }
    );
  } catch (e) {
    // Some tests may fail (e.g. title check) but captures still succeed
    const captured = await listFiles(BASELINES_DIR, ".png");
    if (captured.length === 0) {
      console.error("Playwright capture failed. Is the server running?");
      console.error("Start with: pnpm serve (from project root)");
      process.exit(1);
    }
    console.log("  (some tests had warnings, but captures completed)");
  }

  const files = await listFiles(BASELINES_DIR, ".png");
  const a11yFiles = await listFiles(BASELINES_DIR, ".a11y.json");
  console.log(`\nBaselines created: ${files.length} screenshots, ${a11yFiles.length} a11y trees`);
  console.log(`Stored in: ${BASELINES_DIR}`);
}

async function capture() {
  console.log("=== VRT Capture: Taking snapshots ===\n");

  // Clean previous snapshots
  if (existsSync(SNAPSHOTS_DIR)) {
    await rm(SNAPSHOTS_DIR, { recursive: true });
  }
  await mkdir(SNAPSHOTS_DIR, { recursive: true });

  console.log("Running Playwright to capture current state...");
  try {
    execSync(
      `npx playwright test e2e/vrt-capture.spec.ts --reporter=list`,
      {
        ...EXEC_OPTS,
        env: { ...EXEC_OPTS.env, VRT_MODE: "capture" },
      }
    );
  } catch (e) {
    const captured = await listFiles(SNAPSHOTS_DIR, ".png");
    if (captured.length === 0) {
      console.error("Playwright capture failed. Is the server running?");
      process.exit(1);
    }
    console.log("  (some tests had warnings, but captures completed)");
  }

  const files = await listFiles(SNAPSHOTS_DIR, ".png");
  console.log(`\nSnapshots captured: ${files.length} screenshots`);
}

async function verify() {
  console.log("=== VRT Verify: Running verification pipeline ===\n");

  if (!existsSync(BASELINES_DIR)) {
    console.error("No baselines found. Run `vrt init` first.");
    process.exit(1);
  }
  if (!existsSync(SNAPSHOTS_DIR)) {
    console.error("No snapshots found. Run `vrt capture` first.");
    process.exit(1);
  }

  await mkdir(OUTPUT_DIR, { recursive: true });

  // ---- Track 1: Intent ----
  console.log("[Track 1] Extracting change intent...");
  let intent;
  try {
    const semantics = await extractDiffSemantics(PROJECT_ROOT);
    intent = semantics.intent;
    console.log(`  Intent: ${intent.summary} (${intent.changeType})`);
  } catch {
    console.log("  (no git diff available, using unknown intent)");
    intent = {
      summary: "unknown change",
      changeType: "unknown" as const,
      expectedVisualChanges: [],
      expectedA11yChanges: [],
      affectedComponents: [],
    };
  }

  // ---- Track 1: Dep graph ----
  console.log("[Track 1] Building dependency graph...");
  let affected;
  try {
    const graph = await buildDepGraph(PROJECT_ROOT, { languages: ["typescript", "moonbit"] });
    const stats = graphStats(graph);
    console.log(`  ${stats.totalFiles} files, ${stats.components} components`);
    const changed = intent.affectedComponents;
    affected = findAffectedComponents(graph, changed);
    console.log(`  ${affected.length} components affected`);
  } catch {
    console.log("  (dep graph skipped)");
    affected = [];
  }

  // ---- Track 2: Visual diff ----
  console.log("[Track 2] Comparing screenshots...");
  const baselineFiles = await listFiles(BASELINES_DIR, ".png");
  const vrtDiffs: VrtDiff[] = [];

  for (const baseFile of baselineFiles) {
    const name = baseFile.replace(/\.png$/, "");
    const snapFile = join(SNAPSHOTS_DIR, `${name}.png`);
    if (!existsSync(snapFile)) {
      console.log(`  MISSING: ${name} (no snapshot)`);
      continue;
    }

    const snapshot = {
      testId: name,
      testTitle: name,
      projectName: "vrt",
      screenshotPath: snapFile,
      baselinePath: join(BASELINES_DIR, baseFile),
      status: "changed" as const,
    };

    const diff = await compareScreenshots(snapshot, { outputDir: OUTPUT_DIR });
    if (diff && diff.diffPixels > 0) {
      vrtDiffs.push(diff);
      console.log(
        `  CHANGED: ${name} — ${(diff.diffRatio * 100).toFixed(2)}% (${diff.regions.length} region(s))`
      );
    } else {
      console.log(`  OK: ${name}`);
    }
  }

  // ---- Track 3: A11y diff ----
  console.log("[Track 3] Comparing a11y trees...");
  const a11yDiffs: A11yDiff[] = [];
  const baseA11yFiles = await listFiles(BASELINES_DIR, ".a11y.json");

  for (const baseFile of baseA11yFiles) {
    const name = baseFile.replace(/\.a11y\.json$/, "");
    const snapA11yFile = join(SNAPSHOTS_DIR, `${name}.a11y.json`);
    if (!existsSync(snapA11yFile)) continue;

    try {
      const baseRaw = JSON.parse(await readFile(join(BASELINES_DIR, baseFile), "utf-8"));
      const snapRaw = JSON.parse(await readFile(snapA11yFile, "utf-8"));

      if (!baseRaw || !snapRaw) continue;

      const baseSnap = parsePlaywrightA11ySnapshot(name, name, baseRaw);
      const snapSnap = parsePlaywrightA11ySnapshot(name, name, snapRaw);
      const diff = diffA11yTrees(baseSnap, snapSnap);

      if (diff.changes.length > 0) {
        a11yDiffs.push(diff);
        const emoji = diff.hasRegression ? "NG" : "~~";
        console.log(
          `  [${emoji}] ${name}: +${diff.stats.added}/-${diff.stats.removed}/~${diff.stats.modified}`
        );
      } else {
        console.log(`  OK: ${name}`);
      }

      // A11y quality check on current snapshot
      const issues = checkA11yTree(snapSnap.tree);
      if (issues.length > 0) {
        console.log(`  A11Y ISSUES in ${name}:`);
        for (const issue of issues) {
          console.log(`    [${issue.severity}] ${issue.rule}: ${issue.message}`);
        }
      }
    } catch (err) {
      console.log(`  SKIP: ${name} (parse error)`);
    }
  }

  // ---- Load Expectations (if available) ----
  let expectations: VrtExpectation | undefined;
  if (existsSync(EXPECTATION_PATH)) {
    expectations = await loadExpectation(EXPECTATION_PATH);
    console.log(`\n[Expectations] Loaded: "${expectations.description}"`);
    console.log(`  ${expectations.pages.length} page(s) with expectations`);
    if (expectations.intent) {
      // partial intent をマージ (description → summary のフォールバック含む)
      intent = {
        ...intent,
        ...expectations.intent,
        summary: expectations.intent.summary ?? expectations.description,
        expectedA11yChanges: expectations.intent.expectedA11yChanges ?? intent.expectedA11yChanges,
        expectedVisualChanges: expectations.intent.expectedVisualChanges ?? intent.expectedVisualChanges,
        affectedComponents: expectations.intent.affectedComponents ?? intent.affectedComponents,
        changeType: expectations.intent.changeType ?? intent.changeType,
      };
      console.log(`  Intent: ${intent.summary} (${intent.changeType})`);
    }
  }

  // ---- Cross-Validation ----
  console.log("\n[Cross-Validation] Visual x A11y x Intent...");
  const visualSemanticDiffs: VisualSemanticDiff[] = vrtDiffs.map(classifyVisualDiff);

  // Collect all testIds (from diffs + expectations)
  const allTestIds = new Set([
    ...vrtDiffs.map((d) => d.snapshot.testId),
    ...a11yDiffs.map((d) => d.testId),
    ...(expectations?.pages.map((p) => p.testId) ?? []),
  ]);

  const crossValidations = [...allTestIds].map((testId) => {
    const visDiff = visualSemanticDiffs.find((d) => d.testId === testId);
    const a11yDiff = a11yDiffs.find((d) => d.testId === testId);
    const pageExp = expectations?.pages.find((p) => p.testId === testId);

    if (pageExp) {
      return crossValidateWithExpectation(testId, pageExp, visDiff, a11yDiff, intent);
    }
    return crossValidate(testId, visDiff, a11yDiff, intent);
  });

  for (const cv of crossValidations) {
    const icon = cv.recommendation === "approve" ? "OK"
      : cv.recommendation === "reject" ? "NG" : "??";
    console.log(`  [${icon}] ${cv.testId}: ${cv.reasoning}`);
  }

  // ---- Quality + Verdicts ----
  console.log("\n[Verdict] Final verification...");
  const snapshots = vrtDiffs.map((d) => d.snapshot);

  // Expectations で approved された regression は quality error から除外
  const approvedTestIds = new Set(
    crossValidations.filter((cv) => cv.recommendation === "approve").map((cv) => cv.testId)
  );
  const filteredCrossValidations = crossValidations.map((cv) => {
    if (approvedTestIds.has(cv.testId) && cv.a11yDiff?.hasRegression) {
      // Expected regression が承認された → hasRegression を無効化してチェックに渡す
      return { ...cv, a11yDiff: { ...cv.a11yDiff, hasRegression: false } };
    }
    return cv;
  });

  const unresolvedSnapshots = snapshots.filter((s) => !approvedTestIds.has(s.testId));
  const unresolvedDiffs = vrtDiffs.filter((d) => !approvedTestIds.has(d.snapshot.testId));
  const qualityChecks = [
    ...(await runQualityChecks(unresolvedSnapshots, unresolvedDiffs)),
    ...crossValidationToQualityChecks(filteredCrossValidations),
  ];

  // Expectation で approved 済みの diff は agent loop から除外
  const unresolved = vrtDiffs.filter((d) => !approvedTestIds.has(d.snapshot.testId));
  const agentResult = await runVerificationLoop(unresolved, intent, qualityChecks);

  const ctx: UnifiedAgentContext = {
    intent,
    vrtDiffs,
    a11yDiffs,
    visualSemanticDiffs,
    crossValidations,
    verdicts: agentResult.verdicts,
    qualityChecks,
  };

  // Save report
  await writeFile(REPORT_PATH, JSON.stringify(ctx, null, 2));

  // Print summary
  const approved = agentResult.verdicts.filter((v) => v.decision === "approve").length;
  const rejected = agentResult.verdicts.filter((v) => v.decision === "reject").length;
  const escalated = agentResult.verdicts.filter((v) => v.decision === "escalate").length;
  const failedQuality = qualityChecks.filter((c) => !c.passed && c.severity === "error").length;

  // Score
  const score = scoreLoop(ctx, expectations, {
    fixSteps: 1, // will be tracked across iterations
    tokenUsage: 0, // placeholder — real value from agent metadata
    startTime: 0,
    endTime: Date.now(),
  });

  console.log("\n========================================");
  console.log("  VRT + Semantic Verification Summary");
  console.log("========================================");
  console.log(`  Visual diffs:    ${vrtDiffs.length}`);
  console.log(`  A11y diffs:      ${a11yDiffs.length}`);
  console.log(`  Approved:        ${approved}`);
  console.log(`  Rejected:        ${rejected}`);
  console.log(`  Escalated:       ${escalated}`);
  console.log(`  Quality errors:  ${failedQuality}`);
  console.log("----------------------------------------");
  console.log("  Scores:");
  for (const d of score.details) {
    console.log(`    ${d.category.padEnd(14)} ${d.score}/${d.maxScore}  ${d.reasoning}`);
  }
  console.log("========================================");

  if (rejected > 0 || failedQuality > 0) {
    console.log("\nFAILED — Fix the issues and run `vrt capture && vrt verify` again.");
    console.log("Details: " + REPORT_PATH);
    process.exit(1);
  } else if (escalated > 0) {
    console.log("\nWARNING — Some changes need review. Run `vrt report` for details.");
    console.log("If changes are intentional, run `vrt approve` to update baselines.");
    process.exit(0);
  } else if (vrtDiffs.length === 0 && a11yDiffs.length === 0) {
    console.log("\nPASS — No visual or semantic changes detected.");
    process.exit(0);
  } else {
    console.log("\nPASS — All changes approved.");
    console.log("Run `vrt approve` to update baselines.");
    process.exit(0);
  }
}

async function approve() {
  console.log("=== VRT Approve: Updating baselines ===\n");

  if (!existsSync(SNAPSHOTS_DIR)) {
    console.error("No snapshots found. Run `vrt capture` first.");
    process.exit(1);
  }

  // Copy snapshots → baselines
  if (existsSync(BASELINES_DIR)) {
    await rm(BASELINES_DIR, { recursive: true });
  }
  await cp(SNAPSHOTS_DIR, BASELINES_DIR, { recursive: true });

  const files = await listFiles(BASELINES_DIR, ".png");
  console.log(`Baselines updated: ${files.length} screenshots`);
  console.log("New baselines stored in: " + BASELINES_DIR);
}

async function report() {
  if (!existsSync(REPORT_PATH)) {
    console.error("No report found. Run `vrt verify` first.");
    process.exit(1);
  }

  const raw = await readFile(REPORT_PATH, "utf-8");
  const ctx: UnifiedAgentContext = JSON.parse(raw);

  // Rebuild human-readable report
  console.log("# VRT + Semantic Verification Report\n");
  console.log(`Intent: ${ctx.intent.summary} (${ctx.intent.changeType})\n`);

  if (ctx.crossValidations.length > 0) {
    console.log("## Cross-Validation Results");
    for (const cv of ctx.crossValidations) {
      console.log(`  [${cv.recommendation.toUpperCase()}] ${cv.testId}`);
      console.log(`    ${cv.reasoning}\n`);
    }
  }

  const failed = ctx.qualityChecks.filter((c) => !c.passed);
  if (failed.length > 0) {
    console.log("## Quality Issues");
    for (const c of failed) {
      console.log(`  [${c.severity}] ${c.check}: ${c.details}`);
    }
    console.log();
  }

  if (ctx.verdicts.length > 0) {
    console.log("## Verdicts");
    for (const v of ctx.verdicts) {
      console.log(`  [${v.decision.toUpperCase()}] ${v.snapshotId}`);
      console.log(`    ${v.reasoning}`);
      console.log(`    confidence: ${(v.confidence * 100).toFixed(0)}%\n`);
    }
  }
}

async function graph() {
  console.log("=== Dependency Graph ===\n");
  const g = await buildDepGraph(PROJECT_ROOT, {
    languages: ["typescript", "moonbit"],
  });
  const s = graphStats(g);
  console.log(`Files: ${s.totalFiles}  Edges: ${s.totalEdges}  Components: ${s.components}`);
  console.log(`Languages: ${JSON.stringify(s.byLanguage)}\n`);

  console.log("Components:");
  for (const node of g.nodes.values()) {
    if (node.isComponent) {
      console.log(`  ${node.id}`);
    }
  }
}

async function affectedCmd() {
  console.log("=== Affected Components ===\n");
  const g = await buildDepGraph(PROJECT_ROOT, {
    languages: ["typescript", "moonbit"],
  });

  let changedFiles: string[];
  try {
    const diff = execSync("git diff --name-only HEAD", {
      cwd: PROJECT_ROOT,
      encoding: "utf-8",
    });
    changedFiles = diff.trim().split("\n").filter(Boolean);
  } catch {
    console.log("(no git changes)");
    return;
  }

  console.log("Changed files:");
  for (const f of changedFiles) console.log(`  ${f}`);
  console.log();

  const affected = findAffectedComponents(g, changedFiles);
  if (affected.length === 0) {
    console.log("No components affected.");
    return;
  }

  console.log("Affected components:");
  for (const a of affected) {
    console.log(`  [depth=${a.depth}] ${a.node.id}`);
    console.log(`    changed deps: ${a.changedDependencies.join(", ")}`);
  }
}

// ---- Helpers ----

async function listFiles(dir: string, suffix: string): Promise<string[]> {
  try {
    const entries = await readdir(dir);
    return entries.filter((e) => e.endsWith(suffix));
  } catch {
    return [];
  }
}

// ---- Main ----

const command = process.argv[2];

const commands: Record<string, () => Promise<void>> = {
  init,
  capture,
  verify,
  approve,
  report,
  graph,
  affected: affectedCmd,
};

const handler = commands[command];
if (handler) {
  handler().catch((err) => {
    console.error(err);
    process.exit(1);
  });
} else {
  console.log(`vrt — Visual Regression + Semantic Testing CLI

Usage: tsx vrt/src/vrt-cli.ts <command>

Commands:
  init       Create baseline screenshots + a11y trees (requires running server)
  capture    Take current snapshots (requires running server)
  verify     Compare snapshots against baselines, run verification pipeline
  approve    Promote current snapshots to new baselines
  report     Show last verification report
  graph      Display dependency graph
  affected   Show components affected by current changes

Workflow for coding agents:
  1. vrt init            — One-time baseline setup
  2. (make code changes)
  3. vrt capture         — Snapshot current state
  4. vrt verify          — Check for regressions
  5. (fix if needed, repeat 3-4)
  6. vrt approve         — Accept changes as new baseline
`);
}
