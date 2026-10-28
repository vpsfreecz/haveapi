(function () {
  'use strict';

  var storageKey = 'haveapi.docs.preferences.v1';

  function preferences(value) {
    var source = value && typeof value === 'object' ? value : {};
    var clients = Object.create(null);
    if (source.clients && typeof source.clients === 'object') {
      Object.keys(source.clients).forEach(function (language) {
        if (typeof source.clients[language] === 'string') clients[language] = source.clients[language];
      });
    }
    return {
      theme: ['auto', 'light', 'dark'].indexOf(source.theme) >= 0 ? source.theme : 'auto',
      language: typeof source.language === 'string' ? source.language : '',
      clients: clients,
      detail: source.detail === 'thorough' ? 'thorough' : 'simple'
    };
  }

  function readPreferences(storage) {
    try { return preferences(JSON.parse(storage.getItem(storageKey))); }
    catch (error) { return preferences(null); }
  }

  function clientChoice(state, clients) {
    if (!clients.length) return null;
    var group = clients.filter(function (client) { return client.language === state.language; });
    if (!group.length) group = clients.filter(function (client) { return client.language === clients[0].language; });
    return group.find(function (client) { return client.id === state.clients[group[0].language]; }) || group[0];
  }

  function detailLevels(client) {
    if (client && client.details === undefined) return ['simple', 'thorough'];
    var levels = client && client.details;
    return Array.isArray(levels) && levels.length === 2 && levels[0] === 'simple' && levels[1] === 'thorough'
      ? ['simple', 'thorough'] : ['simple'];
  }

  function effectiveDetail(state, client) {
    return detailLevels(client).includes(state.detail) ? state.detail : 'simple';
  }

  function nativeCopy(text, win, doc) {
    if (typeof doc.execCommand !== 'function') return false;
    var active = doc.activeElement;
    var selection = win.getSelection ? win.getSelection() : null;
    var ranges = [];
    var scroll = [];
    var inputSelection = active && typeof active.selectionStart === 'number'
      ? [active.selectionStart, active.selectionEnd, active.selectionDirection] : null;
    var x = win.scrollX;
    var y = win.scrollY;
    if (selection) for (var i = 0; i < selection.rangeCount; i += 1) ranges.push(selection.getRangeAt(i).cloneRange());
    for (var ancestor = active; ancestor; ancestor = ancestor.parentElement) {
      scroll.push({ element: ancestor, left: ancestor.scrollLeft, top: ancestor.scrollTop });
    }
    var field = doc.createElement('textarea');
    field.value = text;
    field.tabIndex = -1;
    field.setAttribute('readonly', '');
    field.style.cssText = 'position:fixed;top:0;left:0;width:1px;height:1px;padding:0;border:0;opacity:0;pointer-events:none';
    try {
      doc.body.appendChild(field);
      field.focus({ preventScroll: true });
      field.select();
      return doc.execCommand('copy') === true;
    } catch (error) { return false; }
    finally {
      field.remove();
      if (active && active.isConnected) {
        try {
          active.focus({ preventScroll: true });
          if (inputSelection) active.setSelectionRange.apply(active, inputSelection);
        } catch (error) { /* A removed or disabled control cannot regain focus. */ }
      }
      if (selection) {
        try { selection.removeAllRanges(); ranges.forEach(function (range) { selection.addRange(range); }); }
        catch (error) { /* A selection may refer to content removed by the page. */ }
      }
      scroll.forEach(function (position) { position.element.scrollLeft = position.left; position.element.scrollTop = position.top; });
      win.scrollTo(x, y);
    }
  }

  function copyText(text, win, doc, navigator) {
    try {
      if (win.isSecureContext && navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        return Promise.resolve(navigator.clipboard.writeText(text)).then(function () { return true; }, function () { return false; });
      }
      return Promise.resolve(!win.isSecureContext && win.location.protocol === 'http:' && nativeCopy(text, win, doc));
    } catch (error) { return Promise.resolve(false); }
  }

  function visibleExampleCode(panel) {
    if (panel.closest('[hidden]') || (panel.tagName === 'DETAILS' && !panel.open) || !panel.getClientRects().length) return null;
    return panel.querySelector(':scope > pre > code');
  }

  function exampleCopyControls(root, win, doc, navigator) {
    var generation = 0;
    var statuses = [];
    function clear() { generation += 1; statuses.forEach(function (status) { status.textContent = ''; }); }
    Array.from(root.querySelectorAll('[data-example] > [data-example-panel] > pre > code')).forEach(function (source) {
      var pre = source.parentElement;
      var panel = pre.parentElement;
      var button = doc.createElement('button');
      button.type = 'button';
      button.setAttribute('data-copy-example', '');
      button.setAttribute('aria-label', 'Copy example');
      button.title = 'Copy example';
      var icon = doc.createElementNS('http://www.w3.org/2000/svg', 'svg');
      icon.setAttribute('viewBox', '0 0 24 24');
      icon.setAttribute('aria-hidden', 'true');
      icon.setAttribute('focusable', 'false');
      icon.setAttribute('fill', 'none');
      icon.setAttribute('stroke', 'currentColor');
      icon.setAttribute('stroke-width', '2');
      var outline = doc.createElementNS('http://www.w3.org/2000/svg', 'path');
      outline.setAttribute('d', 'M8 8h12v13H8zM16 8V3H3v13h5');
      icon.appendChild(outline);
      button.appendChild(icon);
      var status = doc.createElement('span');
      status.className = 'docs-copy-status';
      status.setAttribute('role', 'status');
      status.setAttribute('aria-live', 'polite');
      panel.classList.add('docs-copy-panel');
      panel.insertBefore(button, pre);
      panel.insertBefore(status, pre);
      statuses.push(status);
      button.addEventListener('click', function () {
        var code = visibleExampleCode(panel);
        if (!code) return;
        clear();
        var current = generation;
        copyText(code.textContent, win, doc, navigator).then(function (success) {
          if (current !== generation || visibleExampleCode(panel) !== code) return;
          status.textContent = success ? 'Copied' : 'Select the code and copy it.';
        });
      });
    });
    return clear;
  }

  function disclosureMenus(root, sidebar, win, doc) {
    var menus = Array.from(root.querySelectorAll('[data-theme-menu], [data-account-menu]'));
    function position(menu) {
      if (!menu.open) return;
      var content = menu.querySelector('.docs-theme-choices, .docs-account-content');
      if (!content) return;
      var bounds = sidebar ? sidebar.getBoundingClientRect() : { left: 0, right: win.innerWidth };
      var left = menu.getBoundingClientRect().left;
      var desired = Math.max(bounds.left + 8, Math.min(left, bounds.right - content.getBoundingClientRect().width - 8));
      content.style.left = (desired - left) + 'px';
    }
    menus.forEach(function (menu) {
      menu.addEventListener('toggle', function () {
        if (menu.open) menus.forEach(function (other) { if (other !== menu) other.open = false; });
        position(menu);
      });
      menu.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape' || !menu.open) return;
        event.preventDefault();
        event.stopPropagation();
        menu.open = false;
        menu.querySelector('summary').focus({ preventScroll: true });
      });
    });
    doc.addEventListener('pointerdown', function (event) {
      menus.forEach(function (menu) { if (!menu.contains(event.target)) menu.open = false; });
    });
    win.addEventListener('resize', function () { menus.forEach(position); });
    return function () { menus.forEach(function (menu) { menu.open = false; }); };
  }

  function legacyTarget(fragment, anchors) {
    var anchor;
    try { anchor = decodeURIComponent(fragment.replace(/^#/, '')); }
    catch (error) { return null; }
    var keys = Object.keys(anchors).sort(function (left, right) { return right.length - left.length; });
    var key = keys.find(function (entry) {
      return anchor === entry || (entry.indexOf('example-') === 0 && anchor.indexOf(entry) === 0);
    });
    return key && typeof anchors[key] === 'string' ? anchors[key] : null;
  }

  function loginTarget(href, currentHref, fragment) {
    var url;
    var current;
    try { current = new URL(currentHref); url = new URL(href, current); }
    catch (error) { return null; }
    if (url.origin !== current.origin || url.username || url.password) return null;
    var anchor = fragment.replace(/^#/, '');
    url.searchParams.delete('fragment');
    if (/^[A-Za-z0-9_.-]{1,256}$/.test(anchor)) url.searchParams.set('fragment', anchor);
    return url.href;
  }

  function highlighterTarget(scriptSrc, currentHref, suppliedURL) {
    try {
      if (!scriptSrc && !suppliedURL) return null;
      var current = new URL(currentHref);
      var url = suppliedURL ? new URL(suppliedURL, current) : new URL('highlighter.js', scriptSrc);
      return url.origin === current.origin && !url.username && !url.password ? url.href : null;
    } catch (error) { return null; }
  }

  function basicAuthentication(href, currentHref, logout, createRequest, reload) {
    var url;
    try { url = new URL(href, currentHref); }
    catch (error) { return false; }
    if (url.origin !== new URL(currentHref).origin) return false;
    url.username = '';
    url.password = '';
    var request = createRequest();
    // Preserve the legacy browser Basic challenge and dummy-credential logout
    // without navigating to the endpoint's otherwise empty response page.
    if (logout) request.open('GET', url.href, true, '_log', 'out');
    else request.open('GET', url.href, true);
    request.onloadend = reload;
    request.send();
    return true;
  }

  function activeSection(sections, scrollPadding) {
    var active = null;
    var padding = parseFloat(scrollPadding) || 0;
    sections.forEach(function (section) {
      // Native fragment scrolling combines root padding and target margin.
      // Allow one pixel for fractional layout rounding at the landing point.
      if (section.top <= padding + (parseFloat(section.margin) || 0) + 1) active = section;
    });
    return active || sections[0] || null;
  }

  function navigationTargets(fragments, lookup) {
    var seen = new Set();
    return fragments.map(function (fragment) {
      if (!fragment || fragment.charAt(0) !== '#') return null;
      try { return lookup(decodeURIComponent(fragment.slice(1))); }
      catch (error) { return null; }
    }).filter(function (target) {
      if (!target || seen.has(target)) return false;
      seen.add(target);
      return true;
    });
  }

  function searchConfiguration(action, indexURL, key, version, currentHref, bootstrap) {
    try {
      var current = new URL(currentHref);
      var base = new URL(action, current);
      var url = new URL(indexURL, current);
      if (!/^https?:$/.test(base.protocol) || base.origin !== current.origin || base.username || base.password
        || base.search || base.hash || !base.pathname.endsWith('/') || url.origin !== base.origin
        || url.pathname !== base.pathname || url.username || url.password || url.hash
        || Array.from(url.searchParams).length !== 2 || url.searchParams.getAll('page').length !== 1
        || url.searchParams.get('page') !== 'resources' || url.searchParams.getAll('search_index').length !== 1
        || typeof version !== 'string' || !version || (key !== '' && !/^[a-f0-9]{64}$/.test(key))) return null;
      if (url.searchParams.get('search_index') !== (key || 'current')) return null;
      if (bootstrap) { url.searchParams.set('search_index', 'current'); key = ''; }
      return { url: url.href, origin: base.origin, base_path: base.pathname, version: version, key: key };
    } catch (error) { return null; }
  }

  function validateSearchIndex(envelope, expected) {
    function fail() { throw new Error('Invalid documentation search index'); }
    function shape(object, fields) {
      if (!object || typeof object !== 'object' || Array.isArray(object)
        || Object.keys(object).length !== fields.length
        || !fields.every(function (field) { return Object.prototype.hasOwnProperty.call(object, field); })) fail();
    }
    function string(value) {
      if (typeof value !== 'string') fail();
      Array.from(value).forEach(function (character) {
        var code = character.codePointAt(0);
        if (code >= 0xd800 && code <= 0xdfff) fail();
      });
    }
    function strings(values) { if (!Array.isArray(values)) fail(); values.forEach(string); }
    function parent(value, length) { if (!Number.isInteger(value) || value < 0 || value >= length) fail(); }
    shape(envelope, ['key', 'index']);
    if (typeof envelope.key !== 'string' || !/^[a-f0-9]{64}$/.test(envelope.key)
      || (expected.key && envelope.key !== expected.key)) fail();
    var index = envelope.index;
    shape(index, ['format', 'version', 'base_path', 'locale', 'visibility', 'resources', 'actions', 'parameters']);
    if (index.format !== 1 || index.version !== expected.version || index.base_path !== expected.base_path
      || ['anonymous', 'authenticated'].indexOf(index.visibility) < 0) fail();
    ['version', 'base_path', 'locale', 'visibility'].forEach(function (field) { string(index[field]); });
    if (!Array.isArray(index.resources) || !Array.isArray(index.actions) || !Array.isArray(index.parameters)) fail();
    index.resources.forEach(function (resource) {
      shape(resource, ['path', 'label', 'authentication', 'search']);
      strings(resource.path);
      if (!resource.path.length) fail();
      string(resource.label);
      if (resource.authentication !== null) string(resource.authentication);
      strings(resource.search);
    });
    index.actions.forEach(function (action) {
      shape(action, ['resource', 'name', 'label', 'identifiers', 'search']);
      parent(action.resource, index.resources.length);
      string(action.name); string(action.label); strings(action.identifiers); strings(action.search);
    });
    index.parameters.forEach(function (parameter) {
      shape(parameter, ['action', 'name', 'label', 'type', 'direction', 'humanized_name']);
      parent(parameter.action, index.actions.length);
      ['name', 'label', 'type', 'direction', 'humanized_name'].forEach(function (field) { string(parameter[field]); });
      if (['input', 'output'].indexOf(parameter.direction) < 0) fail();
    });
    return index;
  }

  function searchMatcher(index) {
    var labels = new Map(index.resources.map(function (resource) {
      return [JSON.stringify([resource.authentication, resource.path]), resource.label];
    }));
    var resourceLabels = new Map(index.resources.map(function (resource) {
      return [resource, resource.path.map(function (name, position) {
        var key = JSON.stringify([resource.authentication, resource.path.slice(0, position + 1)]);
        return labels.has(key) ? labels.get(key) : name;
      }).join(' / ')];
    }));
    var resourceText = index.resources.map(function (resource) { return resource.search.join(' ').toLowerCase(); });
    var actionText = index.actions.map(function (action) { return action.identifiers.concat(action.search).join(' ').toLowerCase(); });
    var parameterText = index.parameters.map(function (parameter) {
      return [parameter.name, parameter.label, parameter.type, parameter.direction, parameter.humanized_name].join(' ').toLowerCase();
    });
    function compare(left, right) {
      for (var field = 0; field < left.length; field += 1) {
        if (typeof left[field] === 'number') { if (left[field] !== right[field]) return left[field] - right[field]; }
        else {
          var a = Array.from(left[field]); var b = Array.from(right[field]);
          for (var part = 0; part < Math.min(a.length, b.length); part += 1) {
            if (a[part] !== b[part]) return a[part].codePointAt(0) - b[part].codePointAt(0);
          }
          if (a.length !== b.length) return a.length - b.length;
        }
      }
      return 0;
    }
    return function (query) {
      var needle = query.trim().toLowerCase();
      if (!needle || Array.from(needle).length > 256) return { results: [], more: false };
      var tokens = needle.split(/[\s\u0085]+/u);
      var matches = [];
      function match(kind, resource, action, parameter, texts, identifiers) {
        if (!tokens.every(function (token) { return texts.some(function (text) { return text.includes(token); }); })) return;
        var names = identifiers.map(function (name) { return name.toLowerCase(); });
        var rank = names.includes(needle) ? 0 : names.some(function (name) { return name.startsWith(needle); }) ? 1 : 2;
        var name = parameter ? parameter.name : action ? action.name : resource.path[resource.path.length - 1];
        var record = { kind: ['resource', 'action', 'parameter'][kind], resource_path: resource.path,
          authentication: resource.authentication, action_name: action ? action.name : null,
          name: name, label: parameter ? parameter.label : action ? action.label : resource.label,
          resource_label: resourceLabels.get(resource),
          direction: parameter ? parameter.direction : null, type: parameter ? parameter.type : null };
        matches.push({ record: record, order: [kind, rank, resource.authentication || '', resource.path.join('.'),
          action ? action.name : '', name, parameter ? parameter.direction : ''] });
      }
      index.resources.forEach(function (resource, position) {
        match(0, resource, null, null, [resourceText[position]], [resource.path[resource.path.length - 1], resource.path.join('.')]);
      });
      index.actions.forEach(function (action, position) {
        match(1, index.resources[action.resource], action, null, [resourceText[action.resource], actionText[position]], action.identifiers);
      });
      index.parameters.forEach(function (parameter, position) {
        var action = index.actions[parameter.action];
        match(2, index.resources[action.resource], action, parameter,
          [resourceText[action.resource], actionText[parameter.action], parameterText[position]], [parameter.name]);
      });
      matches.sort(function (left, right) { return compare(left.order, right.order); });
      return { results: matches.slice(0, 20).map(function (entry) { return entry.record; }), more: matches.length > 20 };
    };
  }

  function searchResultURL(index, result, origin) {
    var url = new URL(index.base_path, origin);
    if (url.origin !== new URL(origin).origin || url.pathname !== index.base_path || url.search || url.hash) throw new Error('Invalid search base path');
    var anchor = 'root-' + result.resource_path.join('-') + (result.action_name === null ? '' : '-' + result.action_name);
    if (result.kind === 'parameter') {
      var tuple = [result.authentication, result.resource_path, result.action_name, result.direction, result.name];
      anchor = 'parameter-' + Array.from(new TextEncoder().encode(JSON.stringify(tuple)))
        .map(function (byte) { return byte.toString(16).padStart(2, '0'); }).join('');
    }
    if (result.authentication !== null) url.searchParams.set('page', 'authentication');
    else url.searchParams.set('resource', result.resource_path.join('.'));
    if (result.kind !== 'resource' || result.authentication !== null) url.hash = anchor;
    return url.href;
  }

  function renderSearchResult(doc, index, result, origin) {
    var item = doc.createElement('li');
    var link = doc.createElement('a');
    var name = result.kind === 'resource' ? result.resource_path.join('.') : result.name;
    link.href = searchResultURL(index, result, origin);
    link.textContent = result.kind.charAt(0).toUpperCase() + result.kind.slice(1) + ': ';
    var code = doc.createElement('code');
    code.textContent = name;
    link.appendChild(code);
    item.appendChild(link);
    var context = [];
    if (result.kind === 'resource') {
      if (typeof result.resource_label === 'string' && result.resource_label !== name) context.push(result.resource_label);
    } else {
      context.push(result.resource_path.join('.') + (result.action_name !== null ? ' · ' + result.action_name : ''));
    }
    if (result.kind === 'parameter') context.push(result.direction.charAt(0).toUpperCase() + result.direction.slice(1) + ' · ' + result.type);
    if (result.authentication !== null) context.push('Authentication: ' + result.authentication);
    if (result.kind !== 'resource' && typeof result.label === 'string' && result.label !== result.name) context.push(result.label);
    context.forEach(function (text) {
      var detail = doc.createElement('span');
      detail.textContent = text;
      item.appendChild(detail);
    });
    return item;
  }

  function searchIndexLoader(fetcher, Controller, parse) {
    var entries = new Map();
    var epoch = 0;
    function entryKey(config) { return JSON.stringify([config.url, config.version, config.key]); }
    return {
      peek: function (config) { var entry = entries.get(entryKey(config)); return entry ? entry.snapshot || null : null; },
      reset: function () {
        epoch += 1;
        entries.forEach(function (entry) { entry.controller.abort(); });
        entries.clear();
      },
      load: function (config) {
        var key = entryKey(config);
        if (entries.has(key)) return entries.get(key).promise;
        var current = epoch;
        var entry = { controller: new Controller(), promise: null };
        entry.promise = Promise.resolve().then(function () {
          return fetcher(config.url, { method: 'GET', credentials: 'same-origin', cache: 'default', redirect: 'error',
            headers: { Accept: 'text/html' }, signal: entry.controller.signal });
        }).then(function (response) {
          if (!response.ok) throw new Error('Search index unavailable');
          return response.text();
        }).then(function (html) {
          if (current !== epoch) throw new Error('Obsolete search index');
          var index = parse(html, config);
          entry.snapshot = { index: index, match: searchMatcher(index) };
          return entry.snapshot;
        }).catch(function (error) {
          if (entries.get(key) === entry) entries.delete(key);
          throw error;
        });
        entries.set(key, entry);
        return entry.promise;
      }
    };
  }

  // Pure helpers keep saved-state and legacy-link contracts independently testable.
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { preferences: preferences, readPreferences: readPreferences, clientChoice: clientChoice,
      detailLevels: detailLevels, effectiveDetail: effectiveDetail, copyText: copyText,
      exampleCopyControls: exampleCopyControls, disclosureMenus: disclosureMenus,
      legacyTarget: legacyTarget, loginTarget: loginTarget,
      highlighterTarget: highlighterTarget, basicAuthentication: basicAuthentication,
      activeSection: activeSection, navigationTargets: navigationTargets,
      searchConfiguration: searchConfiguration, validateSearchIndex: validateSearchIndex, searchMatcher: searchMatcher,
      searchResultURL: searchResultURL, renderSearchResult: renderSearchResult, searchIndexLoader: searchIndexLoader };
  }
  if (typeof document === 'undefined') return;

  // Capture the script URL while this synchronous head script is executing;
  // document.currentScript is no longer available at DOMContentLoaded.
  var script = document.currentScript;
  var workerURL = highlighterTarget(script && script.src, window.location.href,
    script && script.getAttribute('data-highlighter-url'));

  var state;
  try { state = readPreferences(window.localStorage); }
  catch (error) { state = preferences(null); }
  var colorScheme = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

  function applyTheme() {
    document.documentElement.setAttribute('data-docs-theme', state.theme === 'auto'
      ? (colorScheme && colorScheme.matches ? 'dark' : 'light') : state.theme);
  }
  applyTheme();
  if (colorScheme && colorScheme.addEventListener) colorScheme.addEventListener('change', applyTheme);

  function ready() {
    var root = document.querySelector('[data-docs]');
    if (!root) return;
    var all = function (selector) { return Array.from(root.querySelectorAll(selector)); };
    var json = function (selector, fallback) {
      var element = root.querySelector(selector);
      try { return element ? JSON.parse(element.textContent) : fallback; }
      catch (error) { return fallback; }
    };
    var metadata = json('[data-documentation-clients]', []);
    var clients = Array.isArray(metadata) ? metadata.filter(function (client, index, list) {
      return client && typeof client.id === 'string' && typeof client.language === 'string'
        && typeof client.language_label === 'string' && client.id && client.language
        && list.findIndex(function (entry) { return entry && entry.id === client.id; }) === index;
    }) : [];
    var sidebar = root.querySelector('[data-docs-sidebar]');
    var examples = all('[data-example]');
    var sections = all('[data-doc-section]');
    var actionLinks = all('[data-action-nav] a[href^="#"]');
    var actionTargets = navigationTargets(actionLinks.map(function (link) { return link.getAttribute('href'); }),
      function (id) { return document.getElementById(id); });
    actionTargets.sort(function (left, right) { return left.compareDocumentPosition(right) & 2 ? 1 : -1; });
    var status = root.querySelector('[data-preference-status]');
    var clearCopyStatus = exampleCopyControls(root, window, document, window.navigator || {});
    var closeMenus = disclosureMenus(root, sidebar, window, document);

    function persist() {
      try { window.localStorage.setItem(storageKey, JSON.stringify(state)); }
      catch (error) { /* Preferences still work for this page when storage is denied. */ }
    }

    function redirectLegacy() {
      if (root.getAttribute('data-page') !== 'overview' || !window.location.hash) return;
      var anchors = json('[data-legacy-anchors]', {});
      if (!anchors || typeof anchors !== 'object' || Array.isArray(anchors)) return;
      var target = legacyTarget(window.location.hash, anchors);
      if (!target) return;
      var url = new URL(target, window.location.href);
      // Only page URLs supplied by the authorized server map can redirect locally.
      if (url.origin !== window.location.origin) return;
      url.hash = window.location.hash;
      if (url.href !== window.location.href) window.location.replace(url.href);
    }

    // One queued worker highlights only visible sources. A failed worker leaves
    // the original text in place; no synchronous fallback blocks a large page.
    var worker = null;
    var queue = [];
    var pending = new WeakSet();
    var current = null;
    var codeObserver = null;
    try { if (window.Worker && workerURL) worker = new Worker(workerURL); }
    catch (error) { worker = null; }

    function visible(code) {
      if (code.closest('[hidden]')) return false;
      var panel = code.closest('details');
      if (panel && !panel.open) return false;
      var rect = code.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 && rect.bottom >= 0 && rect.top < window.innerHeight;
    }

    function nextHighlight() {
      if (!worker || current) return;
      while (queue.length) {
        var code = queue.shift();
        pending.delete(code);
        if (!visible(code) || code.classList.contains('hljs')) continue;
        current = code;
        try { worker.postMessage({ language: code.getAttribute('data-language') || code.classList.item(0), code: code.textContent }); }
        catch (error) { stopWorker(); }
        break;
      }
    }
    function stopWorker() {
      if (worker) worker.terminate();
      worker = null;
      queue = [];
      current = null;
    }

    function highlight(code) {
      if (!worker || pending.has(code) || current === code || code.classList.contains('hljs') || !visible(code)) return;
      pending.add(code);
      queue.push(code);
      nextHighlight();
    }
    if (worker) {
      worker.onmessage = function (event) {
        if (current && typeof event.data === 'string') {
          current.innerHTML = event.data;
          current.classList.add('hljs');
        }
        current = null;
        nextHighlight();
      };
      worker.onerror = stopWorker;
      if (window.IntersectionObserver) {
        codeObserver = new IntersectionObserver(function (entries) {
          entries.forEach(function (entry) { if (entry.isIntersecting) highlight(entry.target); });
        });
        all('pre code').forEach(function (code) { codeObserver.observe(code); });
      }
    }

    function highlightVisible() { all('pre code').forEach(highlight); }

    function option(select, value, label) {
      var element = document.createElement('option');
      element.value = value;
      element.textContent = label;
      select.appendChild(element);
    }

    function updateControls(choice) {
      var languages = clients.filter(function (client, index, list) {
        return list.findIndex(function (entry) { return entry.language === client.language; }) === index;
      });
      all('[data-language-select]').forEach(function (select) {
        select.replaceChildren();
        languages.forEach(function (client) { option(select, client.language, client.language_label); });
        select.disabled = !choice;
        if (choice) select.value = choice.language;
      });
      all('[data-variant-select]').forEach(function (select) {
        select.replaceChildren();
        var variants = clients.filter(function (client) { return choice && client.language === choice.language; });
        variants.forEach(function (client) { option(select, client.id, client.variant || client.language_label); });
        if (choice) select.value = choice.id;
        var control = select.closest('[data-variant-control]') || select;
        control.hidden = variants.length < 2;
        select.disabled = variants.length < 2;
      });
      all('[data-detail-select]').forEach(function (select) {
        var available = !!choice && detailLevels(choice).length > 1;
        (select.closest('[data-detail-control]') || select).hidden = !available;
        select.disabled = !available;
        select.value = effectiveDetail(state, choice);
      });
      all('[data-theme-choice]').forEach(function (button) {
        button.setAttribute('aria-pressed', String(button.getAttribute('data-theme-choice') === state.theme));
      });
      all('[data-theme-menu]').forEach(function (menu) {
        var selected = menu.querySelector('[data-theme-choice="' + state.theme + '"]');
        var summary = menu.querySelector('summary');
        var slot = menu.querySelector('[data-theme-current]');
        if (!selected || !summary || !slot) return;
        var label = selected.getAttribute('aria-label');
        summary.setAttribute('aria-label', label);
        summary.setAttribute('title', label);
        slot.replaceChildren();
        var icon = selected.querySelector('svg');
        if (icon) slot.appendChild(icon.cloneNode(true));
        var text = document.createElement('span');
        text.className = 'sr-only';
        text.textContent = label;
        slot.appendChild(text);
      });
      if (status) {
        var fallback = choice && ((state.language && state.language !== choice.language)
          || (state.clients[choice.language] && state.clients[choice.language] !== choice.id));
        status.textContent = fallback ? 'Your saved example is unavailable. Showing ' + choice.language_label
          + (choice.variant ? ' (' + choice.variant + ')' : '') + '.' : '';
        status.hidden = !fallback;
      }
    }

    function updateExamples() {
      var choice = clientChoice(state, clients);
      var detail = effectiveDetail(state, choice);
      clearCopyStatus();
      updateControls(choice);
      examples.forEach(function (example) {
        var panels = Array.from(example.querySelectorAll('[data-example-panel]'));
        var chosen = choice && panels.find(function (panel) {
          return panel.getAttribute('data-client') === choice.id && panel.getAttribute('data-detail') === detail;
        });
        // Missing renderers remain visible as explicit limitations from the
        // server; never silently replace the selected client with another one.
        panels.forEach(function (panel) {
          panel.hidden = panel !== chosen;
          if (panel.tagName === 'DETAILS') panel.open = panel === chosen;
        });
        var unavailable = example.querySelector('[data-example-unavailable]');
        if (!unavailable) {
          unavailable = document.createElement('p');
          unavailable.setAttribute('data-example-unavailable', '');
          unavailable.className = 'docs-notice';
          unavailable.textContent = 'No example is available for this client.';
          example.appendChild(unavailable);
        }
        unavailable.hidden = !!chosen;
      });
      highlightVisible();
    }

    function capturePosition(control) {
      var anchor = control && control.closest('[data-example]');
      if (!anchor) {
        var top = parseFloat(window.getComputedStyle(document.documentElement).scrollPaddingTop) || 0;
        var candidates = examples.concat(sections).filter(function (element) {
          var rect = element.getBoundingClientRect();
          return rect.bottom > top && rect.top < window.innerHeight;
        });
        candidates.sort(function (left, right) {
          return Math.abs(left.getBoundingClientRect().top - top) - Math.abs(right.getBoundingClientRect().top - top);
        });
        anchor = candidates[0];
      }
      return { anchor: anchor, top: anchor ? anchor.getBoundingClientRect().top : 0,
        sidebarTop: sidebar ? sidebar.scrollTop : 0 };
    }

    function updatePreservingPosition(control) {
      var position = capturePosition(control);
      updateExamples();
      window.requestAnimationFrame(function () {
        window.requestAnimationFrame(function () {
          if (position.anchor && position.anchor.isConnected) window.scrollBy(0, position.anchor.getBoundingClientRect().top - position.top);
          if (sidebar) sidebar.scrollTop = position.sidebarTop;
          updateActiveAction();
          highlightVisible();
        });
      });
    }

    all('[data-language-select]').forEach(function (select) {
      select.addEventListener('change', function () { state.language = select.value; persist(); updatePreservingPosition(select); });
    });
    all('[data-variant-select]').forEach(function (select) {
      select.addEventListener('change', function () {
        var client = clients.find(function (entry) { return entry.id === select.value; });
        if (!client) return;
        state.language = client.language;
        state.clients[client.language] = client.id;
        persist();
        updatePreservingPosition(select);
      });
    });
    all('[data-detail-select]').forEach(function (select) {
      select.addEventListener('change', function () { state.detail = select.value === 'thorough' ? 'thorough' : 'simple'; persist(); updatePreservingPosition(select); });
    });
    all('[data-theme-choice]').forEach(function (button) {
      button.addEventListener('click', function () {
        var theme = button.getAttribute('data-theme-choice');
        if (['auto', 'light', 'dark'].indexOf(theme) < 0) return;
        state.theme = theme;
        persist();
        applyTheme();
        updateControls(clientChoice(state, clients));
        var menu = button.closest('[data-theme-menu]');
        if (menu) { menu.open = false; menu.querySelector('summary').focus({ preventScroll: true }); }
      });
    });
    all('a[data-documentation-login]').forEach(function (link) {
      var prepareLogin = function () {
        var target = loginTarget(link.href, window.location.href, window.location.hash);
        if (target) link.href = target;
      };
      link.addEventListener('click', prepareLogin);
      link.addEventListener('auxclick', prepareLogin);
    });
    all('.authentication a.login, .authentication a.logout').forEach(function (link) {
      link.addEventListener('click', function (event) {
        if (event.button || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
        if (basicAuthentication(link.href, window.location.href, link.classList.contains('logout'),
          function () { return new XMLHttpRequest(); }, function () { window.location.reload(); })) event.preventDefault();
      });
    });

    var searches = [];
    function clearSearches() { searches.forEach(function (search) { search.clear(); }); }
    var bootstrapSearch = false;
    var indexLoader = null;
    if (window.fetch && window.AbortController && window.TextEncoder && 'content' in document.createElement('template')) {
      indexLoader = searchIndexLoader(window.fetch.bind(window), window.AbortController, function (html, expected) {
        var parsed = document.createElement('template');
        parsed.innerHTML = html;
        var scripts = parsed.content.querySelectorAll('script');
        var data = parsed.content.querySelectorAll('script[type="application/json"][data-documentation-search-index]');
        if (scripts.length !== 1 || data.length !== 1) throw new Error('Search index representation unavailable');
        return validateSearchIndex(JSON.parse(data[0].textContent), expected);
      });
    }
    if (indexLoader) all('[data-documentation-search]').forEach(function (form) {
      var input = form.querySelector('[data-search-query]');
      var suggestions = form.querySelector('[data-search-suggestions]');
      var preview = form.querySelector('[data-search-preview]');
      var searchStatus = form.querySelector('[data-search-status]');
      if (!input || !suggestions || !preview || !searchStatus || form.method.toLowerCase() !== 'get') return;
      var generation = 0;
      var suppressFocus = false;
      function clear() {
        generation += 1;
        preview.replaceChildren();
        searchStatus.textContent = '';
        suggestions.hidden = true;
      }
      searches.push({ clear: clear });
      function render(snapshot, query) {
        var results = snapshot.match(query);
        var list = document.createElement('ol');
        results.results.forEach(function (result) {
          list.appendChild(renderSearchResult(document, snapshot.index, result, window.location.origin));
        });
        preview.replaceChildren(list);
        searchStatus.textContent = !results.results.length ? 'No matches. Try another resource, action or parameter name.'
          : results.more ? 'Showing ' + results.results.length + ' results. More matches are available; refine your search.'
            : results.results.length + (results.results.length === 1 ? ' result.' : ' results.');
        suggestions.hidden = false;
      }
      function intent() {
        clearSearches();
        var current = generation;
        var query = input.value.trim();
        var config = searchConfiguration(form.action, form.getAttribute('data-search-index-url'),
          form.getAttribute('data-search-view-key'), form.getAttribute('data-search-version'), window.location.href, bootstrapSearch);
        if (!config) {
          if (query) { suggestions.hidden = false; searchStatus.textContent = 'Search could not be loaded. Submit to open the results page.'; }
          return;
        }
        var loaded = indexLoader.peek(config);
        if (loaded) { if (query && Array.from(query).length <= 256) render(loaded, query); return; }
        if (query) { suggestions.hidden = false; searchStatus.textContent = 'Loading search…'; }
        indexLoader.load(config).then(function (snapshot) {
          if (current !== generation || input.value.trim() !== query || !query || Array.from(query).length > 256) return;
          render(snapshot, query);
        }).catch(function () {
          if (current === generation && query) {
            searchStatus.textContent = 'Search could not be loaded. Submit to open the results page.';
            suggestions.hidden = false;
          }
        });
      }
      input.addEventListener('input', function () { if (input.value.trim()) intent(); else clearSearches(); });
      input.addEventListener('pointerdown', intent);
      input.addEventListener('focus', function () { if (!suppressFocus) intent(); });
      form.addEventListener('submit', clearSearches);
      form.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        event.preventDefault();
        var focusWasInside = suggestions.contains(document.activeElement);
        clear();
        if (focusWasInside) {
          suppressFocus = true;
          input.focus({ preventScroll: true });
          suppressFocus = false;
        }
      });
    });
    window.addEventListener('pageshow', function (event) {
      clearSearches();
      if (event.persisted) { bootstrapSearch = true; if (indexLoader) indexLoader.reset(); }
    });
    window.addEventListener('pagehide', function () { clearSearches(); clearCopyStatus(); });
    window.addEventListener('focus', clearSearches);

    function updateActiveAction() {
      var active = activeSection(actionTargets.map(function (section) {
        return { id: section.id, top: section.getBoundingClientRect().top,
          margin: window.getComputedStyle(section).scrollMarginTop };
      }), window.getComputedStyle(document.documentElement).scrollPaddingTop);
      actionLinks.forEach(function (link) {
        var id;
        try { id = decodeURIComponent(link.hash.slice(1)); } catch (error) { id = ''; }
        if (active && id === active.id) link.setAttribute('aria-current', 'location');
        else link.removeAttribute('aria-current');
      });
    }
    if (window.IntersectionObserver) {
      var actionObserver = new IntersectionObserver(updateActiveAction);
      actionTargets.forEach(function (section) { actionObserver.observe(section); });
    }
    var scrollPending = false;
    window.addEventListener('scroll', function () {
      if (scrollPending) return;
      scrollPending = true;
      window.requestAnimationFrame(function () { scrollPending = false; updateActiveAction(); if (!codeObserver) highlightVisible(); });
    }, { passive: true });
    window.addEventListener('resize', function () { updateActiveAction(); highlightVisible(); });

    var toggle = root.querySelector('[data-nav-toggle]');
    var main = root.querySelector('.docs-main');
    var navigationMedia = window.matchMedia('(max-width: 900px)');
    var previousOverflow = null;
    function closeNavigation() {
      closeMenus();
      root.removeAttribute('data-nav-open');
      if (toggle) toggle.setAttribute('aria-expanded', 'false');
      if (main) main.inert = false;
      if (previousOverflow !== null) { document.body.style.overflow = previousOverflow; previousOverflow = null; }
    }
    if (toggle) toggle.addEventListener('click', function () {
      var open = !root.hasAttribute('data-nav-open');
      if (!open) { closeNavigation(); return; }
      root.setAttribute('data-nav-open', '');
      toggle.setAttribute('aria-expanded', 'true');
      if (navigationMedia.matches) {
        if (main) main.inert = true;
        previousOverflow = document.body.style.overflow;
        document.body.style.overflow = 'hidden';
      }
    });
    root.addEventListener('keydown', function (event) {
      if (!root.hasAttribute('data-nav-open')) return;
      if (event.key === 'Escape') { closeNavigation(); toggle.focus({ preventScroll: true }); }
      if (event.key === 'Tab' && sidebar && navigationMedia.matches) {
        var focusable = [toggle].concat(Array.from(sidebar.querySelectorAll('a[href],button,input,select,textarea,summary,[tabindex]')))
          .filter(function (element) { return !element.disabled && element.tabIndex >= 0 && element.getClientRects().length; });
        var first = focusable[0];
        var last = focusable[focusable.length - 1];
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
      }
    });
    if (navigationMedia.addEventListener) navigationMedia.addEventListener('change', function () { if (!navigationMedia.matches) closeNavigation(); });
    if (sidebar) sidebar.addEventListener('click', function (event) {
      var link = event.target.closest('a[href]');
      if (link && navigationMedia.matches) {
        closeNavigation();
        if (link.hash && new URL(link.href).pathname === window.location.pathname && new URL(link.href).search === window.location.search) {
          var target = document.getElementById(decodeURIComponent(link.hash.slice(1)));
          if (target) { target.setAttribute('tabindex', '-1'); target.focus({ preventScroll: true }); }
        }
      }
    });
    window.addEventListener('hashchange', function () { redirectLegacy(); updateActiveAction(); });
    window.addEventListener('pageshow', updateActiveAction);
    window.addEventListener('storage', function (event) {
      if (event.key !== storageKey) return;
      try { state = preferences(JSON.parse(event.newValue)); } catch (error) { state = preferences(null); }
      applyTheme();
      updatePreservingPosition(null);
    });
    root.setAttribute('data-docs-enhanced', '');
    updateExamples();
    redirectLegacy();
    updateActiveAction();
    // Fragment targets may start inside a panel whose visibility just changed.
    if (window.location.hash) {
      var target;
      try { target = document.getElementById(decodeURIComponent(window.location.hash.slice(1))); }
      catch (error) { target = null; }
      if (target && target.closest('[hidden]')) {
        var example = target.closest('[data-example]');
        if (example) example.scrollIntoView();
      }
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready);
  else ready();
})();
