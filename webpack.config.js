module.exports = {
    entry: './src/hello.js',
    output: {
        path: './bin',
        filename: 'hello.bundle.js',
        pathInfo: true,
        libraryTarget: 'amd',
    },
    module: {
        loaders: [
            {test: /\.js$/, exclude: /node_modules/, loader: 'babel-loader'},
        ],
    },
    externals: ['jquery'],
};