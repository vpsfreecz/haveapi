var nodeResolve = require("@rollup/plugin-node-resolve").nodeResolve;

function inputOptions() {
  return {
    input: "build/haveapi.js",
    // tslib's module condition selects ES5 ESM, not its modern Node wrapper.
    plugins: [nodeResolve({ exportConditions: ["module"] })],
  };
}

module.exports = { inputOptions: inputOptions };
