var path = require('path');

// Options
const buildMode = process.env.NODE_ENV || 'development';
const debugMode = buildMode !== 'production';
const sourcemapsMode = debugMode ? 'eval-source-map' : undefined;
const dist = `${__dirname}/www/`;

module.exports = {
    entry: {
        agreeOrDisagree: './build.hxml'
    },
    output: {
        path: dist,
        filename: '[name].bundle.js',
        libraryTarget: 'amd',
    },
    module: {
        rules: [
            // Haxe loader (through HXML files for now)
            {
                test: /\.hxml$/,
                loader: 'haxe-loader',
                options: {
                    // Additional compiler options added to all builds
                    extra: `-D build_mode=${buildMode}`,
                    debug: debugMode
                }
            },
            {
                test: /\.less$/,
                use: [
                    'style-loader',
                    { loader: 'css-loader', options: { importLoaders: 1 } },
                    { loader: 'less-loader', options: { strictMath: true, noIeCompat: true } }
                ]
            }
        ]
    },
    devtool: sourcemapsMode,
    externals: ['jquery', 'cdnjs'],
    devServer: {
            contentBase: dist,
            compress: true,
            port: 9000,
            overlay: true
    },
};
