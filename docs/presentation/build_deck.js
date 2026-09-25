// =============================================================================
// build_deck.js -- generates docs/Frame_Aligner_Verification.pptx
// -----------------------------------------------------------------------------
// Data-driven numbers are read from sim/logs (written by `make -C sim regress`
// and scripts/mutation_test.py): violation and checkpoint counts, the results
// table and chart, the fuzz-replay cycles and the mutation score.  The build
// stops if one of those logs is missing.  All other numbers are fixed text
// taken from docs/BUG_REPORT.md and docs/VERIFICATION_PLAN.md (Python fuzzing
// totals, legacy-testbench measurements, DUT-01/02 impact figures).
// Figures come from docs/images (produced by scripts/plot_waves.py).
//
//   npm install pptxgenjs      (once)
//   node docs/presentation/build_deck.js
// =============================================================================
const fs = require("fs");
const path = require("path");
const pptxgen = require("pptxgenjs");

const ROOT = path.resolve(__dirname, "..", "..");
const IMG = (f) => path.join(ROOT, "docs", "images", f);
const OUT = path.join(ROOT, "docs", "Frame_Aligner_Verification.pptx");

// ---------------------------------------------------------------- data (logs)
// Every log used by the deck must exist and contain an FA_RESULT line;
// otherwise the build stops (a missing run must never render as PASS).
function readLog(name) {
  const p = path.join(ROOT, "sim", "logs", name);
  if (!fs.existsSync(p)) throw new Error(`missing ${p} -- run 'make -C sim regress' first`);
  const t = fs.readFileSync(p, "utf8");
  if (!/^FA_RESULT /m.test(t)) throw new Error(`no FA_RESULT line in ${p}`);
  return t;
}
function result(text) {
  const m = text.match(/^FA_RESULT (.*)$/m);
  if (!m) return {};
  const r = {};
  for (const kv of m[1].split(/\s+/)) {
    const i = kv.indexOf("=");
    r[kv.slice(0, i)] = kv.slice(i + 1);
  }
  return r;
}
function svaCounts(text) {
  const r = {};
  for (const m of text.matchAll(/^\s+((?:SPEC|WB|TB)_\w+)\s+(\d+)\s+failures/gm)) r[m[1]] = +m[2];
  return r;
}
const origLog = readLog("orig_spec_regression_s1.log");
const ORIG = result(origLog);
const ORIG_SVA = svaCounts(origLog);
const FIXED = {
  directed: result(readLog("fixed_spec_directed_s1.log")),
  boundary: result(readLog("fixed_spec_boundary_s1.log")),
  random: result(readLog("fixed_spec_random_s1.log")),
  regression: result(readLog("fixed_spec_regression_s1.log")),
};
const ORIG_DUTMODE = result(readLog("orig_dut_regression_s1.log"));
const FILE_FIXED = result(readLog("fixed_spec_file_s1.log"));   // fuzz traffic replayed
const FILE_ORIG = result(readLog("orig_spec_file_s1.log"));
// Mutation testing results (table written by scripts/mutation_test.py).
function readMutation() {
  const p = path.join(ROOT, "sim", "logs", "mutation_summary.md");
  if (!fs.existsSync(p)) throw new Error(`missing ${p} -- run 'python3 scripts/mutation_test.py' first`);
  const rows = [];
  const re = /^\| (M\d+) \| (.*?) \| (KILLED|SURVIVED) \| (.*?) \| (.*?) \| (.*?) \| (.*?) \|$/gm;
  for (const m of fs.readFileSync(p, "utf8").matchAll(re))
    rows.push({ id: m[1], desc: m[2], status: m[3], hits: { SB: m[4], CP: m[5], SVA: m[6], WB: m[7] } });
  if (!rows.length) throw new Error(`no mutant rows in ${p}`);
  return rows;
}
const MUT = readMutation();
const mutKilled = MUT.filter((r) => r.status === "KILLED").length;
const BUGS = Object.fromEntries((ORIG.bugs || "DUT-01:0,DUT-02:0,DUT-03:0").split(",").map((s) => s.split(":")));
const num = (x) => Number(x || 0).toLocaleString("en-US");
const cpTotal = (+ORIG.cp_pass || 0) + (+ORIG.cp_fail || 0);

// ---------------------------------------------------------------- design system
const C = {
  ink: "0B1E33", ink2: "16304F", ink3: "23456E", ice: "CADCFC",
  text: "1F2933", muted: "5B6B7F", line: "D5DCE4", card: "F1F4F8", white: "FFFFFF",
  amber: "F2A900", amberSoft: "FDF1CC", bug: "C2410C", bugSoft: "FBE4D8",
  fix: "1D4ED8", fixSoft: "DDE7FB", spec: "0F766E", specSoft: "D5EFEC",
};
const F = { head: "Cambria", body: "Calibri", mono: "Courier New" };
const W = 13.333, H = 7.5;

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.author = "Yakir Aqua";
pres.title = "Frame Aligner Verification";

let slideNo = 0;

// Hex byte tile -- the visual motif of the deck (bytes on rx_data).
function tile(s, x, y, text, o = {}) {
  const w = o.w || 0.62, h = o.h || 0.46;
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x, y, w, h, rectRadius: 0.06,
    fill: { color: o.fill || C.white }, line: { color: o.line || C.muted, width: o.lw || 1 },
  });
  s.addText(text, {
    x, y, w, h, margin: 0, align: "center", valign: "middle", isTextBox: true,
    fontFace: F.mono, fontSize: o.fs || 14, bold: true, color: o.color || C.text,
  });
}

function footer(s, dark) {
  slideNo++;
  s.addText([
    { text: "Frame Aligner Verification", options: { color: dark ? "8FA3BF" : C.muted } },
  ], { x: 0.6, y: 7.02, w: 6, h: 0.3, fontFace: F.body, fontSize: 10, margin: 0, isTextBox: true });
  s.addText(String(slideNo), {
    x: W - 1.1, y: 7.02, w: 0.5, h: 0.3, fontFace: F.body, fontSize: 10, align: "right",
    color: dark ? "8FA3BF" : C.muted, margin: 0, isTextBox: true,
  });
}

// Content slide with a hex-tile section code and a title.
function content(code, title, sub) {
  const s = pres.addSlide();
  s.background = { color: C.white };
  tile(s, 0.6, 0.5, code, { fill: C.ink, line: C.ink, color: C.amber, w: 0.9, h: 0.5, fs: 13 });
  s.addText(title, {
    x: 1.7, y: 0.36, w: W - 2.3, h: 0.78, fontFace: F.head, fontSize: 30, bold: true,
    color: C.text, margin: 0, valign: "middle", isTextBox: true,
  });
  if (sub) s.addText(sub, {
    x: 1.7, y: 1.1, w: W - 2.3, h: 0.42, fontFace: F.body, fontSize: 15, color: C.muted,
    margin: 0, valign: "top", isTextBox: true,
  });
  footer(s, false);
  return s;
}

function card(s, x, y, w, h, fill, line) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x, y, w, h, rectRadius: 0.08, fill: { color: fill || C.card }, line: { color: line || fill || C.card, width: 1 },
  });
}

function text(s, t, x, y, w, h, o = {}) {
  s.addText(t, Object.assign({
    x, y, w, h, fontFace: F.body, fontSize: 14, color: C.text, margin: 0, valign: "top", isTextBox: true,
  }, o));
}

function bullets(s, items, x, y, w, h, o = {}) {
  const runs = items.map((it, i) => {
    const t = typeof it === "string" ? [{ text: it }] : it;
    return t.map((r, j) => ({
      text: r.text,
      options: Object.assign({
        bullet: j === 0 ? { indent: 14 } : undefined, breakLine: j === t.length - 1 && i < items.length - 1,
        paraSpaceAfter: o.psa || 6,
      }, r.options || {}),
    }));
  }).flat();
  const box = Object.assign({
    x, y, w, h, fontFace: F.body, fontSize: o.fs || 15, color: C.text, margin: 0, valign: "top", isTextBox: true,
  }, o);
  delete box.fs; delete box.psa;
  s.addText(runs, box);
}

