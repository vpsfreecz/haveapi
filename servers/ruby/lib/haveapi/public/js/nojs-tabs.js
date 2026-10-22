(function (root) {
	var nojsTabs = function (opts) {
		this.opts = opts;

		var ul = this.createElement(document.createElement('UL'));
		ul.setAttribute('role', 'tablist');
		var tabNum = opts.tabs.children.length;
		if (!tabNum) return;

		for (var i = 0; i < tabNum; i++) {
			var tab = opts.tabs.children[i];

			ul.appendChild(this.createTab(tab));
		}

		opts.tabBar.appendChild(ul);

		this.init();

		var that = this;
		var prevOnPopState = window.onpopstate;

		window.onpopstate = function(e) {
			if (!e.state || !e.state.tabBar || that.opts.tabBar.id !== e.state.tabBar) {
				if (prevOnPopState)
					prevOnPopState(e);

				return;
			}
			
			that.switchTab(document.getElementById(e.state.tab), false);
		};
	};

	nojsTabs.Version = '0.2.0';

	nojsTabs.prototype.createElement = function (el) {
		if (this.opts.createElement !== undefined) {
			var ret = this.opts.createElement(el);
			
			return ret === undefined ? el : ret;
		}

		return el;
	}

	nojsTabs.prototype.createTab = function (tab) {
		var li = this.createElement(document.createElement('LI'));
		li.id = 'tab-anchor-' + tab.id;
		
		var a = this.createElement(document.createElement('A'));
		var a_text = document.createTextNode(this.getTitle(tab));

		a.href = '#' + tab.id;
		a.id = 'tab-button-' + tab.id;
		a.setAttribute('role', 'tab');
		a.setAttribute('aria-controls', tab.id);
		tab.setAttribute('role', 'tabpanel');
		tab.setAttribute('aria-labelledby', a.id);

		var that = this;

		a.addEventListener('click', function (e) {
			that.switchTab(tab);

			if (history.pushState)
				e.preventDefault();
		});
		a.addEventListener('keydown', function (e) {
			var links = Array.prototype.slice.call(that.opts.tabBar.querySelectorAll('[role="tab"]'));
			var index = links.indexOf(a);
			if (e.key === 'ArrowRight') index = (index + 1) % links.length;
			else if (e.key === 'ArrowLeft') index = (index + links.length - 1) % links.length;
			else if (e.key === 'Home') index = 0;
			else if (e.key === 'End') index = links.length - 1;
			else return;
			e.preventDefault();
			links[index].focus();
			that.switchTab(that.opts.tabs.children[index]);
		});

		a.appendChild(a_text);
		li.appendChild(a);

		tab.tabAnchor = li;
		tab.tabAnchor.activate = function () {
			that.activate([this]);
		};
		
		tab.tabAnchor.deactivate = function () {
			that.deactivate([this]);
		};
	
		return li;
	};

	nojsTabs.prototype.getTitle = function (tab) {
		var s = this.opts.titleSelector;

		if (typeof s === 'string' || s instanceof String) {
			var el = tab.querySelector(s);
			var ret = el.textContent;
			
			if (this.opts.removeHeading === undefined || this.opts.removeHeading)
				el.parentElement.removeChild(el);

			return ret;

		} else
			return s(tab);
	};

	nojsTabs.prototype.init = function () {
		var that = this;
		var targetTab = this.opts.tabs.children[0];

		// Find initial tab
		if (location.hash) {
				this.eachTab(function (tab) {
					if (location.hash == '#'+tab.id) {
						targetTab = tab;
						return true;
					}
				});

		} else {
			this.eachTab(function (tab) {
				if (tab.classList.contains(that.opts.activeClass)) {
					targetTab = tab;
					return true;
				}
			});
		}

		// Show/hide tabs
		this.eachTab(function (tab, i) {
			var a = that.opts.tabBar.getElementsByTagName('li')[i];

			if (targetTab.id == tab.id)
				that.activate([tab, a]);
			else
				that.deactivate([tab, a]);
		});
	};

	nojsTabs.prototype.eachTab = function (fn) {
		var tabs = this.opts.tabs.children;
		var tabNum = tabs.length;

		for (var i = 0; i < tabNum; i++) {
			if (fn(tabs[i], i))
				break;
		}
	};

	nojsTabs.prototype.switchTab = function (targetTab, pushState) {
		var that = this;
		var activeTab = this.opts.tabs.querySelector('.'+this.opts.activeClass);

		if (activeTab.id == targetTab.id)
			return;

		// beforeChange
		if (this.opts.beforeChange !== undefined)
			this.opts.beforeChange(activeTab, targetTab);

		// transition
		if (this.opts.transition !== undefined)
			this.opts.transition(activeTab, targetTab, function () {
				that.transition(activeTab, targetTab);
			});

		else
			this.transition(activeTab, targetTab);

		if ((pushState === undefined || pushState) && history.pushState) {
			history.pushState({
				tabBar: this.opts.tabBar.id,
				tab: targetTab.id
			}, null, '#'+targetTab.id);
		}
	};

	nojsTabs.prototype.transition = function(activeTab, targetTab) {
		this.deactivate([activeTab, activeTab.tabAnchor]);
		this.activate([targetTab, targetTab.tabAnchor]);
		
		// afterChange
		if (this.opts.afterChange !== undefined)
			this.opts.afterChange(targetTab, activeTab);
	};

	nojsTabs.prototype.activate = function (elems) {
		var len = elems.length;

		for (var i = 0; i < len; i++) {
			elems[i].classList.remove(this.opts.hiddenClass);
			elems[i].classList.add(this.opts.activeClass);
			var link = elems[i].querySelector('[role="tab"]');
			if (link) {
				link.setAttribute('aria-selected', 'true');
				link.setAttribute('tabindex', '0');
			} else if (elems[i].getAttribute('role') === 'tabpanel') {
				elems[i].setAttribute('aria-hidden', 'false');
			}
		}
	};

	nojsTabs.prototype.deactivate = function (elems) {
		var len = elems.length;

		for (var i = 0; i < len; i++) {
			elems[i].classList.remove(this.opts.activeClass);
			if (elems[i].getAttribute('role') === 'tabpanel')
				elems[i].classList.add(this.opts.hiddenClass);
			var link = elems[i].querySelector('[role="tab"]');
			if (link) {
				link.setAttribute('aria-selected', 'false');
				link.setAttribute('tabindex', '-1');
			} else if (elems[i].getAttribute('role') === 'tabpanel') {
				elems[i].setAttribute('aria-hidden', 'true');
			}
		}
	};

	root.nojsTabs = function (opts) {
		return new nojsTabs(opts);
	};

})(window);
