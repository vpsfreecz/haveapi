(function () {

$(document).ready(function () {
	if (window.Worker) {
		var worker = new Worker('/js/highlighter.js');
		var codes = $('pre code').toArray();
		var currentElement;

		var highlightNext = function () {
			if (!codes.length)
				return;

			currentElement = codes.shift();
			worker.postMessage({
				language: currentElement.classList.item(0),
				code: currentElement.textContent
			});
		};

		worker.onmessage = function (e) {
			currentElement.innerHTML = e.data;
			currentElement.classList.add('hljs');
			highlightNext();
		};
		worker.onerror = function () {
			worker.terminate();
			// The server's escaped source remains readable if the worker fails.
		};

		highlightNext();

	} else {
		document.querySelectorAll('pre code').forEach(function (element) {
			if (hljs.getLanguage(element.classList.item(0)))
				hljs.highlightElement(element);
		});
	}
});

})();
