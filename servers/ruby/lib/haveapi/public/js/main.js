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
			highlightNext();
		};

		highlightNext();

	} else {
		hljs.initHighlighting();
	}
});

})();