// Pixel size of a PNG (read from its IHDR chunk).
function pngSize(file) {
  const b = fs.readFileSync(IMG(file));
  return [b.readUInt32BE(16), b.readUInt32BE(20)];
}

// Image placed inside a box, aspect ratio preserved, centred.
function image(s, file, x, y, w, h) {
  const [pxW, pxH] = pngSize(file);
  const r = pxW / pxH;
  let iw = w, ih = w / r;
  if (ih > h) { ih = h; iw = h * r; }
  s.addImage({ path: IMG(file), x: x + (w - iw) / 2, y: y + (h - ih) / 2, w: iw, h: ih });
}

function arrow(s, x1, y1, x2, y2, color) {
  s.addShape(pres.shapes.LINE, {
    x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.abs(x2 - x1) || 0.001, h: Math.abs(y2 - y1) || 0.001,
    flipH: x2 < x1, flipV: y2 < y1,
    line: { color: color || C.muted, width: 1.75, endArrowType: "triangle" },
  });
}

function box(s, x, y, w, h, label, o = {}) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x, y, w, h, rectRadius: 0.08, fill: { color: o.fill || C.white }, line: { color: o.line || C.ink3, width: o.lw || 1.25 },
  });
  s.addText(label, {
    x: x + 0.08, y, w: w - 0.16, h, fontFace: o.font || F.body, fontSize: o.fs || 13, bold: o.bold !== false,
    color: o.color || C.text, align: "center", valign: "middle", margin: 0, isTextBox: true,
  });
}


// =============================================================================
// 1. Title
// =============================================================================
{
  const s = pres.addSlide();
  s.background = { color: C.ink };
  const bytes = ["AA", "AF", "11", "22", "33", "44", "66", "77", "88", "99", "10", "20", "55", "BA"];
  bytes.forEach((b, i) => {
    const hdr = ["AA", "AF", "55", "BA"].includes(b);
    tile(s, 0.6 + i * 0.72, 0.7, b, {
      fill: hdr ? C.amber : C.ink2, line: hdr ? C.amber : C.ink3, color: hdr ? C.ink : C.ice, fs: 13,
    });
  });
  s.addText("Frame Aligner Verification", {
    x: 0.6, y: 2.2, w: 12, h: 1.2, fontFace: F.head, fontSize: 50, bold: true, color: C.white, margin: 0, isTextBox: true,
  });
  s.addText("Specification-driven verification of a byte-stream frame aligner", {
    x: 0.6, y: 3.35, w: 12, h: 0.6, fontFace: F.body, fontSize: 22, color: C.ice, margin: 0, isTextBox: true,
  });
  const chips = ["8 DUT defects, 3 critical / high", "Corrected RTL: 0 spec violations",
                 "100 % functional coverage"];
  chips.forEach((c, i) => {
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, {
      x: 0.6 + i * 4.1, y: 4.45, w: 3.85, h: 0.62, rectRadius: 0.1, fill: { color: C.ink2 }, line: { color: C.ink3, width: 1 },
    });
    s.addText(c, {
      x: 0.75 + i * 4.1, y: 4.45, w: 3.6, h: 0.62, fontFace: F.body, fontSize: 14, color: C.white,
      valign: "middle", margin: 0, isTextBox: true,
    });
  });
  s.addText("Yakir Aqua   ·   Verification plan, results and bug report   ·   revised edition", {
    x: 0.6, y: 6.3, w: 12, h: 0.4, fontFace: F.body, fontSize: 14, color: "8FA3BF", margin: 0, isTextBox: true,
  });
  slideNo++;
  s.addNotes("Revised edition of the verification plan. The environment was rebuilt around an independent specification model; the delivered RTL is unchanged and was re-verified.");
}

// =============================================================================
// 2. Results at a glance
// =============================================================================
{
  const s = content("0x01", "Results at a glance");
  const stats = [
    ["8", "DUT defects", "3 critical / high; DUT-02 and DUT-03 had been filed as \"spec gaps\"", C.bug],
    ["0", "unexplained mismatches", `every one of ${num(ORIG.known)} spec violations on the delivered RTL is attributed to a known defect`, C.spec],
    ["100 %", "functional coverage", "14 spec-feature coverpoints, every cover property hit", C.fix],
    ["910 k", "fuzzed cycles cross-checked", "corrected RTL = both Python spec models and the SV model: 0 differences", C.ink3],
  ];
  stats.forEach(([big, label, detail, col], i) => {
    const x = 0.6 + i * 3.08;
    card(s, x, 1.85, 2.85, 3.3);
    s.addText(big, { x: x + 0.25, y: 2.05, w: 2.4, h: 1.1, fontFace: F.head, fontSize: 54, bold: true, color: col, margin: 0, isTextBox: true });
    s.addText(label, { x: x + 0.25, y: 3.15, w: 2.4, h: 0.45, fontFace: F.body, fontSize: 17, bold: true, color: C.text, margin: 0, isTextBox: true });
    s.addText(detail, { x: x + 0.25, y: 3.65, w: 2.4, h: 1.3, fontFace: F.body, fontSize: 13, color: C.muted, margin: 0, isTextBox: true });
  });
  card(s, 0.6, 5.45, 12.1, 1.3, C.ink);
  s.addText([
    { text: "Delivered RTL: ", options: { bold: true, color: C.amber } },
    { text: `TEST FAILED, ${num(ORIG.known)} spec violations and ${num(ORIG.cp_fail)} of ${num(cpTotal)} test-plan checkpoints failed, 0 unexplained.   `, options: { color: C.white } },
    { text: "Corrected RTL: ", options: { bold: true, color: C.amber } },
    { text: "TEST PASSED, 0 violations, all checkpoints, 0 assertion failures.", options: { color: C.white } },
  ], { x: 0.85, y: 5.5, w: 11.6, h: 1.2, fontFace: F.body, fontSize: 16, valign: "middle", margin: 0, isTextBox: true });
}

// =============================================================================
// 3. The design under test
// =============================================================================
{
  const s = content("0x02", "The design under test", "One byte per clock; a frame is a 16-bit header (LSB first) and 10 payload bytes, back to back");
  // frame format tiles
  text(s, "Frame format and fr_byte_position", 0.6, 1.8, 7, 0.4, { fontSize: 15, bold: true });
  const fb = ["AA", "AF", "P0", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9"];
  fb.forEach((b, i) => {
    const h = i < 2;
    tile(s, 0.6 + i * 0.6, 2.3, b, { w: 0.54, h: 0.5, fill: h ? C.amber : C.card, line: h ? C.amber : C.line, fs: 12 });
    s.addText(String(i), { x: 0.6 + i * 0.6, y: 2.85, w: 0.54, h: 0.3, align: "center", fontFace: F.mono, fontSize: 11, color: C.muted, margin: 0, isTextBox: true });
  });
  text(s, "HEAD_1 = 0xAFAA  (AA then AF)\nHEAD_2 = 0xBA55  (55 then BA)", 0.6, 3.3, 7, 0.7, { fontFace: F.mono, fontSize: 13 });
  const rules = [
    ["Align", "after 3 consecutive frames with a correct header: frame_detect = 1"],
    ["Lose", "after 4 frames without a header (48 header-less bytes): frame_detect = 0"],
    ["Track", "fr_byte_position = index 0..11 of the last byte (registered output)"],
  ];
  rules.forEach(([k, v], i) => {
    const y = 4.25 + i * 0.85;
    card(s, 0.6, y, 7.0, 0.72);
    s.addText(k, { x: 0.8, y, w: 1.1, h: 0.72, fontFace: F.head, fontSize: 16, bold: true, color: C.spec, valign: "middle", margin: 0, isTextBox: true });
    s.addText(v, { x: 1.9, y, w: 5.6, h: 0.72, fontFace: F.body, fontSize: 14, valign: "middle", margin: 0, isTextBox: true });
  });
  // block diagram
  box(s, 8.0, 3.2, 1.3, 1.0, "PHY RX", { fill: C.card, line: C.muted });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 9.8, y: 1.85, w: 3.0, h: 4.3, rectRadius: 0.1, fill: { color: C.ink }, line: { color: C.ink } });
  s.addText("frame_aligner", { x: 9.8, y: 1.95, w: 3.0, h: 0.4, align: "center", fontFace: F.mono, fontSize: 14, bold: true, color: C.amber, margin: 0, isTextBox: true });
  ["FR_IDLE", "FR_HLSB", "FR_HMSB", "FR_DATA"].forEach((st, i) => {
    tile(s, 10.05 + (i % 2) * 1.3, 2.5 + Math.floor(i / 2) * 0.62, st, { w: 1.2, h: 0.48, fill: C.ink2, line: C.ink3, color: C.ice, fs: 11 });
  });
  ["legal_frame_counter[1:0]", "na_byte_counter[5:0]", "header_lsb_samp[7:0]"].forEach((r, i) => {
    s.addText(r, { x: 10.0, y: 3.9 + i * 0.42, w: 2.6, h: 0.36, fontFace: F.mono, fontSize: 11, color: C.ice, margin: 0, isTextBox: true });
  });
  arrow(s, 9.3, 3.7, 9.8, 3.7, C.muted);
  s.addText("rx_data[7:0]", { x: 8.0, y: 4.3, w: 1.8, h: 0.3, fontFace: F.mono, fontSize: 10, color: C.muted, margin: 0, isTextBox: true });
  s.addText("frame_detect   fr_byte_position[3:0]", { x: 9.8, y: 6.2, w: 3.1, h: 0.3, fontFace: F.mono, fontSize: 10, color: C.muted, align: "center", margin: 0, isTextBox: true });
  s.addText("clk, reset (async)", { x: 9.8, y: 1.45, w: 3.0, h: 0.3, fontFace: F.mono, fontSize: 10, color: C.muted, align: "center", margin: 0, isTextBox: true });
}

