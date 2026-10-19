var gulp = require('gulp'),
	fs = require('fs'),
	path = require('path'),
	spawn = require('child_process').spawn,
	rollup = require('rollup'),
	jsdoc = require('gulp-jsdoc3');

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
	return rollup.rollup({ input: 'build/haveapi.js' }).then(function(built) {
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
			fs.writeFileSync('dist/haveapi-client.js', wrapper);
			return built.close();
		});
	}).then(function() {
		fs.rmSync('dist/types', { recursive: true, force: true });
		declarations('build');
	});
}

gulp.task('scripts', gulp.series(compile, bundle));
gulp.task('doc', gulp.series('scripts', function(done) {
	return gulp.src(['build/**/*.js', 'README.md'], { read: false }).pipe(jsdoc({
		plugins: ['plugins/markdown'],
		opts: { destination: 'html_doc' }
	}, done));
}));
gulp.task('watch', function() {
	return gulp.watch(['src/**/*.ts', 'src/haveapi/i18n_messages.js'], gulp.series('scripts'));
});
gulp.task('default', gulp.series('scripts'));
