importScripts('highlight.pack.js');

function plainText(source) {
	return source.replace(/[&<>"']/g, function (value) {
		return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[value];
	});
}

onmessage = function (e) {
	var source = String(e.data.code || '');
	var language = e.data.language;
	try {
		postMessage(language && hljs.getLanguage(language)
			? hljs.highlight(source, { language: language, ignoreIllegals: true }).value
			: plainText(source));
	} catch (error) {
		postMessage(plainText(source));
	}
};