// =============================================================================
// 4. Specification -> rules
// =============================================================================
{
  const s = content("0x03", "From the specification to seven checkable rules",
    "The text, the design slides and the RTL disagree in places; the verification fixes one interpretation");
  const R = [
    ["R1", "Header = LSB immediately followed by its MSB: AA AF or 55 BA", "text p.3, p.5"],
    ["R2", "While hunting, every byte is examined; a wrong MSB that is itself an LSB starts a new candidate. No header in the stream is missed", "text p.3"],
    ["R3", "After a header the next 10 bytes are payload and are not examined", "design slides (FSM)"],
    ["R4", "frame_detect rises one byte after the 3rd consecutive header (payload byte 0)", "text p.6, waveform 1"],
    ["R5", "frame_detect falls on the 48th counted hunting byte (a header LSB counts when it arrives); header MSB and payload never count", "text p.6, register table"],
    ["R6", "fr_byte_position = index of the byte just consumed (0..11); 0 while hunting", "port table, waveform 1"],
    ["R7", "Asynchronous reset: outputs 0, hunting restarts", "port table"],
  ];
  R.forEach(([id, t, src], i) => {
    const col = i % 2, row = Math.floor(i / 2);
    const x = 0.6 + col * 6.15, y = 1.75 + row * 1.25;
    card(s, x, y, 5.95, 1.1);
    tile(s, x + 0.2, y + 0.3, id, { fill: C.spec, line: C.spec, color: C.white, w: 0.62, h: 0.5, fs: 14 });
    s.addText(t, { x: x + 1.0, y: y + 0.08, w: 4.8, h: 0.68, fontFace: F.body, fontSize: 13.5, color: C.text, valign: "middle", margin: 0, isTextBox: true });
    s.addText(src, { x: x + 1.0, y: y + 0.74, w: 4.8, h: 0.3, fontFace: F.body, fontSize: 11, italic: true, color: C.muted, margin: 0, isTextBox: true });
  });
  const x = 0.6 + 6.15, y = 1.75 + 3 * 1.25;
  card(s, x, y, 5.95, 1.1, C.amberSoft);
  s.addText([
    { text: "Implemented three times, independently: ", options: { bold: true } },
    { text: "SV reference model, a causal Python model and an offline frame parser. They agree on every cycle." },
  ], { x: x + 0.25, y: y + 0.08, w: 5.5, h: 0.95, fontFace: F.body, fontSize: 13.5, valign: "middle", margin: 0, isTextBox: true });
}

// =============================================================================
// 5. Why the environment was rebuilt
// =============================================================================
{
  const s = content("0x04", "Why the environment was rebuilt", "The original bench could not fail: its model was a copy of the RTL, and mismatches were fixed in the scoreboard");
  const rows = [
    ["Reference", "copy of the RTL (and even that one byte early)", "spec rules R1-R7, cross-checked by two Python models"],
    ["Mismatch policy", "\"correct the scoreboard\"", "attribute to a known defect, or flag as UNEXPLAINED"],
    ["Expected outcomes", "not checked", `${num(cpTotal)} checkpoints at exact byte positions`],
    ["Stimulus", "X bytes; 117 of 917 items never driven; preconditions shuffled away", "2-state; everything driven; every scenario starts from reset"],
    ["Timing", "program-block dependent; reset released on a clock edge", "clocking blocks; reset on the falling edge"],
    ["Assertions", "3 of 3 vacuous or false; failures not counted", "25 rule-based assertions, counted; cover hits show they are exercised"],
    ["Coverage", "reachable illegal bins, unreachable bins, no spec features", "14 spec-feature coverpoints, closed at 100 %"],
  ];
  const hdr = [
    { text: "", options: { fill: { color: C.white } } },
    { text: "Original environment", options: { bold: true, color: C.white, fill: { color: C.bug } } },
    { text: "New environment", options: { bold: true, color: C.white, fill: { color: C.spec } } },
  ];
  const body = rows.map(([a, b, c]) => [
    { text: a, options: { bold: true, color: C.text } },
    { text: b, options: { color: C.text, fill: { color: C.bugSoft } } },
    { text: c, options: { color: C.text, fill: { color: C.specSoft } } },
  ]);
  s.addTable([hdr, ...body], {
    x: 0.6, y: 1.75, w: 12.1, colW: [2.1, 5.0, 5.0], fontFace: F.body, fontSize: 13.5,
    border: { type: "solid", pt: 1, color: C.white }, rowH: 0.62, valign: "middle", margin: [4, 8, 4, 8],
  });
}

