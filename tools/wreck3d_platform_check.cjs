const path = require('node:path');
const { pathToFileURL } = require('node:url');

process.env.WRECK3D_ENTRY = pathToFileURL(path.resolve(__dirname, '../.runtime/wreck3d-package/index.html')).href;
process.env.WRECK3D_SKIP_PACKAGE = '1';
require('./wreck3d_browser_check.cjs');
