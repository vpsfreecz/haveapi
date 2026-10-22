'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
class Element {
  constructor(tag, document) {
    this.tagName = tag.toUpperCase(); this.document = document;
    this.children = []; this.attributes = {}; this.listeners = {};
    const classes = new Set();
    this.classList = { add: (...values) => values.forEach(value => classes.add(value)), remove: value => classes.delete(value), contains: value => classes.has(value) };
    this.textContent = '';
  }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  getAttribute(name) { return this.attributes[name]; }
  appendChild(child) { child.parentElement = this; this.children.push(child); return child; }
  removeChild(child) { this.children.splice(this.children.indexOf(child), 1); }
  addEventListener(name, handler) { this.listeners[name] = handler; }
  querySelectorAll(selector) {
    const matches = element => selector === '[role="tab"]' ? element.getAttribute('role') === 'tab' : selector[0] === '.' ? element.classList.contains(selector.slice(1)) : element.tagName === selector.toUpperCase();
    return this.children.flatMap(child => [...(matches(child) ? [child] : []), ...child.querySelectorAll(selector)]);
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0]; }
  getElementsByTagName(name) { return this.querySelectorAll(name); }
  focus() { this.document.activeElement = this; }
}
const document = { createElement: tag => new Element(tag, document), createTextNode: value => Object.assign(new Element('#text', document), { textContent: value }) };
const page = document.createElement('main');
document.getElementById = id => [page, ...page.querySelectorAll('div')].find(element => element.id === id);
const tabs = page.appendChild(document.createElement('div')); tabs.id = 'examples';
const bar = page.appendChild(document.createElement('div')); bar.id = 'bar';
for (let index = 0; index < 3; index++) {
  const panel = tabs.appendChild(document.createElement('div')); panel.id = 'example-' + index;
  const heading = panel.appendChild(document.createElement('h4')); heading.textContent = 'Language ' + index;
}
const context = vm.createContext({ window: {}, document, history: { pushState() {} }, location: { hash: '' } });
vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../../../lib/haveapi/public/js/nojs-tabs.js'), 'utf8'), context);
context.window.nojsTabs({ tabs, tabBar: bar, titleSelector: 'h4', hiddenClass: 'tab-hidden', activeClass: 'active' });
const links = bar.querySelectorAll('[role="tab"]');
assert.equal(links.length, 3);
assert.equal(links[0].getAttribute('aria-selected'), 'true');
assert.equal(links[1].getAttribute('tabindex'), '-1');
for (const link of links) assert(!link.parentElement.classList.contains('tab-hidden'));
const key = (index, value) => links[index].listeners.keydown({ key: value, preventDefault() {} });
key(0, 'ArrowRight');
assert.equal(document.activeElement, links[1]);
assert.equal(tabs.children[1].getAttribute('aria-hidden'), 'false');
assert.equal(tabs.children[0].getAttribute('aria-hidden'), 'true');
key(1, 'End'); assert.equal(document.activeElement, links[2]);
key(2, 'ArrowRight'); assert.equal(document.activeElement, links[0]);
key(0, 'ArrowLeft'); assert.equal(document.activeElement, links[2]);
key(2, 'Home'); assert.equal(document.activeElement, links[0]);
context.window.nojsTabs({ tabs: document.createElement('div'), tabBar: document.createElement('div') });
console.log('Keyboard tabs, accessible state and empty panels passed');