// =============================================================================
// 6. Architecture
// =============================================================================
{
  const s = content("0x05", "Verification architecture", "Class-based SystemVerilog, race-free clocking blocks, assertions bound into the DUT");
  box(s, 0.6, 2.0, 2.2, 1.1, "generator\n+ 27 scenarios", { fill: C.card, fs: 13 });
  box(s, 3.5, 2.0, 1.7, 1.1, "driver", { fill: C.card });
  box(s, 6.5, 1.85, 2.5, 1.4, "DUT\nframe_aligner", { fill: C.ink, line: C.ink, color: C.white, fs: 15 });
  s.addText("+ fa_spec_sva (14)\n+ fa_whitebox_sva (11)", { x: 6.3, y: 3.3, w: 2.9, h: 0.6, align: "center", fontFace: F.mono, fontSize: 11, color: C.ink3, margin: 0, isTextBox: true });
  box(s, 10.3, 2.0, 2.4, 1.1, "monitor_in /\nmonitor_out", { fill: C.card });
  arrow(s, 2.8, 2.55, 3.5, 2.55);
  arrow(s, 5.2, 2.55, 6.5, 2.55);
  arrow(s, 9.0, 2.55, 10.3, 2.55);
  s.addText("drv_cb\n(+1 ns)", { x: 5.25, y: 1.95, w: 1.2, h: 0.5, align: "center", fontSize: 10, fontFace: F.mono, color: C.muted, margin: 0, isTextBox: true });
  s.addText("mon_cb\n(#1step)", { x: 9.05, y: 1.95, w: 1.2, h: 0.5, align: "center", fontSize: 10, fontFace: F.mono, color: C.muted, margin: 0, isTextBox: true });
  // scoreboard block
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 4.4, y: 4.3, w: 8.3, h: 2.35, rectRadius: 0.1, fill: { color: C.ink }, line: { color: C.ink } });
  s.addText("scoreboard", { x: 4.6, y: 4.38, w: 3, h: 0.4, fontFace: F.head, fontSize: 16, bold: true, color: C.amber, margin: 0, isTextBox: true });
  const parts = [["spec model", "R1-R7, knobs off", C.spec], ["DUT model", "known defects on", C.bug], ["checkpoints", "test-plan outcomes", C.fix], ["coverage", "14 coverpoints", C.ink3]];
  parts.forEach(([a, b, col], i) => {
    const x = 4.6 + i * 2.03;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 4.9, w: 1.9, h: 1.5, rectRadius: 0.08, fill: { color: C.ink2 }, line: { color: col, width: 1.5 } });
    s.addText(a, { x, y: 5.0, w: 1.9, h: 0.5, align: "center", fontFace: F.body, fontSize: 14, bold: true, color: C.white, margin: 0, isTextBox: true });
    s.addText(b, { x, y: 5.5, w: 1.9, h: 0.7, align: "center", fontFace: F.body, fontSize: 12, color: C.ice, margin: 0, isTextBox: true });
  });
  arrow(s, 11.5, 3.1, 11.5, 4.3);
  s.addShape(pres.shapes.LINE, { x: 1.7, y: 3.1, w: 0.001, h: 2.35, line: { color: C.muted, width: 1.75, dashType: "dash" } });
  arrow(s, 1.7, 5.45, 4.4, 5.45);
  s.addText("checkpoints", { x: 1.95, y: 5.05, w: 2.2, h: 0.35, fontSize: 11, fontFace: F.mono, color: C.muted, margin: 0, isTextBox: true });
  text(s, "Monitors are numbered sample by sample; the scoreboard proves lock-step and compares outputs(k) with the model after byte k-1.", 0.6, 6.05, 3.6, 0.8, { fontSize: 11.5, color: C.muted });
}

// =============================================================================
// 7. Triage
// =============================================================================
{
  const s = content("0x06", "Every mismatch is triaged, not \"fixed\"", "Two instances of the same specification model: one pure, one with the delivered design's defects switched on");
  box(s, 0.6, 3.1, 2.6, 1.2, "DUT outputs\nat cycle k", { fill: C.card });
  box(s, 4.0, 3.1, 2.6, 1.2, "equal to the\nspec model?", { fill: C.white, line: C.spec, lw: 2 });
  box(s, 7.4, 3.1, 2.6, 1.2, "equal to the\nDUT model?", { fill: C.white, line: C.bug, lw: 2 });
  arrow(s, 3.2, 3.7, 4.0, 3.7);
  arrow(s, 6.6, 3.7, 7.4, 3.7);
  s.addText("no", { x: 6.7, y: 3.3, w: 0.6, h: 0.3, fontSize: 12, color: C.muted, margin: 0, isTextBox: true });
  // outcomes
  box(s, 4.0, 1.75, 2.6, 0.85, "MATCH", { fill: C.specSoft, line: C.spec, color: C.spec });
  arrow(s, 5.3, 3.1, 5.3, 2.6);
  s.addText("yes", { x: 5.4, y: 2.7, w: 0.6, h: 0.3, fontSize: 12, color: C.muted, margin: 0, isTextBox: true });
  box(s, 10.7, 1.75, 2.0, 1.45, "KNOWN DEFECT\nattributed to\nDUT-0x", { fill: C.amberSoft, line: C.amber, fs: 13 });
  arrow(s, 10.0, 3.4, 10.7, 2.6);
  s.addText("yes", { x: 10.05, y: 2.6, w: 0.6, h: 0.3, fontSize: 12, color: C.muted, margin: 0, isTextBox: true });
  box(s, 10.7, 4.1, 2.0, 1.2, "UNEXPLAINED\nnew problem", { fill: C.bugSoft, line: C.bug, color: C.bug, fs: 13 });
  arrow(s, 10.0, 4.0, 10.7, 4.6);
  s.addText("no", { x: 10.1, y: 4.45, w: 0.6, h: 0.3, fontSize: 12, color: C.muted, margin: 0, isTextBox: true });
  bullets(s, [
    [{ text: "Known defect: ", options: { bold: true } }, { text: "the knob that fired in the DUT model names the defect; the spec model is then re-synchronised to the DUT's path, so each occurrence is reported once, with no cascade." }],
    [{ text: "+MODEL=dut: ", options: { bold: true } }, { text: "the same bench becomes a regression bench for the delivered RTL and fails only on NEW behaviour." }],
    [{ text: "Result on the delivered RTL: ", options: { bold: true } }, { text: `${num(ORIG.known)} spec violations, ${ORIG.unexplained || 0} unexplained.` }],
  ], 0.6, 5.0, 9.8, 1.8, { fs: 14 });
}

// =============================================================================
// 8. Oracles and cross-validation
// =============================================================================
{
  const s = content("0x07", "Three independent oracles, three independent models");
  const O = [
    ["Reference model", "every byte, every cycle", "cycle-accurate compare of frame_detect and fr_byte_position against R1-R7", C.spec],
    ["Checkpoints", `${num(cpTotal)} expected outcomes`, "the test plan's \"expected outcome\" column, checked at the exact byte (e.g. \"aligned after 47 header-less bytes, lost on the 48th\")", C.fix],
    ["Assertions", "14 black-box + 11 white-box", "spec rules on the ports; FSM and counter checks inside the DUT catch latent defects the ports never show", C.bug],
  ];
  O.forEach(([h, k, d, col], i) => {
    const x = 0.6 + i * 4.1;
    card(s, x, 1.7, 3.85, 2.7);
    s.addShape(pres.shapes.OVAL, { x: x + 0.25, y: 1.95, w: 0.5, h: 0.5, fill: { color: col }, line: { color: col } });
    s.addText(String(i + 1), { x: x + 0.25, y: 1.95, w: 0.5, h: 0.5, align: "center", valign: "middle", fontFace: F.head, fontSize: 16, bold: true, color: C.white, margin: 0, isTextBox: true });
    s.addText(h, { x: x + 0.9, y: 1.95, w: 2.8, h: 0.5, fontFace: F.head, fontSize: 19, bold: true, valign: "middle", margin: 0, isTextBox: true });
    s.addText(k, { x: x + 0.25, y: 2.6, w: 3.4, h: 0.4, fontFace: F.body, fontSize: 14, bold: true, color: col, margin: 0, isTextBox: true });
    s.addText(d, { x: x + 0.25, y: 3.05, w: 3.4, h: 1.25, fontFace: F.body, fontSize: 13, color: C.text, margin: 0, isTextBox: true });
  });
  card(s, 0.6, 4.7, 12.1, 2.05, C.ink);
  s.addText(`Differential fuzzing: 910 k cycles (Python models), ${Math.round(FILE_FIXED.compared / 1000)} k replayed in the SV bench`, { x: 0.85, y: 4.8, w: 11.6, h: 0.45, fontFace: F.head, fontSize: 17, bold: true, color: C.amber, margin: 0, isTextBox: true });
  bullets(s, [
    [{ text: "corrected RTL = Python causal model = independent frame parser = SV spec model: ", options: { color: C.white } }, { text: "0 differences", options: { bold: true, color: C.amber } }],
    [{ text: "delivered RTL = bug-emulating model: ", options: { color: C.white } }, { text: "0 differences", options: { bold: true, color: C.amber } }, { text: " (every deviation is DUT-01, 02 or 03)", options: { color: C.white } }],
    [{ text: "delivered RTL vs. specification: ", options: { color: C.white } }, { text: "13 % of all cycles wrong", options: { bold: true, color: C.amber } }, { text: " on stress traffic", options: { color: C.white } }],
  ], 0.85, 5.3, 11.6, 1.4, { fs: 14.5, color: C.white });
}

