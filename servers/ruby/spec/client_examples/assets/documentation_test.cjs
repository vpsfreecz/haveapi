'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const filename = path.resolve(__dirname, '../../../lib/haveapi/public/js/documentation.js');
const { preferences, readPreferences, clientChoice, detailLevels, effectiveDetail, copyText, exampleCopyControls,
  disclosureMenus, legacyTarget, loginTarget, highlighterTarget, basicAuthentication, activeSection, navigationTargets,
  searchConfiguration, validateSearchIndex, searchMatcher, searchResultURL, renderSearchResult, searchIndexLoader } = require(filename);
const clients = [
  { id: '0', language: 'ruby', language_label: 'Ruby', variant: null },
  { id: 'python-sync', language: 'python', language_label: 'Python', variant: 'Sync' },
  { id: 'python-async', language: 'python', language_label: 'Python', variant: 'Async' }
];

assert.equal(preferences(null).theme, 'auto');
assert.equal(preferences(null).detail, 'simple');
assert.equal(preferences({ theme: 'invalid', detail: 'advanced' }).detail, 'simple');
assert.equal(preferences({ theme: 'invalid' }).theme, 'auto');
assert.equal(readPreferences({ getItem() { throw new Error('storage denied'); } }).theme, 'auto');
assert.equal(readPreferences({ getItem: () => '{broken json' }).detail, 'simple');
const saved = preferences({ theme: 'dark', language: 'python', clients: { python: 'python-async' }, detail: 'thorough' });
assert.equal(clientChoice(saved, clients).id, 'python-async');
assert.equal(clientChoice(saved, clients.slice(0, 2)).id, 'python-sync');
assert.equal(saved.clients.python, 'python-async', 'temporary unavailability must retain the saved client');
assert.equal(clientChoice(saved, clients.slice(0, 1)).id, '0');
assert.equal(saved.language, 'python', 'another API must not overwrite the preferred language');
assert.equal(clientChoice(saved, clients).id, 'python-async');
assert.equal(clientChoice(saved, []), null);
const malicious = preferences(JSON.parse('{"clients":{"__proto__":"safe-data","python":42}}'));
assert.equal(Object.getPrototypeOf(malicious.clients), null);
assert.equal(malicious.clients.__proto__, 'safe-data');
assert.equal(malicious.clients.python, undefined);

assert.deepEqual(detailLevels({}), ['simple', 'thorough'], 'old/custom metadata preserves both levels');
assert.deepEqual(detailLevels({ details: ['simple', 'thorough'] }), ['simple', 'thorough']);
for (const details of [null, [], 'simple', ['thorough'], ['simple', 'simple'], ['thorough', 'simple'], ['simple', 'other']]) {
  assert.deepEqual(detailLevels({ details }), ['simple'], 'malformed capabilities retain the renderer with safe simple UI');
}
assert.equal(effectiveDetail(saved, { details: ['simple'] }), 'simple');
assert.equal(saved.detail, 'thorough');
assert.equal(effectiveDetail(saved, {}), 'thorough', 'returning to a capable client restores the saved level');

function element(tag) {
  return {
    tagName: tag.toUpperCase(), children: [], attributes: {}, listeners: {}, style: {}, text: '',
    get textContent() { return this.text + this.children.map(child => child.textContent).join(''); },
    set textContent(value) { this.text = value; this.children = []; },
    setAttribute(name, value) { this.attributes[name] = value; },
    appendChild(child) { this.children.push(child); child.parentElement = this; return child; },
    insertBefore(child, before) { this.children.splice(this.children.indexOf(before), 0, child); child.parentElement = this; },
    remove() { this.parentElement.children.splice(this.parentElement.children.indexOf(this), 1); },
    addEventListener(name, listener) { this.listeners[name] = listener; },
    classList: { add() {} }
  };
}
const elements = { createElement: element, createElementNS: (namespace, tag) => element(tag) };

