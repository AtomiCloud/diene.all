export const CONSOLE_STYLES = `
:root {
  color-scheme: dark;
  --ink: #090b0a;
  --panel: #111412;
  --line: #343a34;
  --line-hot: #6d755f;
  --paper: #e8e6d9;
  --muted: #999d91;
  --oxide: #c35d32;
  --signal: #ffc247;
  --cyan: #72dfce;
  --danger: #ff6b56;
  --focus: #f7e27d;
  --rail: clamp(11rem, 17vw, 15rem);
}
* { box-sizing: border-box; }
html { background: var(--ink); scroll-behavior: smooth; }
body {
  min-width: 19rem;
  margin: 0;
  color: var(--paper);
  background:
    linear-gradient(90deg, rgba(255,255,255,.026) 1px, transparent 1px) 0 0 / 42px 42px,
    linear-gradient(rgba(255,255,255,.021) 1px, transparent 1px) 0 0 / 42px 42px,
    radial-gradient(circle at 88% 5%, rgba(195,93,50,.14), transparent 28rem),
    var(--ink);
  font-family: "IBM Plex Mono", "Azeret Mono", "Lucida Console", monospace;
  font-size: 14px;
  line-height: 1.5;
}
body::before {
  position: fixed;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  content: "";
  opacity: .22;
  background-image: repeating-linear-gradient(112deg, transparent 0 7px, rgba(255,255,255,.015) 8px 9px);
  mix-blend-mode: screen;
}
a { color: var(--cyan); text-underline-offset: .22em; text-decoration-thickness: 1px; }
a:hover { color: var(--paper); }
button, input, select, textarea { font: inherit; }
button, .button {
  display: inline-flex;
  min-height: 2.55rem;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--signal);
  border-radius: 0;
  padding: .55rem .85rem;
  color: var(--ink);
  background: var(--signal);
  font-weight: 800;
  letter-spacing: .055em;
  text-decoration: none;
  text-transform: uppercase;
  cursor: pointer;
  transition: background-color 120ms ease, color 120ms ease, translate 120ms ease;
}
button:hover, .button:hover {
  color: var(--paper);
  background: var(--oxide);
  translate: 0 -1px;
}
.button--ghost { color: var(--paper); background: transparent; border-color: var(--line-hot); }
.button--danger { color: var(--paper); background: #802f27; border-color: var(--danger); }
:where(a, button, input, select, textarea):focus-visible {
  outline: 3px solid var(--focus);
  outline-offset: 3px;
}
input, select, textarea {
  width: 100%;
  min-height: 2.6rem;
  border: 1px solid var(--line-hot);
  border-radius: 0;
  padding: .55rem .65rem;
  color: var(--paper);
  background: #0c0f0d;
}
textarea { min-height: 6rem; resize: vertical; }
input::placeholder, textarea::placeholder { color: #777c72; }
label {
  display: block;
  margin-bottom: .35rem;
  color: var(--muted);
  font-size: .76rem;
  font-weight: 800;
  letter-spacing: .09em;
  text-transform: uppercase;
}
.skip-link { position: fixed; top: .5rem; left: .5rem; z-index: 20; translate: 0 -180%; }
.skip-link:focus { translate: 0; }
.shell { display: grid; min-height: 100vh; grid-template-columns: var(--rail) minmax(0, 1fr); }
.rail {
  position: sticky;
  top: 0;
  height: 100vh;
  display: flex;
  flex-direction: column;
  border-right: 1px solid var(--line);
  padding: 1.25rem 1rem;
  background: rgba(9,11,10,.94);
}
.brand {
  margin: 0;
  font-family: "DIN Condensed", "Bahnschrift Condensed", "Franklin Gothic Medium", sans-serif;
  font-size: clamp(2rem, 3.4vw, 3.7rem);
  font-stretch: condensed;
  font-weight: 900;
  letter-spacing: -.055em;
  line-height: .8;
  text-transform: uppercase;
}
.brand span { display: block; color: var(--oxide); }
.brand-code {
  margin-top: .7rem;
  color: var(--muted);
  font-size: .65rem;
  letter-spacing: .18em;
  text-transform: uppercase;
}
.rail__nav { margin: 2rem 0 auto; }
.rail__nav a {
  display: block;
  border-top: 1px solid var(--line);
  padding: .65rem .1rem;
  color: var(--muted);
  font-size: .72rem;
  font-weight: 800;
  letter-spacing: .08em;
  text-decoration: none;
  text-transform: uppercase;
}
.rail__nav a:hover { color: var(--signal); padding-left: .35rem; }
.account { border-top: 2px solid var(--oxide); padding-top: .8rem; }
.account__kind {
  color: var(--signal);
  font-size: .64rem;
  font-weight: 900;
  letter-spacing: .12em;
  text-transform: uppercase;
}
.account__name { margin: .25rem 0 0; font-weight: 800; overflow-wrap: anywhere; }
.account__user { margin: .15rem 0 .8rem; color: var(--muted); font-size: .72rem; overflow-wrap: anywhere; }
.account button { width: 100%; min-height: 2.1rem; padding: .35rem; font-size: .68rem; }
.workspace { min-width: 0; padding: 1.2rem clamp(1rem, 3vw, 3.2rem) 5rem; }
.mast {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 2rem;
  align-items: end;
  border-bottom: 3px double var(--line-hot);
  padding: 1rem 0 1.2rem;
}
.eyebrow {
  margin: 0 0 .45rem;
  color: var(--oxide);
  font-size: .7rem;
  font-weight: 900;
  letter-spacing: .18em;
  text-transform: uppercase;
}
h1, h2, h3 {
  font-family: "DIN Condensed", "Bahnschrift Condensed", "Franklin Gothic Medium", sans-serif;
  font-stretch: condensed;
  text-transform: uppercase;
}
h1 { max-width: 16ch; margin: 0; font-size: clamp(2.1rem, 5vw, 5.2rem); letter-spacing: -.045em; line-height: .87; }
h2 { margin: 0; font-size: clamp(1.35rem, 2.5vw, 2.2rem); letter-spacing: -.025em; }
h3 { margin: 0; font-size: 1.15rem; letter-spacing: .02em; }
.mast__time { text-align: right; }
.mast__time strong { display: block; color: var(--signal); font-size: 1.15rem; }
.mast__time span { color: var(--muted); font-size: .65rem; letter-spacing: .12em; text-transform: uppercase; }
.notice {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  gap: .8rem;
  margin: 1rem 0;
  border: 1px solid #72602e;
  border-left: .4rem solid var(--signal);
  padding: .8rem;
  background: rgba(255,194,71,.07);
}
.notice--bad { border-color: #74392f; border-left-color: var(--danger); background: rgba(255,107,86,.08); }
.notice__code { color: var(--signal); font-weight: 900; letter-spacing: .08em; }
.notice p { margin: 0; }
.filter-matrix {
  margin: 1.35rem 0 2rem;
  border-top: 1px solid var(--line-hot);
  border-bottom: 1px solid var(--line-hot);
  padding: .9rem 0;
}
.filter-matrix__grid {
  display: grid;
  grid-template-columns: repeat(5, minmax(7.5rem, 1fr)) auto;
  gap: .7rem;
  align-items: end;
}
.section { margin-top: 2.7rem; scroll-margin-top: 1rem; }
.section__heading {
  display: grid;
  grid-template-columns: minmax(0, auto) 1fr auto;
  gap: 1rem;
  align-items: center;
  margin-bottom: .75rem;
}
.section__heading::after { height: 1px; background: var(--line); content: ""; }
.section__heading p {
  order: 3;
  margin: 0;
  color: var(--muted);
  font-size: .7rem;
  letter-spacing: .08em;
  text-transform: uppercase;
}
.telemetry-strip {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(13rem, 1fr));
  border-top: 1px solid var(--line);
  border-left: 1px solid var(--line);
}
.telemetry-cell {
  min-height: 9rem;
  border-right: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
  padding: .8rem;
  background: rgba(17,20,18,.86);
}
.telemetry-cell__top { display: flex; justify-content: space-between; gap: .8rem; align-items: start; }
.telemetry-cell__name { margin: 0; font-weight: 900; }
.telemetry-cell dl { display: grid; grid-template-columns: 1fr auto; gap: .25rem .7rem; margin: 1.1rem 0 0; font-size: .75rem; }
.telemetry-cell dt { color: var(--muted); }
.telemetry-cell dd { margin: 0; text-align: right; }
.table-wrap {
  width: 100%;
  overflow-x: auto;
  border: 1px solid var(--line);
  background: rgba(13,16,14,.92);
}
table { width: 100%; min-width: 52rem; border-collapse: collapse; font-size: .74rem; }
caption { padding: .65rem .75rem; color: var(--muted); text-align: left; }
th, td { border-bottom: 1px solid var(--line); padding: .58rem .7rem; text-align: left; vertical-align: top; }
th {
  position: sticky;
  top: 0;
  z-index: 1;
  color: var(--signal);
  background: #151813;
  font-size: .65rem;
  letter-spacing: .08em;
  text-transform: uppercase;
}
tbody tr:hover { background: rgba(114,223,206,.045); }
tbody tr:last-child td { border-bottom: 0; }
.numeric { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
.nowrap { white-space: nowrap; }
.actions { display: flex; flex-wrap: wrap; gap: .35rem; }
.actions .button { min-height: 1.8rem; padding: .25rem .42rem; font-size: .62rem; }
.state {
  display: inline-flex;
  align-items: center;
  gap: .38rem;
  color: var(--muted);
  font-size: .63rem;
  font-weight: 900;
  letter-spacing: .06em;
  white-space: nowrap;
}
.state__pip {
  width: .55rem;
  height: .55rem;
  border: 1px solid currentColor;
  background: currentColor;
  box-shadow: 0 0 .6rem currentColor;
}
.state--good { color: var(--cyan); }
.state--warn { color: var(--signal); }
.state--bad { color: var(--danger); }
.state--quiet { color: var(--muted); }
.muted { color: var(--muted); }
.empty { border: 1px dashed var(--line-hot); padding: 1.5rem; color: var(--muted); text-align: center; }
.split { display: grid; grid-template-columns: minmax(0, 1.35fr) minmax(18rem, .65fr); gap: 1rem; }
.definition { margin: 0; border-top: 1px solid var(--line); }
.definition > div {
  display: grid;
  grid-template-columns: minmax(8rem, .38fr) minmax(0, 1fr);
  border-bottom: 1px solid var(--line);
  padding: .65rem 0;
}
.definition dt { color: var(--muted); font-size: .68rem; font-weight: 800; letter-spacing: .06em; text-transform: uppercase; }
.definition dd { min-width: 0; margin: 0; overflow-wrap: anywhere; }
.code-block {
  max-height: 30rem;
  overflow: auto;
  border: 1px solid var(--line);
  border-left: 3px solid var(--oxide);
  padding: 1rem;
  color: #d6dfd4;
  background: #050706;
  font-size: .75rem;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.confirm {
  max-width: 52rem;
  margin: clamp(2rem, 7vh, 7rem) auto;
  border-top: .5rem solid var(--oxide);
  border-bottom: 1px solid var(--line-hot);
  padding: 1.4rem;
  background: rgba(17,20,18,.96);
}
.confirm h1 { max-width: 100%; }
.confirm__target { margin: 1.5rem 0; border-left: 1px solid var(--signal); padding-left: 1rem; }
.confirm__grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
.confirm__actions { display: flex; flex-wrap: wrap; gap: .7rem; margin-top: 1rem; }
.login-shell { min-height: 100vh; display: grid; grid-template-columns: minmax(13rem, .65fr) minmax(20rem, 1.35fr); }
.login-mark {
  position: relative;
  display: flex;
  min-height: 100vh;
  flex-direction: column;
  justify-content: space-between;
  border-right: 1px solid var(--line);
  padding: clamp(1.3rem, 5vw, 5rem);
  overflow: hidden;
  background: #0c0e0c;
}
.login-mark::after {
  position: absolute;
  right: -5rem;
  bottom: 5rem;
  color: rgba(195,93,50,.11);
  content: "M";
  font-family: "DIN Condensed", "Bahnschrift Condensed", sans-serif;
  font-size: 35rem;
  font-weight: 900;
  line-height: .5;
}
.login-mark .brand { position: relative; z-index: 1; font-size: clamp(4rem, 10vw, 10rem); }
.login-mark__copy { position: relative; z-index: 1; max-width: 32rem; color: var(--muted); }
.login-panel { display: grid; place-items: center; padding: 1.5rem; }
.login-form {
  width: min(100%, 34rem);
  border-top: .55rem solid var(--signal);
  padding: clamp(1.2rem, 4vw, 3rem);
  background: rgba(17,20,18,.93);
  box-shadow: 1.2rem 1.2rem 0 rgba(195,93,50,.11);
}
.login-form h1 { max-width: none; margin-bottom: .6rem; }
.login-form__intro { margin: 0 0 1.8rem; color: var(--muted); }
.field { margin: 1rem 0; }
.login-form button { width: 100%; margin-top: .8rem; }
.form-help { color: var(--muted); font-size: .72rem; }
.result-mark {
  display: inline-grid;
  width: 3rem;
  height: 3rem;
  place-items: center;
  border: 1px solid var(--cyan);
  color: var(--cyan);
  font-size: 1.5rem;
}
.result-mark--bad { border-color: var(--danger); color: var(--danger); }
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0,0,0,0);
  white-space: nowrap;
  border: 0;
}
@media (max-width: 900px) {
  .shell { grid-template-columns: 1fr; }
  .rail {
    position: relative;
    height: auto;
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 1rem;
    border-right: 0;
    border-bottom: 1px solid var(--line);
  }
  .rail__nav { display: none; }
  .account { border-top: 0; border-left: 2px solid var(--oxide); padding: 0 0 0 .8rem; }
  .brand { font-size: 2.4rem; }
  .filter-matrix__grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .split { grid-template-columns: 1fr; }
  .login-shell { grid-template-columns: 1fr; }
  .login-mark { min-height: 17rem; border-right: 0; border-bottom: 1px solid var(--line); }
  .login-mark .brand { font-size: 5rem; }
}
@media (max-width: 560px) {
  .workspace { padding-inline: .75rem; }
  .mast { grid-template-columns: 1fr; }
  .mast__time { text-align: left; }
  .filter-matrix__grid, .confirm__grid { grid-template-columns: 1fr; }
  .section__heading { grid-template-columns: 1fr; gap: .25rem; }
  .section__heading::after { display: none; }
  .section__heading p { order: initial; }
  .rail { grid-template-columns: 1fr; }
}
@media (prefers-reduced-motion: no-preference) {
  .workspace > * { animation: settle 320ms ease-out both; }
  .workspace > *:nth-child(2) { animation-delay: 45ms; }
  .workspace > *:nth-child(3) { animation-delay: 90ms; }
  @keyframes settle {
    from { opacity: 0; translate: 0 .45rem; }
    to { opacity: 1; translate: 0; }
  }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    scroll-behavior: auto !important;
    animation-duration: .01ms !important;
    transition-duration: .01ms !important;
  }
}
@media print {
  .rail, .filter-matrix, .actions, button { display: none !important; }
  .shell { display: block; }
  body { color: #111; background: #fff; }
}
`;

export const CONSOLE_SCRIPT = `
const clock = document.querySelector('[data-live-clock]');
const renderClock = () => {
  if (clock instanceof HTMLElement) {
    clock.textContent = new Intl.DateTimeFormat('en-GB', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
      timeZone: 'UTC',
    }).format(new Date()) + ' UTC';
  }
};
renderClock();
window.setInterval(renderClock, 1000);

for (const form of document.querySelectorAll('[data-confirm-form]')) {
  const input = form.querySelector('[data-confirm-input]');
  const status = form.querySelector('[data-confirm-status]');
  if (!(input instanceof HTMLInputElement) || !(status instanceof HTMLElement)) continue;
  const expected = input.dataset.expected || '';
  const update = () => {
    status.textContent =
      input.value === expected ? 'Confirmation phrase matched.' : 'Exact phrase required.';
  };
  input.addEventListener('input', update);
  update();
}
`;