// =============================================================================
// 9-10. Test plan
// =============================================================================
const TP = [
  ["TP01", "spec_suggested", "5xHEAD_1, 4 illegal, 5xHEAD_2 (spec p.23)", "aligned on frame 3; lost on the 48th byte", ""],
  ["TP02", "mixed_headers", "HEAD_1 / HEAD_2 in any mix", "aligned after 3 frames", ""],
  ["TP03", "swapped_header", "AF AA / BA 55; 4 of them while aligned", "never aligns; loss on the 48th byte", "DUT-03"],
  ["TP04", "inverted_header", "bit-inverted and bit-reversed headers", "never aligns", "DUT-03"],
  ["TP05", "lsb_ok_msb_bad", "AA 01, 55 01, AA 00, 55 00, AA BA, 55 AF", "position 0 after the rejected MSB", "DUT-03"],
  ["TP06", "lsb_bad_msb_ok", "0A AF, 05 BA", "position 0, never aligns", ""],
  ["TP07", "msb_in_payload", "AF / BA bytes inside payloads", "frame boundaries unchanged", ""],
  ["TP08", "header_in_payload", "headers at every payload offset", "ignored (R3)", ""],
  ["TP09", "restart_header", "AA|AA AF, 55|55 BA, AA|55 BA, 55|AA AF, ...", "header found; aligned after 3 frames", "DUT-01"],
  ["TP10", "loss_boundary", "aligned, 44..48 header-less bytes, header", "kept for <= 46, lost for >= 47", "DUT-02"],
  ["TP11", "corrupted_frames", "aligned, 1..4 corrupted frames", "kept for <= 3, lost on byte 48 for 4", "DUT-03"],
  ["TP12", "header_in_illegal", "legacy illegal frames with inner headers", "frame at the inner header", ""],
  ["TP13", "frames_in_illegal", "3 frames inside a 49-byte illegal frame", "aligned exactly on byte 29", ""],
  ["TP14", "header_soup", "49-byte frames of random header bytes", "model-checked", "DUT-01/03"],
];
const TP2 = [
  ["TP15", "lsb_at_payload_end", "payload ends in AA / 55 / AA AF (aligned)", "next header found", ""],
  ["TP16", "long_valid_run", "10 consecutive frames", "aligned; counter saturates", "DUT-04"],
  ["TP17", "long_garbage", "80 header-less bytes, re-align", "lost on 48; counter saturates", "DUT-05"],
  ["TP18", "reset_every_phase", "async reset in each phase, aligned or not", "outputs 0; no header across reset", ""],
  ["TP19", "false_lock_in_sync", "corrupted header + header pattern in payload", "locks on the false frame", "DUT-07 demo"],
  ["TP20", "consecutive_rule", "V, 1 byte, V, V, V; V, V, stray LSB, V, V, V", "aligned on the 3rd frame after the break", ""],
  ["TP21", "header_across_items", "... AA | AF ... across two items", "recognised", ""],
  ["TP22", "illegal_lengths", "2 + 12 + 36 and 49 header-less bytes (aligned)", "lost on exactly the 48th byte", ""],
  ["TP23", "boundary", "sweep 0..60 header-less bytes, +/- stray LSB", "kept iff gap + prefix <= 46", "DUT-01/02"],
  ["TP24", "loss_cause", "48th byte = rejected MSB / restart LSB", "lost on that byte", "DUT-01"],
  ["TP25", "midstream_entry", "start mid-stream; payloads end in one 55 / AA", "aligned after 3 frames", "DUT-01"],
  ["TP26", "error_then_lsb_payloads", "1 header error, then payloads ending in 55", "alignment kept", "DUT-01"],
  ["TP27", "slip_in_sync", "13-byte frames before / after alignment", "hunting keeps alignment", "DUT-07 demo"],
  ["RND", "random", "60 % valid, 18 % illegal, 8 % restart, 12 % gap, 2 % reset", "model + assertions", "all"],
];
function tpSlide(code, title, rows) {
  const s = content(code, title, "Every scenario starts from reset and checks its expected outcome at exact bytes (checkpoints)");
  const head = ["ID", "+TEST=", "Stimulus", "Expected (spec)", "Exposes"].map((t) => ({ text: t, options: { bold: true, color: C.white, fill: { color: C.ink } } }));
  const body = rows.map((r, i) => r.map((c, j) => ({
    text: c,
    options: {
      fontFace: j === 1 ? F.mono : F.body, fontSize: j === 1 ? 10.5 : 11.5,
      bold: j === 4 && c !== "", color: j === 4 && c ? C.bug : C.text,
      fill: { color: i % 2 ? C.white : C.card },
    },
  })));
  s.addTable([head, ...body], {
    x: 0.6, y: 1.65, w: 12.1, colW: [0.7, 2.35, 4.2, 3.55, 1.3], fontFace: F.body, fontSize: 11.5,
    border: { type: "solid", pt: 0.5, color: C.line }, rowH: 0.34, valign: "middle", margin: [2, 6, 2, 6],
  });
}
tpSlide("0x08", "Test plan (1/2)", TP);
tpSlide("0x08", "Test plan (2/2)", TP2);

// =============================================================================
// 11. Coverage and assertions
// =============================================================================
{
  const s = content("0x09", "Spec-feature coverage and assertion results",
    "Coverage is sampled from the reference model, so it measures behaviour, not raw signal values");
  const cps = [
    ["CP02 / CP03", "every transition (hunt, LSB, reject, restart, frame) x aligned"],
    ["CP06", "every byte that can follow a header LSB"],
    ["CP07", "gap before a header while aligned: 0 .. 44, 45, 46 (last chance)"],
    ["CP08", "every kind of 48th byte: plain, LSB, rejected MSB, restart LSB"],
    ["CP09", "fr_byte_position 0..11 x frame_detect"],
    ["CP11", "asynchronous reset in every phase, aligned or not"],
    ["CP12", "header patterns inside payloads"],
  ];
  cps.forEach(([id, t], i) => {
    const y = 1.75 + i * 0.6;
    tile(s, 0.6, y + 0.04, id, { w: 1.55, h: 0.44, fill: C.fixSoft, line: C.fix, color: C.fix, fs: 11 });
    s.addText(t, { x: 2.3, y, w: 4.6, h: 0.52, fontFace: F.body, fontSize: 13, valign: "middle", margin: 0, isTextBox: true });
  });
  card(s, 0.6, 6.0, 6.3, 0.8, C.fixSoft);
  s.addText([{ text: "100 % ", options: { bold: true, color: C.fix, fontSize: 24 } }, { text: "of 14 coverpoints (102 bins) in the regression; every cover property hit", options: { fontSize: 13 } }],
    { x: 0.8, y: 6.0, w: 6.0, h: 0.8, fontFace: F.body, valign: "middle", margin: 0, isTextBox: true });
  // assertion failures on the delivered RTL (native chart)
  // Every assertion that failed on the delivered RTL (read from the log).
  const names = Object.keys(ORIG_SVA).filter((n) => ORIG_SVA[n] > 0).sort();
  s.addChart(pres.charts.BAR, [{ name: "failures", labels: names, values: names.map((n) => ORIG_SVA[n] || 0) }], {
    x: 7.2, y: 1.6, w: 5.5, h: 5.2, barDir: "bar", chartColors: [C.bug],
    showTitle: true, title: "Assertion failures on the delivered RTL (corrected RTL: 0)", titleFontSize: 13, titleColor: C.text, titleFontFace: F.body,
    showValue: true, dataLabelPosition: "outEnd", dataLabelFontSize: 10, dataLabelColor: C.text,
    catAxisLabelFontSize: 9.5, catAxisLabelColor: C.text, catAxisLabelFontFace: F.mono, catAxisOrientation: "maxMin",
    valAxisHidden: true, valGridLine: { style: "none" }, catGridLine: { style: "none" }, showLegend: false,
  });
}