const menuEvents = {};
let focusedSummary;
function menuFixture(left, width) {
  const summary = { focus(options) { focusedSummary = this; assert.equal(options.preventScroll, true); } };
  const content = { style: {}, getBoundingClientRect: () => ({ width }) };
  return { open: false, listeners: {}, summary, content,
    querySelector: selector => selector === 'summary' ? summary : content,
    getBoundingClientRect: () => ({ left }),
    addEventListener(name, listener) { this.listeners[name] = listener; },
    contains(target) { return target === summary || target === content; } };
}
const themeMenu = menuFixture(210, 145);
const accountMenu = menuFixture(260, 232);
const closeMenus = disclosureMenus({ querySelectorAll: () => [themeMenu, accountMenu] },
  { getBoundingClientRect: () => ({ left: 0, right: 296 }) }, { addEventListener() {} },
  { addEventListener(name, listener) { menuEvents[name] = listener; } });
themeMenu.open = true; themeMenu.listeners.toggle();
assert.equal(themeMenu.content.style.left, '-67px', 'disclosure remains within sidebar bounds');
accountMenu.open = true; accountMenu.listeners.toggle();
assert.equal(themeMenu.open, false, 'opening Account closes theme');
let prevented = false; let stopped = false;
accountMenu.listeners.keydown({ key: 'Escape', preventDefault() { prevented = true; }, stopPropagation() { stopped = true; } });
assert.equal(accountMenu.open, false);
assert.equal(focusedSummary, accountMenu.summary);
assert(prevented && stopped, 'Account Escape preserves the outer mobile drawer and restores summary focus');
accountMenu.open = true; menuEvents.pointerdown({ target: accountMenu.content });
assert.equal(accountMenu.open, true, 'touching account content leaves native controls usable');
menuEvents.pointerdown({ target: {} }); assert.equal(accountMenu.open, false);
themeMenu.open = true; accountMenu.open = true; closeMenus();
assert.equal(themeMenu.open || accountMenu.open, false, 'closing mobile navigation also closes disclosures');

const anchors = {
  'root-vps': '/api/v7.0/?resource=vps',
  'root-vps-show': '/api/v7.0/?resource=vps',
  'example-vps-show-': '/api/v7.0/?resource=vps',
  'example-vps.snapshot-show-': '/api/v7.0/?resource=vps.snapshot',
  'auth-basic': '/api/v7.0/?page=authentication'
};
assert.equal(legacyTarget('#root-vps-show', anchors), '/api/v7.0/?resource=vps');
assert.equal(legacyTarget('#example-vps.snapshot-show-0-python-async', anchors), '/api/v7.0/?resource=vps.snapshot');
assert.equal(legacyTarget('#root-vps-unknown', anchors), null, 'resource prefixes must not guess unknown action links');
assert.equal(legacyTarget('#auth-basic', anchors), '/api/v7.0/?page=authentication');
assert.equal(legacyTarget('#%E0%A4%A', anchors), null);
assert.equal(legacyTarget('#not-visible', anchors), null);

const current = 'https://docs.example/api/v7.0/?resource=vps#root-vps-show';
const login = '/api/_documentation/oauth/login?version=7.0&page=resource&resource=vps';
const withFragment = new URL(loginTarget(login, current, '#root-vps-show'));
assert.equal(withFragment.origin, 'https://docs.example');
assert.equal(withFragment.searchParams.get('version'), '7.0');
assert.equal(withFragment.searchParams.get('page'), 'resource');
assert.equal(withFragment.searchParams.get('resource'), 'vps');
assert.equal(withFragment.searchParams.get('fragment'), 'root-vps-show');
assert.equal(loginTarget('https://foreign.example/login', current, '#root-vps-show'), null);
assert.equal(loginTarget('//foreign.example/login', current, '#root-vps-show'), null);
assert.equal(loginTarget('https://user:secret@docs.example/login', current, '#root-vps-show'), null);
assert.equal(loginTarget('javascript:alert(1)', current, '#root-vps-show'), null);
for (const fragment of ['', '#', '#%3Cunsafe%3E', '#root-vps/show', '#' + 'x'.repeat(257)]) {
  assert.equal(new URL(loginTarget(login + '&fragment=stale', current, fragment)).searchParams.has('fragment'), false);
}
assert.equal(new URL(loginTarget(login, current, '#' + 'x'.repeat(256))).searchParams.get('fragment').length, 256);

assert.equal(highlighterTarget('https://docs.example/js/documentation.js', current), 'https://docs.example/js/highlighter.js');
assert.equal(highlighterTarget('https://docs.example/api/js/documentation.js', current), 'https://docs.example/api/js/highlighter.js');
assert.equal(highlighterTarget('https://docs.example/js/documentation.js', current, '/mounted/js/highlighter.js'), 'https://docs.example/mounted/js/highlighter.js');
assert.equal(highlighterTarget('https://foreign.example/js/documentation.js', current), null);
assert.equal(highlighterTarget(null, current), null);

