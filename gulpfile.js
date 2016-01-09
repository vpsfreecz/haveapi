var gulp = require('gulp'),
	concat = require('gulp-concat'),
	umd = require('gulp-umd');

gulp.task('scripts', function() {
	return gulp.src([
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
			'src/haveapi/resource_instance.js',
			'src/haveapi/resource_instance_list.js',
			'src/haveapi/exceptions.js',
			'src/*.js',
		])
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

gulp.task('watch', function() {
	gulp.watch('src/*.js', ['scripts']);
	gulp.watch('src/**/*.js', ['scripts']);
});

gulp.task('default', ['scripts'])