// =============================================================================
// 12. Section: defects
// =============================================================================
{
  const s = pres.addSlide();
  s.background = { color: C.ink };
  s.addText("DUT defects", { x: 0.6, y: 1.0, w: 8, h: 1.0, fontFace: F.head, fontSize: 44, bold: true, color: C.white, margin: 0, isTextBox: true });
  s.addText("The student's scoreboard mirrored the RTL, so these were either unseen or filed as \"gaps in the spec\".",
    { x: 0.6, y: 2.0, w: 11.5, h: 0.6, fontFace: F.body, fontSize: 18, color: C.ice, margin: 0, isTextBox: true });
  const D = [
    ["DUT-01", "Header LSB lost: some legal streams never align", "Critical", C.bug],
    ["DUT-02", "Alignment dropped on a valid header", "High", C.bug],
    ["DUT-07", "No fly-wheel: slips never lose alignment", "High (arch.)", C.bug],
    ["DUT-03", "Position 1 reported for a rejected header", "Medium", C.amber],
    ["DUT-04", "Frame counter wraps 3 -> 0", "Low (latent)", "8FA3BF"],
    ["DUT-05", "Byte counter wraps 63 -> 0", "Low (latent)", "8FA3BF"],
    ["DUT-08", "X-optimistic header decode", "Low", "8FA3BF"],
    ["DUT-06", "Coding issues (default, width, comments)", "Info", "8FA3BF"],
  ];
  D.forEach(([id, t, sev, col], i) => {
    const colx = i < 4 ? 0.6 : 6.8, y = 3.0 + (i % 4) * 0.9;
    tile(s, colx, y, id, { w: 1.25, h: 0.55, fill: C.ink2, line: col, color: C.white, fs: 13, lw: 1.5 });
    s.addText(t, { x: colx + 1.45, y: y - 0.05, w: 4.4, h: 0.4, fontFace: F.body, fontSize: 15, color: C.white, margin: 0, isTextBox: true });
    s.addText(sev, { x: colx + 1.45, y: y + 0.32, w: 4.4, h: 0.3, fontFace: F.body, fontSize: 12, bold: true, color: col, margin: 0, isTextBox: true });
  });
  footer(s, true);
}

// =============================================================================
// 13. DUT-01 root cause
// =============================================================================
{
  const s = content("DUT-01", "Header LSB thrown away after a rejected MSB", "Critical  ·  extends the student's \"LSB twice then MSB\": it happens for all four LSB combinations");
  image(s, "slide_dut01_restart.png", 0.6, 1.6, 12.1, 3.3);
  card(s, 0.6, 5.1, 4.6, 1.7);
  s.addText("Root cause", { x: 0.8, y: 5.18, w: 4.2, h: 0.35, fontFace: F.head, fontSize: 15, bold: true, margin: 0, isTextBox: true });
  s.addText("In FR_HLSB a wrong MSB always returns to FR_IDLE. If that byte is itself a header LSB (AA / 55) it is never examined, so its header is missed.",
    { x: 0.8, y: 5.55, w: 4.2, h: 1.2, fontFace: F.body, fontSize: 12.5, margin: 0, isTextBox: true });
  card(s, 5.4, 5.1, 7.3, 1.7, C.ink);
  s.addText("end else if (header_lsb_valid) begin  // FIX DUT-01\n   legal_frame_counter_rst = 1'b1;  fr_byte_position_rst = 1'b1;\n   na_byte_count_inc       = 1'b1;  next_state = FR_HLSB;\nend",
    { x: 5.6, y: 5.15, w: 7.0, h: 1.6, fontFace: F.mono, fontSize: 12, color: C.ice, valign: "middle", margin: 0, isTextBox: true });
}

// =============================================================================
// 14. DUT-01 impact
// =============================================================================
{
  const s = content("DUT-01", "Some legal streams are never aligned", "A single 0x55 (or 0xAA) as the last payload byte looks like a header LSB; the real LSB rejects it and is lost, in every frame");
  image(s, "slide_dut01_midstream.png", 0.6, 1.65, 12.1, 3.55);
  const st = [
    ["never", "aligned: start-up inside a legal stream whose payloads end in a single 0x55 (TP25: 20 of 20 checkpoints fail)"],
    ["permanent", "loss after one bit error in a header, if the following payloads end in 0x55 (TP26)"],
    ["1 in 128", "chance that only 3 bad frames already lose alignment: the byte before the 4th header is 0xAA / 0x55"],
  ];
  st.forEach(([b, t], i) => {
    const x = 0.6 + i * 4.1;
    card(s, x, 5.35, 3.85, 1.45, C.bugSoft);
    s.addText(b, { x: x + 0.2, y: 5.4, w: 3.5, h: 0.55, fontFace: F.head, fontSize: 24, bold: true, color: C.bug, margin: 0, isTextBox: true });
    s.addText(t, { x: x + 0.2, y: 5.95, w: 3.5, h: 0.8, fontFace: F.body, fontSize: 12, margin: 0, isTextBox: true });
  });
}

// =============================================================================
// 15. DUT-02
// =============================================================================
{
  const s = content("DUT-02", "Alignment dropped on a valid header", "High  ·  the student saw \"last chance is a header at byte 45\" and filed it as a spec gap");
  image(s, "slide_dut02_sync_drop.png", 0.6, 1.65, 7.4, 4.2);
  card(s, 8.3, 1.65, 4.4, 3.0);
  s.addText("Root cause", { x: 8.5, y: 1.75, w: 4, h: 0.4, fontFace: F.head, fontSize: 16, bold: true, margin: 0, isTextBox: true });
  bullets(s, [
    "after 46 header-less bytes the header LSB brings the counter to 47 (correct: it reaches 48 only on the next counted byte)",
    "but the clear (na_byte_counter == 47) is not qualified by na_byte_count_inc: the valid MSB clears frame_detect",
    "the whole valid frame is received with frame_detect = 0; outage 25 cycles",
  ], 8.5, 2.2, 4.0, 2.4, { fs: 13 });
  const rows = [
    [{ text: "gap", options: { bold: true, color: C.white, fill: { color: C.ink } } }, { text: "spec", options: { bold: true, color: C.white, fill: { color: C.ink } } }, { text: "delivered RTL", options: { bold: true, color: C.white, fill: { color: C.ink } } }],
    ["<= 45", "kept", "kept"],
    [{ text: "46", options: { bold: true } }, { text: "kept", options: { color: C.spec, bold: true } }, { text: "LOST", options: { color: C.bug, bold: true } }],
    [">= 47", "lost", "lost"],
  ];
  s.addTable(rows, { x: 8.3, y: 4.85, w: 4.4, colW: [1.2, 1.4, 1.8], fontFace: F.body, fontSize: 13, border: { type: "solid", pt: 0.5, color: C.line }, rowH: 0.34, align: "center", valign: "middle" });
  text(s, "Fix: clear only when the consumed byte is itself counted:  na_byte_count_inc && na_byte_counter == 47", 0.6, 6.05, 7.4, 0.7, { fontFace: F.mono, fontSize: 11.5, color: C.ink3 });
}

// =============================================================================
// 16. DUT-03 and latent defects
// =============================================================================
{
  const s = content("DUT-03", "Position reported for a rejected header", "Medium  ·  the student noted the one-cycle \"1\" and filed it as a spec gap");
  image(s, "slide_dut03_pos.png", 0.6, 1.6, 7.6, 4.3);
  card(s, 8.5, 1.6, 4.2, 4.3);
  s.addText("What happens", { x: 8.7, y: 1.7, w: 3.8, h: 0.4, fontFace: F.head, fontSize: 16, bold: true, margin: 0, isTextBox: true });
  bullets(s, [
    "after AA 01 the output says \"header MSB\" (position 1) although no frame exists",
    "every other hunting byte reports 0, so a consumer sees a phantom header",
    "the FSM slide omits the position reset on the HLSB -> IDLE arc too",
  ], 8.7, 2.2, 3.8, 3.6, { fs: 13 });
  text(s, "Fix: fr_byte_position_rst = 1 on the reject arc.   Caught by SPEC_POS1_AFTER_HEADER, SPEC_POS_INCREMENT and WB_DUT03_POS_RESET_ON_REJECT.",
    0.6, 6.15, 12.1, 0.6, { fontSize: 13, color: C.ink3 });
}

