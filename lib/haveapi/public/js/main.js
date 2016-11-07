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
			worker.postMessage(currentElement.textContent);
		};

		worker.onmessage = function (e) {
			currentElement.innerHTML = e.data.value;
			highlightNext();
		};

		highlightNext();

	} else {
		hljs.initHighlighting();
	}
});

})();
