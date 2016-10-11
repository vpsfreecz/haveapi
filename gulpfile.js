var gulp = require('gulp'),
	concat = require('gulp-concat'),
	umd = require('gulp-umd'),
	jsdoc = require('gulp-jsdoc3');

var src = [
	'src/haveapi/client.js',
	'src/haveapi/hooks.js',
	'src/haveapi/http.js',
	'src/haveapi/authentication.js',
	'src/haveapi/authentication/base.js',
	'src/haveapi/authentication/basic.js',
	'src/haveapi/authentication/token.js',
	'src/haveapi/base_resource.js',
	'src/haveapi/resource.js',
	'src/haveapi/action.js',
	'src/haveapi/response.js',
	'src/haveapi/local_response.js',
	'src/haveapi/resource_instance.js',
	'src/haveapi/resource_instance_list.js',
	'src/haveapi/parameters.js',
	'src/haveapi/validator.js',
	'src/haveapi/validators/*.js',
	'src/haveapi/exceptions.js',
	'src/*.js',
];

gulp.task('scripts', function() {
	return gulp.src(src)
		.pipe(concat('haveapi-client.js'))
		.pipe(umd({
			exports: function (file) {
				return 'HaveAPI';
			},
			namespace: function (file) {
				return 'HaveAPI';
			}
		}))
		.pipe(gulp.dest('./dist/'));
});

gulp.task('doc', function (cb) {
	gulp.src(src.concat(['README.md']), {read: false}).pipe(jsdoc({
		opts: { destination: "html_doc" }
	}, cb));
});

gulp.task('watch', function() {
	gulp.watch('src/*.js', ['scripts', 'doc']);
	gulp.watch('src/**/*.js', ['scripts', 'doc']);
});

gulp.task('default', ['scripts']);
