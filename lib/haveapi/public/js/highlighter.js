importScripts('highlight.pack.js');

onmessage = function (e) {
	postMessage(hljs.highlightAuto(e.data));
}