for (const logout of [false, true]) {
  let opened;
  let sent = false;
  let reloaded = false;
  const request = { open(...args) { opened = args; }, send() { sent = true; } };
  const href = logout ? 'https://_log:out@docs.example/api/_logout' : 'https://docs.example/api/_login';
  assert.equal(basicAuthentication(href, current, logout, () => request, () => { reloaded = true; }), true);
  assert.deepEqual(opened, logout ? ['GET', 'https://docs.example/api/_logout', true, '_log', 'out'] : ['GET', href, true]);
  assert.equal(sent, true);
  assert.equal(reloaded, false);
  request.onloadend();
  assert.equal(reloaded, true, 'reload retains the resource query and fragment through location.reload');
}
assert.equal(basicAuthentication('https://foreign.example/_login', current, false, () => { throw new Error('must not request'); }), false);

const actions = [
  { id: 'clone', top: -500, margin: '80px' },
  { id: 'create', top: 160.296875, margin: '80px' },
  { id: 'index', top: 2400, margin: '80px' }
];
assert.equal(activeSection(actions, '80px').id, 'create', 'native anchor landing must select Create, not preceding Clone');
assert.equal(activeSection(actions.map(action => ({ ...action, top: action.top + 32 })), '80px').id, 'clone', 'scrolling above the same activation line returns to Clone');
assert.equal(activeSection(actions.map(action => ({ ...action, top: action.top - 32 })), '80px').id, 'create');
assert.equal(activeSection([{ id: 'clone', top: -500, margin: '16px' }, { id: 'create', top: 80, margin: '16px' }], '0px').id, 'clone', 'changed header offsets must replace the old fixed threshold');
assert.equal(activeSection([{ id: 'clone', top: -500, margin: '16px' }, { id: 'create', top: 16.5, margin: '16px' }], '0px').id, 'create', 'changed header offsets need no click state');
assert.equal(activeSection([], 'auto'), null);

const headings = {
  intro: { id: 'intro', top: -200, margin: '24px' },
  'protocol syntax': { id: 'protocol syntax', top: 24.2, margin: '24px' }
};
const tocTargets = navigationTargets(['#intro', '#protocol%20syntax', '#intro', '#missing', 'other-page#intro', '#%E0%A4%A'], id => headings[id]);
assert.deepEqual(tocTargets, [headings.intro, headings['protocol syntax']], 'TOCs resolve exact existing headings, without wrappers or duplicate/missing targets');
assert.equal(activeSection(tocTargets, '0px').id, 'protocol syntax');