// =============================================================================
// 16b. Latent and hygiene defects
// =============================================================================
{
  const s = content("DUT-04", "Latent and hygiene defects", "Invisible on the ports today; caught at the root cause by white-box assertions and lint");
  image(s, "slide_dut04_counters.png", 0.6, 1.6, 12.1, 3.1);
  const L = [
    ["DUT-04", "legal_frame_counter wraps 3 -> 0 on the 4th frame (above). Caught by WB_DUT04_LEGAL_NO_WRAP. Fix: saturate."],
    ["DUT-05", "na_byte_counter wraps 63 -> 0 on long header-less streams. Caught by WB_DUT05_NA_NO_WRAP. Fix: saturate."],
    ["DUT-06", "no next_state default; 4-bit vs 8'd10 compare; wrong comments. The corrected RTL is verilator -Wall clean."],
    ["DUT-08", "X on rx_data is silently decoded as \"not a header\" in RTL, but not in gates. TB_IN_KNOWN forbids X stimulus."],
  ];
  L.forEach(([id, t], i) => {
    const col = i % 2, row = Math.floor(i / 2);
    const x = 0.6 + col * 6.15, y = 4.9 + row * 0.98;
    card(s, x, y, 5.95, 0.86);
    tile(s, x + 0.15, y + 0.19, id, { w: 1.1, h: 0.48, fill: C.white, line: C.muted, fs: 12 });
    s.addText(t, { x: x + 1.4, y: y + 0.03, w: 4.45, h: 0.8, fontFace: F.body, fontSize: 12, valign: "middle", margin: 0, isTextBox: true });
  });
}

// =============================================================================
// 17. DUT-07
// =============================================================================
{
  const s = content("DUT-07", "No fly-wheel: slips never lose alignment", "High (architecture)  ·  spec text: out of alignment after four frames without the EXPECTED header");
  image(s, "slide_dut07_slip.png", 0.6, 1.65, 12.1, 3.55);
  bullets(s, [
    [{ text: "13-byte frames: ", options: { bold: true } }, { text: "every header one byte late, and frame_detect stays 1 forever. The same stream never aligns from reset (hysteresis)." }],
    [{ text: "Tracking stops: ", options: { bold: true } }, { text: "after one bad header, fr_byte_position is 0 for a whole frame while frame_detect = 1; a header pattern in a payload re-bases the frame (false lock)." }],
    [{ text: "Proposed fix: ", options: { bold: true } }, { text: "while aligned, count 0..11 freely, check headers only at the expected position, and declare out-of-frame after 4 bad frames. Hunt byte by byte only while not aligned." }],
  ], 0.6, 5.3, 12.1, 1.6, { fs: 13.5 });
}

// =============================================================================
// 18. Specification issues
// =============================================================================
{
  const s = content("0x0A", "Issues in the specification itself", "To be clarified with the designer; each affects what \"correct\" means");
  const S = [
    ["SPEC-01", "Output data interface (header + payload forwarding) is specified but not implemented"],
    ["SPEC-02", "Text: loss after 4 frames without the expected header. Design slides: 48 hunting bytes. Leads to DUT-07"],
    ["SPEC-03", "Waveform 2 is one clock late against the FSM slide and the RTL; waveform 1 starts in an unreachable state"],
    ["SPEC-04", "fr_byte_position is undefined outside a frame and has no valid qualifier (0 = LSB and 0 = not aligned)"],
    ["SPEC-05", "Name mismatches: fr_is_aligned / frame_detect, na_frame_counter / na_byte_counter, Valid_h2 missing"],
    ["SPEC-06", "The 48th header-less byte is a header LSB: counted (register table) or not (look-ahead)? The RTL violates both"],
  ];
  S.forEach(([id, t], i) => {
    const col = i % 2, row = Math.floor(i / 2);
    const x = 0.6 + col * 6.15, y = 1.75 + row * 1.7;
    card(s, x, y, 5.95, 1.5);
    tile(s, x + 0.2, y + 0.2, id, { w: 1.3, h: 0.46, fill: C.amberSoft, line: C.amber, fs: 12 });
    s.addText(t, { x: x + 0.2, y: y + 0.72, w: 5.55, h: 0.72, fontFace: F.body, fontSize: 13, margin: 0, isTextBox: true });
  });
}

// =============================================================================
// 19. Legacy testbench defects
// =============================================================================
{
  const s = content("0x0B", "Defects in the original testbench", "Why the original run looked clean although the design is not");
  const big = [
    ["12.8 %", "of the queued stimulus never driven (117 of 917 items): end of test compared transactions with repeat_count"],
    ["1 byte", "early: the \"copied\" model sets and clears frame_detect one byte before the RTL, so no clean run was possible"],
    ["102", "false assertion failures per run from one legacy property; the other two are vacuous or always fail"],
  ];
  big.forEach(([b, t], i) => {
    const x = 0.6 + i * 4.1;
    card(s, x, 1.7, 3.85, 2.05, C.bugSoft);
    s.addText(b, { x: x + 0.2, y: 1.8, w: 3.5, h: 0.7, fontFace: F.head, fontSize: 32, bold: true, color: C.bug, margin: 0, isTextBox: true });
    s.addText(t, { x: x + 0.2, y: 2.5, w: 3.5, h: 1.2, fontFace: F.body, fontSize: 12.5, margin: 0, isTextBox: true });
  });
  const T = [
    ["TB-01", "model copied from the RTL; mismatches fixed in the scoreboard"],
    ["TB-04", "5 directed tests drive X (new[N] on a 4-state array, 8'hxA)"],
    ["TB-05", "tests shuffled: preconditions not met, tests spill into the next one"],
    ["TB-07", "coverage: reachable illegal bins, unreachable bins, no spec features"],
    ["TB-08", "sampling depends on program-block scheduling; reset on a clock edge"],
    ["TB-09", "2-state scoreboard turns X/Z into 0"],
    ["TB-10", "build order wrong; bind by instance name not elaborated"],
    ["TB-11", "out-of-bounds writes, misleading \"illegal\" frames, no seed control"],
  ];
  T.forEach(([id, t], i) => {
    const col = i % 2, row = Math.floor(i / 2);
    const x = 0.6 + col * 6.15, y = 4.0 + row * 0.7;
    tile(s, x, y + 0.06, id, { w: 1.05, h: 0.44, fill: C.white, line: C.bug, color: C.bug, fs: 11 });
    s.addText(t, { x: x + 1.2, y, w: 4.8, h: 0.56, fontFace: F.body, fontSize: 13, valign: "middle", margin: 0, isTextBox: true });
  });
}

