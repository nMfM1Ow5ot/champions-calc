const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const root = fs.realpathSync(process.env.SHOWDOWN_ROOT);
const original = Module._resolveFilename;
const missing = new Set();
Module._resolveFilename = function(request, parent, ...rest) {
  try { return original.call(this, request, parent, ...rest); }
  catch (e) {
    if (e.code === 'MODULE_NOT_FOUND' && parent?.filename?.startsWith(root + '/')) {
      const req = request.startsWith('/') ? path.relative(root, request) : request;
      missing.add(path.relative(root, parent.filename) + ' -> ' + req);
    }
    throw e;
  }
};
process.on('exit', () => {
  const files = Object.keys(require.cache).filter(f => f.startsWith(root + '/')).map(f => path.relative(root, f)).sort();
  fs.writeFileSync(process.env.V11_TRACE, JSON.stringify({files, missing:[...missing].sort()}, null, 2) + '\n', {flag:'wx'});
});