function browserFixture(workerMode, blockedStorage, display) {
  const attributes = {};
  const messages = [];
  const writes = [];
  const themeButtons = ['auto', 'light', 'dark'].map(theme => ({
    attributes: { 'data-theme-choice': theme }, listeners: {},
    closest() { return null; },
    getAttribute(name) { return this.attributes[name]; },
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(name, listener) { this.listeners[name] = listener; }
  }));
  let worker;
  const code = (visible, hidden) => ({
    textContent: '<unsafe>', innerHTML: '&lt;unsafe&gt;',
    classList: { item: () => 'ruby', contains: () => false, add() {} },
    getAttribute: () => null,
    closest: selector => selector === '[hidden]' && hidden ? {} : null,
    getBoundingClientRect: () => ({ width: 200, height: 50, top: visible ? 100 : 2000, bottom: visible ? 150 : 2050 })
  });
  const visibleCode = code(true, false);
  const codes = [visibleCode, code(false, false), code(true, true)];
  const root = {
    querySelector: selector => display && selector === '[data-documentation-clients]' ? { textContent: JSON.stringify(display.metadata) }
      : display && selector === '[data-docs-sidebar]' ? display.sidebar : null,
    querySelectorAll: selector => display && display.matches[selector] ? display.matches[selector]
      : selector === 'pre code' ? codes : selector === '[data-theme-choice]' ? themeButtons : [],
    getAttribute: () => 'resource',
    setAttribute() {}, addEventListener() {}
  };
  const localStorage = { getItem: () => JSON.stringify(display ? display.saved : { theme: 'dark' }), setItem: (key, value) => writes.push({ key, value }) };
  const themeMedia = { matches: false, addEventListener(name, listener) { this.listener = listener; } };
  const window = {
    matchMedia: query => query.includes('prefers-color-scheme') ? themeMedia : ({ matches: false, addEventListener() {} }),
    getComputedStyle: () => ({ scrollPaddingTop: '80px', scrollMarginTop: '80px' }),
    addEventListener() {}, location: { hash: '', href: current }, innerHeight: 800,
    requestAnimationFrame(callback) { callback(); },
    scrollBy(x, y) { if (display) display.geometry.scroll += y; }
  };
  Object.defineProperty(window, 'localStorage', { get() { if (blockedStorage) throw new Error('denied'); return localStorage; } });
  const document = { readyState: 'complete', currentScript: { src: 'https://docs.example/api/js/documentation.js', getAttribute: () => null }, documentElement: { setAttribute: (key, value) => { attributes[key] = value; } }, querySelector: () => root, addEventListener() {}, createElement: element };
  const Worker = function (url) {
    assert.equal(url, 'https://docs.example/api/js/highlighter.js');
    if (workerMode === 'constructor-failure') throw new Error('worker denied');
    worker = this;
    this.postMessage = message => { if (workerMode === 'post-failure') throw new Error('worker stopped'); messages.push(message); };
    this.terminate = () => { this.stopped = true; };
  };
  if (workerMode !== 'missing') window.Worker = Worker;
  vm.runInNewContext(fs.readFileSync(filename, 'utf8'), { window, document, Worker, URL, console });
  return { attributes, messages, worker, visibleCode, themeButtons, writes, themeMedia };
}
for (const mode of ['missing', 'constructor-failure', 'post-failure', 'working']) {
  const fixture = browserFixture(mode, true);
  assert.equal(fixture.attributes['data-docs-theme'], 'light', 'blocked storage uses automatic system theme');
  if (mode === 'working') {
    assert.equal(fixture.messages.length, 1, 'only visible, selected source is queued');
    assert.equal(fixture.messages[0].code, '<unsafe>');
    fixture.worker.onerror();
    assert.equal(fixture.worker.stopped, true);
  }
  assert.equal(fixture.visibleCode.innerHTML, '&lt;unsafe&gt;', 'worker failures preserve escaped source');
}
assert.equal(browserFixture('missing', false).attributes['data-docs-theme'], 'dark', 'saved theme applies before page initialization');
const themed = browserFixture('missing', false);
assert.equal(themed.themeButtons[2].attributes['aria-pressed'], 'true');
themed.themeButtons[0].listeners.click();
assert.equal(themed.themeButtons[0].attributes['aria-pressed'], 'true');
assert.equal(themed.themeButtons[2].attributes['aria-pressed'], 'false');
assert.equal(themed.writes.at(-1).key, 'haveapi.docs.preferences.v1');
assert.equal(JSON.parse(themed.writes.at(-1).value).theme, 'auto');
themed.themeMedia.matches = true;
themed.themeMedia.listener();
assert.equal(themed.attributes['data-docs-theme'], 'dark', 'automatic theme follows OS changes');
themed.themeButtons[1].listeners.click();
themed.themeMedia.listener();
assert.equal(themed.attributes['data-docs-theme'], 'light', 'explicit choice survives OS changes');
const blockedTheme = browserFixture('missing', true);
blockedTheme.themeButtons[2].listeners.click();
assert.equal(blockedTheme.attributes['data-docs-theme'], 'dark', 'native theme buttons work when storage is blocked');

