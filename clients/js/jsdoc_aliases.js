var fs = require("fs"),
  path = require("path");

var page = "HaveAPI.Client.Action.html";
var alias = '<span id="invoke__anchor"></span>';

function transform(html) {
  var target = /<h4\b[^>]*\bid="invoke"[^>]*>/g;
  var matches = Array.from(html.matchAll(target));
  var destinations = html.match(/\bid\s*=\s*["']invoke["']/g) || [];
  if (matches.length !== 1 || destinations.length !== 1)
    throw new Error("JSDoc Action page must have exactly one invoke heading");
  var aliases = html.match(/\bid\s*=\s*["']invoke__anchor["']/g) || [];
  var position = matches[0].index;
  if (aliases.length) {
    if (
      aliases.length !== 1 ||
      html.slice(position - alias.length, position) !== alias
    )
      throw new Error(
        "JSDoc invoke__anchor collides with an existing destination",
      );
    return html;
  }
  return html.slice(0, position) + alias + html.slice(position);
}

function write(directory) {
  var filename = path.join(directory, page);
  fs.writeFileSync(filename, transform(fs.readFileSync(filename, "utf8")));
}

module.exports = { transform: transform, write: write };
