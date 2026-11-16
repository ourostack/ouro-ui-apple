// The accessibility pass's VoiceOver walk (.github/workflows/accessibility-pass.yml), on a throwaway macOS runner only:
// Guidepup's setup rewrites VoiceOver's and TCC's settings. It opens each page of the macOS gallery, has VoiceOver read
// it from its first item to its last, going into each group and scroll area, and reports what a VoiceOver user would
// trip on: a control or image spoken with no name, "unlabeled", or a symbol's raw name read out ("chevron.down").
//
//   node walk.mjs "<path to HX Gallery.app>" buttons,badges,… [out.json]
//
// It writes every phrase VoiceOver spoke, by page, to out.json, and a summary to $GITHUB_STEP_SUMMARY. It fails only
// when VoiceOver itself could not run; findings are the pass's inventory, not a gate.
import { voiceOver } from "@guidepup/guidepup";
import { execFileSync } from "node:child_process";
import { appendFileSync, writeFileSync } from "node:fs";

const [appPath, pagesArg = "", out = "voiceover-pass.json"] = process.argv.slice(2);
if (!appPath || !pagesArg) {
  console.error("usage: node walk.mjs <app> <page,page,…> [out.json]");
  process.exit(2);
}
const pages = pagesArg.split(",").filter(Boolean);
const bundle = "bot.ouro.hx.gallery.mac";
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const osascript = (script) => execFileSync("osascript", ["-e", script], { stdio: "ignore" });

// VoiceOver's own hints and announcements, which name nothing on the page.
const HINT = /^(You are (currently )?(on|in) |To (interact|exit|select|click|enter)|Press Control-Option|Out of |Entering |Exiting )/i;
const ROLE = "(button|image|text field|edit text|text|group|check ?box|switch|toggle button|pop up button|menu button|link|heading|slider|radio button|scroll area|menu item)";
// A phrase that is only a role, maybe after a state ("dimmed button", ", button").
const ROLE_ONLY = new RegExp(`^[,\\s]*(dimmed |selected |checked |unchecked |on |off )?${ROLE}[.,]?$`, "i");
const UNLABELED = /\bunlabell?ed\b/i;
// An SF Symbol's name read out: two or more lower-case words joined by dots, not a web address.
const SYMBOL = /(?<![\w/.:@])[a-z]+(?:\.[a-z0-9]+)+(?![\w/])/;
const ADDRESS = /\b[\w-]+\.(bot|com|dev|org|app|io|md|json|swift)\b/i;

/** What a VoiceOver user would trip on in one phrase. */
export function problems(phrase) {
  const text = phrase.trim();
  const found = [];
  if (ROLE_ONLY.test(text)) found.push("a role with no name");
  if (UNLABELED.test(text)) found.push("unlabeled");
  const symbol = text.match(SYMBOL);
  if (symbol && !ADDRESS.test(symbol[0])) found.push(`a symbol's raw name ("${symbol[0]}")`);
  return found;
}

/** Reads the focused window from its first item to its last, going into groups, at most `limit` moves. */
async function readWindow(limit = 150) {
  await voiceOver.perform(voiceOver.keyboardCommands.moveToFirst);
  let last = "";
  let repeats = 0;
  let depth = 0;
  const entered = new Set();
  for (let move = 0; move < limit; move++) {
    const phrase = (await voiceOver.lastSpokenPhrase()).trim();
    if (/\b(scroll area|group)\b/i.test(phrase) && !entered.has(phrase) && depth < 6) {
      entered.add(phrase);
      depth += 1;
      await voiceOver.interact();
      last = "";
      continue;
    }
    if (phrase === last) {
      repeats += 1;
      // The end of a group: VoiceOver repeats its last item. Step out and on, or stop at the window's end.
      if (repeats >= 2) {
        if (depth === 0) break;
        depth -= 1;
        repeats = 0;
        await voiceOver.stopInteracting();
      }
    } else {
      repeats = 0;
    }
    last = phrase;
    await voiceOver.next();
  }
}

const results = [];
await voiceOver.start();
try {
  for (const page of pages) {
    execFileSync("open", ["-n", appPath, "--args", "-page", page, "-theme", "pearl", "-scheme", "light", "-open", "1"]);
    await sleep(4000);
    osascript(`tell application id "${bundle}" to activate`);
    await sleep(1500);
    await voiceOver.clearSpokenPhraseLog();
    let error;
    try {
      await readWindow();
    } catch (caught) {
      error = String(caught?.message ?? caught);
    }
    const phrases = (await voiceOver.spokenPhraseLog()).map((phrase) => phrase.trim()).filter((phrase) => phrase && !HINT.test(phrase));
    const found = [...new Map(phrases.flatMap((phrase) => problems(phrase).map((why) => [`${why}: ${phrase}`, { phrase, why }]))).values()];
    results.push({ page, phrases, found, ...(error ? { error } : {}) });
    console.log(`${page}: ${phrases.length} phrases, ${found.length} findings${error ? `, stopped: ${error}` : ""}`);
    for (const { phrase, why } of found) console.log(`  ${why}: "${phrase}"`);
    try {
      osascript(`tell application id "${bundle}" to quit`);
    } catch {
      // Already gone.
    }
    await sleep(1500);
  }
} finally {
  await voiceOver.stop();
}

writeFileSync(out, `${JSON.stringify(results, null, 2)}\n`);
const summary = process.env.GITHUB_STEP_SUMMARY;
if (summary) {
  const rows = results.flatMap(({ page, found, error }) =>
    found.length ? found.map(({ phrase, why }) => `| ${page} | ${why} | ${phrase.replaceAll("|", "\\|")} |`) : [`| ${page} | ${error ? `stopped: ${error}` : "none"} | |`],
  );
  appendFileSync(summary, ["## VoiceOver on macOS", "", "| Page | Finding | VoiceOver said |", "| --- | --- | --- |", ...rows, ""].join("\n"));
}
if (results.length && results.every(({ phrases }) => phrases.length === 0)) {
  console.error("VoiceOver spoke nothing on any page: the walk did not run.");
  process.exit(1);
}