const detailWrapper = { hidden: false };
const detailSelect = { value: '', closest: () => detailWrapper, addEventListener() {} };
const languageSelect = Object.assign(element('select'), { closest: () => null, replaceChildren() { this.children = []; } });
const detailPanels = ['capable', 'single'].flatMap(client => ['simple', 'thorough'].map(detail => ({
  client, detail, tagName: 'DETAILS', hidden: false, open: false,
  getAttribute(name) { return name === 'data-client' ? client : detail; }
})));
const geometry = { scroll: 0 };
const example = {
  isConnected: true,
  querySelectorAll: () => detailPanels, querySelector: () => ({ hidden: true }),
  getBoundingClientRect: () => ({ top: 100 + (detailPanels.find(panel => !panel.hidden)?.client === 'single' ? 80 : 0) - geometry.scroll, bottom: 600 })
};
const detailDisplay = {
  metadata: [{ id: 'capable', language: 'capable', language_label: 'Capable', details: ['simple', 'thorough'] },
    { id: 'single', language: 'single', language_label: 'Single', details: ['simple'] }],
  saved: { language: 'capable', detail: 'thorough' }, geometry, sidebar: { scrollTop: 17, addEventListener() {} },
  matches: { '[data-language-select]': [languageSelect], '[data-detail-select]': [detailSelect], '[data-example]': [example] }
};
const detailFixture = browserFixture('missing', false, detailDisplay);
assert.equal(detailSelect.value, 'thorough');
assert.equal(detailWrapper.hidden, false);
languageSelect.value = 'single'; languageSelect.listeners.change();
assert.equal(detailWrapper.hidden, true); assert.equal(detailSelect.disabled, true);
assert.equal(detailSelect.value, 'simple');
assert.equal(detailPanels.find(panel => !panel.hidden).detail, 'simple');
assert.equal(JSON.parse(detailFixture.writes.at(-1).value).detail, 'thorough', 'incapable clients never replace the saved preference');
assert.equal(example.getBoundingClientRect().top, 100, 'capability changes preserve the stable example position');
assert.equal(geometry.scroll, 80, 'scroll compensation covers layout movement');
languageSelect.value = 'capable'; languageSelect.listeners.change();
assert.equal(detailWrapper.hidden, false); assert.equal(detailSelect.disabled, false);
assert.equal(detailPanels.find(panel => !panel.hidden).detail, 'thorough');
assert.equal(detailSelect.value, 'thorough'); assert.equal(geometry.scroll, 0);
detailDisplay.metadata[1].details = null;
browserFixture('missing', false, { ...detailDisplay, saved: { language: 'single', detail: 'thorough' } });
assert.equal(detailSelect.disabled, true); assert.equal(detailWrapper.hidden, true);
assert.equal(detailPanels.find(panel => !panel.hidden).client, 'single', 'malformed metadata must not discard the renderer');
assert.equal(detailPanels.find(panel => !panel.hidden).detail, 'simple');
delete detailDisplay.metadata[1].details;
browserFixture('missing', false, { ...detailDisplay, saved: { language: 'single', detail: 'thorough' } });
assert.equal(detailSelect.disabled, false); assert.equal(detailWrapper.hidden, false);
assert.equal(detailPanels.find(panel => !panel.hidden).detail, 'thorough', 'missing metadata keeps legacy two-level markup');