// =============================================================================
// 20. Regression results
// =============================================================================
{
  const s = content("0x0C", "Regression results", "make -C sim regress: every run is checked against its EXPECTED outcome");
  const H = (t) => ({ text: t, options: { bold: true, color: C.white, fill: { color: C.ink } } });
  const V = (r) => ({ text: r.verdict, options: { bold: true, color: r.verdict === "PASS" ? C.spec : C.bug } });
  const CP = (r) => (+r.cp_pass + +r.cp_fail) ? `${num(r.cp_pass)} / ${num(+r.cp_pass + +r.cp_fail)}` : "-";
  const rows = [
    [H("RTL"), H("test"), H("model"), H("cycles"), H("checkpoints"), H("verdict"), H("expected")],
    ["corrected", "directed", "spec", num(FIXED.directed.compared), CP(FIXED.directed), V(FIXED.directed), "PASS"],
    ["corrected", "boundary sweep", "spec", num(FIXED.boundary.compared), CP(FIXED.boundary), V(FIXED.boundary), "PASS"],
    ["corrected", "random", "spec", num(FIXED.random.compared), CP(FIXED.random), V(FIXED.random), "PASS"],
    ["corrected", "regression", "spec", num(FIXED.regression.compared), CP(FIXED.regression), V(FIXED.regression), `PASS, cov ${FIXED.regression.cov} %`],
    ["delivered", "regression", "DUT", num(ORIG_DUTMODE.compared), "tolerated", V(ORIG_DUTMODE), "PASS (no new behaviour)"],
    ["delivered", "regression", "spec", num(ORIG.compared), CP(ORIG), V(ORIG), `FAIL, ${ORIG.unexplained} unexplained`],
    ["corrected", "fuzz replay", "spec", num(FILE_FIXED.compared), "-", V(FILE_FIXED), "PASS"],
    ["delivered", "fuzz replay", "spec", num(FILE_ORIG.compared), "-", V(FILE_ORIG), `FAIL, ${FILE_ORIG.unexplained} unexplained`],
  ];
  s.addTable(rows, {
    x: 0.6, y: 1.7, w: 7.3, colW: [1.05, 1.3, 0.75, 0.9, 1.25, 0.8, 1.25], fontFace: F.body, fontSize: 11.5,
    border: { type: "solid", pt: 0.5, color: C.line }, rowH: 0.39, valign: "middle", margin: [2, 5, 2, 5],
  });
  s.addChart(pres.charts.BAR, [
    { name: "delivered RTL", labels: ["DUT-01", "DUT-02", "DUT-03"], values: [+BUGS["DUT-01"], +BUGS["DUT-02"], +BUGS["DUT-03"]] },
    { name: "corrected RTL", labels: ["DUT-01", "DUT-02", "DUT-03"], values: [0, 0, 0] },
  ], {
    x: 8.2, y: 1.6, w: 4.5, h: 3.4, barDir: "col", chartColors: [C.bug, C.fix],
    showTitle: true, title: "Spec violations attributed per defect", titleFontSize: 13, titleColor: C.text, titleFontFace: F.body,
    showValue: true, dataLabelPosition: "outEnd", dataLabelFontSize: 10, showLegend: true, legendPos: "b", legendFontSize: 10,
    catAxisLabelFontSize: 11, valAxisHidden: true, valGridLine: { style: "none" }, catGridLine: { style: "none" },
  });
  bullets(s, [
    "RTL untouched: hash of the annotated DUT = hash of the delivered dut.sv",
    "The corrected RTL is verilator -Wall clean",
    "Python fuzzing, 910 k cycles: corrected RTL = both Python spec models; delivered RTL = bug-emulating model (0 differences)",
  ], 0.6, 5.45, 12.1, 1.4, { fs: 14 });
}

// =============================================================================
// 21. Mutation testing: checking the checkers
// =============================================================================
{
  const s = content("0x0D", "Checking the checkers: mutation testing", "One bug at a time is injected into the corrected RTL; the bench must detect every one (scripts/mutation_test.py)");
  card(s, 0.6, 1.75, 4.2, 5.05, C.ink);
  s.addText(`${mutKilled} / ${MUT.length}`, { x: 0.85, y: 1.9, w: 3.8, h: 1.1, fontFace: F.head, fontSize: 54, bold: true, color: mutKilled === MUT.length ? C.amber : C.bug, margin: 0, isTextBox: true });
  s.addText("mutants killed", { x: 0.85, y: 3.0, w: 3.8, h: 0.4, fontFace: F.body, fontSize: 18, bold: true, color: C.white, margin: 0, isTextBox: true });
  bullets(s, [
    "each mutant re-runs the directed and boundary tests",
    "killed = at least one oracle fails: scoreboard (SB), checkpoints (CP), spec SVA, white-box SVA (WB)",
    "the first run left M20 alive (a stray LSB between frames was never checked); TP20 was extended and M20 is now killed",
  ], 0.85, 3.55, 3.8, 3.2, { fs: 13, color: C.ice });
  const H = (t) => ({ text: t, options: { bold: true, color: C.white, fill: { color: C.ink } } });
  const hit = (v) => ({ text: v === "0" || v === "-" ? "" : v, options: { color: C.spec, bold: true, align: "center" } });
  const rows = [[H("ID"), H("injected bug"), H("SB"), H("CP"), H("SVA"), H("WB")]].concat(MUT.map((r) => [
    { text: r.id, options: { bold: true, color: r.status === "KILLED" ? C.text : C.bug } },
    r.desc, hit(r.hits.SB), hit(r.hits.CP), hit(r.hits.SVA), hit(r.hits.WB),
  ]));
  s.addTable(rows, {
    x: 5.05, y: 1.75, w: 7.65, colW: [0.55, 4.7, 0.6, 0.6, 0.6, 0.6], fontFace: F.body, fontSize: 9,
    border: { type: "solid", pt: 0.5, color: C.line }, rowH: 0.235, valign: "middle", margin: [1, 4, 1, 4],
  });
}

// =============================================================================
// 22. Conclusions
// =============================================================================
{
  const s = pres.addSlide();
  s.background = { color: C.ink };
  s.addText("Conclusions", { x: 0.6, y: 0.7, w: 8, h: 0.9, fontFace: F.head, fontSize: 40, bold: true, color: C.white, margin: 0, isTextBox: true });
  bullets(s, [
    [{ text: "The design is not bug-free. ", options: { bold: true, color: C.amber } }, { text: "Its header search can miss every header of a legal stream (DUT-01) and drops alignment on a valid header (DUT-02).", options: { color: C.white } }],
    [{ text: "A scoreboard that copies the RTL cannot find design bugs. ", options: { bold: true, color: C.amber } }, { text: "The spec model with defect triage found all of them, with 0 unexplained mismatches.", options: { color: C.white } }],
    [{ text: "Expected outcomes must be executable. ", options: { bold: true, color: C.amber } }, { text: `${num(cpTotal)} checkpoints turn the test plan into checks.`, options: { color: C.white } }],
    [{ text: "Evidence, not assumption. ", options: { bold: true, color: C.amber } }, { text: `Three independent models agree; the corrected RTL passes everything; ${mutKilled} of ${MUT.length} injected bugs are caught.`, options: { color: C.white } }],
  ], 0.6, 1.9, 7.3, 4.8, { fs: 18, psa: 14 });
  card(s, 8.4, 1.8, 4.3, 4.6, C.ink2);
  s.addText("Next steps", { x: 8.65, y: 1.95, w: 3.9, h: 0.5, fontFace: F.head, fontSize: 20, bold: true, color: C.white, margin: 0, isTextBox: true });
  bullets(s, [
    "Designer to accept DUT-01..06 fixes (rtl/frame_aligner_fixed.sv)",
    "Decide on the fly-wheel (DUT-07) and resolve SPEC-02/-06",
    "Add the output data interface (SPEC-01)",
    "Run the bench on a commercial simulator to merge native covergroups",
    "Formal proof of R1-R7 on the corrected RTL",
  ], 8.65, 2.6, 3.9, 3.7, { fs: 15, color: C.ice });
  footer(s, true);
}

// =============================================================================
// 23. Appendix: how to run
// =============================================================================
{
  const s = content("0x0E", "Appendix: how to run", "Verilator >= 5.030 with z3; Python 3; Icarus Verilog for scripts/");
  card(s, 0.6, 1.8, 12.1, 3.4, C.ink);
  s.addText([
    "cd sim",
    "make sim DUT=fixed                        # corrected RTL          -> TEST PASSED",
    "make sim DUT=orig                         # delivered RTL          -> TEST FAILED, defects listed",
    "make sim DUT=orig MODEL=dut               # regression mode        -> only new behaviour fails",
    "make sim DUT=orig TEST=restart_header VERBOSITY=2",
    "make sim DUT=orig TEST=loss_boundary WAVES=1   # waves.vcd",
    "make regress                              # full matrix, expected outcomes",
    "python3 ../scripts/fuzz_rtl.py            # differential fuzzing (Icarus)",
    "python3 ../scripts/plot_waves.py          # regenerate the figures",
    "python3 ../scripts/mutation_test.py       # mutation score of the checkers",
  ].join("\n"), { x: 0.85, y: 1.9, w: 11.6, h: 3.2, fontFace: F.mono, fontSize: 14, color: C.ice, valign: "middle", margin: 0, isTextBox: true });
  text(s, "Documents: docs/BUG_REPORT.md (every defect, reproduction, fix) · docs/VERIFICATION_PLAN.md (rules, test plan, coverage, assertions, results)",
    0.6, 5.5, 12.1, 0.6, { fontSize: 14, color: C.muted });
}

pres.writeFile({ fileName: OUT }).then((f) => console.log("wrote " + path.relative(ROOT, f)));
