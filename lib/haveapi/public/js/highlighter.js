importScripts('highlight.pack.js');

onmessage = function (e) {
	if (e.data.language)
		postMessage(hljs.highlight(e.data.language, e.data.code).value);

	else
		postMessage(hljs.highlightAuto(e.data.code).value);
}