const fixture = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../documentation/fixtures/search_index.json'), 'utf8'));
const key = 'a'.repeat(64);
const action = 'https://docs.example' + fixture.index.base_path;
const indexURL = action + '?page=resources&search_index=' + key;
const config = searchConfiguration(action, indexURL, key, fixture.index.version, current, false);
assert.equal(config.base_path, fixture.index.base_path);
assert.equal(config.key, key);
assert.equal(searchConfiguration(action, indexURL, key, fixture.index.version, current, true).url, action + '?page=resources&search_index=current');
assert.equal(searchConfiguration(action, action + '?page=resources&search_index=current', '', fixture.index.version, current, false).key, '');
assert.equal(searchConfiguration(action, 'https://foreign.example/api/v1/?page=resources&search_index=' + key, key, '1', current, false), null);
assert.equal(searchConfiguration(action, indexURL + '&q=secret', key, '1', current, false), null);
assert.equal(searchConfiguration(action, indexURL, '', '1', current, false), null);
assert.equal(searchConfiguration(action, indexURL.replace(key, 'b'.repeat(64)), key, '1', current, false), null);
const index = validateSearchIndex({ key, index: fixture.index }, config);
const matchIndex = searchMatcher(index);
for (const example of fixture.queries) {
  const result = matchIndex(example.query);
  const identities = result.results.map(item => [item.kind, item.authentication || '', item.resource_path.join('.'), item.action_name || '', item.direction || '', item.name].join(':'));
  assert.deepEqual(identities, example.expected, example.query + ': shared Ruby/browser kind-first ordering');
  assert.equal(result.more, example.more, example.query);
}
for (const example of fixture.display_queries) {
  const rendered = matchIndex(example.query).results.map(result => renderSearchResult(elements, index, result, config.origin));
  assert.deepEqual(rendered.map(item => ({ title: item.children[0].textContent, context: item.children.slice(1).map(span => span.textContent) })),
    example.expected, example.query + ': actual suggestion title/context matches native HTML');
}
const labelIndex = { resources: [
  { path: ['same'], label: 'Application', authentication: null, search: ['needle'] },
  { path: ['same', 'child'], label: 'Child', authentication: null, search: ['needle'] },
  { path: ['same'], label: 'Provider', authentication: 'token', search: ['needle'] },
  { path: ['same', 'child'], label: 'Member', authentication: 'token', search: ['needle'] },
  { path: ['missing', 'child'], label: 'Leaf', authentication: null, search: ['needle'] }
], actions: [], parameters: [] };
const labels = searchMatcher(labelIndex)('needle').results;
assert.equal(labels.find(result => result.resource_path.join('.') === 'same.child' && result.authentication === null).resource_label, 'Application / Child');
assert.equal(labels.find(result => result.resource_path.join('.') === 'same.child' && result.authentication === 'token').resource_label, 'Provider / Member');
assert.equal(labels.find(result => result.resource_path[0] === 'missing').resource_label, 'missing / Leaf');
const identical = renderSearchResult(elements, index, { kind: 'resource', resource_path: ['same'], resource_label: 'same', authentication: null }, config.origin);
assert.equal(identical.children.length, 1, 'identical resource context is omitted');
const emptyLabel = renderSearchResult(elements, index, { kind: 'resource', resource_path: ['same'], resource_label: '', authentication: null }, config.origin);
assert.equal(emptyLabel.children[1].textContent, '', 'valid empty labels preserve native HTML presentation semantics');
for (const mutate of [
  value => { value.key = 'b'.repeat(64); },
  value => { value.index.format = 2; },
  value => { value.index.version = 'other'; },
  value => { value.index.base_path = '//foreign.example/'; },
  value => { value.index.visibility = 'unknown'; },
  value => { value.index.resources[0].secret = 'not part of projection'; },
  value => { value.index.resources[0].search = 'not an array'; },
  value => { value.index.resources[0].path = []; },
  value => { value.index.resources[0].label = '\ud800'; },
  value => { value.index.actions[0].resource = -1; },
  value => { value.index.actions[0].resource = value.index.resources.length; },
  value => { value.index.actions[0].identifiers = [null]; },
  value => { value.index.parameters[0].action = 0.5; },
  value => { value.index.parameters[0].direction = 'both'; },
  value => { value.index.parameters[0].type = null; }
]) {
  const envelope = JSON.parse(JSON.stringify({ key, index: fixture.index }));
  mutate(envelope);
  assert.throws(() => validateSearchIndex(envelope, config));
}
const unicodeResult = { kind: 'parameter', authentication: 'token', resource_path: ['síť', 'a.b'], action_name: 'vytvoř', direction: 'input', name: 'číslo_😀' };
const unicodeURL = new URL(searchResultURL(index, unicodeResult, config.origin));
assert.equal(unicodeURL.origin, config.origin);
assert.equal(unicodeURL.searchParams.get('page'), 'authentication');
assert.deepEqual(JSON.parse(Buffer.from(unicodeURL.hash.slice('#parameter-'.length), 'hex').toString('utf8')), ['token', ['síť', 'a.b'], 'vytvoř', 'input', 'číslo_😀']);
assert.notEqual(searchResultURL(index, { ...unicodeResult, resource_path: ['síť.a', 'b'] }, config.origin), unicodeURL.href);
assert.throws(() => searchResultURL({ base_path: '//foreign.example/' }, unicodeResult, config.origin));
const unusualResource = new URL(searchResultURL(index, { kind: 'resource', authentication: null,
  resource_path: ['https://foreign.example/?q=<script>'], action_name: null }, config.origin));
assert.equal(unusualResource.origin, config.origin);
assert.equal(unusualResource.searchParams.get('resource'), 'https://foreign.example/?q=<script>');

