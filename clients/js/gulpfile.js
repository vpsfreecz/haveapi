var gulp = require('gulp'),
	fs = require('fs'),
	path = require('path'),
	spawn = require('child_process').spawn,
	rollup = require('rollup'),
	inputOptions = require('./rollup.config.js').inputOptions,
	jsdocAliases = require('./jsdoc_aliases.js');

function compile(done) {
	fs.rmSync('build', { recursive: true, force: true });
	var child = spawn(process.execPath, [require.resolve('typescript/bin/tsc')], {
		stdio: 'inherit'
	});
	child.on('error', done);
	child.on('exit', function(code) {
		done(code === 0 ? null : new Error('TypeScript compilation failed (' + code + ')'));
	});
}

function declarations(directory) {
	fs.readdirSync(directory, { withFileTypes: true }).forEach(function(entry) {
		var source = path.join(directory, entry.name);
		if (entry.isDirectory()) {
			declarations(source);
		} else if (entry.name.endsWith('.d.ts')) {
			var destination = path.join('dist/types', path.relative('build', source));
			fs.mkdirSync(path.dirname(destination), { recursive: true });
			fs.copyFileSync(source, destination);
		}
	});
}

function bundle() {
	return rollup.rollup(inputOptions()).then(function(built) {
		return built.generate({
			format: 'iife',
			name: 'HaveAPI',
			exports: 'named',
			indent: false,
			strict: false,
			// Generated catalog stays factory-local, as in the original bundle.
			intro: fs.readFileSync('src/haveapi/i18n_messages.js', 'utf8')
		}).then(function(result) {
			// Rollup owns the named-export payload. Keep the existing UMD shell:
			// AMD has no dependencies and receives the returned namespace object.
			var wrapper = ';(function(root, factory) {\n' +
				"  if (typeof define === 'function' && define.amd) {\n" +
				'    define([], factory);\n' +
				"  } else if (typeof exports === 'object') {\n" +
				'    module.exports = factory();\n' +
				'  } else {\n' +
				'    root.HaveAPI = factory();\n' +
				'  }\n' +
				'}(this, function() {\n' +
				// Capture before Rollup introduces its own export-container binding.
				"var haveapiCommonJS = typeof exports === 'object';\n" +
				result.output[0].code +
				'\nreturn HaveAPI;\n}));\n';
			fs.mkdirSync('dist', { recursive: true });
			var helperLicense = fs.readFileSync(path.join(
				path.dirname(require.resolve('tslib/package.json')), 'LICENSE.txt'
			), 'utf8').replace(/\r\n/g, '\n');
			fs.writeFileSync('dist/haveapi-client.js', '/*! Bundled tslib license:\n' +
				helperLicense + '\n*/\n' + wrapper);
			return built.close();
		});
	}).then(function() {
		fs.rmSync('dist/types', { recursive: true, force: true });
		declarations('build');
	});
}

gulp.task('scripts', gulp.series(compile, bundle));
gulp.task('doc', gulp.series('scripts', function(done) {
	var child = spawn(process.execPath, [require.resolve('jsdoc/jsdoc.js'), '-c', 'jsdoc.json'], {
		stdio: 'inherit'
	});
	child.once('error', done);
	child.once('exit', function(code) {
		if (code !== 0) return done(new Error('JSDoc generation failed (' + code + ')'));
		try {
			jsdocAliases.write('html_doc');
			done();
		} catch (error) { done(error); }
	});
}));
gulp.task('watch', function() {
	return gulp.watch(['src/**/*.ts', 'src/haveapi/i18n_messages.js'], gulp.series('scripts'));
});
gulp.task('default', gulp.series('scripts'));