function clipboardFixture(secure, nativeResult) {
  const body = Object.assign(element('body'), { scrollLeft: 9, scrollTop: 33 });
  const active = Object.assign(element('input'), { isConnected: true, scrollLeft: 3, scrollTop: 7,
    selectionStart: 2, selectionEnd: 6, selectionDirection: 'backward' });
  body.appendChild(active);
  const range = { name: 'original selection', cloneRange() { return this; } };
  const selection = { ranges: [range], get rangeCount() { return this.ranges.length; },
    getRangeAt(index) { return this.ranges[index]; }, removeAllRanges() { this.ranges = []; }, addRange(value) { this.ranges.push(value); } };
  const win = { isSecureContext: secure, location: { protocol: secure ? 'https:' : 'http:' }, scrollX: 4, scrollY: 321,
    getSelection: () => selection, scrollTo(x, y) { this.scrollX = x; this.scrollY = y; } };
  const copied = [];
  const doc = { body, activeElement: active,
    createElement(tag) {
      const field = element(tag);
      field.focus = options => {
        assert.equal(options.preventScroll, true); doc.activeElement = field;
        win.scrollX = 999; win.scrollY = 999; body.scrollTop = 999; active.scrollTop = 999;
      };
      field.select = () => { selection.ranges = []; active.selectionStart = 0; active.selectionEnd = 0; };
      return field;
    },
    execCommand(command) {
      assert.equal(command, 'copy'); copied.push(doc.activeElement.value);
      if (nativeResult === 'throw') throw new Error('clipboard denied');
      return nativeResult;
    }
  };
  active.focus = options => { assert.equal(options.preventScroll, true); doc.activeElement = active; };
  active.setSelectionRange = (start, end, direction) => { active.selectionStart = start; active.selectionEnd = end; active.selectionDirection = direction; };
  return { win, doc, copied, assertRestored() {
    assert.equal(doc.activeElement, active);
    assert.deepEqual([active.selectionStart, active.selectionEnd, active.selectionDirection], [2, 6, 'backward']);
    assert.deepEqual(selection.ranges, [range]); assert.deepEqual([win.scrollX, win.scrollY], [4, 321]);
    assert.equal(body.scrollTop, 33); assert.equal(active.scrollTop, 7);
    assert.deepEqual(body.children, [active], 'temporary clipboard field is removed');
  } };
}

(async () => {
  const exactText = '  <unsafe>\n\tcurrent example\n';
  const secure = clipboardFixture(true, true);
  const secureCalls = [];
  const secureResult = copyText(exactText, secure.win, secure.doc, { clipboard: { writeText(text) { secureCalls.push(text); return Promise.resolve(); } } });
  assert.deepEqual(secureCalls, [exactText], 'secure clipboard starts synchronously in the click gesture with exact text');
  assert.equal(await secureResult, true); assert.deepEqual(secure.copied, []); secure.assertRestored();
  assert.equal(await copyText(exactText, secure.win, secure.doc, { clipboard: { writeText() { return Promise.reject(new Error('denied')); } } }), false);
  assert.equal(await copyText(exactText, secure.win, secure.doc, {}), false, 'missing secure API offers honest manual copy');
  assert.deepEqual(secure.copied, [], 'denied secure clipboard does not invoke a second clipboard mechanism');
  secure.assertRestored();
  for (const outcome of [true, false, 'throw']) {
    const native = clipboardFixture(false, outcome);
    assert.equal(await copyText(exactText, native.win, native.doc, {}), outcome === true);
    assert.deepEqual(native.copied, [exactText]); native.assertRestored();
  }
  const unsupported = clipboardFixture(false, true); unsupported.doc.execCommand = undefined;
  assert.equal(await copyText(exactText, unsupported.win, unsupported.doc, {}), false); unsupported.assertRestored();

  function copyPanel(text, hidden) {
    const panel = Object.assign(element('details'), { hidden, open: !hidden,
      closest: () => panel.hidden ? panel : null, getClientRects: () => panel.hidden ? [] : [{}] });
    const pre = element('pre'); const code = element('code'); code.textContent = text;
    panel.appendChild(pre); pre.appendChild(code);
    panel.querySelector = selector => { assert.equal(selector, ':scope > pre > code'); return code; };
    return { panel, pre, code };
  }
  const simple = copyPanel(exactText, false); const thorough = copyPanel(' other panel\n', true);
  let release;
  let mode = 'success';
  const panelCopies = [];
  const clearCopies = exampleCopyControls({ querySelectorAll(selector) {
    assert.equal(selector, '[data-example] > [data-example-panel] > pre > code', 'guide/limitation blocks are outside copy controls');
    return [simple.code, thorough.code];
  } }, secure.win, elements, { clipboard: { writeText(text) {
    panelCopies.push(text);
    return mode === 'pending' ? new Promise(resolve => { release = resolve; })
      : mode === 'failure' ? Promise.reject(new Error('denied')) : Promise.resolve();
  } } });
  const button = pair => pair.panel.children.find(child => child.tagName === 'BUTTON');
  const status = pair => pair.panel.children.find(child => child.tagName === 'SPAN');
  const flush = () => new Promise(resolve => setImmediate(resolve));
  assert.equal(button(simple).attributes['aria-label'], 'Copy example');
  assert.equal(button(simple).type, 'button');
  assert.equal(status(simple).attributes['aria-live'], 'polite');
  assert.deepEqual(simple.pre.children, [simple.code], 'controls remain outside code/highlighter ownership');
  button(thorough).listeners.click(); assert.equal(panelCopies.length, 0, 'hidden panels cannot copy');
  button(simple).listeners.click(); await flush();
  assert.deepEqual(panelCopies, [exactText]); assert.equal(status(simple).textContent, 'Copied');
  simple.panel.hidden = true; simple.panel.open = false; thorough.panel.hidden = false; thorough.panel.open = true; clearCopies();
  thorough.code.textContent = '\n updated currently visible error-handling text\n';
  button(thorough).listeners.click(); await flush();
  assert.equal(panelCopies.at(-1), thorough.code.textContent, 'click reads current selected panel text, not an earlier snapshot');
  assert.equal(status(thorough).textContent, 'Copied');
  mode = 'pending'; button(thorough).listeners.click();
  thorough.panel.hidden = true; thorough.panel.open = false; simple.panel.hidden = false; simple.panel.open = true; clearCopies();
  release(); await flush(); assert.equal(status(thorough).textContent, ''); assert.equal(status(simple).textContent, '', 'obsolete completion announces neither panel');
  mode = 'failure'; button(simple).listeners.click(); await flush();
  assert.equal(status(simple).textContent, 'Select the code and copy it.');
  simple.panel.open = false; button(simple).listeners.click(); assert.equal(panelCopies.length, 4, 'closed details cannot copy');

  const operations = [];
  class Controller {
    constructor() { this.signal = { aborted: false }; }
    abort() { this.signal.aborted = true; }
  }
  const loader = searchIndexLoader((url, options) => new Promise((resolve, reject) => operations.push({ url, options, resolve, reject })), Controller,
    (html, expected) => validateSearchIndex(JSON.parse(html), expected));
  assert.equal(operations.length, 0, 'constructing an index loader must not fetch on page load');
  const first = loader.load(config);
  const second = loader.load(config);
  assert.equal(first, second, 'forms share the same pending index load');
  await Promise.resolve();
  assert.equal(operations.length, 1);
  assert.equal(operations[0].options.cache, 'default');
  assert.equal(operations[0].options.credentials, 'same-origin');
  assert.equal(operations[0].options.redirect, 'error');
  assert.equal(operations[0].options.headers.Accept, 'text/html');
  operations[0].resolve({ ok: true, text: async () => JSON.stringify({ key, index }) });
  const loaded = await first;
  assert.equal(loader.peek(config), loaded);
  assert.equal(await loader.load(config), loaded, 'warm queries reuse document memory');
  assert.equal(operations.length, 1);
  loader.reset();
  assert.equal(loader.peek(config), null, 'BFCache restoration discards the prior proof');
  const boot = searchConfiguration(action, indexURL, key, config.version, current, true);
  const pending = loader.load(boot);
  await Promise.resolve();
  loader.reset();
  assert.equal(operations[1].options.signal.aborted, true);
  operations[1].resolve({ ok: true, text: async () => JSON.stringify({ key, index }) });
  await assert.rejects(pending);
  assert.equal(loader.peek(boot), null, 'obsolete completions cannot restore discarded snapshots');
  const failed = loader.load(config);
  await Promise.resolve();
  operations[2].resolve({ ok: false });
  await assert.rejects(failed);
  const retry = loader.load(config);
  await Promise.resolve();
  operations[3].resolve({ ok: true, text: async () => JSON.stringify({ key: 'b'.repeat(64), index }) });
  await assert.rejects(retry, 'mismatched proof must use the normal-search fallback');
  console.log('Documentation controls, clipboard preservation, shared search display, strict projection and lazy cache loading passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
